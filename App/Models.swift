import Foundation

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var artist: String
    var artwork: URL?
    var duration: Double?
}

struct SavedPlaylist: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var url: URL { URL(string: "https://www.youtube.com/playlist?list=\(id)")! }
}

enum YouTubeInput: Equatable {
    case search(String)
    case video(String)
    case playlist(String)

    static func parse(_ text: String) throws -> Self {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SonoraError.emptyQuery }
        let isLink = value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
        guard isLink else { return .search(value) }
        guard let url = URLComponents(string: value), let host = url.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        else { throw SonoraError.invalidLink }
        let values = url.queryItems ?? []
        if let id = values.first(where: { $0.name == "list" })?.value,
           valid(id, pattern: "^[a-zA-Z0-9_-]{3,150}$") { return .playlist(id) }
        let parts = url.path.split(separator: "/").map(String.init)
        var id = values.first(where: { $0.name == "v" })?.value
        if host == "youtu.be" { id = parts.first }
        if parts.count >= 2 && ["shorts", "embed", "live"].contains(parts[0]) { id = parts[1] }
        guard let videoID = id, valid(videoID, pattern: "^[a-zA-Z0-9_-]{11}$") else { throw SonoraError.invalidLink }
        return .video(videoID)
    }

    private static func valid(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

enum SonoraError: LocalizedError {
    case emptyQuery, invalidLink, playlistRequired, noAudio, liveUnsupported, unavailable
    var errorDescription: String? {
        switch self {
        case .emptyQuery: return "Écris un titre, un artiste ou colle un lien YouTube."
        case .invalidLink: return "Ce lien YouTube n’est pas reconnu."
        case .playlistRequired: return "Colle le lien d’une playlist publique ou non répertoriée."
        case .noAudio: return "Aucun flux audio compatible iPhone n’est disponible. Une mise à jour de l’accès YouTube peut être nécessaire."
        case .liveUnsupported: return "Les directs ne sont pas encore pris en charge."
        case .unavailable: return "Ce contenu est indisponible. Vérifie ta connexion et réessaie."
        }
    }
}

func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 && seconds < Double(Int.max) else { return "—" }
    let value = Int(seconds)
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}
