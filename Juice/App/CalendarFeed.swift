import Foundation

// The subscribed calendar: an .ics link added in Settings, shown read-only beside tasks.
// Kept on this device only (docs/sync-schema.md, "Not synced"), like the website's.
// Refreshed on launch and on returning to the app when it's over 30 minutes old.
@MainActor
final class CalendarFeed: ObservableObject {
    enum Status: Equatable {
        case idle, loading
        case failed(String)
    }

    private struct Cache: Codable {
        var url: String
        var fetchedAt: Date
        var events: [CalendarEvent]
    }

    @Published private(set) var url: String
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var status: Status = .idle

    private static let urlKey = "calendarURL"
    private static let cacheURL = URL.cachesDirectory.appending(path: "calendar.json")
    private static let refreshAfter: TimeInterval = 30 * 60

    init() {
        url = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.url == url {
            events = cache.events
            fetchedAt = cache.fetchedAt
        }
    }

    var isOn: Bool { !url.isEmpty }

    // Saves the link and loads it; an empty one removes the calendar. Throws when the
    // link doesn't give a calendar, leaving the previous one in place.
    func setURL(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            url = ""
            events = []
            fetchedAt = nil
            status = .idle
            UserDefaults.standard.removeObject(forKey: Self.urlKey)
            try? FileManager.default.removeItem(at: Self.cacheURL)
            return
        }
        let loaded = try await download(trimmed)
        url = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.urlKey)
        store(loaded)
    }

    func refreshIfStale() async {
        guard isOn, Date().timeIntervalSince(fetchedAt ?? .distantPast) > Self.refreshAfter else { return }
        await refresh()
    }

    func refresh() async {
        guard isOn, status != .loading else { return }
        do {
            store(try await download(url))
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func store(_ loaded: [CalendarEvent]) {
        events = loaded
        fetchedAt = Date()
        status = .idle
        if let data = try? JSONEncoder().encode(Cache(url: url, fetchedAt: fetchedAt!, events: loaded)) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private func download(_ link: String) async throws -> [CalendarEvent] {
        guard let source = ICS.normalizeURL(link) else {
            throw Failure(errorDescription: "That doesn't look like a calendar link.")
        }
        status = .loading
        defer { if status == .loading { status = .idle } }
        var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure(errorDescription: "The calendar server responded with \(http.statusCode).")
        }
        let text = String(decoding: data, as: UTF8.self)
        guard ICS.looksLikeCalendar(text) else {
            throw Failure(errorDescription: "That link didn't return a calendar (.ics) file.")
        }
        // From the start of last month to a year ahead, as on the website.
        let calendar = Calendar.current
        let today = CalendarDay.today()
        let start = today.firstOfMonth.adding(months: -1).start(in: calendar)
        let end = today.adding(days: 365).start(in: calendar)
        return await Task.detached(priority: .userInitiated) {
            ICS.events(text, from: start, to: end, calendar: calendar)
        }.value
    }
}
