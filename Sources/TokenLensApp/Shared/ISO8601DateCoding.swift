import Foundation

enum ISO8601DateCoding {
    private static let internetTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let internetTimeFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        internetTimeFractionalFormatter.date(from: text)
            ?? internetTimeFormatter.date(from: text)
    }

    static func string(from date: Date) -> String {
        internetTimeFractionalFormatter.string(from: date)
    }
}
