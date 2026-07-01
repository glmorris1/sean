import Foundation
import UserNotifications

enum TradeDirection: String, CaseIterable, Codable, Identifiable {
    case long = "Buy"
    case short = "Sell / Short"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .long:
            return "Long"
        case .short:
            return "Short"
        }
    }
}

enum SimulatedOrderType: String, CaseIterable, Codable, Identifiable {
    case market = "Market"
    case limit = "Limit"
    case stop = "Stop"

    var id: String { rawValue }
}

enum SimulatedOrderStatus: String, Codable {
    case pending
    case filled
    case cancelled
}

enum SimulatedExitReason: String, Codable {
    case takeProfit = "Take Profit"
    case stopLoss = "Stop Loss"
    case manual = "Manual Close"
}

struct SimulatedOrder: Identifiable, Codable, Equatable {
    let id: UUID
    var symbol: String
    var direction: TradeDirection
    var type: SimulatedOrderType
    var quantity: Double
    var entryPrice: Double
    var stopLoss: Double?
    var takeProfit: Double?
    var tickSize: Double?
    var tickValue: Double?
    var pointValue: Double?
    var isFutures: Bool?
    var assetClass: String?
    var contractSize: Double?
    var isReplayTrade: Bool?
    var createdAt: Date
    var createdBarIndex: Int
    var status: SimulatedOrderStatus

    init(
        id: UUID = UUID(),
        symbol: String,
        direction: TradeDirection,
        type: SimulatedOrderType,
        quantity: Double,
        entryPrice: Double,
        stopLoss: Double?,
        takeProfit: Double?,
        tickSize: Double? = nil,
        tickValue: Double? = nil,
        pointValue: Double? = nil,
        isFutures: Bool? = nil,
        assetClass: String? = nil,
        contractSize: Double? = nil,
        isReplayTrade: Bool? = nil,
        createdAt: Date,
        createdBarIndex: Int,
        status: SimulatedOrderStatus = .pending
    ) {
        self.id = id
        self.symbol = symbol
        self.direction = direction
        self.type = type
        self.quantity = quantity
        self.entryPrice = entryPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.tickSize = tickSize
        self.tickValue = tickValue
        self.pointValue = pointValue
        self.isFutures = isFutures
        self.assetClass = assetClass
        self.contractSize = contractSize
        self.isReplayTrade = isReplayTrade
        self.createdAt = createdAt
        self.createdBarIndex = createdBarIndex
        self.status = status
    }

    var quantityText: String {
        if quantity.rounded() == quantity {
            return String(format: "%.0f", quantity)
        }
        return String(format: "%.2f", quantity)
    }
}

struct SimulatedPosition: Identifiable, Codable, Equatable {
    let id: UUID
    var symbol: String
    var direction: TradeDirection
    var quantity: Double
    var entryPrice: Double
    var entryTime: Date
    var entryBarIndex: Int
    var stopLoss: Double?
    var takeProfit: Double?
    var tickSize: Double?
    var tickValue: Double?
    var pointValue: Double?
    var isFutures: Bool?
    var assetClass: String?
    var contractSize: Double?
    var isReplayTrade: Bool?
    var lastPrice: Double

    init(
        id: UUID = UUID(),
        symbol: String,
        direction: TradeDirection,
        quantity: Double,
        entryPrice: Double,
        entryTime: Date,
        entryBarIndex: Int,
        stopLoss: Double?,
        takeProfit: Double?,
        tickSize: Double? = nil,
        tickValue: Double? = nil,
        pointValue: Double? = nil,
        isFutures: Bool? = nil,
        assetClass: String? = nil,
        contractSize: Double? = nil,
        isReplayTrade: Bool? = nil,
        lastPrice: Double
    ) {
        self.id = id
        self.symbol = symbol
        self.direction = direction
        self.quantity = quantity
        self.entryPrice = entryPrice
        self.entryTime = entryTime
        self.entryBarIndex = entryBarIndex
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.tickSize = tickSize
        self.tickValue = tickValue
        self.pointValue = pointValue
        self.isFutures = isFutures
        self.assetClass = assetClass
        self.contractSize = contractSize
        self.isReplayTrade = isReplayTrade
        self.lastPrice = lastPrice
    }

    var unrealizedPL: Double {
        if isFutures == true, let tickSize, let tickValue, tickSize > 0 {
            let ticks: Double
            switch direction {
            case .long:
                ticks = (lastPrice - entryPrice) / tickSize
            case .short:
                ticks = (entryPrice - lastPrice) / tickSize
            }
            return ticks * tickValue * quantity
        }

        let units = quantity * (contractSize ?? 1)
        switch direction {
        case .long:
            return (lastPrice - entryPrice) * units
        case .short:
            return (entryPrice - lastPrice) * units
        }
    }

    var unrealizedPercent: Double {
        guard entryPrice != 0 else { return 0 }
        switch direction {
        case .long:
            return ((lastPrice - entryPrice) / entryPrice) * 100
        case .short:
            return ((entryPrice - lastPrice) / entryPrice) * 100
        }
    }

    var quantityText: String {
        if quantity.rounded() == quantity {
            return String(format: "%.0f", quantity)
        }
        return String(format: "%.2f", quantity)
    }
}

struct SimulatedTrade: Identifiable, Codable, Equatable {
    let id: UUID
    var symbol: String
    var direction: TradeDirection
    var entryTime: Date
    var exitTime: Date
    var entryBarIndex: Int
    var exitBarIndex: Int
    var entryPrice: Double
    var exitPrice: Double
    var quantity: Double
    var stopLoss: Double?
    var takeProfit: Double?
    var tickSize: Double?
    var tickValue: Double?
    var pointValue: Double?
    var isFutures: Bool?
    var assetClass: String?
    var contractSize: Double?
    var profitLoss: Double
    var percentReturn: Double
    var exitReason: SimulatedExitReason

    var isWin: Bool {
        profitLoss >= 0
    }
}

struct PaperTradingAccount: Codable, Equatable {
    var startingBalance: Double = 100_000
    var cashBalance: Double = 100_000
    var openPositions: [SimulatedPosition] = []
    var pendingOrders: [SimulatedOrder] = []
    var closedTrades: [SimulatedTrade] = []
    var lastProcessedBarIndexBySymbol: [String: Int] = [:]

    var realizedPL: Double {
        closedTrades.reduce(0) { $0 + $1.profitLoss }
    }

    var unrealizedPL: Double {
        openPositions.reduce(0) { $0 + $1.unrealizedPL }
    }

    var equity: Double {
        cashBalance + unrealizedPL
    }

    var buyingPower: Double {
        equity * 2
    }
}

struct PaperTradingStats {
    let totalTrades: Int
    let wins: Int
    let losses: Int
    let winRate: Double
    let netProfit: Double
    let averageWin: Double
    let averageLoss: Double
    let profitFactor: Double
    let largestWin: Double
    let largestLoss: Double
}

struct TradeHistoryRepository {
    private var storageKey = "sean.paperTrading.account.guest"

    mutating func setUserID(_ userID: String?) {
        let cleanID = userID?.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: ".", with: "_") ?? "guest"
        storageKey = "sean.paperTrading.account.\(cleanID)"
    }

    func loadAccount() -> PaperTradingAccount {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let account = try? JSONDecoder().decode(PaperTradingAccount.self, from: data) else {
            return PaperTradingAccount()
        }
        return account
    }

    func saveAccount(_ account: PaperTradingAccount) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@Observable
@MainActor
final class PaperTradingService {
    private var repository = TradeHistoryRepository()
    private var futuresBySymbol: [String: FuturesSymbol] = [:]
    private var instrumentsBySymbol: [String: InstrumentMetadata] = [:]

    var account: PaperTradingAccount = PaperTradingAccount() {
        didSet {
            repository.saveAccount(account)
        }
    }

    var ticketDirection: TradeDirection = .long
    var ticketOrderType: SimulatedOrderType = .market
    var ticketQuantity: Double = 100
    var ticketEntryPrice: Double = 0
    var ticketStopLoss: Double = 0
    var ticketTakeProfit: Double = 0
    var ticketRiskAmount: Double = 1_000
    var ticketRiskPercent: Double = 1
    var chartPlacementEnabled = false
    var ticketIsReplayTrade = false

    init() {
        account = repository.loadAccount()
    }

    func setUserID(_ userID: String?) {
        repository.setUserID(userID)
        account = repository.loadAccount()
    }

    func configureInstrument(_ symbol: MarketSymbol) {
        if let futures = symbol.futures {
            futuresBySymbol[symbol.ticker] = futures
        }
        if let instrument = symbol.instrument {
            instrumentsBySymbol[symbol.ticker] = instrument
        }
    }

    @discardableResult
    func createChartSetupOrder(
        symbol: String,
        direction: TradeDirection,
        price: Double,
        candle: Candle?,
        stopLoss: Double? = nil,
        takeProfit: Double? = nil,
        isReplayTrade: Bool = false
    ) -> SimulatedOrder? {
        ticketDirection = direction
        ticketOrderType = .limit
        ticketEntryPrice = price
        let previousStop = ticketStopLoss > 0 ? ticketStopLoss : 0
        let previousTarget = ticketTakeProfit > 0 ? ticketTakeProfit : 0
        let previousReplayTrade = ticketIsReplayTrade
        ticketStopLoss = stopLoss ?? 0
        ticketTakeProfit = takeProfit ?? 0
        ticketIsReplayTrade = isReplayTrade
        defer {
            ticketStopLoss = previousStop
            ticketTakeProfit = previousTarget
            ticketIsReplayTrade = previousReplayTrade
        }
        return submitOrder(symbol: symbol, latestCandle: candle)
    }

    func updatePendingOrder(_ id: UUID, entryPrice: Double? = nil, stopLoss: Double? = nil, takeProfit: Double? = nil) {
        guard let index = account.pendingOrders.firstIndex(where: { $0.id == id }) else { return }
        if let entryPrice {
            account.pendingOrders[index].entryPrice = max(0.0001, entryPrice)
        }
        if let stopLoss {
            account.pendingOrders[index].stopLoss = stopLoss > 0 ? stopLoss : nil
        }
        if let takeProfit {
            account.pendingOrders[index].takeProfit = takeProfit > 0 ? takeProfit : nil
        }
    }

    func estimatedProfitLoss(for order: SimulatedOrder, markPrice: Double) -> Double {
        profitLoss(
            direction: order.direction,
            entryPrice: order.entryPrice,
            exitPrice: markPrice,
            quantity: order.quantity,
            tickSize: order.tickSize,
            tickValue: order.tickValue,
            isFutures: order.isFutures == true,
            assetClass: order.assetClass,
            contractSize: order.contractSize
        )
    }

    func profitLoss(
        direction: TradeDirection,
        entryPrice: Double,
        exitPrice: Double,
        quantity: Double,
        tickSize: Double?,
        tickValue: Double?,
        isFutures: Bool,
        assetClass: String? = nil,
        contractSize: Double? = nil
    ) -> Double {
        if isFutures, let tickSize, let tickValue, tickSize > 0 {
            let ticks: Double
            switch direction {
            case .long:
                ticks = (exitPrice - entryPrice) / tickSize
            case .short:
                ticks = (entryPrice - exitPrice) / tickSize
            }
            return ticks * tickValue * quantity
        }

        let units = quantity * (contractSize ?? 1)
        switch direction {
        case .long:
            return (exitPrice - entryPrice) * units
        case .short:
            return (entryPrice - exitPrice) * units
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    var stats: PaperTradingStats {
        let trades = account.closedTrades
        let wins = trades.filter(\.isWin)
        let losses = trades.filter { !$0.isWin }
        let grossWin = wins.reduce(0) { $0 + $1.profitLoss }
        let grossLoss = abs(losses.reduce(0) { $0 + $1.profitLoss })
        return PaperTradingStats(
            totalTrades: trades.count,
            wins: wins.count,
            losses: losses.count,
            winRate: trades.isEmpty ? 0 : (Double(wins.count) / Double(trades.count)) * 100,
            netProfit: account.realizedPL,
            averageWin: wins.isEmpty ? 0 : grossWin / Double(wins.count),
            averageLoss: losses.isEmpty ? 0 : -grossLoss / Double(losses.count),
            profitFactor: grossLoss == 0 ? grossWin : grossWin / grossLoss,
            largestWin: wins.map(\.profitLoss).max() ?? 0,
            largestLoss: losses.map(\.profitLoss).min() ?? 0
        )
    }

    func resetAccount() {
        account = PaperTradingAccount()
    }

    func processVisibleCandles(_ candles: [Candle], symbol: String, isReplayMode: Bool = false) {
        guard !candles.isEmpty else { return }
        let processedKey = paperProcessingKey(symbol: symbol, isReplayMode: isReplayMode)
        let lastProcessed = account.lastProcessedBarIndexBySymbol[processedKey] ?? -1
        let freshCandles = candles.filter { $0.index > lastProcessed }
        guard !freshCandles.isEmpty else {
            if let last = candles.last {
                markToMarket(symbol: symbol, price: last.close, isReplayMode: isReplayMode)
            }
            return
        }

        for candle in freshCandles {
            process(candle, symbol: symbol, isReplayMode: isReplayMode)
            account.lastProcessedBarIndexBySymbol[processedKey] = candle.index
        }
    }

    func resyncForReplay(symbol: String, through candles: [Candle]) {
        account.lastProcessedBarIndexBySymbol[paperProcessingKey(symbol: symbol, isReplayMode: true)] = -1
        processVisibleCandles(candles, symbol: symbol, isReplayMode: true)
    }

    @discardableResult
    func submitOrder(symbol: String, latestCandle: Candle?) -> SimulatedOrder? {
        guard ticketQuantity > 0 else { return nil }
        let fallbackPrice = latestCandle?.close ?? ticketEntryPrice
        let entryPrice = ticketOrderType == .market ? fallbackPrice : max(ticketEntryPrice, 0)
        guard entryPrice > 0 else { return nil }

        let order = SimulatedOrder(
            symbol: symbol,
            direction: ticketDirection,
            type: ticketOrderType,
            quantity: ticketQuantity,
            entryPrice: entryPrice,
            stopLoss: ticketStopLoss > 0 ? ticketStopLoss : nil,
            takeProfit: ticketTakeProfit > 0 ? ticketTakeProfit : nil,
            tickSize: futuresBySymbol[symbol]?.tickSize,
            tickValue: futuresBySymbol[symbol]?.tickValue,
            pointValue: futuresBySymbol[symbol]?.pointValue,
            isFutures: futuresBySymbol[symbol] != nil,
            assetClass: instrumentsBySymbol[symbol]?.assetType ?? (futuresBySymbol[symbol] != nil ? "futures" : "stocks"),
            contractSize: instrumentsBySymbol[symbol]?.contractSize,
            isReplayTrade: ticketIsReplayTrade,
            createdAt: latestCandle?.date ?? Date(),
            createdBarIndex: latestCandle?.index ?? 0
        )

        if ticketOrderType == .market, let latestCandle {
            fill(order, at: latestCandle.close, on: latestCandle)
        } else {
            account.pendingOrders.append(order)
        }

        return order
    }

    @discardableResult
    func submitChartOrder(symbol: String, price: Double, candle: Candle?) -> SimulatedOrder? {
        ticketEntryPrice = price
        if ticketOrderType == .market {
            ticketOrderType = .limit
        }
        return submitOrder(symbol: symbol, latestCandle: candle)
    }

    func cancelOrder(_ order: SimulatedOrder) {
        account.pendingOrders.removeAll { $0.id == order.id }
    }

    func closePosition(_ position: SimulatedPosition, at price: Double, time: Date, barIndex: Int) {
        close(position, at: price, time: time, barIndex: barIndex, reason: .manual)
    }

    private func process(_ candle: Candle, symbol: String, isReplayMode: Bool) {
        markToMarket(symbol: symbol, price: candle.close, isReplayMode: isReplayMode)
        fillTriggeredOrders(on: candle, symbol: symbol, isReplayMode: isReplayMode)
        triggerStopsAndTargets(on: candle, symbol: symbol, isReplayMode: isReplayMode)
        markToMarket(symbol: symbol, price: candle.close, isReplayMode: isReplayMode)
    }

    private func markToMarket(symbol: String, price: Double, isReplayMode: Bool) {
        for index in account.openPositions.indices where account.openPositions[index].symbol == symbol && (account.openPositions[index].isReplayTrade == true) == isReplayMode {
            account.openPositions[index].lastPrice = price
        }
    }

    private func fillTriggeredOrders(on candle: Candle, symbol: String, isReplayMode: Bool) {
        let pending = account.pendingOrders.filter { $0.symbol == symbol && ($0.isReplayTrade == true) == isReplayMode }
        for order in pending {
            let shouldFill: Bool
            guard candle.index > order.createdBarIndex else { continue }
            switch order.type {
            case .market:
                shouldFill = true
            case .limit:
                switch order.direction {
                case .long:
                    shouldFill = candle.low <= order.entryPrice
                case .short:
                    shouldFill = candle.high >= order.entryPrice
                }
            case .stop:
                switch order.direction {
                case .long:
                    shouldFill = candle.high >= order.entryPrice
                case .short:
                    shouldFill = candle.low <= order.entryPrice
                }
            }

            if shouldFill {
                fill(order, at: order.entryPrice, on: candle)
                account.pendingOrders.removeAll { $0.id == order.id }
                sendPaperNotification(
                    title: "Paper \(order.direction.shortLabel) Filled",
                    body: "\(order.symbol) filled at \(order.entryPrice.priceText)"
                )
            }
        }
    }

    private func triggerStopsAndTargets(on candle: Candle, symbol: String, isReplayMode: Bool) {
        let positions = account.openPositions.filter { $0.symbol == symbol && ($0.isReplayTrade == true) == isReplayMode }
        for position in positions {
            guard candle.index > position.entryBarIndex else { continue }
            if position.direction == .long {
                if let stopLoss = position.stopLoss, candle.low <= stopLoss {
                    close(position, at: stopLoss, time: candle.date, barIndex: candle.index, reason: .stopLoss)
                } else if let takeProfit = position.takeProfit, candle.high >= takeProfit {
                    close(position, at: takeProfit, time: candle.date, barIndex: candle.index, reason: .takeProfit)
                }
            } else {
                if let stopLoss = position.stopLoss, candle.high >= stopLoss {
                    close(position, at: stopLoss, time: candle.date, barIndex: candle.index, reason: .stopLoss)
                } else if let takeProfit = position.takeProfit, candle.low <= takeProfit {
                    close(position, at: takeProfit, time: candle.date, barIndex: candle.index, reason: .takeProfit)
                }
            }
        }
    }

    private func fill(_ order: SimulatedOrder, at price: Double, on candle: Candle) {
        let position = SimulatedPosition(
            symbol: order.symbol,
            direction: order.direction,
            quantity: order.quantity,
            entryPrice: price,
            entryTime: candle.date,
            entryBarIndex: candle.index,
            stopLoss: order.stopLoss,
            takeProfit: order.takeProfit,
            tickSize: order.tickSize,
            tickValue: order.tickValue,
            pointValue: order.pointValue,
            isFutures: order.isFutures,
            assetClass: order.assetClass,
            contractSize: order.contractSize,
            isReplayTrade: order.isReplayTrade,
            lastPrice: candle.close
        )
        account.openPositions.append(position)
        account.cashBalance -= marginImpact(for: position)
    }

    private func paperProcessingKey(symbol: String, isReplayMode: Bool) -> String {
        "\(symbol)|\(isReplayMode ? "replay" : "live")"
    }

    private func close(_ position: SimulatedPosition, at price: Double, time: Date, barIndex: Int, reason: SimulatedExitReason) {
        guard account.openPositions.contains(where: { $0.id == position.id }) else { return }
        let profitLoss = profitLoss(
            direction: position.direction,
            entryPrice: position.entryPrice,
            exitPrice: price,
            quantity: position.quantity,
            tickSize: position.tickSize,
            tickValue: position.tickValue,
            isFutures: position.isFutures == true,
            assetClass: position.assetClass,
            contractSize: position.contractSize
        )

        let units = position.quantity * (position.contractSize ?? 1)
        let basis = position.isFutures == true ? position.entryPrice * (position.pointValue ?? 1) * position.quantity : position.entryPrice * units
        let percentReturn = basis == 0 ? 0 : (profitLoss / basis) * 100
        account.openPositions.removeAll { $0.id == position.id }
        account.cashBalance += marginImpact(for: position) + profitLoss
        account.closedTrades.insert(
            SimulatedTrade(
                id: UUID(),
                symbol: position.symbol,
                direction: position.direction,
                entryTime: position.entryTime,
                exitTime: time,
                entryBarIndex: position.entryBarIndex,
                exitBarIndex: barIndex,
                entryPrice: position.entryPrice,
                exitPrice: price,
                quantity: position.quantity,
                stopLoss: position.stopLoss,
                takeProfit: position.takeProfit,
                tickSize: position.tickSize,
                tickValue: position.tickValue,
                pointValue: position.pointValue,
                isFutures: position.isFutures,
                assetClass: position.assetClass,
                contractSize: position.contractSize,
                profitLoss: profitLoss,
                percentReturn: percentReturn,
                exitReason: reason
            ),
            at: 0
        )
        sendPaperNotification(
            title: "Paper Trade \(reason.rawValue)",
            body: "\(position.symbol) closed at \(price.priceText) · \(profitLoss.signedMoneyText)"
        )
    }

    private func marginImpact(for position: SimulatedPosition) -> Double {
        if position.isFutures == true {
            return position.entryPrice * (position.pointValue ?? 1) * position.quantity * 0.05
        }
        return position.entryPrice * position.quantity * 0.5
    }

    private func sendPaperNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
