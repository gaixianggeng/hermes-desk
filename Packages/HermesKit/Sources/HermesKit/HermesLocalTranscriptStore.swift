import Foundation
import SQLite3

struct HermesLocalTranscriptStore: Sendable {
    let stateDBPath: String

    func fetchSessionMessages(sessionID: String) throws -> [HermesConversationMessage] {
        try fetchSessionMessagesPage(sessionID: sessionID, limit: .max, before: nil).messages
    }

    func fetchSessionMessagesPage(
        sessionID: String,
        limit: Int,
        before: HermesConversationPageCursor?
    ) throws -> HermesConversationPage {
        try withReadOnlyDatabase { database in
            let pagedSQL = """
            SELECT id, session_id, role, COALESCE(content, ''), tool_name, timestamp, reasoning
            FROM messages
            WHERE session_id = ?
              AND (
                ? IS NULL
                OR timestamp < ?
                OR (timestamp = ? AND id < ?)
              )
            ORDER BY timestamp DESC, id DESC
            LIMIT ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, pagedSQL, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, sessionID, -1, transientSQLiteDestructor)
            if let before {
                sqlite3_bind_double(statement, 2, before.timestamp.timeIntervalSince1970)
                sqlite3_bind_double(statement, 3, before.timestamp.timeIntervalSince1970)
                sqlite3_bind_double(statement, 4, before.timestamp.timeIntervalSince1970)
                sqlite3_bind_int64(statement, 5, before.id)
            } else {
                sqlite3_bind_null(statement, 2)
                sqlite3_bind_null(statement, 3)
                sqlite3_bind_null(statement, 4)
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_int(statement, 6, Int32(max(1, min(limit, Int(Int32.max)))))

            var results: [HermesConversationMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let sessionID = text(at: 1, statement: statement)
                let role = HermesConversationRole(rawRole: text(at: 2, statement: statement))
                let content = text(at: 3, statement: statement)
                let toolName = optionalText(at: 4, statement: statement)
                let timestamp = sqlite3_column_double(statement, 5)
                let reasoning = optionalText(at: 6, statement: statement)

                results.append(
                    HermesConversationMessage(
                        id: id,
                        sessionID: sessionID,
                        role: role,
                        content: content,
                        toolName: toolName,
                        reasoning: reasoning,
                        timestamp: Date(timeIntervalSince1970: timestamp)
                    )
                )
            }

            let finalCode = sqlite3_errcode(database)
            guard finalCode == SQLITE_OK || finalCode == SQLITE_DONE else {
                throw HermesLocalTranscriptStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
            }

            results.reverse()

            let oldestLoadedCursor = results.first.map { HermesConversationPageCursor(id: $0.id, timestamp: $0.timestamp) }
            let hasMoreBefore = try oldestLoadedCursor.map {
                try hasMessagesBefore(sessionID: sessionID, cursor: $0, database: database)
            } ?? false

            return HermesConversationPage(messages: results, hasMoreBefore: hasMoreBefore)
        }
    }

    func fetchSessionBinding(preferredSessionID: String, rootSessionID: String?) throws -> HermesSessionBinding? {
        try withReadOnlyDatabase { database in
            let anchorSessionID = rootSessionID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? rootSessionID!
                : preferredSessionID

            guard let rootDescriptor = try fetchSessionDescriptor(sessionID: anchorSessionID, database: database) else {
                return nil
            }

            let descendantSessionID = try fetchLatestDescendantSessionID(anchorSessionID: preferredSessionID, database: database)
                ?? preferredSessionID
            let currentDescriptor = try fetchSessionDescriptor(sessionID: descendantSessionID, database: database)
                ?? rootDescriptor

            let lineage = try fetchLineage(to: currentDescriptor.sessionID, database: database)
            let resolvedRootSessionID = lineage.first?.sessionID ?? rootDescriptor.sessionID

            return HermesSessionBinding(
                rootSessionID: resolvedRootSessionID,
                currentSessionID: currentDescriptor.sessionID,
                lineage: lineage
            )
        }
    }

    func withReadOnlyDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: stateDBPath) else {
            throw HermesLocalTranscriptStoreError.databaseMissing
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(stateDBPath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open Hermes state.db"
            sqlite3_close(database)
            throw HermesLocalTranscriptStoreError.databaseOpenFailed(message)
        }
        defer { sqlite3_close(database) }

        return try body(database)
    }

    func fetchSessionDescriptor(sessionID: String, database: OpaquePointer) throws -> HermesSessionDescriptor? {
        let sql = """
        SELECT id, parent_session_id, title, source, started_at, ended_at
        FROM sessions
        WHERE id = ?
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, transientSQLiteDestructor)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return HermesSessionDescriptor(
            sessionID: text(at: 0, statement: statement),
            parentSessionID: optionalText(at: 1, statement: statement),
            title: optionalText(at: 2, statement: statement),
            source: optionalText(at: 3, statement: statement),
            startedAt: optionalDate(at: 4, statement: statement),
            endedAt: optionalDate(at: 5, statement: statement)
        )
    }

    func fetchLineage(to sessionID: String, database: OpaquePointer) throws -> [HermesSessionDescriptor] {
        var descriptors: [HermesSessionDescriptor] = []
        var cursor = sessionID
        var seen: Set<String> = []

        while seen.contains(cursor) == false,
              let descriptor = try fetchSessionDescriptor(sessionID: cursor, database: database) {
            descriptors.append(descriptor)
            seen.insert(cursor)
            guard let parentSessionID = descriptor.parentSessionID else {
                break
            }
            cursor = parentSessionID
        }

        return descriptors.reversed()
    }

    func fetchLatestDescendantSessionID(anchorSessionID: String, database: OpaquePointer) throws -> String? {
        let sql = """
        WITH RECURSIVE subtree(id, parent_session_id, started_at, depth) AS (
            SELECT id, parent_session_id, started_at, 0
            FROM sessions
            WHERE id = ?
            UNION ALL
            SELECT s.id, s.parent_session_id, s.started_at, subtree.depth + 1
            FROM sessions s
            JOIN subtree ON s.parent_session_id = subtree.id
        )
        SELECT subtree.id
        FROM subtree
        LEFT JOIN sessions child ON child.parent_session_id = subtree.id
        WHERE child.id IS NULL
        ORDER BY subtree.depth DESC, subtree.started_at DESC, subtree.id DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, anchorSessionID, -1, transientSQLiteDestructor)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return text(at: 0, statement: statement)
    }

    private func hasMessagesBefore(
        sessionID: String,
        cursor: HermesConversationPageCursor,
        database: OpaquePointer
    ) throws -> Bool {
        let sql = """
        SELECT 1
        FROM messages
        WHERE session_id = ?
          AND (
            timestamp < ?
            OR (timestamp = ? AND id < ?)
          )
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw HermesLocalTranscriptStoreError.statementPreparationFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, transientSQLiteDestructor)
        sqlite3_bind_double(statement, 2, cursor.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, cursor.timestamp.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 4, cursor.id)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func text(at index: Int32, statement: OpaquePointer) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private func optionalText(at index: Int32, statement: OpaquePointer) -> String? {
        let value = text(at: index, statement: statement)
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func optionalDate(at index: Int32, statement: OpaquePointer) -> Date? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }
}

private let transientSQLiteDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum HermesLocalTranscriptStoreError: LocalizedError, Equatable {
    case databaseMissing
    case databaseOpenFailed(String)
    case statementPreparationFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseMissing:
            return "Hermes state.db is not available yet."
        case let .databaseOpenFailed(message):
            return "Could not open Hermes state.db: \(message)"
        case let .statementPreparationFailed(message):
            return "Could not prepare session transcript query: \(message)"
        case let .queryFailed(message):
            return "Could not load session transcript: \(message)"
        }
    }
}
