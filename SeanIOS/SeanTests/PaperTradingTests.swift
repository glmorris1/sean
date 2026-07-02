import XCTest
@testable import GhostTrade

@MainActor
final class PaperTradingTests: XCTestCase {
    private func makeService(_ name: String = #function) -> PaperTradingService {
        let service = PaperTradingService()
        service.setUserID("paper-tests-\(name)-\(UUID().uuidString)")
        service.resetAccount()
        service.requestNotificationsEnabled = false
        return service
    }

    private func candle(_ index: Int, open: Double = 100, high: Double = 100, low: Double = 100, close: Double = 100) -> Candle {
        Candle(
            index: index,
            date: Date(timeIntervalSince1970: TimeInterval(index * 60)),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: 1_000
        )
    }

    func testMarketOrderExecution() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .market
        service.ticketQuantity = 10

        let order = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        XCTAssertNotNil(order)
        XCTAssertEqual(service.account.openPositions.count, 1)
        XCTAssertEqual(service.account.openPositions[0].quantity, 10)
        XCTAssertEqual(service.account.openPositions[0].entryPrice, 100)
        XCTAssertEqual(service.account.orderHistory.first?.status, .filled)
    }

    func testLimitOrderExecution() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .limit
        service.ticketQuantity = 5
        service.ticketEntryPrice = 95

        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))
        service.processVisibleCandles([
            candle(0, high: 101, low: 99, close: 100),
            candle(1, high: 98, low: 94, close: 96)
        ], symbol: "AAPL")

        XCTAssertTrue(service.account.pendingOrders.isEmpty)
        XCTAssertEqual(service.account.openPositions.count, 1)
        XCTAssertEqual(service.account.openPositions[0].entryPrice, 95)
        XCTAssertEqual(service.account.orderHistory.first?.status, .filled)
    }

    func testStopOrderExecution() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .stop
        service.ticketQuantity = 2
        service.ticketEntryPrice = 105

        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))
        service.processVisibleCandles([
            candle(0, high: 101, low: 99, close: 100),
            candle(1, high: 106, low: 102, close: 105)
        ], symbol: "AAPL")

        XCTAssertTrue(service.account.pendingOrders.isEmpty)
        XCTAssertEqual(service.account.openPositions.count, 1)
        XCTAssertEqual(service.account.openPositions[0].entryPrice, 105)
    }

    func testLongProfitAndLoss() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        service.processVisibleCandles([candle(1, high: 111, low: 99, close: 110)], symbol: "AAPL")
        XCTAssertEqual(service.account.unrealizedPL, 100, accuracy: 0.0001)

        service.closePosition(service.account.openPositions[0], at: 110, time: candle(2).date, barIndex: 2)
        XCTAssertEqual(service.account.realizedPL, 100, accuracy: 0.0001)
    }

    func testShortProfitAndLoss() {
        let service = makeService()
        service.ticketDirection = .short
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        service.processVisibleCandles([candle(1, high: 101, low: 89, close: 90)], symbol: "AAPL")
        XCTAssertEqual(service.account.unrealizedPL, 100, accuracy: 0.0001)

        service.closePosition(service.account.openPositions[0], at: 90, time: candle(2).date, barIndex: 2)
        XCTAssertEqual(service.account.realizedPL, 100, accuracy: 0.0001)
    }

    func testPartialExits() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        service.closePosition(service.account.openPositions[0], quantity: 4, at: 110, time: candle(1).date, barIndex: 1)

        XCTAssertEqual(service.account.openPositions[0].quantity, 6)
        XCTAssertEqual(service.account.closedTrades[0].quantity, 4)
        XCTAssertEqual(service.account.realizedPL, 40, accuracy: 0.0001)
    }

    func testScalingIn() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        service.scaleIntoPosition(service.account.openPositions[0], quantity: 10, at: 110, time: candle(1).date, barIndex: 1)

        XCTAssertEqual(service.account.openPositions.count, 1)
        XCTAssertEqual(service.account.openPositions[0].quantity, 20)
        XCTAssertEqual(service.account.openPositions[0].entryPrice, 105, accuracy: 0.0001)
    }

    func testScalingOut() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        service.scaleOutOfPosition(service.account.openPositions[0], quantity: 3, at: 108, time: candle(1).date, barIndex: 1)

        XCTAssertEqual(service.account.openPositions[0].quantity, 7)
        XCTAssertEqual(service.account.realizedPL, 24, accuracy: 0.0001)
    }

    func testReversingPosition() {
        let service = makeService()
        service.ticketDirection = .long
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        service.reversePosition(service.account.openPositions[0], at: 90, time: candle(1).date, barIndex: 1)

        XCTAssertEqual(service.account.openPositions.count, 1)
        XCTAssertEqual(service.account.openPositions[0].direction, .short)
        XCTAssertEqual(service.account.openPositions[0].quantity, 10)
        XCTAssertEqual(service.account.realizedPL, -100, accuracy: 0.0001)
    }

    func testClosingAllPositions() {
        let service = makeService()
        service.ticketOrderType = .market
        service.ticketQuantity = 10
        service.ticketDirection = .long
        _ = service.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))
        _ = service.submitOrder(symbol: "MSFT", latestCandle: candle(0, close: 100))

        service.closeAllPositions(at: 105, time: candle(1).date, barIndex: 1)

        XCTAssertTrue(service.account.openPositions.isEmpty)
        XCTAssertEqual(service.account.closedTrades.count, 2)
        XCTAssertEqual(service.account.realizedPL, 100, accuracy: 0.0001)
    }

    func testPersistenceAfterAppRestart() {
        let userID = "paper-tests-persistence-\(UUID().uuidString)"
        let first = PaperTradingService()
        first.setUserID(userID)
        first.resetAccount()
        first.requestNotificationsEnabled = false
        first.ticketDirection = .long
        first.ticketOrderType = .market
        first.ticketQuantity = 7
        _ = first.submitOrder(symbol: "AAPL", latestCandle: candle(0, close: 100))

        let second = PaperTradingService()
        second.setUserID(userID)
        second.requestNotificationsEnabled = false

        XCTAssertEqual(second.account.openPositions.count, 1)
        XCTAssertEqual(second.account.openPositions[0].quantity, 7)
        XCTAssertEqual(second.account.openPositions[0].entryPrice, 100)
    }
}
