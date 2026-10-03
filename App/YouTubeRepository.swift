import Foundation
import YouTubeKit

enum CatalogCursor: Sendable {
    case search(SearchResponse)
    case playlist(PlaylistInfosResponse)
}

struct CatalogPage: Sendable {
    var title: String
    var tracks: [Track]
    var cursor: CatalogCursor? = nil
    var playlistID: String? = nil
}

struct AudioSource: Sendable {
    let url: URL
    let expires: Date
}

actor YouTubeRepository {
    static let shared = YouTubeRepository()
    private var audioCache: [String: AudioSource] = [:]

    private func model() -> YouTubeModel {
        let model = YouTubeModel()
        model.selectedLocale = "fr-FR"
        model.alwaysUseCookies = false
        return model
    }

    func search(_ query: String) async throws -> CatalogPage {
        let response = try await SearchResponse.sendThrowingRequest(youtubeModel: model(), data: [.query: query], useCookies: false)
        try Task.checkCancellation()
        return CatalogPage(title: "Résultats", tracks: response.results.compactMap { ($0 as? YTVideo).map(track) }, cursor: response.continuationToken == nil ? nil : .search(response))
    }

    func playlist(_ id: String) async throws -> CatalogPage {
        let response = try await PlaylistInfosResponse.sendThrowingRequest(youtubeModel: model(), data: [.browseId: id], useCookies: false)
        try Task.checkCancellation()
        return CatalogPage(title: response.title ?? "Playlist YouTube", tracks: response.results.map(track), cursor: response.continuationToken == nil ? nil : .playlist(response), playlistID: id)
    }

    func more(_ page: CatalogPage) async throws -> CatalogPage {
        var next = page
        switch page.cursor {
        case .search(var response):
            let continuation = try await response.fetchContinuationThrowing(youtubeModel: model(), useCookies: false)
            response.mergeContinuation(continuation)
            next.tracks = response.results.compactMap { ($0 as? YTVideo).map(track) }
            next.cursor = response.continuationToken == nil ? nil : .search(response)
        case .playlist(var response):
            let continuation = try await response.fetchContinuationThrowing(youtubeModel: model(), useCookies: false)
            response.mergeContinuation(continuation)
            next.tracks = response.results.map(track)
            next.cursor = response.continuationToken == nil ? nil : .playlist(response)
        case nil: return page
        }
        try Task.checkCancellation()
        return next
    }

    func video(_ id: String) async throws -> Track {
        let response = try await VideoInfosResponse.sendThrowingRequest(youtubeModel: model(), data: [.query: id], useCookies: false)
        return Track(id: id, title: response.title ?? "Vidéo YouTube", artist: response.channel?.name ?? "YouTube", artwork: response.thumbnails.last?.url, duration: nil)
    }

    func audio(_ id: String, refresh: Bool = false) async throws -> AudioSource {
        if !refresh, let cached = audioCache[id], cached.expires.timeIntervalSinceNow > 120 { return cached }
        let response = try await VideoInfosResponse.sendThrowingRequest(youtubeModel: model(), data: [.query: id], useCookies: false)
        try Task.checkCancellation()
        guard response.isLive != true else { throw SonoraError.liveUnsupported }
        // Select only AAC/M4A audio. A combined video stream is never a fallback.
        let formats = response.downloadFormats.compactMap { $0 as? AudioOnlyFormat }
            .filter { $0.mimeType == "audio/mp4" && ($0.codec == nil || $0.codec?.hasPrefix("mp4a") == true) }
            .sorted { lhs, rhs in
                let leftOriginal = lhs.formatLocaleInfos?.isAutoDubbed != true
                let rightOriginal = rhs.formatLocaleInfos?.isAutoDubbed != true
                if leftOriginal != rightOriginal { return leftOriginal }
                return (lhs.averageBitrate ?? lhs.bitrate ?? 0) > (rhs.averageBitrate ?? rhs.bitrate ?? 0)
            }
        for format in formats {
            var candidate: any AdaptiveDownloadFormat = format
            do {
                if let player = response.player { try player.processDownloadFormatURL(item: &candidate) }
                guard let url = candidate.url, url.scheme == "https" else { continue }
                let expiry = min(response.videoURLsExpireAt ?? Date().addingTimeInterval(1200), Date().addingTimeInterval(1200))
                let result = AudioSource(url: url, expires: expiry)
                audioCache[id] = result
                return result
            } catch { continue }
        }
        throw SonoraError.noAudio
    }

    private func track(_ value: YTVideo) -> Track {
        Track(id: value.videoId, title: value.title ?? "Vidéo YouTube", artist: value.channel?.name ?? "YouTube", artwork: value.thumbnails.last?.url, duration: value.timeLengthSeconds.map(Double.init))
    }
}
