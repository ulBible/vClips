import XCTest
@testable import vClips

final class ContentTypeTests: XCTestCase {
    func test_detectsURL() {
        XCTAssertEqual(ContentType.detect("https://example.com"), .url)
        XCTAssertEqual(ContentType.detect("http://a.b/c?d=e"), .url)
    }

    func test_detectsURL_trimsWhitespace() {
        XCTAssertEqual(ContentType.detect("  https://example.com \n"), .url)
    }

    func test_detectsEmail() {
        XCTAssertEqual(ContentType.detect("john@example.com"), .email)
    }

    func test_detectsFilePath() {
        XCTAssertEqual(ContentType.detect("/Users/bible/file.txt"), .filePath)
        XCTAssertEqual(ContentType.detect("~/Documents/notes.md"), .filePath)
    }

    func test_plainTextFallback() {
        XCTAssertEqual(ContentType.detect("hello world"), .text)
        XCTAssertEqual(ContentType.detect("not@an@email"), .text)
    }

    func test_symbolNames() {
        XCTAssertEqual(ContentType.url.symbolName, "link")
        XCTAssertEqual(ContentType.email.symbolName, "envelope.fill")
        XCTAssertEqual(ContentType.filePath.symbolName, "folder.fill")
        XCTAssertEqual(ContentType.text.symbolName, "text.alignleft")
    }

    func test_labels() {
        XCTAssertEqual(ContentType.url.label, "Link")
        XCTAssertEqual(ContentType.email.label, "Email")
        XCTAssertEqual(ContentType.filePath.label, "File")
        XCTAssertEqual(ContentType.text.label, "Text")
    }
}
