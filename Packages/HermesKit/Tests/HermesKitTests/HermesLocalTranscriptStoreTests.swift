import Foundation
import SQLite3
import XCTest
@testable import HermesKit

final class HermesLocalTranscriptStoreTests: XCTestCase {
    func testFetchSessionMessagesReturnsOrderedConversationMessages() throws {
        let databaseURL = try makeDatabaseURL()
        let database = try openDatabase(at: databaseURL.path)
        defer { sqlite3_close(database) }

        try createSchema(database: database)
        try insertMessage(sessionID: "session-1", role: "user", content: "Ship the fix", toolName: nil, timestamp: 100, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "I'll inspect the repo.", toolName: nil, timestamp: 101, reasoning: "Plan first", database: database)
        try insertMessage(sessionID: "session-1", role: "tool", content: "xcodebuild -project HermesDesk.xcodeproj", toolName: "terminal", timestamp: 102, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-2", role: "user", content: "Ignore me", toolName: nil, timestamp: 103, reasoning: nil, database: database)

        let store = HermesLocalTranscriptStore(stateDBPath: databaseURL.path)
        let messages = try store.fetchSessionMessages(sessionID: "session-1")

        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .tool])
        XCTAssertEqual(messages.map(\.displayText), ["Ship the fix", "I'll inspect the repo.", "xcodebuild -project HermesDesk.xcodeproj"])
        XCTAssertEqual(messages[1].reasoning, "Plan first")
        XCTAssertEqual(messages[2].toolName, "terminal")
        XCTAssertEqual(messages.count, 3)
    }

    func testFetchSessionBindingReturnsRootCurrentAndLineage() throws {
        let databaseURL = try makeDatabaseURL()
        let database = try openDatabase(at: databaseURL.path)
        defer { sqlite3_close(database) }

        try createSchema(database: database)
        try insertSession(id: "root-session", parentSessionID: nil, startedAt: 100, database: database)
        try insertSession(id: "child-session", parentSessionID: "root-session", startedAt: 200, database: database)
        try insertSession(id: "leaf-session", parentSessionID: "child-session", startedAt: 300, database: database)

        let store = HermesLocalTranscriptStore(stateDBPath: databaseURL.path)
        let binding = try store.fetchSessionBinding(preferredSessionID: "child-session", rootSessionID: "root-session")

        XCTAssertEqual(binding?.rootSessionID, "root-session")
        XCTAssertEqual(binding?.currentSessionID, "leaf-session")
        XCTAssertEqual(binding?.lineage.map(\.sessionID), ["root-session", "child-session", "leaf-session"])
    }

    func testFetchSessionMessagesPageReturnsMostRecentMessagesFirst() throws {
        let databaseURL = try makeDatabaseURL()
        let database = try openDatabase(at: databaseURL.path)
        defer { sqlite3_close(database) }

        try createSchema(database: database)
        try insertMessage(sessionID: "session-1", role: "user", content: "m1", toolName: nil, timestamp: 100, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "m2", toolName: nil, timestamp: 200, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "m3", toolName: nil, timestamp: 300, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "m4", toolName: nil, timestamp: 400, reasoning: nil, database: database)

        let store = HermesLocalTranscriptStore(stateDBPath: databaseURL.path)
        let page = try store.fetchSessionMessagesPage(sessionID: "session-1", limit: 2, before: nil)

        XCTAssertEqual(page.messages.map(\.displayText), ["m3", "m4"])
        XCTAssertTrue(page.hasMoreBefore)
    }

    func testFetchSessionMessagesPageCanLoadOlderMessagesBeforeCursor() throws {
        let databaseURL = try makeDatabaseURL()
        let database = try openDatabase(at: databaseURL.path)
        defer { sqlite3_close(database) }

        try createSchema(database: database)
        try insertMessage(sessionID: "session-1", role: "user", content: "m1", toolName: nil, timestamp: 100, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "m2", toolName: nil, timestamp: 200, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "m3", toolName: nil, timestamp: 300, reasoning: nil, database: database)
        try insertMessage(sessionID: "session-1", role: "assistant", content: "m4", toolName: nil, timestamp: 400, reasoning: nil, database: database)

        let store = HermesLocalTranscriptStore(stateDBPath: databaseURL.path)
        let recentPage = try store.fetchSessionMessagesPage(sessionID: "session-1", limit: 2, before: nil)
        let cursor = HermesConversationPageCursor(id: recentPage.messages[0].id, timestamp: recentPage.messages[0].timestamp)
        let olderPage = try store.fetchSessionMessagesPage(sessionID: "session-1", limit: 2, before: cursor)

        XCTAssertEqual(olderPage.messages.map(\.displayText), ["m1", "m2"])
        XCTAssertFalse(olderPage.hasMoreBefore)
    }

    func testFetchSessionMessagesThrowsWhenStateDatabaseMissing() throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-state.db")
            .path

        let store = HermesLocalTranscriptStore(stateDBPath: missingPath)

        XCTAssertThrowsError(try store.fetchSessionMessages(sessionID: "session-1")) { error in
            XCTAssertEqual(error as? HermesLocalTranscriptStoreError, .databaseMissing)
        }
    }

    private func makeDatabaseURL() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory.appendingPathComponent("state.db")
    }

    private func openDatabase(at path: String) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Could not open sqlite database"
            sqlite3_close(database)
            throw XCTSkip("Database open failed: \(message)")
        }
        return database
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw XCTSkip("SQLite exec failed: \(String(cString: sqlite3_errmsg(database)))")
        }
    }

    private func createSchema(database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                parent_session_id TEXT,
                title TEXT,
                source TEXT,
                started_at REAL,
                ended_at REAL
            );
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT,
                tool_name TEXT,
                timestamp REAL NOT NULL,
                reasoning TEXT
            );
            """,
            database: database
        )
    }

    private func insertSession(
        id: String,
        parentSessionID: String?,
        startedAt: Double,
        database: OpaquePointer
    ) throws {
        let sql = "INSERT INTO sessions (id, parent_session_id, title, source, started_at, ended_at) VALUES (?, ?, ?, ?, ?, NULL)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw XCTSkip("Could not prepare session insert statement: \(String(cString: sqlite3_errmsg(database)))")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let parentSessionID {
            sqlite3_bind_text(statement, 2, parentSessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, 2)
        }
        sqlite3_bind_text(statement, 3, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 4, "api_server", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(statement, 5, startedAt)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw XCTSkip("Session insert failed: \(String(cString: sqlite3_errmsg(database)))")
        }
    }

    private func insertMessage(
        sessionID: String,
        role: String,
        content: String,
        toolName: String?,
        timestamp: Double,
        reasoning: String?,
        database: OpaquePointer
    ) throws {
        let sql = "INSERT INTO messages (session_id, role, content, tool_name, timestamp, reasoning) VALUES (?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw XCTSkip("Could not prepare insert statement: \(String(cString: sqlite3_errmsg(database)))")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 2, role, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(statement, 3, content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let toolName {
            sqlite3_bind_text(statement, 4, toolName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_double(statement, 5, timestamp)
        if let reasoning {
            sqlite3_bind_text(statement, 6, reasoning, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, 6)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw XCTSkip("Insert failed: \(String(cString: sqlite3_errmsg(database)))")
        }
    }
}
