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
    case stopLimit = "Stop Limit"

    var id: String { rawValue }
}

enum SimulatedOrderStatus: String, Codable {
    case pending
    case partiallyFilled
    case filled
    case cancelled
    case expired
}

enum SimulatedOrderTimeInForce: String, CaseIterable, Codable, Identifiable {
    case day = "Day"
    case gtc = "GTC"

    var id: String { rawValue }
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
    var limitPrice: Double?
    var stopPrice: Double?
    var stopLoss: Double?
    var takeProfit: Double?
    var tickSize: Double?
    var tickValue: Double?
    var pointValue: Double?
    var isFutures: Bool?
    var assetClass: String?
    var contractSize: Double?
    var isReplayTrade: Bool?
    var timeInForce: SimulatedOrderTimeInForce?
    var filledQuantity: Double?
    var averageFillPrice: Double?
    var commission: Double?
    var slippage: Double?
    var parentOrderID: UUID?
    var ocoGroupID: UUID?
    var createdAt: Date
    var createdBarIndex: Int
    var updatedAt: Date?
    var status: SimulatedOrderStatus

    init(
        id: UUID = UUID(),
        symbol: String,
        direction: TradeDirection,
        type: SimulatedOrderType,
        quantity: Double,
        entryPrice: Double,
        limitPrice: Double? = nil,
        stopPrice: Double? = nil,
        stopLoss: Double?,
        takeProfit: Double?,
        tickSize: Double? = nil,
        tickValue: Double? = nil,
        pointValue: Double? = nil,
        isFutures: Bool? = nil,
        assetClass: String? = nil,
        contractSize: Double? = nil,
        isReplayTrade: Bool? = nil,
        timeInForce: SimulatedOrderTimeInForce? = .gtc,
        filledQuantity: Double? = nil,
        averageFillPrice: Double? = nil,
        commission: Double? = nil,
        slippage: Double? = nil,
        parentOrderID: UUID? = nil,
        ocoGroupID: UUID? = nil,
        createdAt: Date,
        createdBarIndex: Int,
        updatedAt: Date? = nil,
        status: SimulatedOrderStatus = .pending
    ) {
        self.id = id
        self.symbol = symbol
        self.direction = direction
        self.type = type
        self.quantity = quantity
        self.entryPrice = entryPrice
        self.limitPrice = limitPrice
        self.stopPrice = stopPrice
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.tickSize = tickSize
        self.tickValue = tickValue
        self.pointValue = pointValue
        self.isFutures = isFutures
        self.assetClass = assetClass
        self.contractSize = contractSize
        self.isReplayTrade = isReplayTrade
        self.timeInForce = timeInForce
        self.filledQuantity = filledQuantity
        self.averageFillPrice = averageFillPrice
        self.commission = commission
        self.slippage = slippage
        self.parentOrderID = parentOrderID
        self.ocoGroupID = ocoGroupID
        self.createdAt = createdAt
        self.createdBarIndex = createdBarIndex
        self.updatedAt = updatedAt
        self.status = status
    }

    var quantityText: String {
        if quantity.rounded() == quantity {
            return String(format: "%.0f", quantity)
        }
        return String(format: "%.2f", quantity)
    }

    var remainingQuantity: Double {
        max(0, quantity - (filledQuantity ?? 0))
    }

    var effectiveTimeInForce: SimulatedOrderTimeInForce {
        timeInForce ?? .gtc
    }

    var effectiveLimitPrice: Double {
        limitPrice ?? entryPrice
    }

    var effectiveStopPrice: Double {
        stopPrice ?? entryPrice
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
    var commission: Double?
    var slippage: Double?
    var profitLoss: Double
    var percentReturn: Double
    var exitReason: SimulatedExitReason

    var isWin: Bool {
        profitLoss >= 0
    }
}

struct PaperAccountSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var barIndex: Int
    var cashBalance: Double
    var equity: Double
    var portfolioValue: Double
    var realizedPL: Double
    var unrealizedPL: Double

    init(
        id: UUID = UUID(),
        date: Date,
        barIndex: Int,
        cashBalance: Double,
        equity: Double,
        portfolioValue: Double,
        realizedPL: Double,
        unrealizedPL: Double
    ) {
        self.id = id
        self.date = date
        self.barIndex = barIndex
        self.cashBalance = cashBalance
        self.equity = equity
        self.portfolioValue = portfolioValue
        self.realizedPL = realizedPL
        self.unrealizedPL = unrealizedPL
    }
}

struct PaperTradingAccount: Codable, Equatable {
    var startingBalance: Double = 100_000
    var cashBalance: Double = 100_000
    var openPositions: [SimulatedPosition] = []
    var pendingOrders: [SimulatedOrder] = []
    var orderHistory: [SimulatedOrder] = []
    var closedTrades: [SimulatedTrade] = []
    var equityHistory: [PaperAccountSnapshot] = []
    var lastProcessedBarIndexBySymbol: [String: Int] = [:]

    init(
        startingBalance: Double = 100_000,
        cashBalance: Double = 100_000,
        openPositions: [SimulatedPosition] = [],
        pendingOrders: [SimulatedOrder] = [],
        orderHistory: [SimulatedOrder] = [],
        closedTrades: [SimulatedTrade] = [],
        equityHistory: [PaperAccountSnapshot] = [],
        lastProcessedBarIndexBySymbol: [String: Int] = [:]
    ) {
        self.startingBalance = startingBalance
        self.cashBalance = cashBalance
        self.openPositions = openPositions
        self.pendingOrders = pendingOrders
        self.orderHistory = orderHistory
        self.closedTrades = closedTrades
        self.equityHistory = equityHistory
        self.lastProcessedBarIndexBySymbol = lastProcessedBarIndexBySymbol
    }

    enum CodingKeys: String, CodingKey {
        case startingBalance
        case cashBalance
        case openPositions
        case pendingOrders
        case orderHistory
        case closedTrades
        case equityHistory
        case lastProcessedBarIndexBySymbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startingBalance = try container.decodeIfPresent(Double.self, forKey: .startingBalance) ?? 100_000
        cashBalance = try container.decodeIfPresent(Double.self, forKey: .cashBalance) ?? startingBalance
        openPositions = try container.decodeIfPresent([SimulatedPosition].self, forKey: .openPositions) ?? []
        pendingOrders = try container.decodeIfPresent([SimulatedOrder].self, forKey: .pendingOrders) ?? []
        orderHistory = try container.decodeIfPresent([SimulatedOrder].self, forKey: .orderHistory) ?? pendingOrders
        closedTrades = try container.decodeIfPresent([SimulatedTrade].self, forKey: .closedTrades) ?? []
        equityHistory = try container.decodeIfPresent([PaperAccountSnapshot].self, forKey: .equityHistory) ?? []
        lastProcessedBarIndexBySymbol = try container.decodeIfPresent([String: Int].self, forKey: .lastProcessedBarIndexBySymbol) ?? [:]
    }

    var realizedPL: Double {
        closedTrades.reduce(0) { $0 + $1.profitLoss }
    }

    var unrealizedPL: Double {
        openPositions.reduce(0) { $0 + $1.unrealizedPL }
    }

    var equity: Double {
        cashBalance + unrealizedPL
    }

    var portfolioValue: Double {
        equity
    }

    var buyingPower: Double {
        equity * 2
    }

    var closedPositions: [SimulatedTrade] {
        closedTrades
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
    var ticketLimitPrice: Double = 0
    var ticketStopPrice: Double = 0
    var ticketStopLoss: Double = 0
    var ticketTakeProfit: Double = 0
    var ticketRiskAmount: Double = 1_000
    var ticketRiskPercent: Double = 1
    var ticketTimeInForce: SimulatedOrderTimeInForce = .gtc
    var commissionPerOrder: Double = 0
    var slippageTicks: Double = 0
    var chartPlacementEnabled = false
    var ticketIsReplayTrade = false
    var requestNotificationsEnabled = true

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
        ticketLimitPrice = price
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

    func updatePendingOrder(
        _ id: UUID,
        entryPrice: Double? = nil,
        limitPrice: Double? = nil,
        stopPrice: Double? = nil,
        stopLoss: Double? = nil,
        takeProfit: Double? = nil,
        quantity: Double? = nil,
        timeInForce: SimulatedOrderTimeInForce? = nil
    ) {
        guard let index = account.pendingOrders.firstIndex(where: { $0.id == id }) else { return }
        if let entryPrice {
            account.pendingOrders[index].entryPrice = max(0.0001, entryPrice)
        }
        if let limitPrice {
            account.pendingOrders[index].limitPrice = max(0.0001, limitPrice)
        }
        if let stopPrice {
            account.pendingOrders[index].stopPrice = max(0.0001, stopPrice)
        }
        if let stopLoss {
            account.pendingOrders[index].stopLoss = stopLoss > 0 ? stopLoss : nil
        }
        if let takeProfit {
            account.pendingOrders[index].takeProfit = takeProfit > 0 ? takeProfit : nil
        }
        if let quantity {
            account.pendingOrders[index].quantity = max(0.0001, quantity)
        }
        if let timeInForce {
            account.pendingOrders[index].timeInForce = timeInForce
        }
        account.pendingOrders[index].updatedAt = Date()
        upsertOrderHistory(account.pendingOrders[index])
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
            recordAccountSnapshot(on: candle)
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
        let resolvedLimitPrice = ticketLimitPrice > 0 ? ticketLimitPrice : entryPrice
        let resolvedStopPrice = ticketStopPrice > 0 ? ticketStopPrice : entryPrice

        var order = SimulatedOrder(
            symbol: symbol,
            direction: ticketDirection,
            type: ticketOrderType,
            quantity: ticketQuantity,
            entryPrice: entryPrice,
            limitPrice: ticketOrderType == .stopLimit ? resolvedLimitPrice : (ticketOrderType == .limit ? entryPrice : nil),
            stopPrice: ticketOrderType == .stopLimit ? resolvedStopPrice : (ticketOrderType == .stop ? entryPrice : nil),
            stopLoss: ticketStopLoss > 0 ? ticketStopLoss : nil,
            takeProfit: ticketTakeProfit > 0 ? ticketTakeProfit : nil,
            tickSize: futuresBySymbol[symbol]?.tickSize,
            tickValue: futuresBySymbol[symbol]?.tickValue,
            pointValue: futuresBySymbol[symbol]?.pointValue,
            isFutures: futuresBySymbol[symbol] != nil,
            assetClass: instrumentsBySymbol[symbol]?.assetType ?? (futuresBySymbol[symbol] != nil ? "futures" : "stocks"),
            contractSize: instrumentsBySymbol[symbol]?.contractSize,
            isReplayTrade: ticketIsReplayTrade,
            timeInForce: ticketTimeInForce,
            createdAt: latestCandle?.date ?? Date(),
            createdBarIndex: latestCandle?.index ?? 0
        )

        if ticketOrderType == .market, let latestCandle {
            order.status = .filled
            order.filledQuantity = order.quantity
            order.averageFillPrice = executionPrice(for: order, basePrice: latestCandle.close)
            order.commission = commissionPerOrder
            order.slippage = abs((order.averageFillPrice ?? latestCandle.close) - latestCandle.close)
            upsertOrderHistory(order)
            fill(order, at: order.averageFillPrice ?? latestCandle.close, on: latestCandle)
            recordAccountSnapshot(on: latestCandle)
        } else {
            account.pendingOrders.append(order)
            upsertOrderHistory(order)
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
        guard let pending = account.pendingOrders.first(where: { $0.id == order.id }) else { return }
        account.pendingOrders.removeAll { $0.id == order.id }
        var cancelled = pending
        cancelled.status = .cancelled
        cancelled.updatedAt = Date()
        upsertOrderHistory(cancelled)
    }

    func closePosition(_ position: SimulatedPosition, at price: Double, time: Date, barIndex: Int) {
        closePosition(position, quantity: position.quantity, at: price, time: time, barIndex: barIndex, reason: .manual)
    }

    func closePosition(_ position: SimulatedPosition, quantity: Double, at price: Double, time: Date, barIndex: Int, reason: SimulatedExitReason = .manual) {
        close(position, quantity: quantity, at: price, time: time, barIndex: barIndex, reason: reason)
        recordAccountSnapshot(date: time, barIndex: barIndex)
    }

    func closePercentage(of position: SimulatedPosition, percent: Double, at price: Double, time: Date, barIndex: Int) {
        let clampedPercent = min(max(percent, 0), 1)
        closePosition(position, quantity: position.quantity * clampedPercent, at: price, time: time, barIndex: barIndex)
    }

    func closeAllPositions(symbol: String? = nil, at price: Double, time: Date, barIndex: Int) {
        let positions = account.openPositions.filter { position in
            symbol == nil || position.symbol == symbol
        }
        for position in positions {
            close(position, quantity: position.quantity, at: price, time: time, barIndex: barIndex, reason: .manual)
        }
        recordAccountSnapshot(date: time, barIndex: barIndex)
    }

    func flattenAll(at price: Double, time: Date, barIndex: Int) {
        closeAllPositions(at: price, time: time, barIndex: barIndex)
        for order in account.pendingOrders {
            var cancelled = order
            cancelled.status = .cancelled
            cancelled.updatedAt = time
            upsertOrderHistory(cancelled)
        }
        account.pendingOrders.removeAll()
    }

    func modifyPosition(_ id: UUID, stopLoss: Double? = nil, takeProfit: Double? = nil) {
        guard let index = account.openPositions.firstIndex(where: { $0.id == id }) else { return }
        if let stopLoss {
            account.openPositions[index].stopLoss = stopLoss > 0 ? stopLoss : nil
        }
        if let takeProfit {
            account.openPositions[index].takeProfit = takeProfit > 0 ? takeProfit : nil
        }
    }

    func scaleIntoPosition(_ position: SimulatedPosition, quantity: Double, at price: Double, time: Date, barIndex: Int) {
        guard quantity > 0 else { return }
        let order = orderForPositionFill(position, quantity: quantity, price: price, time: time, barIndex: barIndex)
        fill(order, at: price, on: syntheticCandle(price: price, date: time, index: barIndex))
        recordAccountSnapshot(date: time, barIndex: barIndex)
    }

    func scaleOutOfPosition(_ position: SimulatedPosition, quantity: Double, at price: Double, time: Date, barIndex: Int) {
        closePosition(position, quantity: quantity, at: price, time: time, barIndex: barIndex)
    }

    func reversePosition(_ position: SimulatedPosition, at price: Double, time: Date, barIndex: Int) {
        let reverseDirection: TradeDirection = position.direction == .long ? .short : .long
        let order = SimulatedOrder(
            symbol: position.symbol,
            direction: reverseDirection,
            type: .market,
            quantity: position.quantity * 2,
            entryPrice: price,
            stopLoss: nil,
            takeProfit: nil,
            tickSize: position.tickSize,
            tickValue: position.tickValue,
            pointValue: position.pointValue,
            isFutures: position.isFutures,
            assetClass: position.assetClass,
            contractSize: position.contractSize,
            isReplayTrade: position.isReplayTrade,
            timeInForce: .gtc,
            filledQuantity: position.quantity * 2,
            averageFillPrice: price,
            commission: commissionPerOrder,
            createdAt: time,
            createdBarIndex: barIndex,
            status: .filled
        )
        upsertOrderHistory(order)
        fill(order, at: price, on: syntheticCandle(price: price, date: time, index: barIndex))
        recordAccountSnapshot(date: time, barIndex: barIndex)
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
            if order.effectiveTimeInForce == .day && !Calendar.current.isDate(order.createdAt, inSameDayAs: candle.date) {
                expireOrder(order, at: candle.date)
                continue
            }

            let shouldFill: Bool
            let fillPrice: Double
            guard candle.index > order.createdBarIndex else { continue }
            switch order.type {
            case .market:
                shouldFill = true
                fillPrice = candle.open
            case .limit:
                switch order.direction {
                case .long:
                    shouldFill = candle.low <= order.entryPrice
                case .short:
                    shouldFill = candle.high >= order.entryPrice
                }
                fillPrice = order.entryPrice
            case .stop:
                switch order.direction {
                case .long:
                    shouldFill = candle.high >= order.entryPrice
                case .short:
                    shouldFill = candle.low <= order.entryPrice
                }
                fillPrice = executionPrice(for: order, basePrice: order.entryPrice)
            case .stopLimit:
                switch order.direction {
                case .long:
                    shouldFill = candle.high >= order.effectiveStopPrice && candle.low <= order.effectiveLimitPrice
                case .short:
                    shouldFill = candle.low <= order.effectiveStopPrice && candle.high >= order.effectiveLimitPrice
                }
                fillPrice = order.effectiveLimitPrice
            }

            if shouldFill {
                var filledOrder = order
                filledOrder.status = .filled
                filledOrder.filledQuantity = order.quantity
                filledOrder.averageFillPrice = fillPrice
                filledOrder.commission = commissionPerOrder
                filledOrder.slippage = abs(fillPrice - order.entryPrice)
                filledOrder.updatedAt = candle.date
                fill(filledOrder, at: fillPrice, on: candle)
                account.pendingOrders.removeAll { $0.id == order.id }
                upsertOrderHistory(filledOrder)
                cancelOCOSiblings(of: filledOrder, at: candle.date)
                sendPaperNotification(
                    title: "Paper \(order.direction.shortLabel) Filled",
                    body: "\(order.symbol) filled at \(fillPrice.priceText)"
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
                    close(position, quantity: position.quantity, at: stopLoss, time: candle.date, barIndex: candle.index, reason: .stopLoss)
                } else if let takeProfit = position.takeProfit, candle.high >= takeProfit {
                    close(position, quantity: position.quantity, at: takeProfit, time: candle.date, barIndex: candle.index, reason: .takeProfit)
                }
            } else {
                if let stopLoss = position.stopLoss, candle.high >= stopLoss {
                    close(position, quantity: position.quantity, at: stopLoss, time: candle.date, barIndex: candle.index, reason: .stopLoss)
                } else if let takeProfit = position.takeProfit, candle.low <= takeProfit {
                    close(position, quantity: position.quantity, at: takeProfit, time: candle.date, barIndex: candle.index, reason: .takeProfit)
                }
            }
        }
    }

    private func fill(_ order: SimulatedOrder, at price: Double, on candle: Candle) {
        let remainingQuantity = closeOppositePositions(for: order, at: price, on: candle)
        guard remainingQuantity > 0 else {
            return
        }

        if let index = account.openPositions.firstIndex(where: {
            $0.symbol == order.symbol &&
            $0.direction == order.direction &&
            ($0.isReplayTrade == true) == (order.isReplayTrade == true)
        }) {
            let oldPosition = account.openPositions[index]
            let combinedQuantity = oldPosition.quantity + remainingQuantity
            guard combinedQuantity > 0 else { return }
            let averageEntry = ((oldPosition.entryPrice * oldPosition.quantity) + (price * remainingQuantity)) / combinedQuantity
            account.openPositions[index].quantity = combinedQuantity
            account.openPositions[index].entryPrice = averageEntry
            account.openPositions[index].lastPrice = candle.close
            if let stopLoss = order.stopLoss {
                account.openPositions[index].stopLoss = stopLoss
            }
            if let takeProfit = order.takeProfit {
                account.openPositions[index].takeProfit = takeProfit
            }
            account.cashBalance -= marginImpact(
                symbol: oldPosition.symbol,
                direction: oldPosition.direction,
                quantity: remainingQuantity,
                entryPrice: price,
                tickSize: oldPosition.tickSize,
                tickValue: oldPosition.tickValue,
                pointValue: oldPosition.pointValue,
                isFutures: oldPosition.isFutures,
                contractSize: oldPosition.contractSize
            ) + commissionPerOrder
            return
        }

        let position = SimulatedPosition(
            symbol: order.symbol,
            direction: order.direction,
            quantity: remainingQuantity,
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
        account.cashBalance -= marginImpact(for: position) + commissionPerOrder
    }

    private func paperProcessingKey(symbol: String, isReplayMode: Bool) -> String {
        "\(symbol)|\(isReplayMode ? "replay" : "live")"
    }

    private func close(_ position: SimulatedPosition, quantity requestedQuantity: Double, at price: Double, time: Date, barIndex: Int, reason: SimulatedExitReason) {
        guard let index = account.openPositions.firstIndex(where: { $0.id == position.id }) else { return }
        let currentPosition = account.openPositions[index]
        let closeQuantity = min(max(requestedQuantity, 0), currentPosition.quantity)
        guard closeQuantity > 0 else { return }
        let profitLoss = profitLoss(
            direction: currentPosition.direction,
            entryPrice: currentPosition.entryPrice,
            exitPrice: price,
            quantity: closeQuantity,
            tickSize: currentPosition.tickSize,
            tickValue: currentPosition.tickValue,
            isFutures: currentPosition.isFutures == true,
            assetClass: currentPosition.assetClass,
            contractSize: currentPosition.contractSize
        )
        let commission = commissionPerOrder
        let netProfitLoss = profitLoss - commission

        let units = closeQuantity * (currentPosition.contractSize ?? 1)
        let basis = currentPosition.isFutures == true ? currentPosition.entryPrice * (currentPosition.pointValue ?? 1) * closeQuantity : currentPosition.entryPrice * units
        let percentReturn = basis == 0 ? 0 : (netProfitLoss / basis) * 100
        if closeQuantity >= currentPosition.quantity {
            account.openPositions.remove(at: index)
        } else {
            account.openPositions[index].quantity = currentPosition.quantity - closeQuantity
            account.openPositions[index].lastPrice = price
        }

        let releasedMargin = marginImpact(
            symbol: currentPosition.symbol,
            direction: currentPosition.direction,
            quantity: closeQuantity,
            entryPrice: currentPosition.entryPrice,
            tickSize: currentPosition.tickSize,
            tickValue: currentPosition.tickValue,
            pointValue: currentPosition.pointValue,
            isFutures: currentPosition.isFutures,
            contractSize: currentPosition.contractSize
        )
        account.cashBalance += releasedMargin + netProfitLoss
        account.closedTrades.insert(
            SimulatedTrade(
                id: UUID(),
                symbol: currentPosition.symbol,
                direction: currentPosition.direction,
                entryTime: currentPosition.entryTime,
                exitTime: time,
                entryBarIndex: currentPosition.entryBarIndex,
                exitBarIndex: barIndex,
                entryPrice: currentPosition.entryPrice,
                exitPrice: price,
                quantity: closeQuantity,
                stopLoss: currentPosition.stopLoss,
                takeProfit: currentPosition.takeProfit,
                tickSize: currentPosition.tickSize,
                tickValue: currentPosition.tickValue,
                pointValue: currentPosition.pointValue,
                isFutures: currentPosition.isFutures,
                assetClass: currentPosition.assetClass,
                contractSize: currentPosition.contractSize,
                commission: commission,
                slippage: nil,
                profitLoss: netProfitLoss,
                percentReturn: percentReturn,
                exitReason: reason
            ),
            at: 0
        )
        sendPaperNotification(
            title: "Paper Trade \(reason.rawValue)",
            body: "\(currentPosition.symbol) closed at \(price.priceText) · \(netProfitLoss.signedMoneyText)"
        )
    }

    private func marginImpact(for position: SimulatedPosition) -> Double {
        marginImpact(
            symbol: position.symbol,
            direction: position.direction,
            quantity: position.quantity,
            entryPrice: position.entryPrice,
            tickSize: position.tickSize,
            tickValue: position.tickValue,
            pointValue: position.pointValue,
            isFutures: position.isFutures,
            contractSize: position.contractSize
        )
    }

    private func marginImpact(
        symbol: String,
        direction: TradeDirection,
        quantity: Double,
        entryPrice: Double,
        tickSize: Double?,
        tickValue: Double?,
        pointValue: Double?,
        isFutures: Bool?,
        contractSize: Double?
    ) -> Double {
        if isFutures == true {
            return entryPrice * (pointValue ?? 1) * quantity * 0.05
        }
        return entryPrice * quantity * (contractSize ?? 1) * 0.5
    }

    private func closeOppositePositions(for order: SimulatedOrder, at price: Double, on candle: Candle) -> Double {
        let oppositeDirection: TradeDirection = order.direction == .long ? .short : .long
        var remaining = order.quantity
        let matches = account.openPositions.filter {
            $0.symbol == order.symbol &&
            $0.direction == oppositeDirection &&
            ($0.isReplayTrade == true) == (order.isReplayTrade == true)
        }

        for position in matches where remaining > 0 {
            let closeQuantity = min(remaining, position.quantity)
            close(position, quantity: closeQuantity, at: price, time: candle.date, barIndex: candle.index, reason: .manual)
            remaining -= closeQuantity
        }

        return max(0, remaining)
    }

    private func upsertOrderHistory(_ order: SimulatedOrder) {
        if let index = account.orderHistory.firstIndex(where: { $0.id == order.id }) {
            account.orderHistory[index] = order
        } else {
            account.orderHistory.insert(order, at: 0)
        }
    }

    private func expireOrder(_ order: SimulatedOrder, at date: Date) {
        account.pendingOrders.removeAll { $0.id == order.id }
        var expired = order
        expired.status = .expired
        expired.updatedAt = date
        upsertOrderHistory(expired)
    }

    private func cancelOCOSiblings(of order: SimulatedOrder, at date: Date) {
        guard let groupID = order.ocoGroupID else { return }
        let siblings = account.pendingOrders.filter { $0.ocoGroupID == groupID && $0.id != order.id }
        for sibling in siblings {
            var cancelled = sibling
            cancelled.status = .cancelled
            cancelled.updatedAt = date
            upsertOrderHistory(cancelled)
        }
        account.pendingOrders.removeAll { $0.ocoGroupID == groupID && $0.id != order.id }
    }

    private func executionPrice(for order: SimulatedOrder, basePrice: Double) -> Double {
        guard slippageTicks > 0 else { return basePrice }
        let tick = order.tickSize ?? instrumentsBySymbol[order.symbol]?.tickSize ?? 0.01
        let adjustment = tick * slippageTicks
        switch order.direction {
        case .long:
            return basePrice + adjustment
        case .short:
            return basePrice - adjustment
        }
    }

    private func recordAccountSnapshot(on candle: Candle) {
        recordAccountSnapshot(date: candle.date, barIndex: candle.index)
    }

    private func recordAccountSnapshot(date: Date, barIndex: Int) {
        let snapshot = PaperAccountSnapshot(
            date: date,
            barIndex: barIndex,
            cashBalance: account.cashBalance,
            equity: account.equity,
            portfolioValue: account.portfolioValue,
            realizedPL: account.realizedPL,
            unrealizedPL: account.unrealizedPL
        )
        if let last = account.equityHistory.last, last.barIndex == barIndex {
            account.equityHistory[account.equityHistory.count - 1] = snapshot
        } else {
            account.equityHistory.append(snapshot)
        }
    }

    private func orderForPositionFill(_ position: SimulatedPosition, quantity: Double, price: Double, time: Date, barIndex: Int) -> SimulatedOrder {
        SimulatedOrder(
            symbol: position.symbol,
            direction: position.direction,
            type: .market,
            quantity: quantity,
            entryPrice: price,
            stopLoss: position.stopLoss,
            takeProfit: position.takeProfit,
            tickSize: position.tickSize,
            tickValue: position.tickValue,
            pointValue: position.pointValue,
            isFutures: position.isFutures,
            assetClass: position.assetClass,
            contractSize: position.contractSize,
            isReplayTrade: position.isReplayTrade,
            timeInForce: .gtc,
            filledQuantity: quantity,
            averageFillPrice: price,
            commission: commissionPerOrder,
            createdAt: time,
            createdBarIndex: barIndex,
            status: .filled
        )
    }

    private func syntheticCandle(price: Double, date: Date, index: Int) -> Candle {
        Candle(index: index, date: date, open: price, high: price, low: price, close: price, volume: 0)
    }

    private func sendPaperNotification(title: String, body: String) {
        guard requestNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
