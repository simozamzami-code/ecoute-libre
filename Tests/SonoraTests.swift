import XCTest
@testable import Sonora

final class SonoraTests: XCTestCase {
    func testYouTubeLinksAndSearch() throws {
        XCTAssertEqual(try YouTubeInput.parse("  Daft Punk  "), .search("Daft Punk"))
        XCTAssertEqual(try YouTubeInput.parse("https://youtu.be/jNQXAC9IVRw?si=test"), .video("jNQXAC9IVRw"))
        XCTAssertEqual(try YouTubeInput.parse("https://www.youtube.com/shorts/jNQXAC9IVRw"), .video("jNQXAC9IVRw"))
        XCTAssertEqual(try YouTubeInput.parse("https://m.youtube.com/watch?v=jNQXAC9IVRw"), .video("jNQXAC9IVRw"))
        XCTAssertEqual(try YouTubeInput.parse("https://www.youtube.com/watch?v=jNQXAC9IVRw&list=PL123456"), .playlist("PL123456"))
    }
    func testUnrelatedAndMalformedURLsAreRejected() {
        for value in ["", "https://youtube.com.evil.example/watch?v=jNQXAC9IVRw", "https://evil.example/?list=PL123456", "https://youtube.com/watch?v=short", "https://youtu.be/"] {
            XCTAssertThrowsError(try YouTubeInput.parse(value), value)
        }
    }
    func testLibrarySurvivesReloadAndFavoritesToggle() async {
        await MainActor.run {
        let suite = "sonora.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(defaults: defaults)
        let track = Track(id: "jNQXAC9IVRw", title: "Test", artist: "Artist", artwork: nil, duration: 19)
        library.toggle(track)
        library.remember(SavedPlaylist(id: "PL123456", title: "First"))
        library.remember(SavedPlaylist(id: "PL123456", title: "Updated"))
        let restored = LibraryStore(defaults: defaults)
        XCTAssertEqual(restored.favorites, [track])
        XCTAssertEqual(restored.playlists.count, 1)
        XCTAssertEqual(restored.playlists.first?.title, "Updated")
        restored.toggle(track)
        XCTAssertTrue(LibraryStore(defaults: defaults).favorites.isEmpty)
        }
    }
    func testClockHandlesInvalidAndLongDurations() {
        XCTAssertEqual(timeLabel(.infinity), "—")
        XCTAssertEqual(timeLabel(65), "1:05")
        XCTAssertEqual(timeLabel(3661), "1:01:01")
    }
}
