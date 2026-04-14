import Foundation
import XCTest
@testable import HermesKit

final class ConfigurationDiscoveryTests: XCTestCase {
    func testDiscoverPrefersHermesHomeEnvironmentFileOverDefaultHome() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = tempRoot.appendingPathComponent("home", isDirectory: true)
        let defaultHermesHome = homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
        let profiledHermesHome = tempRoot.appendingPathComponent("profiles/kunce", isDirectory: true)

        try fileManager.createDirectory(at: defaultHermesHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: profiledHermesHome, withIntermediateDirectories: true)
        try "API_SERVER_PORT=1111\n".write(to: defaultHermesHome.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "API_SERVER_PORT=8642\nAPI_SERVER_KEY=profile-key\n".write(to: profiledHermesHome.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let configuration = HermesLocalServerConfiguration.discover(
            processEnvironment: ["HERMES_HOME": profiledHermesHome.path],
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(configuration.hermesHomePath, profiledHermesHome.path)
        XCTAssertEqual(configuration.environmentFilePath, profiledHermesHome.appendingPathComponent(".env").path)
        XCTAssertTrue(configuration.environmentFileExists)
        XCTAssertEqual(configuration.endpoint.port, 8642)
        XCTAssertEqual(configuration.apiKey, "profile-key")
    }

    func testDiscoverFallsBackToDefaultHomeWhenHermesHomeUnset() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = tempRoot.appendingPathComponent("home", isDirectory: true)
        let defaultHermesHome = homeDirectory.appendingPathComponent(".hermes", isDirectory: true)

        try fileManager.createDirectory(at: defaultHermesHome, withIntermediateDirectories: true)
        try "API_SERVER_HOST=localhost\nAPI_SERVER_PORT=7777\n".write(to: defaultHermesHome.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let configuration = HermesLocalServerConfiguration.discover(
            processEnvironment: [:],
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(configuration.hermesHomePath, defaultHermesHome.path)
        XCTAssertEqual(configuration.environmentFilePath, defaultHermesHome.appendingPathComponent(".env").path)
        XCTAssertTrue(configuration.environmentFileExists)
        XCTAssertEqual(configuration.endpoint.host, "localhost")
        XCTAssertEqual(configuration.endpoint.port, 7777)
    }

    func testDiscoverProcessEnvironmentOverridesEnvFileValues() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profiledHermesHome = tempRoot.appendingPathComponent("profiles/kunce", isDirectory: true)

        try fileManager.createDirectory(at: profiledHermesHome, withIntermediateDirectories: true)
        try "API_SERVER_HOST=file-host\nAPI_SERVER_PORT=8642\nAPI_SERVER_KEY=file-key\n".write(to: profiledHermesHome.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let configuration = HermesLocalServerConfiguration.discover(
            processEnvironment: [
                "HERMES_HOME": profiledHermesHome.path,
                "API_SERVER_HOST": "127.0.0.1",
                "API_SERVER_PORT": "9900",
                "API_SERVER_KEY": "env-key"
            ],
            fileManager: fileManager,
            homeDirectory: tempRoot
        )

        XCTAssertEqual(configuration.endpoint.host, "127.0.0.1")
        XCTAssertEqual(configuration.endpoint.port, 9900)
        XCTAssertEqual(configuration.apiKey, "env-key")
    }
}
