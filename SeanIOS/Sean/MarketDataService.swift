import Foundation

enum MarketDataError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noRows
    case unsupportedInterval

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build the market data URL."
        case .invalidResponse:
            return "The market data response was not readable."
        case .noRows:
            return "No historical prices were returned for this symbol."
        case .unsupportedInterval:
            return "This interval needs a real-time market data provider."
        }
    }
}

struct FuturesCatalog {
    private struct RootSpec {
        let root: String
        let displayName: String
        let exchange: String
        let tickSize: Double
        let tickValue: Double
        let pointValue: Double
        let providerSymbol: String
    }

    private static let roots: [RootSpec] = [
        RootSpec(root: "MES", displayName: "Micro E-mini S&P 500 Futures", exchange: "CME", tickSize: 0.25, tickValue: 1.25, pointValue: 5, providerSymbol: "MES=F"),
        RootSpec(root: "ES", displayName: "E-mini S&P 500 Futures", exchange: "CME", tickSize: 0.25, tickValue: 12.50, pointValue: 50, providerSymbol: "ES=F"),
        RootSpec(root: "NQ", displayName: "E-mini Nasdaq 100 Futures", exchange: "CME", tickSize: 0.25, tickValue: 5.00, pointValue: 20, providerSymbol: "NQ=F"),
        RootSpec(root: "MNQ", displayName: "Micro E-mini Nasdaq 100 Futures", exchange: "CME", tickSize: 0.25, tickValue: 0.50, pointValue: 2, providerSymbol: "MNQ=F"),
        RootSpec(root: "YM", displayName: "E-mini Dow Futures", exchange: "CBOT", tickSize: 1, tickValue: 5, pointValue: 5, providerSymbol: "YM=F"),
        RootSpec(root: "MYM", displayName: "Micro E-mini Dow Futures", exchange: "CBOT", tickSize: 1, tickValue: 0.50, pointValue: 0.5, providerSymbol: "MYM=F"),
        RootSpec(root: "RTY", displayName: "E-mini Russell 2000 Futures", exchange: "CME", tickSize: 0.10, tickValue: 5, pointValue: 50, providerSymbol: "RTY=F"),
        RootSpec(root: "M2K", displayName: "Micro E-mini Russell 2000 Futures", exchange: "CME", tickSize: 0.10, tickValue: 0.50, pointValue: 5, providerSymbol: "M2K=F")
    ]

    private static let monthCodes: [(code: String, name: String, month: Int)] = [
        ("H", "March", 3),
        ("M", "June", 6),
        ("U", "September", 9),
        ("Z", "December", 12)
    ]

    static func search(matching query: String) -> [MarketSymbol] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return [] }

        var results: [FuturesSymbol] = []
        for root in roots where root.root.hasPrefix(normalized) || normalized.hasPrefix(root.root) {
            results.append(continuous(root, monthIndex: 1))
            results.append(continuous(root, monthIndex: 2))
            results.append(contentsOf: datedContracts(for: root).filter { contract in
                contract.symbol.hasPrefix(normalized) || normalized == root.root
            })
        }

        return results.map(\.marketSymbol)
    }

    static func symbol(for ticker: String) -> FuturesSymbol? {
        let normalized = ticker.uppercased()
        return search(matching: normalized).first { $0.ticker.uppercased() == normalized }?.futures
    }

    private static func continuous(_ root: RootSpec, monthIndex: Int) -> FuturesSymbol {
        FuturesSymbol(
            symbol: "\(root.root)\(monthIndex)!",
            rootSymbol: root.root,
            displayName: "\(root.displayName) Continuous Contract, \(monthIndex == 1 ? "Front Month" : "Second Month")",
            exchange: root.exchange,
            assetType: "futures",
            contractType: "continuous",
            contractMonth: nil,
            contractYear: nil,
            isContinuous: true,
            continuousMonthIndex: monthIndex,
            tickSize: root.tickSize,
            tickValue: root.tickValue,
            pointValue: root.pointValue,
            currency: "USD",
            dataProviderSymbol: root.providerSymbol,
            availableTimeframes: ["1m", "2m", "3m", "5m", "10m", "15m", "30m", "1h", "4h", "1 day"]
        )
    }

    private static func datedContracts(for root: RootSpec) -> [FuturesSymbol] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = Array((currentYear - 1)...(currentYear + 2))
        return years.flatMap { year in
            monthCodes.map { code, monthName, _ in
                FuturesSymbol(
                    symbol: "\(root.root)\(code)\(year)",
                    rootSymbol: root.root,
                    displayName: "\(root.displayName) \(monthName) \(year) Contract",
                    exchange: root.exchange,
                    assetType: "futures",
                    contractType: "dated",
                    contractMonth: monthName,
                    contractYear: year,
                    isContinuous: false,
                    continuousMonthIndex: nil,
                    tickSize: root.tickSize,
                    tickValue: root.tickValue,
                    pointValue: root.pointValue,
                    currency: "USD",
                    dataProviderSymbol: "\(root.root)\(code)\(String(year).suffix(2)).\(root.exchange)",
                    availableTimeframes: ["1m", "5m", "15m", "1h", "1 day"]
                )
            }
        }
    }
}

struct InstrumentCatalog {
    private static let defaultTimeframes = ["1m", "2m", "3m", "5m", "10m", "15m", "30m", "1h", "4h", "1 day"]

    private static let instruments: [InstrumentMetadata] = [
        InstrumentMetadata(symbol: "XAUUSD", displayName: "Gold / U.S. Dollar", assetType: "spot_metal", baseAsset: "XAU", quoteAsset: "USD", exchange: "OTC", provider: "OANDA", providerSymbol: "XAU_USD", tickSize: 0.01, pipSize: 0.01, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "XAUEUR", displayName: "Gold / Euro", assetType: "spot_metal", baseAsset: "XAU", quoteAsset: "EUR", exchange: "OTC", provider: "OANDA", providerSymbol: "XAU_EUR", tickSize: 0.01, pipSize: 0.01, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "XAUGBP", displayName: "Gold / British Pound", assetType: "spot_metal", baseAsset: "XAU", quoteAsset: "GBP", exchange: "OTC", provider: "OANDA", providerSymbol: "XAU_GBP", tickSize: 0.01, pipSize: 0.01, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "XAGUSD", displayName: "Silver / U.S. Dollar", assetType: "spot_metal", baseAsset: "XAG", quoteAsset: "USD", exchange: "OTC", provider: "OANDA", providerSymbol: "XAG_USD", tickSize: 0.001, pipSize: 0.001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "XAGEUR", displayName: "Silver / Euro", assetType: "spot_metal", baseAsset: "XAG", quoteAsset: "EUR", exchange: "OTC", provider: "OANDA", providerSymbol: "XAG_EUR", tickSize: 0.001, pipSize: 0.001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "EURUSD", displayName: "Euro / U.S. Dollar", assetType: "forex", baseAsset: "EUR", quoteAsset: "USD", exchange: "OTC", provider: "OANDA", providerSymbol: "EUR_USD", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "GBPUSD", displayName: "British Pound / U.S. Dollar", assetType: "forex", baseAsset: "GBP", quoteAsset: "USD", exchange: "OTC", provider: "OANDA", providerSymbol: "GBP_USD", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "USDJPY", displayName: "U.S. Dollar / Japanese Yen", assetType: "forex", baseAsset: "USD", quoteAsset: "JPY", exchange: "OTC", provider: "OANDA", providerSymbol: "USD_JPY", tickSize: 0.001, pipSize: 0.01, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "EURJPY", displayName: "Euro / Japanese Yen", assetType: "forex", baseAsset: "EUR", quoteAsset: "JPY", exchange: "OTC", provider: "OANDA", providerSymbol: "EUR_JPY", tickSize: 0.001, pipSize: 0.01, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "EURGBP", displayName: "Euro / British Pound", assetType: "forex", baseAsset: "EUR", quoteAsset: "GBP", exchange: "OTC", provider: "OANDA", providerSymbol: "EUR_GBP", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "EURAUD", displayName: "Euro / Australian Dollar", assetType: "forex", baseAsset: "EUR", quoteAsset: "AUD", exchange: "OTC", provider: "OANDA", providerSymbol: "EUR_AUD", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "AUDUSD", displayName: "Australian Dollar / U.S. Dollar", assetType: "forex", baseAsset: "AUD", quoteAsset: "USD", exchange: "OTC", provider: "OANDA", providerSymbol: "AUD_USD", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "NZDUSD", displayName: "New Zealand Dollar / U.S. Dollar", assetType: "forex", baseAsset: "NZD", quoteAsset: "USD", exchange: "OTC", provider: "OANDA", providerSymbol: "NZD_USD", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "USDCAD", displayName: "U.S. Dollar / Canadian Dollar", assetType: "forex", baseAsset: "USD", quoteAsset: "CAD", exchange: "OTC", provider: "OANDA", providerSymbol: "USD_CAD", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "USDCHF", displayName: "U.S. Dollar / Swiss Franc", assetType: "forex", baseAsset: "USD", quoteAsset: "CHF", exchange: "OTC", provider: "OANDA", providerSymbol: "USD_CHF", tickSize: 0.00001, pipSize: 0.0001, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "GBPJPY", displayName: "British Pound / Japanese Yen", assetType: "forex", baseAsset: "GBP", quoteAsset: "JPY", exchange: "OTC", provider: "OANDA", providerSymbol: "GBP_JPY", tickSize: 0.001, pipSize: 0.01, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "BTCUSD", displayName: "Bitcoin / U.S. Dollar", assetType: "crypto", baseAsset: "BTC", quoteAsset: "USD", exchange: "Crypto", provider: "Yahoo Finance", providerSymbol: "BTC-USD", tickSize: 0.01, pipSize: nil, contractSize: nil, availableTimeframes: defaultTimeframes),
        InstrumentMetadata(symbol: "ETHUSD", displayName: "Ethereum / U.S. Dollar", assetType: "crypto", baseAsset: "ETH", quoteAsset: "USD", exchange: "Crypto", provider: "Yahoo Finance", providerSymbol: "ETH-USD", tickSize: 0.01, pipSize: nil, contractSize: nil, availableTimeframes: defaultTimeframes)
    ]

    static func search(matching query: String) -> [MarketSymbol] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return [] }
        let lowercase = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return instruments
            .filter { instrument in
                instrument.symbol.uppercased().contains(normalized) ||
                instrument.baseAsset.uppercased().contains(normalized) ||
                instrument.quoteAsset.uppercased().contains(normalized) ||
                instrument.providerSymbol.uppercased().contains(normalized) ||
                instrument.displayName.lowercased().contains(lowercase) ||
                instrument.assetType.lowercased().contains(lowercase) ||
                (lowercase == "gold" && instrument.baseAsset == "XAU") ||
                (lowercase == "silver" && instrument.baseAsset == "XAG") ||
                (lowercase == "metals" && instrument.assetType == "spot_metal")
            }
            .map(\.marketSymbol)
    }

    static func instrument(for ticker: String) -> InstrumentMetadata? {
        let normalized = ticker.uppercased()
        return instruments.first { $0.symbol.uppercased() == normalized }
    }
}

struct MarketDataService {
    static func searchSymbols(matching query: String) async throws -> [MarketSymbol] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let futuresResults = FuturesCatalog.search(matching: trimmed)
        let catalogResults = InstrumentCatalog.search(matching: trimmed)
        let backendResults = (try? await searchBackendSymbols(matching: trimmed)) ?? []

        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "quotesCount", value: "20"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "listsCount", value: "0")
        ]

        guard let url = components?.url else { throw MarketDataError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw MarketDataError.invalidResponse
            }

            let payload = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
            let equityResults: [MarketSymbol] = payload.quotes.compactMap { quote -> MarketSymbol? in
                guard let symbol = quote.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !symbol.isEmpty,
                      let quoteType = quote.quoteType?.uppercased(),
                      ["EQUITY", "ETF"].contains(quoteType) else {
                    return nil
                }

                return MarketSymbol(
                    ticker: symbol,
                    name: quote.shortname ?? quote.longname ?? quote.name ?? symbol,
                    exchange: quote.exchange ?? quote.exchDisp ?? "US",
                    assetClass: quoteType == "ETF" ? "etf" : "stocks",
                    last: quote.regularMarketPrice ?? 0,
                    changePercent: quote.regularMarketChangePercent ?? 0,
                    volume: "--"
                )
            }
            return mergedSymbols(futuresResults + catalogResults + backendResults + equityResults)
        } catch {
            let fallbackResults = mergedSymbols(futuresResults + catalogResults + backendResults)
            if !fallbackResults.isEmpty {
                return fallbackResults
            }
            throw error
        }
    }

    static func fetchCandles(for symbol: MarketSymbol, interval: CandleInterval) async throws -> [Candle] {
        if interval == .fifteenSeconds {
            throw MarketDataError.unsupportedInterval
        }

        if symbol.isFutures {
            return try await fetchFuturesCandles(for: symbol, interval: interval)
        }

        if symbol.isProviderBackedInstrument {
            return try await fetchInstrumentCandles(for: symbol, interval: interval)
        }

        if interval == .oneDay {
            return try await fetchDailyCandles(for: symbol)
        }

        return try await fetchIntradayCandles(for: symbol, interval: interval)
    }

    private static func mergedSymbols(_ symbols: [MarketSymbol]) -> [MarketSymbol] {
        var seen = Set<String>()
        var merged: [MarketSymbol] = []
        for symbol in symbols {
            let key = symbol.ticker.uppercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(symbol)
        }
        return merged
    }

    private static func searchBackendSymbols(matching query: String) async throws -> [MarketSymbol] {
        guard var components = backendComponents(userDefaultsKey: "sean.symbolBackendBaseURL") else {
            return []
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/symbols/search"
        }

        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw MarketDataError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode([NormalizedSymbolResult].self, from: data)
        return payload.map(\.marketSymbol)
    }

    static func fetchDailyCandles(for symbol: MarketSymbol) async throws -> [Candle] {
        var components = URLComponents(string: "https://api.nasdaq.com/api/quote/\(symbol.ticker)/historical")
        let today = Date()
        let start = Calendar.current.date(byAdding: .year, value: -40, to: today) ?? today

        components?.queryItems = [
            URLQueryItem(name: "assetclass", value: symbol.assetClass),
            URLQueryItem(name: "fromdate", value: apiDateFormatter.string(from: start)),
            URLQueryItem(name: "todate", value: apiDateFormatter.string(from: today)),
            URLQueryItem(name: "limit", value: "9999")
        ]

        guard let url = components?.url else { throw MarketDataError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let payload = try JSONDecoder().decode(NasdaqHistoricalResponse.self, from: data)
        let rows = payload.data?.tradesTable?.rows ?? []
        let parsed = rows.compactMap(parseRow).sorted { $0.date < $1.date }

        guard !parsed.isEmpty else { throw MarketDataError.noRows }

        return parsed.enumerated().map { index, row in
            Candle(
                index: index,
                date: row.date,
                open: row.open,
                high: row.high,
                low: row.low,
                close: row.close,
                volume: row.volume
            )
        }
    }

    private static func fetchFuturesCandles(for symbol: MarketSymbol, interval: CandleInterval) async throws -> [Candle] {
        guard let futures = symbol.futures ?? FuturesCatalog.symbol(for: symbol.ticker) else {
            throw MarketDataError.noRows
        }

        if let backendCandles = try? await fetchBackendFuturesCandles(for: futures, interval: interval),
           !backendCandles.isEmpty {
            return backendCandles
        }

        guard futures.isContinuous else {
            throw MarketDataError.noRows
        }

        return try await fetchYahooFuturesCandles(providerSymbol: futures.dataProviderSymbol, interval: interval)
    }

    private static func fetchInstrumentCandles(for symbol: MarketSymbol, interval: CandleInterval) async throws -> [Candle] {
        guard let instrument = symbol.instrument ?? InstrumentCatalog.instrument(for: symbol.ticker) else {
            throw MarketDataError.noRows
        }

        if let backendCandles = try? await fetchBackendInstrumentCandles(for: instrument, interval: interval),
           !backendCandles.isEmpty {
            return backendCandles
        }

        if let twelveDataCandles = try? await fetchTwelveDataCandles(for: instrument, interval: interval),
           !twelveDataCandles.isEmpty {
            return twelveDataCandles
        }

        if let traderMadeCandles = try? await fetchTraderMadeCandles(for: instrument, interval: interval),
           !traderMadeCandles.isEmpty {
            return traderMadeCandles
        }

        var lastError: Error?
        for providerSymbol in yahooProviderSymbols(for: instrument) {
            do {
                return try await fetchYahooProviderCandles(providerSymbol: providerSymbol, interval: interval, includePrePost: true)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? MarketDataError.noRows
    }

    private static func fetchTwelveDataCandles(for instrument: InstrumentMetadata, interval: CandleInterval) async throws -> [Candle] {
        guard let apiKey = configuredValue(defaultsKey: "sean.twelveDataAPIKey", infoKey: "TWELVE_DATA_API_KEY") else {
            throw MarketDataError.invalidURL
        }

        let symbol = twelveDataSymbol(for: instrument)
        var components = URLComponents(string: "https://api.twelvedata.com/time_series")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: twelveDataInterval(for: interval)),
            URLQueryItem(name: "outputsize", value: twelveDataOutputSize(for: interval)),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components?.url else { throw MarketDataError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let payload = try JSONDecoder().decode(TwelveDataTimeSeriesResponse.self, from: data)
        guard payload.status?.lowercased() != "error" else {
            throw MarketDataError.invalidResponse
        }

        let rows = (payload.values ?? []).compactMap { value -> ParsedCandle? in
            guard let date = twelveDataFormatter.date(from: value.datetime),
                  let open = Double(value.open),
                  let high = Double(value.high),
                  let low = Double(value.low),
                  let close = Double(value.close) else {
                return nil
            }
            return ParsedCandle(date: date, open: open, high: high, low: low, close: close, volume: Double(value.volume ?? "0") ?? 0)
        }
        let normalized = normalize(rows, interval: interval)
        return try candles(from: normalized)
    }

    private static func fetchTraderMadeCandles(for instrument: InstrumentMetadata, interval: CandleInterval) async throws -> [Candle] {
        guard let apiKey = configuredValue(defaultsKey: "sean.traderMadeAPIKey", infoKey: "TRADERMADE_API_KEY") else {
            throw MarketDataError.invalidURL
        }

        let end = Date()
        let start = traderMadeStartDate(for: interval, endingAt: end)
        var components = URLComponents(string: "https://marketdata.tradermade.com/api/v1/timeseries")
        components?.queryItems = [
            URLQueryItem(name: "currency", value: instrument.symbol),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "start_date", value: apiDateFormatter.string(from: start)),
            URLQueryItem(name: "end_date", value: apiDateFormatter.string(from: end)),
            URLQueryItem(name: "format", value: "records"),
            URLQueryItem(name: "interval", value: traderMadeInterval(for: interval))
        ]

        guard let url = components?.url else { throw MarketDataError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let payload = try JSONDecoder().decode(TraderMadeTimeSeriesResponse.self, from: data)
        let rows = (payload.quotes ?? []).compactMap { quote -> ParsedCandle? in
            guard let date = traderMadeFormatter.date(from: quote.date) ?? traderMadeDateOnlyFormatter.date(from: quote.date) else {
                return nil
            }
            let open = quote.open ?? quote.close
            let high = quote.high ?? max(open, quote.close)
            let low = quote.low ?? min(open, quote.close)
            return ParsedCandle(date: date, open: open, high: high, low: low, close: quote.close, volume: 0)
        }
        let normalized = normalize(rows, interval: interval)
        return try candles(from: normalized)
    }

    private static func fetchBackendInstrumentCandles(for instrument: InstrumentMetadata, interval: CandleInterval) async throws -> [Candle] {
        guard var components = backendComponents(userDefaultsKey: "sean.marketDataBackendBaseURL") else {
            throw MarketDataError.invalidURL
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/candles"
        }

        components.queryItems = [
            URLQueryItem(name: "symbol", value: instrument.symbol),
            URLQueryItem(name: "assetType", value: instrument.assetType),
            URLQueryItem(name: "timeframe", value: backendTimeframe(for: interval))
        ]
        components.queryItems?.append(contentsOf: fullHistoryBackendQueryItems())

        guard let url = components.url else { throw MarketDataError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode([NormalizedMarketCandle].self, from: data)
        let rows = payload.sorted { $0.timestamp < $1.timestamp }
        guard !rows.isEmpty else { throw MarketDataError.noRows }

        return rows.enumerated().map { index, row in
            Candle(
                index: index,
                date: row.timestamp,
                open: row.open,
                high: row.high,
                low: row.low,
                close: row.close,
                volume: row.volume
            )
        }
    }

    private static func fetchBackendFuturesCandles(for futures: FuturesSymbol, interval: CandleInterval) async throws -> [Candle] {
        guard var components = backendComponents(userDefaultsKey: "sean.futuresBackendBaseURL") else {
            throw MarketDataError.invalidURL
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/candles"
        }

        components.queryItems = [
            URLQueryItem(name: "symbol", value: futures.symbol),
            URLQueryItem(name: "exchange", value: futures.exchange),
            URLQueryItem(name: "timeframe", value: backendTimeframe(for: interval))
        ]
        components.queryItems?.append(contentsOf: fullHistoryBackendQueryItems())

        guard let url = components.url else { throw MarketDataError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode([NormalizedFuturesCandle].self, from: data)
        let rows = payload.sorted { $0.timestamp < $1.timestamp }
        guard !rows.isEmpty else { throw MarketDataError.noRows }

        return rows.enumerated().map { index, row in
            Candle(
                index: index,
                date: row.timestamp,
                open: row.open,
                high: row.high,
                low: row.low,
                close: row.close,
                volume: row.volume
            )
        }
    }

    private static func fetchYahooFuturesCandles(providerSymbol: String, interval: CandleInterval) async throws -> [Candle] {
        try await fetchYahooProviderCandles(providerSymbol: providerSymbol, interval: interval, includePrePost: true)
    }

    private static func fetchYahooProviderCandles(providerSymbol: String, interval: CandleInterval, includePrePost: Bool) async throws -> [Candle] {
        let baseInterval = yahooBaseInterval(for: interval)
        let range = yahooRange(for: interval)
        let encodedSymbol = providerSymbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? providerSymbol
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encodedSymbol)")

        components?.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: baseInterval),
            URLQueryItem(name: "includePrePost", value: includePrePost ? "true" : "false"),
            URLQueryItem(name: "events", value: "history")
        ]

        guard let url = components?.url else { throw MarketDataError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let payload = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard let result = payload.chart.result?.first,
              let quote = result.indicators.quote.first else {
            throw MarketDataError.noRows
        }

        let rows = result.timestamp.enumerated().compactMap { index, timestamp -> ParsedCandle? in
            guard index < quote.open.count,
                  let open = quote.open[index],
                  let high = quote.high[index],
                  let low = quote.low[index],
                  let close = quote.close[index] else {
                return nil
            }

            let volume = index < quote.volume.count ? Double(quote.volume[index] ?? 0) : 0
            return ParsedCandle(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        }

        let normalized = normalize(rows, interval: interval)
        return try candles(from: normalized)
    }

    private static func fetchIntradayCandles(for symbol: MarketSymbol, interval: CandleInterval) async throws -> [Candle] {
        let baseInterval = yahooBaseInterval(for: interval)
        let range = yahooRange(for: interval)
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol.ticker)")

        components?.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: baseInterval),
            URLQueryItem(name: "includePrePost", value: "false"),
            URLQueryItem(name: "events", value: "history")
        ]

        guard let url = components?.url else { throw MarketDataError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MarketDataError.invalidResponse
        }

        let payload = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard let result = payload.chart.result?.first,
              let quote = result.indicators.quote.first else {
            throw MarketDataError.noRows
        }

        let rows = result.timestamp.enumerated().compactMap { index, timestamp -> ParsedCandle? in
            guard index < quote.open.count,
                  let open = quote.open[index],
                  let high = quote.high[index],
                  let low = quote.low[index],
                  let close = quote.close[index] else {
                return nil
            }

            let volume = index < quote.volume.count ? Double(quote.volume[index] ?? 0) : 0
            return ParsedCandle(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        }

        let normalized = normalize(rows, interval: interval)
        return try candles(from: normalized)
    }

    private static func yahooBaseInterval(for interval: CandleInterval) -> String {
        switch interval {
        case .fifteenSeconds, .oneMinute, .threeMinutes, .tenMinutes:
            return "1m"
        case .twoMinutes:
            return "2m"
        case .fiveMinutes:
            return "5m"
        case .fifteenMinutes:
            return "15m"
        case .thirtyMinutes:
            return "30m"
        case .oneHour, .fourHours:
            return "60m"
        case .oneDay:
            return "1d"
        }
    }

    private static func yahooRange(for interval: CandleInterval) -> String {
        switch interval {
        case .fifteenSeconds, .oneMinute, .threeMinutes, .tenMinutes:
            return "8d"
        case .twoMinutes, .fiveMinutes, .fifteenMinutes, .thirtyMinutes:
            return "60d"
        case .oneHour, .fourHours:
            return "2y"
        case .oneDay:
            return "40y"
        }
    }

    private static func yahooProviderSymbols(for instrument: InstrumentMetadata) -> [String] {
        var symbols: [String]
        switch instrument.symbol.uppercased() {
        case "XAUUSD":
            symbols = ["XAUUSD=X", "GC=F"]
        case "XAGUSD":
            symbols = ["XAGUSD=X", "SI=F"]
        case "USDJPY":
            symbols = ["JPY=X"]
        case "USDCAD":
            symbols = ["CAD=X"]
        case "USDCHF":
            symbols = ["CHF=X"]
        case "EURUSD", "GBPUSD", "EURJPY", "EURGBP", "EURAUD", "AUDUSD", "NZDUSD", "GBPJPY":
            symbols = ["\(instrument.symbol.uppercased())=X"]
        default:
            symbols = [instrument.providerSymbol]
        }
        var seen = Set<String>()
        return symbols.filter { seen.insert($0).inserted }
    }

    private static func candles(from rows: [ParsedCandle]) throws -> [Candle] {
        let sortedRows = rows.sorted { $0.date < $1.date }
        guard !sortedRows.isEmpty else { throw MarketDataError.noRows }
        return sortedRows.enumerated().map { index, row in
            Candle(
                index: index,
                date: row.date,
                open: row.open,
                high: row.high,
                low: row.low,
                close: row.close,
                volume: row.volume
            )
        }
    }

    private static func configuredValue(defaultsKey: String, infoKey: String) -> String? {
        if let defaultsValue = UserDefaults.standard.string(forKey: defaultsKey),
           !defaultsValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultsValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !infoValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !infoValue.contains("$(") {
            return infoValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func twelveDataSymbol(for instrument: InstrumentMetadata) -> String {
        switch instrument.assetType {
        case "forex", "spot_metal":
            return "\(instrument.baseAsset)/\(instrument.quoteAsset)"
        default:
            return instrument.providerSymbol
        }
    }

    private static func twelveDataInterval(for interval: CandleInterval) -> String {
        switch interval {
        case .fifteenSeconds, .oneMinute:
            return "1min"
        case .twoMinutes:
            return "1min"
        case .threeMinutes:
            return "1min"
        case .fiveMinutes:
            return "5min"
        case .tenMinutes:
            return "5min"
        case .fifteenMinutes:
            return "15min"
        case .thirtyMinutes:
            return "30min"
        case .oneHour:
            return "1h"
        case .fourHours:
            return "4h"
        case .oneDay:
            return "1day"
        }
    }

    private static func twelveDataOutputSize(for interval: CandleInterval) -> String {
        switch interval {
        case .oneDay:
            return "5000"
        case .oneHour, .fourHours:
            return "5000"
        default:
            return "5000"
        }
    }

    private static func traderMadeInterval(for interval: CandleInterval) -> String {
        switch interval {
        case .oneDay:
            return "daily"
        case .oneHour, .fourHours:
            return "hourly"
        default:
            return "minute"
        }
    }

    private static func traderMadeStartDate(for interval: CandleInterval, endingAt end: Date) -> Date {
        switch interval {
        case .oneDay:
            return Calendar.current.date(byAdding: .year, value: -5, to: end) ?? end
        case .oneHour, .fourHours:
            return Calendar.current.date(byAdding: .month, value: -2, to: end) ?? end
        default:
            return Calendar.current.date(byAdding: .day, value: -2, to: end) ?? end
        }
    }

    private static func backendTimeframe(for interval: CandleInterval) -> String {
        interval.rawValue == "1 day" ? "1d" : interval.rawValue
    }

    private static func backendComponents(userDefaultsKey: String) -> URLComponents? {
        let rawBaseURL = UserDefaults.standard.string(forKey: userDefaultsKey) ??
            UserDefaults.standard.string(forKey: "sean.marketDataBackendBaseURL") ??
            (Bundle.main.object(forInfoDictionaryKey: "SEAN_API_BASE_URL") as? String)
        guard let rawBaseURL,
              !rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !rawBaseURL.contains("$(") else {
            return nil
        }
        return URLComponents(string: rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func fullHistoryBackendQueryItems() -> [URLQueryItem] {
        let start = "1900-01-01T00:00:00Z"
        let end = ISO8601DateFormatter().string(from: Date())
        return [
            URLQueryItem(name: "start", value: start),
            URLQueryItem(name: "from", value: start),
            URLQueryItem(name: "end", value: end),
            URLQueryItem(name: "to", value: end),
            URLQueryItem(name: "limit", value: "500000"),
            URLQueryItem(name: "fullHistory", value: "true")
        ]
    }

    private static func normalize(_ rows: [ParsedCandle], interval: CandleInterval) -> [ParsedCandle] {
        let sortedRows = rows.sorted { $0.date < $1.date }

        switch interval {
        case .threeMinutes, .tenMinutes, .fourHours:
            return aggregate(sortedRows, interval: interval)
        case .fifteenSeconds, .oneMinute, .twoMinutes, .fiveMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .oneDay:
            return sortedRows
        }
    }

    private static func aggregate(_ rows: [ParsedCandle], interval: CandleInterval) -> [ParsedCandle] {
        let grouped = Dictionary(grouping: rows) { row in
            bucketStart(for: row.date, interval: interval)
        }

        return grouped.keys.sorted().compactMap { bucketStart in
            guard let chunk = grouped[bucketStart]?.sorted(by: { $0.date < $1.date }),
                  let first = chunk.first,
                  let last = chunk.last else {
                return nil
            }

            return ParsedCandle(
                date: bucketStart,
                open: first.open,
                high: chunk.map(\.high).max() ?? first.high,
                low: chunk.map(\.low).min() ?? first.low,
                close: last.close,
                volume: chunk.map(\.volume).reduce(0, +)
            )
        }
    }

    private static func bucketStart(for date: Date, interval: CandleInterval) -> Date {
        guard interval != .oneDay else { return date }

        let seconds = Int(interval.seconds)
        guard seconds > 0 else { return date }

        let timestamp = Int(date.timeIntervalSince1970)
        let bucketStart = timestamp - (timestamp % seconds)
        return Date(timeIntervalSince1970: TimeInterval(bucketStart))
    }

    private static func parseRow(_ row: NasdaqHistoricalRow) -> ParsedCandle? {
        guard let date = rowDateFormatter.date(from: row.date),
              let open = parseMarketNumber(row.open),
              let high = parseMarketNumber(row.high),
              let low = parseMarketNumber(row.low),
              let close = parseMarketNumber(row.close),
              let volume = parseMarketNumber(row.volume) else {
            return nil
        }

        return ParsedCandle(date: date, open: open, high: high, low: low, close: close, volume: volume)
    }

    private static func parseMarketNumber(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Double(cleaned)
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    private static let twelveDataFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let traderMadeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let traderMadeDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct NasdaqHistoricalResponse: Decodable {
    let data: NasdaqHistoricalData?
}

private struct NasdaqHistoricalData: Decodable {
    let tradesTable: NasdaqTradesTable?
}

private struct NasdaqTradesTable: Decodable {
    let rows: [NasdaqHistoricalRow]
}

private struct NasdaqHistoricalRow: Decodable {
    let date: String
    let close: String
    let volume: String
    let open: String
    let high: String
    let low: String
}

private struct ParsedCandle {
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

private struct NormalizedFuturesCandle: Decodable {
    let symbol: String
    let exchange: String
    let timeframe: String
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

private struct NormalizedMarketCandle: Decodable {
    let symbol: String
    let exchange: String?
    let timeframe: String?
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

private struct TwelveDataTimeSeriesResponse: Decodable {
    let status: String?
    let values: [TwelveDataCandle]?
}

private struct TwelveDataCandle: Decodable {
    let datetime: String
    let open: String
    let high: String
    let low: String
    let close: String
    let volume: String?
}

private struct TraderMadeTimeSeriesResponse: Decodable {
    let quotes: [TraderMadeCandle]?
}

private struct TraderMadeCandle: Decodable {
    let date: String
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double
}

private struct NormalizedSymbolResult: Decodable {
    let symbol: String
    let displayName: String
    let assetType: String
    let baseAsset: String?
    let quoteAsset: String?
    let exchange: String?
    let provider: String?
    let providerSymbol: String?
    let tickSize: Double?
    let pipSize: Double?
    let contractSize: Double?
    let availableTimeframes: [String]?

    var marketSymbol: MarketSymbol {
        let instrument = InstrumentMetadata(
            symbol: symbol,
            displayName: displayName,
            assetType: assetType,
            baseAsset: baseAsset ?? String(symbol.prefix(3)),
            quoteAsset: quoteAsset ?? String(symbol.suffix(3)),
            exchange: exchange ?? "OTC",
            provider: provider ?? "Backend",
            providerSymbol: providerSymbol ?? symbol,
            tickSize: tickSize ?? 0.00001,
            pipSize: pipSize,
            contractSize: contractSize,
            availableTimeframes: availableTimeframes ?? ["1m", "5m", "15m", "1h", "4h", "1 day"]
        )
        return instrument.marketSymbol
    }
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooChartResult]?
}

private struct YahooChartResult: Decodable {
    let timestamp: [Int]
    let indicators: YahooIndicators
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuote]
}

private struct YahooQuote: Decodable {
    let open: [Double?]
    let high: [Double?]
    let low: [Double?]
    let close: [Double?]
    let volume: [Int?]
}

private struct YahooSearchResponse: Decodable {
    let quotes: [YahooSearchQuote]
}

private struct YahooSearchQuote: Decodable {
    let symbol: String?
    let shortname: String?
    let longname: String?
    let name: String?
    let exchange: String?
    let exchDisp: String?
    let quoteType: String?
    let regularMarketPrice: Double?
    let regularMarketChangePercent: Double?
}
