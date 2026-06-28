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
        XCTAssertEqual(ContentType.email.symbolName, "envelope")
        XCTAssertEqual(ContentType.filePath.symbolName, "doc")
        XCTAssertEqual(ContentType.text.symbolName, "doc.on.clipboard")
    }
}
