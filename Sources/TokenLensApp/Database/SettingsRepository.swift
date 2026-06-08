import Foundation
import GRDB

/// Repository for reading and updating application settings.
public final class SettingsRepository {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    /// Fetch a setting value by key. Returns nil if not found.
    public func fetch(_ key: String) throws -> String? {
        try dbManager.reader.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    /// Update (or insert) a setting value.
    public func update(_ key: String, value: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbManager.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                    """,
                arguments: [key, value, now]
            )
        }
    }

    /// Fetch the updated_at timestamp for a setting.
    public func fetchUpdatedAt(_ key: String) throws -> Date? {
        let iso = ISO8601DateFormatter()
        return try dbManager.reader.read { db in
            guard let str = try String.fetchOne(db, sql: "SELECT updated_at FROM settings WHERE key = ?", arguments: [key]) else {
                return nil
            }
            return iso.date(from: str)
        }
    }
}
