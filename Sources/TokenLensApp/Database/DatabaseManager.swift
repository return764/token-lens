import Foundation
import GRDB

/// Manages the SQLite database connection and migrations.
public final class DatabaseManager {
    public enum Kind {
        case inMemory
        case onDisk(URL)
    }

    private let dbQueue: DatabaseQueue

    public init(kind: Kind) throws {
        switch kind {
        case .inMemory:
            dbQueue = try DatabaseQueue()
        case .onDisk(let url):
            dbQueue = try DatabaseQueue(path: url.path)
        }

        try migrate()
        try seedIfNeeded()
    }

    /// POC rebuild helper: delete the SQLite cache ledger and recreate the latest v1 schema.
    public static func resetAndRebuild(at url: URL) throws -> DatabaseManager {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        return try DatabaseManager(kind: .onDisk(url))
    }

    // MARK: - Internal access (for repositories)

    var writer: DatabaseWriter { dbQueue }
    var reader: DatabaseReader { dbQueue }

    // MARK: - Migration

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS settings (
                  key TEXT PRIMARY KEY,
                  value TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS token_usages (
                  id TEXT PRIMARY KEY,
                  agentic_tool TEXT NOT NULL,
                  provider_id TEXT NOT NULL,
                  model TEXT,
                  input_tokens INTEGER DEFAULT 0,
                  output_tokens INTEGER DEFAULT 0,
                  cached_input_tokens INTEGER DEFAULT 0,
                  cache_write_tokens INTEGER DEFAULT 0,
                  reasoning_tokens INTEGER DEFAULT 0,
                  total_tokens INTEGER DEFAULT 0,
                  cost_usd REAL DEFAULT 0,
                  created_at TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_token_usages_agentic_tool
                ON token_usages(agentic_tool, created_at);
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_token_usages_created_at
                ON token_usages(created_at);
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_token_usages_provider_model
                ON token_usages(provider_id, model);
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS local_scan_sources (
                  source_tool TEXT PRIMARY KEY,
                  display_name TEXT NOT NULL,
                  root_path TEXT NOT NULL,
                  status TEXT NOT NULL,
                  last_scan_started_at TEXT,
                  last_scan_finished_at TEXT,
                  files_seen INTEGER DEFAULT 0,
                  files_scanned INTEGER DEFAULT 0,
                  events_imported INTEGER DEFAULT 0,
                  parse_error_count INTEGER DEFAULT 0,
                  last_error TEXT,
                  updated_at TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS local_scan_files (
                  id TEXT PRIMARY KEY,
                  source_tool TEXT NOT NULL,
                  path TEXT NOT NULL,
                  file_size INTEGER DEFAULT 0,
                  modified_at TEXT,
                  file_id TEXT,
                  read_offset INTEGER DEFAULT 0,
                  parse_context_json TEXT,
                  last_scanned_at TEXT,
                  imported_event_count INTEGER DEFAULT 0,
                  status TEXT NOT NULL,
                  last_error TEXT,
                  UNIQUE(source_tool, path)
                );
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS local_usage_imports (
                  key TEXT PRIMARY KEY,
                  source_tool TEXT NOT NULL,
                  source_file TEXT NOT NULL,
                  token_usage_id TEXT NOT NULL,
                  imported_at TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_local_usage_imports_source_tool
                ON local_usage_imports(source_tool, imported_at);
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS models (
                  id TEXT PRIMARY KEY,
                  provider_id TEXT NOT NULL,
                  model TEXT NOT NULL,
                  input_price REAL DEFAULT 0,
                  output_price REAL DEFAULT 0,
                  cached_input_price REAL DEFAULT 0,
                  reasoning_price REAL DEFAULT 0,
                  currency TEXT NOT NULL DEFAULT 'USD',
                  effective_from TEXT NOT NULL,
                  effective_to TEXT,
                  created_at TEXT NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_models_provider_model
                ON models(provider_id, model);
                """)
        }

        migrator.registerMigration("v2_local_scan_parse_context") { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(local_scan_files)")
            let columns = Set(rows.compactMap { $0["name"] as String? })
            if !columns.contains("parse_context_json") {
                try db.execute(sql: "ALTER TABLE local_scan_files ADD COLUMN parse_context_json TEXT")
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Seed

    private func seedIfNeeded() throws {
        let now = ISO8601DateFormatter().string(from: Date())

        // Seed default settings
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings") ?? 0
        }
        guard count == 0 else { return }

        try dbQueue.write { db in
            let settings: [(String, String)] = [
                ("menu_bar_display", "cost"),
            ]
            for (key, value) in settings {
                try db.execute(
                    sql: "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)",
                    arguments: [key, value, now]
                )
            }

            // Models table is seeded asynchronously from models.dev/api.json via ModelsSeeder.
            // See AppState init for the trigger.
        }
    }

    // MARK: - Test helpers

    func fetchColumnNames(table: String) throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
            return rows.compactMap { $0["name"] as String? }
        }
    }

    func fetchTableNames() throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """)
            return rows.compactMap { $0["name"] as String? }
        }
    }

    func fetchSetting(key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }
}


