import Foundation
import SwiftUI

struct MarketSymbol: Identifiable, Hashable {
    let id = UUID()
    let ticker: String
    let name: String
    let exchange: String
    let assetClass: String
    var quoteCurrency: String? = nil
    var provider: String? = nil
    var providerSymbol: String? = nil
    var availableTimeframes: [String]? = nil
    var contractType: String? = nil
    var dataAvailability: String? = nil
    var futures: FuturesSymbol? = nil
    var instrument: InstrumentMetadata? = nil
    var last: Double
    var changePercent: Double
    var volume: String

    var isFutures: Bool {
        assetClass == "futures"
    }

    var isProviderBackedInstrument: Bool {
        instrument != nil
    }

    var assetBadge: String {
        switch assetClass {
        case "stocks":
            return "Stock"
        case "etf":
            return "ETF"
        case "futures":
            return "Futures"
        case "forex":
            return "Forex"
        case "spot_metal":
            return "Metal"
        case "crypto":
            return "Crypto"
        default:
            return assetClass.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct InstrumentMetadata: Hashable, Codable {
    let symbol: String
    let displayName: String
    let assetType: String
    let baseAsset: String
    let quoteAsset: String
    let exchange: String
    let provider: String
    let providerSymbol: String
    let tickSize: Double
    let pipSize: Double?
    let contractSize: Double?
    let availableTimeframes: [String]

    var marketSymbol: MarketSymbol {
        MarketSymbol(
            ticker: symbol,
            name: displayName,
            exchange: exchange,
            assetClass: assetType,
            quoteCurrency: quoteAsset,
            provider: provider,
            providerSymbol: providerSymbol,
            availableTimeframes: availableTimeframes,
            dataAvailability: "Historical candles via \(provider)",
            instrument: self,
            last: 0,
            changePercent: 0,
            volume: "--"
        )
    }
}

struct FuturesSymbol: Hashable, Codable {
    let symbol: String
    let rootSymbol: String
    let displayName: String
    let exchange: String
    let assetType: String
    let contractType: String
    let contractMonth: String?
    let contractYear: Int?
    let isContinuous: Bool
    let continuousMonthIndex: Int?
    let tickSize: Double
    let tickValue: Double
    let pointValue: Double
    let currency: String
    let dataProviderSymbol: String
    let availableTimeframes: [String]

    var dataAvailability: String {
        isContinuous ? "Historical delayed candles via Yahoo Finance" : "Historical delayed candles when provider has contract"
    }

    var marketSymbol: MarketSymbol {
        MarketSymbol(
            ticker: symbol,
            name: displayName,
            exchange: exchange,
            assetClass: assetType,
            provider: "Yahoo Finance",
            providerSymbol: dataProviderSymbol,
            contractType: contractType,
            dataAvailability: dataAvailability,
            futures: self,
            last: 0,
            changePercent: 0,
            volume: "--"
        )
    }
}

struct Candle: Identifiable {
    let id = UUID()
    let index: Int
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

struct EquityPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}

struct Trade: Identifiable {
    let id = UUID()
    let entryIndex: Int
    let exitIndex: Int
    let entry: Double
    let exit: Double

    var profitPercent: Double {
        ((exit - entry) / entry) * 100
    }
}

struct BacktestResult {
    let equity: [EquityPoint]
    let trades: [Trade]
    let totalReturn: Double
    let winRate: Double
    let maxDrawdown: Double
    let sharpe: Double
}

enum StrategyKind: String, CaseIterable, Identifiable {
    case movingAverageCross = "MA Cross"
    case breakout = "Breakout"
    case rsiReversion = "RSI Reversion"

    var id: String { rawValue }
}

enum ChartStyle: String, CaseIterable, Identifiable {
    case candles = "Candles"
    case line = "Line"
    case area = "Area"

    var id: String { rawValue }
}

enum ChartBackgroundTheme: String, CaseIterable, Identifiable {
    case gradient = "Gradient"
    case white = "White"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case indigo = "Indigo"
    case violet = "Violet"
    case pink = "Pink"

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .gradient:
            return [
                Color(red: 0.04, green: 0.05, blue: 0.12),
                Color(red: 0.18, green: 0.08, blue: 0.28),
                Color(red: 0.70, green: 0.10, blue: 0.75)
            ]
        case .white:
            return [.white, Color(red: 0.94, green: 0.95, blue: 0.98)]
        case .red:
            return [Color(red: 0.36, green: 0.02, blue: 0.07), Color(red: 0.92, green: 0.10, blue: 0.18)]
        case .orange:
            return [Color(red: 0.38, green: 0.13, blue: 0.02), Color(red: 1.00, green: 0.48, blue: 0.05)]
        case .yellow:
            return [Color(red: 0.96, green: 0.80, blue: 0.18), Color(red: 1.00, green: 0.96, blue: 0.50)]
        case .green:
            return [Color(red: 0.02, green: 0.25, blue: 0.16), Color(red: 0.02, green: 0.72, blue: 0.38)]
        case .blue:
            return [Color(red: 0.02, green: 0.10, blue: 0.34), Color(red: 0.05, green: 0.48, blue: 0.95)]
        case .indigo:
            return [Color(red: 0.08, green: 0.08, blue: 0.32), Color(red: 0.33, green: 0.24, blue: 0.86)]
        case .violet:
            return [Color(red: 0.18, green: 0.05, blue: 0.28), Color(red: 0.69, green: 0.16, blue: 0.86)]
        case .pink:
            return [Color(red: 0.33, green: 0.03, blue: 0.20), Color(red: 0.94, green: 0.16, blue: 0.56)]
        }
    }

    var isLight: Bool {
        self == .white || self == .yellow || self == .orange
    }

    var markColor: Color {
        isLight ? .black : .white
    }

    var bearishColor: Color {
        isLight ? .red : .black
    }

    var gridColor: Color {
        isLight ? .black.opacity(0.13) : .white.opacity(0.10)
    }
}

enum CandleInterval: String, CaseIterable, Identifiable {
    case fifteenSeconds = "15s"
    case oneMinute = "1m"
    case twoMinutes = "2m"
    case threeMinutes = "3m"
    case fiveMinutes = "5m"
    case tenMinutes = "10m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case fourHours = "4h"
    case oneDay = "1 day"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fifteenSeconds:
            return 15
        case .oneMinute:
            return 60
        case .twoMinutes:
            return 120
        case .threeMinutes:
            return 180
        case .fiveMinutes:
            return 300
        case .tenMinutes:
            return 600
        case .fifteenMinutes:
            return 900
        case .thirtyMinutes:
            return 1_800
        case .oneHour:
            return 3_600
        case .fourHours:
            return 14_400
        case .oneDay:
            return 86_400
        }
    }

    var gridLabel: String {
        let seconds = Int(seconds * 30)
        if seconds < 60 {
            return "\(seconds)s grid"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m grid"
        }
        if seconds < 86_400 {
            return "\(seconds / 3_600)h grid"
        }
        return "\(seconds / 86_400)d grid"
    }
}

@Observable
@MainActor
final class MarketStore {
    private var userStorageKey = "sean.watchlist.guest"

    static let defaultSelectedSymbol: MarketSymbol = FuturesCatalog.symbol(for: "MES1!")?.marketSymbol ??
        MarketSymbol(
            ticker: "MES1!",
            name: "Micro E-mini S&P 500 Futures Continuous Contract, Front Month",
            exchange: "CME",
            assetClass: "futures",
            provider: "Yahoo Finance",
            providerSymbol: "MES=F",
            dataAvailability: "Historical delayed candles via Yahoo Finance",
            last: 0,
            changePercent: 0,
            volume: "--"
        )

    static let defaultSymbols: [MarketSymbol] = [
        defaultSelectedSymbol,
        MarketSymbol(ticker: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "MSFT", name: "Microsoft Corp.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "TSLA", name: "Tesla Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "NVDA", name: "NVIDIA Corp.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "META", name: "Meta Platforms", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "AMZN", name: "Amazon.com Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "GOOGL", name: "Alphabet Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "SPY", name: "S&P 500 ETF", exchange: "NYSE Arca", assetClass: "etf", last: 0, changePercent: 0, volume: "--")
    ]

    static let searchableSymbols: [MarketSymbol] = [
        MarketSymbol(ticker: "AAPL", name: "Apple Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "MSFT", name: "Microsoft Corp.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "TSLA", name: "Tesla Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "NVDA", name: "NVIDIA Corp.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "META", name: "Meta Platforms", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "AMZN", name: "Amazon.com Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "GOOGL", name: "Alphabet Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "SPY", name: "S&P 500 ETF", exchange: "NYSE Arca", assetClass: "etf", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "QQQ", name: "Invesco QQQ Trust", exchange: "NASDAQ", assetClass: "etf", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "IWM", name: "Russell 2000 ETF", exchange: "NYSE Arca", assetClass: "etf", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "DIA", name: "Dow Jones Industrial ETF", exchange: "NYSE Arca", assetClass: "etf", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "AMD", name: "Advanced Micro Devices", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "NFLX", name: "Netflix Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "AVGO", name: "Broadcom Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "PLTR", name: "Palantir Technologies", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "COIN", name: "Coinbase Global", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "MSTR", name: "MicroStrategy Inc.", exchange: "NASDAQ", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "JPM", name: "JPMorgan Chase", exchange: "NYSE", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "V", name: "Visa Inc.", exchange: "NYSE", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "WMT", name: "Walmart Inc.", exchange: "NYSE", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "DIS", name: "Walt Disney Co.", exchange: "NYSE", assetClass: "stocks", last: 0, changePercent: 0, volume: "--"),
        MarketSymbol(ticker: "BA", name: "Boeing Co.", exchange: "NYSE", assetClass: "stocks", last: 0, changePercent: 0, volume: "--")
    ]

    var symbols: [MarketSymbol]
    var selected: MarketSymbol
    var candles: [Candle]
    var selectedInterval: CandleInterval = .tenMinutes
    var chartBackgroundTheme: ChartBackgroundTheme = .white
    var isLoading = false
    var errorMessage: String?
    var latestDataDate: Date?

    init() {
        let initial = Self.defaultSymbols[0]
        symbols = Self.defaultSymbols
        selected = initial
        candles = []
    }

    func setUserID(_ userID: String?) {
        let cleanID = userID?.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: ".", with: "_") ?? "guest"
        userStorageKey = "sean.watchlist.\(cleanID)"
        loadWatchlist()
    }

    func replaceWatchlist(with persistedSymbols: [PersistedMarketSymbol]) {
        guard !persistedSymbols.isEmpty else { return }
        symbols = persistedSymbols.map(\.marketSymbol)
        if !symbols.contains(where: { $0.ticker == selected.ticker }) {
            selected = symbols.first ?? Self.defaultSymbols[0]
        }
        saveWatchlist()
    }

    var persistedWatchlist: [PersistedMarketSymbol] {
        symbols.map(PersistedMarketSymbol.init)
    }

    func select(_ symbol: MarketSymbol) async {
        selected = symbol
        await loadSelectedSymbol()
    }

    func isInWatchlist(_ symbol: MarketSymbol) -> Bool {
        symbols.contains { $0.ticker.caseInsensitiveCompare(symbol.ticker) == .orderedSame }
    }

    func addToWatchlist(_ symbol: MarketSymbol) {
        guard !isInWatchlist(symbol) else { return }
        symbols.append(symbol)
        saveWatchlist()
    }

    func removeFromWatchlist(_ symbol: MarketSymbol) {
        symbols.removeAll { $0.ticker.caseInsensitiveCompare(symbol.ticker) == .orderedSame }
        saveWatchlist()
    }

    func toggleWatchlist(_ symbol: MarketSymbol) {
        if isInWatchlist(symbol) {
            removeFromWatchlist(symbol)
        } else {
            addToWatchlist(symbol)
        }
    }

    func selectInterval(_ interval: CandleInterval) async {
        selectedInterval = interval
        await loadSelectedSymbol()
    }

    func selectChartBackground(_ theme: ChartBackgroundTheme) {
        chartBackgroundTheme = theme
    }

    func loadSelectedSymbol() async {
        isLoading = true
        errorMessage = nil

        do {
            let history = try await MarketDataService.fetchCandles(for: selected, interval: selectedInterval)
            candles = history
            updateQuoteFromCandles()
        } catch {
            candles = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshSelectedSymbol() async {
        do {
            let history = try await MarketDataService.fetchCandles(for: selected, interval: selectedInterval)
            mergeRefreshedCandles(history)
            updateQuoteFromCandles()
            errorMessage = nil
        } catch {
            guard candles.isEmpty else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func mergeRefreshedCandles(_ refreshed: [Candle]) {
        guard !refreshed.isEmpty else { return }
        var rowsByDate = Dictionary(uniqueKeysWithValues: candles.map { ($0.date, $0) })
        for candle in refreshed {
            rowsByDate[candle.date] = candle
        }

        candles = rowsByDate.values
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { index, candle in
                Candle(
                    index: index,
                    date: candle.date,
                    open: candle.open,
                    high: candle.high,
                    low: candle.low,
                    close: candle.close,
                    volume: candle.volume
                )
            }
    }

    private func updateQuoteFromCandles() {
        guard let last = candles.last else { return }
        let previousClose = candles.dropLast().last?.close ?? last.open
        let change = previousClose == 0 ? 0 : ((last.close - previousClose) / previousClose) * 100

        selected.last = last.close
        selected.changePercent = change
        selected.volume = Self.compactVolume(last.volume)
        latestDataDate = last.date

        if let index = symbols.firstIndex(where: { $0.ticker == selected.ticker }) {
            symbols[index].last = selected.last
            symbols[index].changePercent = selected.changePercent
            symbols[index].volume = selected.volume
            saveWatchlist()
        }
    }

    private func loadWatchlist() {
        guard let data = UserDefaults.standard.data(forKey: userStorageKey),
              let saved = try? JSONDecoder().decode([PersistedMarketSymbol].self, from: data),
              !saved.isEmpty else {
            symbols = Self.defaultSymbols
            return
        }
        symbols = saved.map(\.marketSymbol)
        if !symbols.contains(where: { $0.ticker == selected.ticker }) {
            selected = symbols.first ?? Self.defaultSymbols[0]
        }
    }

    private func saveWatchlist() {
        let payload = symbols.map(PersistedMarketSymbol.init)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: userStorageKey)
    }

    static func compactVolume(_ volume: Double) -> String {
        if volume >= 1_000_000_000 {
            return "\(String(format: "%.1f", volume / 1_000_000_000))B"
        }
        if volume >= 1_000_000 {
            return "\(String(format: "%.1f", volume / 1_000_000))M"
        }
        if volume >= 1_000 {
            return "\(String(format: "%.1f", volume / 1_000))K"
        }
        return String(format: "%.0f", volume)
    }
}

extension Double {
    var percentText: String {
        "\(self >= 0 ? "+" : "")\(String(format: "%.2f", self))%"
    }

    var priceText: String {
        if self >= 1000 {
            return Self.currencyFormatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
        }
        return String(format: "%.2f", self)
    }

    var moneyText: String {
        Self.moneyFormatter.string(from: NSNumber(value: self)) ?? String(format: "$%.2f", self)
    }

    var signedMoneyText: String {
        let value = Self.moneyFormatter.string(from: NSNumber(value: abs(self))) ?? String(format: "$%.2f", abs(self))
        return "\(self >= 0 ? "+" : "-")\(value)"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

extension Date {
    var chartLabel: String {
        Self.fullFormatter.string(from: self)
    }

    var shortChartLabel: String {
        Self.shortFormatter.string(from: self)
    }

    var intradayChartLabel: String {
        Self.intradayFormatter.string(from: self)
    }

    var crosshairIntradayLabel: String {
        Self.crosshairIntradayFormatter.string(from: self)
    }

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let intradayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("h:mm")
        return formatter
    }()

    private static let crosshairIntradayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d h:mm a")
        return formatter
    }()
}
