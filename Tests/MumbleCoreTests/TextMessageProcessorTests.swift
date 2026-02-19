// Copyright 2024 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import XCTest
@testable import MumbleCore

final class TextMessageProcessorTests: XCTestCase {

    // MARK: - Basic Processing Tests

    func testSimpleTextWrappedInParagraph() {
        let input = "Hello, world!"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>Hello, world!</p>")
    }

    func testEmptyString() {
        let input = ""
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p></p>")
    }

    // MARK: - HTML Escaping Tests

    func testEscapesLessThan() {
        let input = "a < b"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>a &lt; b</p>")
    }

    func testEscapesGreaterThan() {
        let input = "a > b"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>a &gt; b</p>")
    }

    func testEscapesHTMLTags() {
        let input = "<script>alert('xss')</script>"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>&lt;script&gt;alert('xss')&lt;/script&gt;</p>")
    }

    func testEscapeHTMLFunction() {
        let input = "<div class=\"test\">'hello' & goodbye</div>"
        let output = TextMessageProcessor.escapeHTML(input)

        XCTAssertEqual(output, "&lt;div class=&quot;test&quot;&gt;&#39;hello&#39; &amp; goodbye&lt;/div&gt;")
    }

    // MARK: - URL Detection Tests

    func testDetectsHTTPURL() {
        let input = "Check out http://example.com for more info"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.contains("<a href=\"http://example.com\">http://example.com</a>"))
    }

    func testDetectsHTTPSURL() {
        let input = "Visit https://secure.example.com"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.contains("<a href=\"https://secure.example.com\">https://secure.example.com</a>"))
    }

    func testDetectsMultipleURLs() {
        let input = "See http://first.com and http://second.com"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.contains("<a href=\"http://first.com\">http://first.com</a>"))
        XCTAssertTrue(output!.contains("<a href=\"http://second.com\">http://second.com</a>"))
    }

    func testURLWithPath() {
        let input = "Read https://example.com/path/to/page.html here"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.contains("https://example.com/path/to/page.html"))
    }

    func testURLWithQueryString() {
        let input = "Link: https://example.com/search?q=test&page=1"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        // The URL should be wrapped in an anchor tag
        XCTAssertTrue(output!.contains("<a href="))
    }

    // MARK: - Mixed Content Tests

    func testTextBeforeAndAfterURL() {
        let input = "Hello http://example.com world"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.hasPrefix("<p>Hello "))
        XCTAssertTrue(output!.hasSuffix(" world</p>"))
    }

    func testURLAtStart() {
        let input = "http://example.com is a great site"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.hasPrefix("<p><a href="))
    }

    func testURLAtEnd() {
        let input = "Visit http://example.com"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertNotNil(output)
        XCTAssertTrue(output!.hasSuffix("</a></p>"))
    }

    // MARK: - URL-Only Message

    func testURLOnlyMessage() {
        let input = "http://example.com"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p><a href=\"http://example.com\">http://example.com</a></p>")
    }

    // MARK: - Ampersand Handling

    func testProcessedHTMLDoesNotEscapeAmpersand() {
        // processedHTML only escapes < and > — ampersand is passed through as-is.
        // This differs from escapeHTML which escapes all five HTML entities.
        let input = "Tom & Jerry"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>Tom & Jerry</p>")
    }

    func testEscapeHTMLEscapesAmpersand() {
        let input = "Tom & Jerry"
        let output = TextMessageProcessor.escapeHTML(input)

        XCTAssertEqual(output, "Tom &amp; Jerry")
    }

    func testEscapeHTMLEscapesDoubleQuotes() {
        let input = "He said \"hello\""
        let output = TextMessageProcessor.escapeHTML(input)

        XCTAssertTrue(output.contains("&quot;"))
    }

    func testEscapeHTMLEscapesSingleQuotes() {
        let input = "It's fine"
        let output = TextMessageProcessor.escapeHTML(input)

        XCTAssertTrue(output.contains("&#39;"))
    }

    // MARK: - Return Type

    func testProcessedHTMLNeverReturnsNil() {
        // processedHTML returns String? but the regex is always valid,
        // so it should never actually return nil for any input.
        let inputs = ["", "hello", "<script>", "http://x.com", "🎉", String(repeating: "a", count: 10000)]

        for input in inputs {
            XCTAssertNotNil(TextMessageProcessor.processedHTML(from: input),
                            "processedHTML returned nil for: \(input.prefix(20))")
        }
    }

    // MARK: - Edge Cases

    func testTextWithNewlines() {
        let input = "Line 1\nLine 2"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>Line 1\nLine 2</p>")
    }

    func testUnicodeText() {
        let input = "Hëllo Wörld 你好 🎉"
        let output = TextMessageProcessor.processedHTML(from: input)

        XCTAssertEqual(output, "<p>Hëllo Wörld 你好 🎉</p>")
    }

    func testURLWithQueryStringPreservesFullURL() {
        let input = "https://example.com/search?q=test&page=1"
        let output = TextMessageProcessor.processedHTML(from: input)

        // The full URL including query parameters should be inside the href
        XCTAssertEqual(output,
            "<p><a href=\"https://example.com/search?q=test&page=1\">https://example.com/search?q=test&page=1</a></p>")
    }
}
