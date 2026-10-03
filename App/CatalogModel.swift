import Foundation
import Combine

@MainActor
final class CatalogModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var page: CatalogPage?
    @Published private(set) var isLoading = false
    @Published var error: String?
    private var request: Task<Void, Never>?
    private var requestID = UUID()

    func submit(_ text: String, library: LibraryStore, requirePlaylist: Bool = false) {
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
                case .search(let query): value = try await YouTubeRepository.shared.search(query)
                case .playlist(let playlist): value = try await YouTubeRepository.shared.playlist(playlist)
                case .video(let video): value = CatalogPage(title: "Prêt à écouter", tracks: [try await YouTubeRepository.shared.video(video)])
                }
                guard !Task.isCancelled, requestID == id else { return }
                page = value
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
