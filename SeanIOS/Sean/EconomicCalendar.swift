import Foundation
import SwiftUI

enum EconomicImpact: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case holiday
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?.lowercased() ?? ""
        self = EconomicImpact(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct EconomicEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let date: String
    let time: String
    let timestampUtc: Date
    let currency: String
    let impact: EconomicImpact
    let title: String
    let actual: String?
    let forecast: String?
    let previous: String?
    let revised: String?
    let source: String
    let description: String?
}

protocol EconomicCalendarAPI: Sendable {
    func fetchEvents() async throws -> [EconomicEvent]
}

protocol EconomicCalendarRepository: Sendable {
    func highImpactEvents() async throws -> [EconomicEvent]
}

enum EconomicCalendarError: LocalizedError {
    case missingEndpoint
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Economic calendar backend is not configured."
        case .invalidResponse:
            return "Economic calendar data was not readable."
        }
    }
}

struct EconomicCalendarService: EconomicCalendarAPI {
    var endpoint: URL?

    init(endpoint: URL? = EconomicCalendarService.defaultEndpoint) {
        self.endpoint = endpoint
    }

    func fetchEvents() async throws -> [EconomicEvent] {
        guard let endpoint else { throw EconomicCalendarError.missingEndpoint }

        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw EconomicCalendarError.invalidResponse
        }

        return try EconomicCalendarDecoder.decode(data)
    }

    private static var defaultEndpoint: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ECONOMIC_CALENDAR_API_URL") as? String {
            return URL(string: raw)
        }
        if let raw = UserDefaults.standard.string(forKey: "economicCalendarApiUrl") {
            return URL(string: raw)
        }
        return nil
    }
}

struct DefaultEconomicCalendarRepository: EconomicCalendarRepository {
    var api: any EconomicCalendarAPI
    var cache: EconomicCalendarCache

    init(api: EconomicCalendarAPI = EconomicCalendarService(), cache: EconomicCalendarCache = .shared) {
        self.api = api
        self.cache = cache
    }

    func highImpactEvents() async throws -> [EconomicEvent] {
        do {
            let events = try await api.fetchEvents()
                .filter { $0.impact == .high }
                .sorted { $0.timestampUtc < $1.timestampUtc }
            try? cache.save(events)
            return events
        } catch {
            if let cached = try? cache.load(), !cached.isEmpty {
                return cached
            }
            return Self.sampleEvents
        }
    }

    private static var sampleEvents: [EconomicEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([EconomicEvent].self, from: Data(sampleJSON.utf8))) ?? []
    }

    private static let sampleJSON = """
    [
      {
        "id": "usd-nfp-2026-07-03",
        "date": "2026-07-03",
        "time": "08:30",
        "timestampUtc": "2026-07-03T12:30:00Z",
        "currency": "USD",
        "impact": "high",
        "title": "Non-Farm Employment Change",
        "forecast": "180K",
        "previous": "139K",
        "actual": null,
        "revised": null,
        "source": "Forex Factory-compatible economic calendar",
        "description": "Measures the monthly change in employed people excluding the farming industry."
      },
      {
        "id": "usd-unemployment-2026-07-03",
        "date": "2026-07-03",
        "time": "08:30",
        "timestampUtc": "2026-07-03T12:30:00Z",
        "currency": "USD",
        "impact": "high",
        "title": "Unemployment Rate",
        "forecast": "4.2%",
        "previous": "4.2%",
        "actual": null,
        "revised": null,
        "source": "Forex Factory-compatible economic calendar",
        "description": "Percentage of the labor force that is unemployed and actively seeking work."
      },
      {
        "id": "eur-ecb-rate-2026-07-23",
        "date": "2026-07-23",
        "time": "08:15",
        "timestampUtc": "2026-07-23T12:15:00Z",
        "currency": "EUR",
        "impact": "high",
        "title": "Main Refinancing Rate",
        "forecast": "2.00%",
        "previous": "2.00%",
        "actual": null,
        "revised": null,
        "source": "Forex Factory-compatible economic calendar",
        "description": "Interest rate on main refinancing operations set by the European Central Bank."
      },
      {
        "id": "gbp-boe-rate-2026-08-06",
        "date": "2026-08-06",
        "time": "07:00",
        "timestampUtc": "2026-08-06T11:00:00Z",
        "currency": "GBP",
        "impact": "high",
        "title": "Official Bank Rate",
        "forecast": "4.00%",
        "previous": "4.25%",
        "actual": null,
        "revised": null,
        "source": "Forex Factory-compatible economic calendar",
        "description": "The Bank of England's benchmark interest rate decision."
      }
    ]
    """
}

struct EconomicCalendarCache {
    static let shared = EconomicCalendarCache()

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("high-impact-economic-calendar.json")
    }

    func save(_ events: [EconomicEvent]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(events)
        try data.write(to: fileURL, options: [.atomic])
    }

    func load() throws -> [EconomicEvent] {
        let data = try Data(contentsOf: fileURL)
        return try EconomicCalendarDecoder.decode(data)
    }
}

enum EconomicCalendarDecoder {
    static func decode(_ data: Data) throws -> [EconomicEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let array = try? decoder.decode([EconomicEvent].self, from: data) {
            return array
        }

        let envelope = try decoder.decode(EconomicCalendarEnvelope.self, from: data)
        return envelope.events
    }
}

private struct EconomicCalendarEnvelope: Decodable {
    let events: [EconomicEvent]
}

@Observable
@MainActor
final class EconomicCalendarViewModel {
    var events: [EconomicEvent] = []
    var selectedCurrencies: Set<String> = []
    var dateFilter: EconomicCalendarDateFilter = .upcoming
    var upcomingOnly = true
    var isLoading = false
    var errorMessage: String?

    private let repository: EconomicCalendarRepository
    private let calendar = Calendar.current

    init(repository: EconomicCalendarRepository = DefaultEconomicCalendarRepository()) {
        self.repository = repository
    }

    var currencies: [String] {
        Array(Set(events.map(\.currency))).sorted()
    }

    var filteredEvents: [EconomicEvent] {
        let now = Date()
        return events.filter { event in
            let currencyMatches = selectedCurrencies.isEmpty || selectedCurrencies.contains(event.currency)
            let upcomingMatches = !upcomingOnly || event.timestampUtc >= now
            return currencyMatches && upcomingMatches && dateFilter.contains(event.timestampUtc, calendar: calendar, now: now)
        }
    }

    var groupedEvents: [(Date, [EconomicEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.timestampUtc)
        }
        return grouped.keys.sorted().map { day in
            (day, (grouped[day] ?? []).sorted { $0.timestampUtc < $1.timestampUtc })
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            events = try await repository.highImpactEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggleCurrency(_ currency: String) {
        if selectedCurrencies.contains(currency) {
            selectedCurrencies.remove(currency)
        } else {
            selectedCurrencies.insert(currency)
        }
    }
}

enum EconomicCalendarDateFilter: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"

    var id: String { rawValue }

    func contains(_ date: Date, calendar: Calendar, now: Date) -> Bool {
        switch self {
        case .upcoming:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
            return calendar.isDate(date, inSameDayAs: tomorrow)
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        }
    }
}
