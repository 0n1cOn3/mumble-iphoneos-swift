// Copyright 2024 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import XCTest
@testable import MumbleCore

final class DataURLTests: XCTestCase {

    // MARK: - Valid Data URL Tests

    func testParseValidPNGDataURL() {
        // A minimal valid PNG (1x1 transparent pixel)
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let dataURL = "data:image/png;base64,\(base64PNG)"

        let result = DataURL.parse(dataURL)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.mimeType, "image/png")
        XCTAssertFalse(result?.data.isEmpty ?? true)
    }

    func testParseValidTextDataURL() {
        let text = "Hello, World!"
        let base64Text = Data(text.utf8).base64EncodedString()
        let dataURL = "data:text/plain;base64,\(base64Text)"

        let result = DataURL.parse(dataURL)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.mimeType, "text/plain")

        if let data = result?.data {
            let decoded = String(data: data, encoding: .utf8)
            XCTAssertEqual(decoded, "Hello, World!")
        }
    }

    func testDataFromDataURL() {
        let text = "Test data"
        let base64Text = Data(text.utf8).base64EncodedString()
        let dataURL = "data:text/plain;base64,\(base64Text)"

        let data = DataURL.data(from: dataURL)

        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Test data")
    }

    // MARK: - Invalid Data URL Tests

    func testInvalidPrefixReturnsNil() {
        let invalid = "http://example.com/image.png"
        XCTAssertNil(DataURL.parse(invalid))
        XCTAssertNil(DataURL.data(from: invalid))
    }

    func testMissingSemicolonReturnsNil() {
        let invalid = "data:image/pngbase64,abc123"
        XCTAssertNil(DataURL.parse(invalid))
    }

    func testMissingBase64MarkerReturnsNil() {
        let invalid = "data:image/png;abc123"
        XCTAssertNil(DataURL.parse(invalid))
    }

    func testInvalidBase64ReturnsNil() {
        let invalid = "data:image/png;base64,not-valid-base64!!!"
        XCTAssertNil(DataURL.parse(invalid))
    }

    func testEmptyDataURLReturnsNil() {
        let empty = ""
        XCTAssertNil(DataURL.parse(empty))
    }

    func testJustPrefixReturnsNil() {
        let justPrefix = "data:"
        XCTAssertNil(DataURL.parse(justPrefix))
    }

    // MARK: - isDataURL Tests

    func testIsDataURLWithValidURL() {
        let base64 = Data("test".utf8).base64EncodedString()
        let valid = "data:text/plain;base64,\(base64)"

        XCTAssertTrue(DataURL.isDataURL(valid))
    }

    func testIsDataURLWithInvalidURL() {
        XCTAssertFalse(DataURL.isDataURL("http://example.com"))
        XCTAssertFalse(DataURL.isDataURL(""))
        XCTAssertFalse(DataURL.isDataURL("data:"))
    }

    // MARK: - Edge Cases

    func testDataURLWithSpacesInBase64() {
        let text = "Test"
        let base64 = Data(text.utf8).base64EncodedString()
        // Add spaces (which should be stripped)
        let base64WithSpaces = base64.enumerated().map { i, c in
            i % 2 == 0 ? "\(c) " : "\(c)"
        }.joined()

        let dataURL = "data:text/plain;base64,\(base64WithSpaces)"
        let data = DataURL.data(from: dataURL)

        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Test")
    }

    func testDataURLWithPercentEncoding() {
        let text = "Hello"
        let base64 = Data(text.utf8).base64EncodedString()
        // Percent-encode some characters
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64

        let dataURL = "data:text/plain;base64,\(encoded)"
        let data = DataURL.data(from: dataURL)

        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testVariousMIMETypes() {
        let testCases = [
            "image/jpeg",
            "image/gif",
            "application/json",
            "application/octet-stream"
        ]

        for mimeType in testCases {
            let base64 = Data("test".utf8).base64EncodedString()
            let dataURL = "data:\(mimeType);base64,\(base64)"

            let result = DataURL.parse(dataURL)
            XCTAssertNotNil(result, "Failed for MIME type: \(mimeType)")
            XCTAssertEqual(result?.mimeType, mimeType)
        }
    }

    // MARK: - Additional Edge Cases

    func testEmptyMIMEType() {
        // "data:;base64,<data>" — empty MIME type string
        let base64 = Data("test".utf8).base64EncodedString()
        let dataURL = "data:;base64,\(base64)"

        let result = DataURL.parse(dataURL)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.mimeType, "")
        XCTAssertEqual(String(data: result!.data, encoding: .utf8), "test")
    }

    func testBase64MarkerIsCaseSensitive() {
        // The code checks hasPrefix("base64,") — uppercase should fail
        let base64 = Data("test".utf8).base64EncodedString()
        let dataURL = "data:text/plain;BASE64,\(base64)"

        let result = DataURL.parse(dataURL)
        XCTAssertNil(result, "Uppercase BASE64 marker should not be recognized")
    }

    func testEmptyBase64Payload() {
        // Empty string base64-encodes to "" — Data(base64Encoded: "") returns empty Data
        let dataURL = "data:text/plain;base64,"

        let result = DataURL.parse(dataURL)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.data.count, 0)
    }

    func testParseResultEquatable() {
        let data = Data("hello".utf8)
        let a = DataURL.ParseResult(mimeType: "text/plain", data: data)
        let b = DataURL.ParseResult(mimeType: "text/plain", data: data)
        let c = DataURL.ParseResult(mimeType: "image/png", data: data)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testDataURLWithMultipleSemicolons() {
        // MIME type containing extra parameters like "text/plain;charset=utf-8"
        // The parser splits on first semicolon, so charset becomes part of the remainder
        let base64 = Data("test".utf8).base64EncodedString()
        let dataURL = "data:text/plain;charset=utf-8;base64,\(base64)"

        let result = DataURL.parse(dataURL)
        // The first semicolon splits: mimeType = "text/plain", remainder = "charset=utf-8;base64,..."
        // "charset=utf-8;base64,..." does NOT start with "base64," so this should fail
        XCTAssertNil(result, "Extra parameters before base64 marker should cause parse failure")
    }
}
