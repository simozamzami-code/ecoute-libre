import XCTest
@testable import Sonora

// Separate from deterministic tests: YouTube can reject cloud-runner addresses.
final class YouTubeNetworkTests: XCTestCase {
    func testSearchReturnsTracks() async throws {
        let page = try await YouTubeRepository.shared.search("Daft Punk")
        XCTAssertFalse(page.tracks.isEmpty)
    }

    func testPublicPlaylistReturnsTracks() async throws {
        let page = try await YouTubeRepository.shared.playlist("PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj")
        XCTAssertFalse(page.tracks.isEmpty)
    }

    func testAudioReturnsPlayableBytes() async throws {
        let audio = try await YouTubeRepository.shared.audio("jNQXAC9IVRw", refresh: true)
        var request = URLRequest(url: audio.url)
        request.timeoutInterval = 30
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue([200, 206].contains(http.statusCode), "HTTP \(http.statusCode)")
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertTrue((http.mimeType ?? "").hasPrefix("audio/"), "Expected audio MIME type")
    }
}
