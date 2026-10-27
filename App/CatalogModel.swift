import Foundation
import Combine

@MainActor
final class CatalogModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var page: CatalogPage?
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var isHome = true
    private var request: Task<Void, Never>?
    private var requestID = UUID()

    func home(library: LibraryStore) {
        request?.cancel()
        let id = UUID(); requestID = id
        isHome = true; query = ""; error = nil
        page = CatalogPage(title: "Clips à découvrir", tracks: library.suggestions)
        isLoading = true
        let seed = library.searches.first ?? "clips musicaux officiels"
        request = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { isLoading = false } }
            do {
                var result = try await YouTubeRepository.shared.search(seed)
                for batch in 0..<3 {
                    guard !Task.isCancelled, requestID == id else { return }
                    var seen = Set<String>()
                    let unique = result.tracks.filter { seen.insert($0.id).inserted }
                    library.cacheSuggestions(unique)
                    page = CatalogPage(title: "Clips à découvrir", tracks: library.suggestions)
                    if unique.count >= 60 || result.cursor == nil || batch == 2 { break }
                    result = try await YouTubeRepository.shared.more(result)
                }
            } catch is CancellationError { }
            catch { if requestID == id { self.error = "Suggestions indisponibles pour le moment. Tu peux relancer une recherche ou réessayer." } }
        }
    }

    func submit(_ text: String, library: LibraryStore, requirePlaylist: Bool = false) {
        isHome = false
        request?.cancel()
        let id = UUID(); requestID = id
        request = Task { [weak self] in
            guard let self else { return }
            isLoading = true; error = nil
            defer { if requestID == id { isLoading = false } }
            do {
                let input = try YouTubeInput.parse(text)
                if requirePlaylist {
                    guard case .playlist = input else { throw SonoraError.playlistRequired }
                }
                let value: CatalogPage
                switch input {
                case .search(let query):
                    library.rememberSearch(query)
                    value = try await YouTubeRepository.shared.search(query)
                case .playlist(let playlist): value = try await YouTubeRepository.shared.playlist(playlist)
                case .video(let video): value = CatalogPage(title: "Prêt à écouter", tracks: [try await YouTubeRepository.shared.video(video)])
                }
                guard !Task.isCancelled, requestID == id else { return }
                page = value
                if case .search = input { library.cacheSuggestions(value.tracks) }
                if let playlistID = value.playlistID { library.remember(SavedPlaylist(id: playlistID, title: value.title)) }
            } catch is CancellationError { }
            catch {
                guard requestID == id else { return }
                self.error = (error as? SonoraError)?.localizedDescription ?? "YouTube ne répond pas. Vérifie ta connexion et réessaie. Les playlists privées ne sont pas accessibles."
            }
        }
    }

    func more() {
        guard !isLoading, let page, page.cursor != nil else { return }
        let id = UUID(); requestID = id
        request = Task { [weak self] in
            guard let self else { return }
            isLoading = true; error = nil
            defer { if requestID == id { isLoading = false } }
            do {
                let result = try await YouTubeRepository.shared.more(page)
                guard !Task.isCancelled, requestID == id else { return }
                self.page = result
            } catch is CancellationError { }
            catch { if requestID == id { self.error = "Impossible de charger la suite. Réessaie." } }
        }
    }
}
