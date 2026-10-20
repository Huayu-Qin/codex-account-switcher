import Foundation

/// Public-post history and an experimental forecast from codex-reset.com.
/// These are global goodwill resets, not an account's scheduled usage-window reset.
public struct TiboResetForecast: Equatable, Sendable {
    public struct Event: Equatable, Sendable, Identifiable {
        public let id: String
        public let postedAt: Date
        public let url: URL
        public let summary: String
    }

    public struct ForwardSignal: Equatable, Sendable {
        public let postedAt: Date
        public let url: URL
    }

    public let updatedAt: Date
    public let lastResetAt: Date
    public let next24HourPercent: Int
    public let next48HourPercent: Int
    public let confidence: String
    public let commonHourStart: Int
    public let commonHourEnd: Int
    public let recentMedianDays: Double?
    public let historicalNextWindow: Range<Date>?
    public let events: [Event]
    public let forwardSignal: ForwardSignal?
}

public enum TiboResetForecastReader {
    private static let conditionalPlanPostID = "2106845241357824205"
    public enum DataError: Error {
        case invalidResponse
        case staleResponse
        case conflictingSources
    }

    public static func read(forecast: Data, timeline: Data, now: Date = Date()) throws -> TiboResetForecast {
        let decoder = JSONDecoder()
        guard let forecast = try? decoder.decode(ForecastWire.self, from: forecast),
              let timeline = try? decoder.decode(TimelineWire.self, from: timeline),
              let updatedAt = date(forecast.updatedAt),
              let timelineUpdatedAt = date(timeline.updatedAt),
              let lastResetAt = date(forecast.lastResetAt),
              let window = forecast.timeWindow,
              window.timezone == "Asia/Shanghai",
              (0...23).contains(window.startHour),
              (0...24).contains(window.endHour),
              window.startHour != window.endHour,
              (0...100).contains(forecast.probabilities.rounded24h),
              (0...100).contains(forecast.probabilities.rounded48h),
              forecast.probabilities.rounded48h >= forecast.probabilities.rounded24h,
              ["low", "medium", "high"].contains(forecast.confidence)
        else { throw DataError.invalidResponse }

        // A live-looking probability built from old source data is more misleading than no prediction.
        guard updatedAt.timeIntervalSince(now) <= 300,
              timelineUpdatedAt.timeIntervalSince(now) <= 300,
              now.timeIntervalSince(updatedAt) <= 7_200,
              now.timeIntervalSince(timelineUpdatedAt) <= 7_200,
              lastResetAt.timeIntervalSince(now) <= 300
        else { throw DataError.staleResponse }

        var seen = Set<String>()
        let forwardSignal = timeline.events.compactMap { event -> TiboResetForecast.ForwardSignal? in
            guard event.id == conditionalPlanPostID,
                  event.group == "reset",
                  let url = originalPostURL(event.url, id: event.id),
                  let postedAt = tweetTime(id: event.id),
                  postedAt <= now.addingTimeInterval(300),
                  now.timeIntervalSince(postedAt) < 28 * 86_400,
                  event.summary.localizedCaseInsensitiveContains("next 28 days"),
                  event.summary.localizedCaseInsensitiveContains("either"),
                  event.summary.localizedCaseInsensitiveContains("full reset")
            else { return nil }
            return .init(postedAt: postedAt, url: url)
        }.first
        let events = timeline.events.compactMap { event -> TiboResetForecast.Event? in
            guard event.id != conditionalPlanPostID,
                  event.group == "reset", event.announcementState == "announced",
                  let url = originalPostURL(event.url, id: event.id),
                  let postedAt = tweetTime(id: event.id),
                  postedAt <= now.addingTimeInterval(300),
                  seen.insert(event.id).inserted
            else { return nil }
            return .init(id: event.id, postedAt: postedAt, url: url,
                         summary: String(event.summary.prefix(180)))
        }.sorted { $0.postedAt > $1.postedAt }

        guard events.count >= 5 else { throw DataError.invalidResponse }
        guard abs(events[0].postedAt.timeIntervalSince(lastResetAt)) <= 21_600 else {
            throw DataError.conflictingSources
        }
        let recentGaps = Array(zip(events, events.dropFirst()).prefix(5)).map {
            $0.0.postedAt.timeIntervalSince($0.1.postedAt)
        }.sorted()
        let medianGap = recentGaps.count == 5 ? recentGaps[2] : nil
        let nextWindow = medianGap.flatMap {
            historicalWindow(
                after: events[0].postedAt.addingTimeInterval($0),
                startHour: window.startHour, endHour: window.endHour, now: now
            )
        }
        return TiboResetForecast(
            updatedAt: updatedAt, lastResetAt: lastResetAt,
            next24HourPercent: forecast.probabilities.rounded24h,
            next48HourPercent: forecast.probabilities.rounded48h,
            confidence: forecast.confidence,
            commonHourStart: window.startHour, commonHourEnd: window.endHour,
            recentMedianDays: medianGap.map { $0 / 86_400 },
            historicalNextWindow: nextWindow,
            events: Array(events.prefix(30)), forwardSignal: forwardSignal
        )
    }

    private static func historicalWindow(after midpoint: Date, startHour: Int, endHour: Int, now: Date) -> Range<Date>? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = calendar.startOfDay(for: midpoint)
        guard let start = calendar.date(byAdding: .hour, value: startHour, to: day),
              let end = calendar.date(byAdding: .hour, value: endHour, to: day),
              end > now, end > start
        else { return nil }
        return start..<end
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func originalPostURL(_ text: String?, id: String) -> URL? {
        guard let text, let url = URL(string: text),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "x.com",
              parts.path == "/thsottiaux/status/\(id)",
              parts.query == nil, parts.fragment == nil,
              UInt64(id) != nil
        else { return nil }
        return url
    }

    private static func tweetTime(id: String) -> Date? {
        guard let value = UInt64(id), value >> 22 > 0 else { return nil }
        let milliseconds = (value >> 22) + 1_288_834_974_657
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private struct ForecastWire: Decodable {
        let updatedAt: String
        let lastResetAt: String
        let probabilities: Probabilities
        let confidence: String
        let timeWindow: TimeWindow?

        enum CodingKeys: String, CodingKey {
            case updatedAt = "updated_at"
            case lastResetAt = "last_reset_at"
            case probabilities, confidence
            case timeWindow = "time_window"
        }

        struct Probabilities: Decodable {
            let rounded24h: Int
            let rounded48h: Int

            enum CodingKeys: String, CodingKey {
                case rounded24h = "rounded_24h"
                case rounded48h = "rounded_48h"
            }
        }

        struct TimeWindow: Decodable {
            let startHour: Int
            let endHour: Int
            let timezone: String

            enum CodingKeys: String, CodingKey {
                case startHour = "start_hour"
                case endHour = "end_hour"
                case timezone
            }
        }
    }

    private struct TimelineWire: Decodable {
        let updatedAt: String
        let events: [EventWire]

        enum CodingKeys: String, CodingKey {
            case updatedAt = "updated_at"
            case events
        }

        struct EventWire: Decodable {
            let id: String
            let group: String
            let announcementState: String?
            let url: String?
            let summary: String

            enum CodingKeys: String, CodingKey {
                case id, group, url, summary
                case announcementState = "announcement_state"
            }
        }
    }
}
