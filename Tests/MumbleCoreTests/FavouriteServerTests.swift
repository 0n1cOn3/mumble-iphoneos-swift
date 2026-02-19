// Copyright 2024 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import XCTest
@testable import MumbleCore

final class FavouriteServerTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        let server = FavouriteServer()

        XCTAssertEqual(server.primaryKey, -1)
        XCTAssertNil(server.displayName)
        XCTAssertNil(server.hostName)
        XCTAssertEqual(server.port, 64738)
        XCTAssertNil(server.userName)
        XCTAssertNil(server.password)
    }

    func testCustomInitialization() {
        let server = FavouriteServer(
            displayName: "Test Server",
            hostName: "mumble.example.com",
            port: 12345,
            userName: "testuser",
            password: "secret"
        )

        XCTAssertEqual(server.primaryKey, -1)
        XCTAssertEqual(server.displayName, "Test Server")
        XCTAssertEqual(server.hostName, "mumble.example.com")
        XCTAssertEqual(server.port, 12345)
        XCTAssertEqual(server.userName, "testuser")
        XCTAssertEqual(server.password, "secret")
    }

    // MARK: - Primary Key Tests

    func testHasPrimaryKeyWhenNotSet() {
        let server = FavouriteServer()
        XCTAssertFalse(server.hasPrimaryKey)
    }

    func testHasPrimaryKeyWhenSet() {
        var server = FavouriteServer()
        server.primaryKey = 42
        XCTAssertTrue(server.hasPrimaryKey)
    }

    func testHasPrimaryKeyWhenZero() {
        var server = FavouriteServer()
        server.primaryKey = 0
        XCTAssertTrue(server.hasPrimaryKey)
    }

    // MARK: - Comparison Tests

    func testCompareBothNilNames() {
        let server1 = FavouriteServer()
        let server2 = FavouriteServer()

        XCTAssertEqual(server1.compare(server2), .orderedSame)
    }

    func testCompareFirstNilName() {
        let server1 = FavouriteServer()
        let server2 = FavouriteServer(displayName: "Server B")

        XCTAssertEqual(server1.compare(server2), .orderedAscending)
    }

    func testCompareSecondNilName() {
        let server1 = FavouriteServer(displayName: "Server A")
        let server2 = FavouriteServer()

        XCTAssertEqual(server1.compare(server2), .orderedDescending)
    }

    func testCompareSameNames() {
        let server1 = FavouriteServer(displayName: "Server")
        let server2 = FavouriteServer(displayName: "Server")

        XCTAssertEqual(server1.compare(server2), .orderedSame)
    }

    func testCompareCaseInsensitive() {
        let server1 = FavouriteServer(displayName: "server")
        let server2 = FavouriteServer(displayName: "SERVER")

        XCTAssertEqual(server1.compare(server2), .orderedSame)
    }

    func testCompareAlphabeticalOrder() {
        let server1 = FavouriteServer(displayName: "Alpha")
        let server2 = FavouriteServer(displayName: "Beta")

        XCTAssertEqual(server1.compare(server2), .orderedAscending)
        XCTAssertEqual(server2.compare(server1), .orderedDescending)
    }

    // MARK: - Comparable Tests

    func testSortableArray() {
        let servers = [
            FavouriteServer(displayName: "Charlie"),
            FavouriteServer(displayName: "Alpha"),
            FavouriteServer(displayName: "Beta")
        ]

        let sorted = servers.sorted()

        XCTAssertEqual(sorted[0].displayName, "Alpha")
        XCTAssertEqual(sorted[1].displayName, "Beta")
        XCTAssertEqual(sorted[2].displayName, "Charlie")
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = FavouriteServer(
            primaryKey: 5,
            displayName: "Test",
            hostName: "test.com",
            port: 64738,
            userName: "user",
            password: "pass"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FavouriteServer.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Equatable Tests

    func testEquality() {
        let server1 = FavouriteServer(displayName: "Test", hostName: "test.com", port: 64738)
        let server2 = FavouriteServer(displayName: "Test", hostName: "test.com", port: 64738)

        XCTAssertEqual(server1, server2)
    }

    func testInequality() {
        let server1 = FavouriteServer(displayName: "Test1", hostName: "test.com")
        let server2 = FavouriteServer(displayName: "Test2", hostName: "test.com")

        XCTAssertNotEqual(server1, server2)
    }

    func testInequalityByPort() {
        let server1 = FavouriteServer(displayName: "Test", hostName: "test.com", port: 64738)
        let server2 = FavouriteServer(displayName: "Test", hostName: "test.com", port: 12345)

        XCTAssertNotEqual(server1, server2)
    }

    // MARK: - Port Edge Cases

    func testPortZero() {
        let server = FavouriteServer(port: 0)
        XCTAssertEqual(server.port, 0)
    }

    func testPortMaxValue() {
        let server = FavouriteServer(port: UInt.max)
        XCTAssertEqual(server.port, UInt.max)
    }

    func testDefaultPortIsMumbleStandard() {
        let server = FavouriteServer()
        XCTAssertEqual(server.port, 64738)
    }

    // MARK: - Primary Key Edge Cases

    func testNegativePrimaryKeyIsNotPersisted() {
        var server = FavouriteServer()
        server.primaryKey = -5
        XCTAssertFalse(server.hasPrimaryKey)
    }

    func testPrimaryKeyExactlyMinusOne() {
        let server = FavouriteServer(primaryKey: -1)
        XCTAssertFalse(server.hasPrimaryKey)
    }
}
