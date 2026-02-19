// Copyright 2024 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import XCTest
@testable import MumbleCore

final class TextMessageTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultInitialization() {
        let message = TextMessage(heading: nil, message: nil)

        XCTAssertNil(message.heading)
        XCTAssertNil(message.message)
        XCTAssertNil(message.date)
        XCTAssertTrue(message.embeddedLinks.isEmpty)
        XCTAssertEqual(message.embeddedImageCount, 0)
        XCTAssertFalse(message.isSentBySelf)
    }

    func testFullInitialization() {
        let date = Date()
        let links = ["http://example.com", "http://test.com"]

        let message = TextMessage(
            heading: "From User",
            message: "Hello!",
            date: date,
            embeddedLinks: links,
            embeddedImageCount: 2,
            isSentBySelf: true
        )

        XCTAssertEqual(message.heading, "From User")
        XCTAssertEqual(message.message, "Hello!")
        XCTAssertEqual(message.date, date)
        XCTAssertEqual(message.embeddedLinks, links)
        XCTAssertEqual(message.embeddedImageCount, 2)
        XCTAssertTrue(message.isSentBySelf)
    }

    // MARK: - Attachment Tests

    func testNumberOfAttachmentsWithLinksOnly() {
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedLinks: ["http://a.com", "http://b.com"]
        )

        XCTAssertEqual(message.numberOfAttachments, 2)
    }

    func testNumberOfAttachmentsWithImagesOnly() {
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedImageCount: 3
        )

        XCTAssertEqual(message.numberOfAttachments, 3)
    }

    func testNumberOfAttachmentsWithBoth() {
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedLinks: ["http://a.com"],
            embeddedImageCount: 2
        )

        XCTAssertEqual(message.numberOfAttachments, 3)
    }

    func testHasAttachmentsWhenEmpty() {
        let message = TextMessage(heading: nil, message: nil)

        XCTAssertFalse(message.hasAttachments)
    }

    func testHasAttachmentsWithLinks() {
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedLinks: ["http://example.com"]
        )

        XCTAssertTrue(message.hasAttachments)
    }

    func testHasAttachmentsWithImages() {
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedImageCount: 1
        )

        XCTAssertTrue(message.hasAttachments)
    }

    // MARK: - Equatable Tests

    func testEqualMessages() {
        let date = Date()
        let message1 = TextMessage(
            heading: "Test",
            message: "Hello",
            date: date,
            embeddedLinks: ["http://example.com"],
            embeddedImageCount: 1,
            isSentBySelf: true
        )
        let message2 = TextMessage(
            heading: "Test",
            message: "Hello",
            date: date,
            embeddedLinks: ["http://example.com"],
            embeddedImageCount: 1,
            isSentBySelf: true
        )

        XCTAssertEqual(message1, message2)
    }

    func testUnequalMessages() {
        let message1 = TextMessage(heading: "Test1", message: "Hello")
        let message2 = TextMessage(heading: "Test2", message: "Hello")

        XCTAssertNotEqual(message1, message2)
    }

    // MARK: - Edge Cases

    func testEmptyStrings() {
        let message = TextMessage(heading: "", message: "")

        XCTAssertEqual(message.heading, "")
        XCTAssertEqual(message.message, "")
    }

    func testLongMessage() {
        let longText = String(repeating: "Hello ", count: 1000)
        let message = TextMessage(heading: nil, message: longText)

        XCTAssertEqual(message.message, longText)
    }

    func testUnicodeContent() {
        let message = TextMessage(
            heading: "Von Benutzer 你好",
            message: "Emoji test: 🎉🎊✨"
        )

        XCTAssertEqual(message.heading, "Von Benutzer 你好")
        XCTAssertEqual(message.message, "Emoji test: 🎉🎊✨")
    }

    func testNegativeImageCountAffectsAttachments() {
        // embeddedImageCount is Int, so negative values are possible.
        // numberOfAttachments = links.count + embeddedImageCount
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedLinks: ["http://a.com"],
            embeddedImageCount: -1
        )

        // 1 + (-1) = 0
        XCTAssertEqual(message.numberOfAttachments, 0)
        XCTAssertFalse(message.hasAttachments)
    }

    func testZeroAttachments() {
        let message = TextMessage(
            heading: nil,
            message: nil,
            embeddedLinks: [],
            embeddedImageCount: 0
        )

        XCTAssertEqual(message.numberOfAttachments, 0)
        XCTAssertFalse(message.hasAttachments)
    }

    func testDateAffectsEquality() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)

        let message1 = TextMessage(heading: "Test", message: "Hello", date: date1)
        let message2 = TextMessage(heading: "Test", message: "Hello", date: date2)

        XCTAssertNotEqual(message1, message2)
    }

    func testIsSentBySelfAffectsEquality() {
        let message1 = TextMessage(heading: "Test", message: "Hello", isSentBySelf: true)
        let message2 = TextMessage(heading: "Test", message: "Hello", isSentBySelf: false)

        XCTAssertNotEqual(message1, message2)
    }
}
