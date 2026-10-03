import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [Track] = []
    @Published private(set) var playlists: [SavedPlaylist] = []
    @Published var error: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "sonora.favorites.v1") { favorites = (try? JSONDecoder().decode([Track].self, from: data)) ?? [] }
        if let data = defaults.data(forKey: "sonora.playlists.v1") { playlists = (try? JSONDecoder().decode([SavedPlaylist].self, from: data)) ?? [] }
    }

    func contains(_ track: Track) -> Bool { favorites.contains { $0.id == track.id } }
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
            defaults.set(try JSONEncoder().encode(favorites), forKey: "sonora.favorites.v1")
            defaults.set(try JSONEncoder().encode(playlists), forKey: "sonora.playlists.v1")
        } catch { self.error = "L’enregistrement de la bibliothèque a échoué." }
    }
}
