import Foundation

struct BacktestEngine {
    static func run(
        candles: [Candle],
        strategy: StrategyKind,
        fastPeriod: Int,
        slowPeriod: Int,
        startingCapital: Double = 10_000
    ) -> BacktestResult {
        guard candles.count > max(fastPeriod, slowPeriod) + 2 else {
            return BacktestResult(equity: [], trades: [], totalReturn: 0, winRate: 0, maxDrawdown: 0, sharpe: 0)
        }

        let closes = candles.map(\.close)
        let fast = movingAverage(closes, period: fastPeriod)
        let slow = movingAverage(closes, period: slowPeriod)

        var inPosition = false
        var entryPrice = 0.0
        var entryIndex = 0
        var capital = startingCapital
        var peak = startingCapital
        var drawdown = 0.0
        var returns: [Double] = []
        var trades: [Trade] = []
        var equity: [EquityPoint] = [EquityPoint(index: 0, value: startingCapital)]

        for index in 1..<candles.count {
            let price = candles[index].close
            let previousPrice = candles[index - 1].close
            let shouldEnter = entrySignal(strategy: strategy, index: index, closes: closes, fast: fast, slow: slow)
            let shouldExit = exitSignal(strategy: strategy, index: index, closes: closes, fast: fast, slow: slow)

            if inPosition {
                let dailyReturn = (price - previousPrice) / previousPrice
                capital *= 1 + dailyReturn
                returns.append(dailyReturn)
            }

            if !inPosition && shouldEnter {
                inPosition = true
                entryPrice = price
                entryIndex = index
            } else if inPosition && shouldExit {
                inPosition = false
                trades.append(Trade(entryIndex: entryIndex, exitIndex: index, entry: entryPrice, exit: price))
            }

            peak = max(peak, capital)
            drawdown = min(drawdown, (capital - peak) / peak)
            equity.append(EquityPoint(index: index, value: capital))
        }

        if inPosition, let last = candles.last {
            trades.append(Trade(entryIndex: entryIndex, exitIndex: last.index, entry: entryPrice, exit: last.close))
        }

        let wins = trades.filter { $0.profitPercent > 0 }.count
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100
        let totalReturn = (capital - startingCapital) / startingCapital * 100

        return BacktestResult(
            equity: equity,
            trades: trades,
            totalReturn: totalReturn,
            winRate: winRate,
            maxDrawdown: abs(drawdown) * 100,
            sharpe: annualizedSharpe(returns)
        )
    }

    private static func movingAverage(_ values: [Double], period: Int) -> [Double?] {
        values.indices.map { index in
            guard index >= period - 1 else { return nil }
            let window = values[(index - period + 1)...index]
            return window.reduce(0, +) / Double(period)
        }
    }

    private static func entrySignal(
        strategy: StrategyKind,
        index: Int,
        closes: [Double],
        fast: [Double?],
        slow: [Double?]
    ) -> Bool {
        switch strategy {
        case .movingAverageCross:
            guard let fastNow = fast[index], let slowNow = slow[index],
                  let fastPrevious = fast[index - 1], let slowPrevious = slow[index - 1] else { return false }
            return fastPrevious <= slowPrevious && fastNow > slowNow
        case .breakout:
            let start = max(0, index - 20)
            let previousHigh = closes[start..<index].max() ?? closes[index]
            return closes[index] > previousHigh
        case .rsiReversion:
            return oscillator(closes, index: index) < 35
        }
    }

    private static func exitSignal(
        strategy: StrategyKind,
        index: Int,
        closes: [Double],
        fast: [Double?],
        slow: [Double?]
    ) -> Bool {
        switch strategy {
        case .movingAverageCross:
            guard let fastNow = fast[index], let slowNow = slow[index],
                  let fastPrevious = fast[index - 1], let slowPrevious = slow[index - 1] else { return false }
            return fastPrevious >= slowPrevious && fastNow < slowNow
        case .breakout:
            let start = max(0, index - 10)
            let previousLow = closes[start..<index].min() ?? closes[index]
            return closes[index] < previousLow
        case .rsiReversion:
            return oscillator(closes, index: index) > 55
        }
    }

    private static func oscillator(_ closes: [Double], index: Int) -> Double {
        let start = max(1, index - 14)
        let changes = (start...index).map { closes[$0] - closes[$0 - 1] }
        let gains = changes.filter { $0 > 0 }.reduce(0, +)
        let losses = abs(changes.filter { $0 < 0 }.reduce(0, +))
        guard losses > 0 else { return 100 }
        let relativeStrength = gains / losses
        return 100 - (100 / (1 + relativeStrength))
    }

    private static func annualizedSharpe(_ returns: [Double]) -> Double {
        guard returns.count > 2 else { return 0 }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count - 1)
        let standardDeviation = sqrt(variance)
        guard standardDeviation > 0 else { return 0 }
        return (mean / standardDeviation) * sqrt(252)
    }
}
