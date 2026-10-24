import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [Track] = []
    @Published private(set) var playlists: [SavedPlaylist] = []
    @Published private(set) var searches: [String] = []
    @Published private(set) var suggestions: [Track] = []
    @Published var error: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        searches = Array((defaults.stringArray(forKey: "sonora.searches.v1") ?? []).prefix(20))
        if let data = defaults.data(forKey: "sonora.suggestions.v1") { suggestions = (try? JSONDecoder().decode([Track].self, from: data)) ?? [] }
        if let data = defaults.data(forKey: "sonora.favorites.v1") { favorites = (try? JSONDecoder().decode([Track].self, from: data)) ?? [] }
        if let data = defaults.data(forKey: "sonora.playlists.v1") { playlists = (try? JSONDecoder().decode([SavedPlaylist].self, from: data)) ?? [] }
    }

    func contains(_ track: Track) -> Bool { favorites.contains { $0.id == track.id } }
    func rememberSearch(_ text: String) {
        let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !value.isEmpty else { return }
        searches.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
        searches.insert(value, at: 0)
        searches = Array(searches.prefix(20))
        save()
    }
    func removeSearch(_ text: String) { searches.removeAll { $0 == text }; suggestions = []; save() }
    func clearSearches() { searches = []; suggestions = []; save() }
    func cacheSuggestions(_ tracks: [Track]) { suggestions = Array(tracks.prefix(12)); save() }
    func toggle(_ track: Track) {
        if contains(track) { favorites.removeAll { $0.id == track.id } } else { favorites.insert(track, at: 0) }
        save()
    }
    func remember(_ playlist: SavedPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) { playlists[index] = playlist } else { playlists.insert(playlist, at: 0) }
        save()
    }
    func remove(_ playlist: SavedPlaylist) { playlists.removeAll { $0.id == playlist.id }; save() }
    private func save() {
        do {
            defaults.set(searches, forKey: "sonora.searches.v1")
            defaults.set(try JSONEncoder().encode(suggestions), forKey: "sonora.suggestions.v1")
            defaults.set(try JSONEncoder().encode(favorites), forKey: "sonora.favorites.v1")
            defaults.set(try JSONEncoder().encode(playlists), forKey: "sonora.playlists.v1")
        } catch { self.error = "L’enregistrement de la bibliothèque a échoué." }
    }
}
