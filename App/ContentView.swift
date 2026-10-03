import SwiftUI
import AVKit

extension Color {
    static let sonoraBackground = Color(red: 16/255, green: 19/255, blue: 16/255)
    static let sonoraCard = Color(red: 30/255, green: 35/255, blue: 29/255)
    static let sonoraGreen = Color(red: 198/255, green: 243/255, blue: 106/255)
    static let sonoraInk = Color(red: 243/255, green: 245/255, blue: 234/255)
    static let sonoraMuted = Color(red: 155/255, green: 164/255, blue: 147/255)
}

struct ContentView: View {
    enum Tab: String, CaseIterable { case search = "Recherche", playlists = "Playlists", favorites = "Favoris" }
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @StateObject private var catalog = CatalogModel()
    @State private var tab: Tab = .search
    @State private var showImport = false
    @State private var importURL = ""
    @State private var showPlayer = false
    @State private var showInfo = false
    @State private var pendingRemoval: SavedPlaylist?
    @FocusState private var searchFocused: Bool

    private var tracks: [Track] { tab == .favorites ? library.favorites : catalog.page?.tracks ?? [] }
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").foregroundStyle(Color.sonoraGreen).font(.title2.bold())
                    Text("sonora").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1.5)
                }
                Spacer()
                Button { showInfo = true } label: { Image(systemName: "info.circle").font(.title3).foregroundStyle(Color.sonoraMuted) }
                    .accessibilityLabel("À propos de Sonora")
            }
            HStack(spacing: 5) {
                ForEach(Tab.allCases, id: \.self) { value in
                    Button { tab = value; searchFocused = false } label: {
                        Text(value.rawValue).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(tab == value ? Color.sonoraBackground : Color.sonoraMuted)
                            .background(tab == value ? Color.sonoraGreen : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(4).background(Color.sonoraCard, in: Capsule())

            if tab == .search {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.sonoraMuted)
                    TextField("Un titre, un artiste, un lien…", text: $catalog.query)
                        .font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).focused($searchFocused).onSubmit(submit)
                    if !catalog.query.isEmpty {
                        Button(action: submit) { Image(systemName: "arrow.right.circle.fill").font(.title2) }.accessibilityLabel("Rechercher")
                    }
                }.padding(15).background(Color.sonoraCard, in: RoundedRectangle(cornerRadius: 17))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == .playlists { playlistsContent }
                    else { tracksContent }
                    if let error = library.error { message(error, error: true) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)
            }.scrollDismissesKeyboard(.interactively)
            dock
        }
        .foregroundStyle(Color.sonoraInk)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Color.sonoraBackground.ignoresSafeArea())
        .sheet(isPresented: $showPlayer) { PlayerSheet().presentationDragIndicator(.visible) }
        .sheet(isPresented: $showImport) { importSheet }
        .sheet(isPresented: $showInfo) { aboutSheet }
        .alert("Retirer cette playlist ?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Retirer", role: .destructive) { if let playlist = pendingRemoval { library.remove(playlist) }; pendingRemoval = nil }
            Button("Annuler", role: .cancel) { pendingRemoval = nil }
        } message: { Text("Elle sera retirée de Sonora uniquement.") }
        .onOpenURL { url in
            guard url.scheme == "sonora", let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else { return }
            catalog.query = value; tab = .search; submit()
        }
    }

    @ViewBuilder private var tracksContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tab == .favorites ? "Tes coups de cœur." : catalog.page?.title ?? "À ton rythme.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
            Text(tab == .favorites ? "Les titres que tu veux retrouver." : "Tout ce que tu aimes. Juste le son.")
                .font(.subheadline).foregroundStyle(Color.sonoraMuted)
        }
        if tab == .search {
            if catalog.isLoading { HStack { ProgressView(); Text("On cherche pour toi…").font(.subheadline) }.foregroundStyle(Color.sonoraGreen) }
            if let error = catalog.error { message(error, error: true) }
        }
        if tracks.isEmpty && !catalog.isLoading {
            VStack(spacing: 16) {
                Image(systemName: tab == .favorites ? "heart" : "headphones").font(.system(size: 48, weight: .light)).foregroundStyle(Color.sonoraGreen)
                Text(tab == .favorites ? "Garde tes découvertes ici." : "Le prochain titre t’attend.").font(.headline)
                Text(tab == .favorites ? "Touche le cœur à côté d’un titre pour l’ajouter à tes favoris." : "Recherche sur YouTube ou colle le lien d’une vidéo ou d’une playlist.")
                    .font(.subheadline).foregroundStyle(Color.sonoraMuted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 35).padding(.horizontal, 15)
        } else if !tracks.isEmpty {
            HStack {
                Text("\(tracks.count) titres").font(.caption).foregroundStyle(Color.sonoraMuted)
                Spacer()
                Button { player.play(tracks) } label: { Label("Tout écouter", systemImage: "play.fill").font(.subheadline.bold()) }
            }
            LazyVStack(spacing: 15) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { position, track in
                    TrackRow(track: track, active: player.current?.id == track.id) { player.play(tracks, startingAt: position) }
                }
            }
            if tab == .search, catalog.page?.cursor != nil {
                Button { catalog.more() } label: { Text("Charger la suite").frame(maxWidth: .infinity).padding(13) }
                    .background(Color.sonoraCard, in: RoundedRectangle(cornerRadius: 14)).disabled(catalog.isLoading)
            }
        }
    }

    private var playlistsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ta collection.").font(.system(size: 29, weight: .bold, design: .rounded))
            Text("Tes playlists YouTube, à portée d’oreille.").font(.subheadline).foregroundStyle(Color.sonoraMuted)
            Button { showImport = true } label: {
                Label("Importer une playlist", systemImage: "plus").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(17)
            }.foregroundStyle(Color.sonoraBackground).background(Color.sonoraGreen, in: RoundedRectangle(cornerRadius: 17))
            if library.playlists.isEmpty {
                Text("Colle le lien d’une playlist publique ou non répertoriée. Elle restera enregistrée ici.")
                    .font(.subheadline).foregroundStyle(Color.sonoraMuted).padding(.top, 12)
            }
            ForEach(library.playlists) { playlist in
                HStack(spacing: 12) {
                    Button {
                        tab = .search
                        catalog.submit(playlist.url.absoluteString, library: library)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note.list").font(.title2).foregroundStyle(Color.sonoraGreen).frame(width: 54, height: 54).background(Color.sonoraCard, in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.title).font(.subheadline.bold()).lineLimit(2)
                                Text("Playlist YouTube").font(.caption).foregroundStyle(Color.sonoraMuted)
                            }
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                    Button { pendingRemoval = playlist } label: { Image(systemName: "trash").padding(8).foregroundStyle(Color.sonoraMuted) }.accessibilityLabel("Retirer \(playlist.title)")
                }
            }
        }
    }

    private var dock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { if player.current != nil { showPlayer = true } } label: {
                    HStack(spacing: 12) {
                        Cover(url: player.current?.artwork).frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.current?.title ?? "Juste le son.").font(.subheadline.bold()).lineLimit(1)
                            Text(player.current?.artist ?? "Ton prochain coup de cœur t’attend").font(.caption).foregroundStyle(Color.sonoraMuted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(.plain)
                if player.isLoading { ProgressView().tint(.sonoraGreen) }
                Button { player.toggle() } label: {
                    Image(systemName: player.error != nil ? "arrow.clockwise" : player.wantsPlayback ? "pause.fill" : "play.fill")
                        .font(.headline).foregroundStyle(Color.sonoraBackground).frame(width: 43, height: 43).background(Color.sonoraGreen, in: Circle())
                }.disabled(player.current == nil).accessibilityLabel(player.error != nil ? "Réessayer" : player.wantsPlayback ? "Pause" : "Écouter")
            }
            if let error = player.error { Text(error).font(.caption).foregroundStyle(Color.orange).fixedSize(horizontal: false, vertical: true) }
            if player.current != nil { ProgressView(value: player.duration > 0 ? min(player.elapsed / player.duration, 1) : 0).tint(.sonoraGreen) }
        }.padding(13).background(Color.sonoraCard, in: RoundedRectangle(cornerRadius: 20))
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ta playlist, en audio.").font(.title.bold())
                Text("Copie le lien de partage depuis YouTube, puis colle-le ici.").foregroundStyle(Color.sonoraMuted)
                TextField("https://www.youtube.com/playlist?list=…", text: $importURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding().background(Color.sonoraCard, in: RoundedRectangle(cornerRadius: 14))
                Button {
                    tab = .search; showImport = false
                    catalog.submit(importURL, library: library, requirePlaylist: true)
                } label: { Text("Importer").bold().frame(maxWidth: .infinity).padding() }
                    .foregroundStyle(Color.sonoraBackground).background(Color.sonoraGreen, in: RoundedRectangle(cornerRadius: 14)).disabled(importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }.padding(22).background(Color.sonoraBackground).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { showImport = false } } }
        }.presentationDetents([.medium, .large])
    }

    private var aboutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(Color.sonoraGreen)
                    Text("sonora").font(.largeTitle.bold())
                    Text("Une bibliothèque à toi, pour écouter YouTube en audio.")
                    Text("Les favoris et liens de playlists restent sur cet iPhone. Aucun compte Google n’est nécessaire.").foregroundStyle(Color.sonoraMuted)
                    Text("Les publicités ajoutées par YouTube ne sont pas chargées. Les sponsors présents dans l’enregistrement restent audibles. Les directs et playlists privées ne sont pas pris en charge.").font(.subheadline).foregroundStyle(Color.sonoraMuted)
                    Text("Accès YouTube non officiel : une évolution du service peut nécessiter une mise à jour de Sonora.").font(.footnote).foregroundStyle(Color.sonoraMuted)
                    Link("YouTubeKit · bibliothèque open source", destination: URL(string: "https://github.com/b5i/YouTubeKit")!)
                    Text("Version de test 0.1.0").font(.caption).foregroundStyle(Color.sonoraMuted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.background(Color.sonoraBackground).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showInfo = false } } }
        }
    }
    private func submit() { searchFocused = false; catalog.submit(catalog.query, library: library) }
    private func message(_ value: String, error: Bool) -> some View { Text(value).font(.subheadline).foregroundStyle(error ? Color.orange : Color.sonoraGreen).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.sonoraCard, in: RoundedRectangle(cornerRadius: 14)) }
}

struct Cover: View {
    let url: URL?
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                ZStack { Color.sonoraCard; Image(systemName: "waveform").resizable().scaledToFit().padding(geometry.size.width * 0.24).foregroundStyle(Color.sonoraGreen) }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    let track: Track
    var active = false
    let play: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: play) {
                HStack(spacing: 12) {
                    Cover(url: track.artwork).frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.subheadline.weight(.semibold)).foregroundStyle(active ? Color.sonoraGreen : Color.sonoraInk).lineLimit(2)
                        Text(track.artist + (track.duration.map { " · " + timeLabel($0) } ?? "")).font(.caption).foregroundStyle(Color.sonoraMuted).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { library.toggle(track) } label: {
                Image(systemName: library.contains(track) ? "heart.fill" : "heart").font(.title3).foregroundStyle(library.contains(track) ? Color.sonoraGreen : Color.sonoraMuted).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(library.contains(track) ? "Retirer des favoris" : "Ajouter aux favoris")
        }
    }
}

struct PlayerSheet: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @State private var showQueue = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("JUSTE LE SON").font(.caption.weight(.bold)).tracking(3).foregroundStyle(Color.sonoraGreen)
                    Cover(url: player.current?.artwork).aspectRatio(1, contentMode: .fit).frame(maxWidth: 330).shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(player.current?.title ?? "Sonora").font(.title2.bold())
                            Text(player.current?.artist ?? "").font(.subheadline).foregroundStyle(Color.sonoraMuted)
                        }
                        Spacer()
                        if let track = player.current { Button { library.toggle(track) } label: { Image(systemName: library.contains(track) ? "heart.fill" : "heart").font(.title2) }.accessibilityLabel("Favori") }
                    }
                    VStack(spacing: 3) {
                        Slider(value: Binding(get: { isScrubbing ? scrubPosition : min(player.elapsed, max(player.duration, 1)) }, set: { scrubPosition = $0 }), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                            if editing { scrubPosition = player.elapsed; isScrubbing = true } else { player.seek(to: scrubPosition); isScrubbing = false }
                        }).disabled(player.duration <= 0).accessibilityLabel("Position dans le titre")
                        HStack { Text(timeLabel(isScrubbing ? scrubPosition : player.elapsed)); Spacer(); Text(timeLabel(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(Color.sonoraMuted)
                    }
                    HStack(spacing: 30) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title2) }.accessibilityLabel("Précédent")
                        Button { player.toggle() } label: {
                            Image(systemName: player.error != nil ? "arrow.clockwise" : player.wantsPlayback ? "pause.fill" : "play.fill").font(.title).foregroundStyle(Color.sonoraBackground).frame(width: 76, height: 76).background(Color.sonoraGreen, in: Circle())
                        }.accessibilityLabel(player.error != nil ? "Réessayer" : player.wantsPlayback ? "Pause" : "Écouter")
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title2) }.accessibilityLabel("Suivant")
                    }.foregroundStyle(Color.sonoraInk)
                    if player.isLoading { ProgressView("Chargement audio…").font(.caption) }
                    if let error = player.error { Text(error).font(.subheadline).foregroundStyle(Color.orange) }
                    if let warning = player.warning { Text(warning).font(.caption).foregroundStyle(Color.sonoraMuted) }
                    HStack {
                        Button { player.toggleShuffle() } label: { Image(systemName: "shuffle").font(.title3).foregroundStyle(player.shuffle ? Color.sonoraGreen : Color.sonoraMuted) }.disabled(player.isLoading).accessibilityLabel("Lecture aléatoire \(player.shuffle ? "activée" : "désactivée")")
                        Spacer()
                        Button { player.cycleRepeat() } label: { Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.title3).foregroundStyle(player.repeatMode == .off ? Color.sonoraMuted : Color.sonoraGreen) }.accessibilityLabel("Répétition : \(player.repeatMode.label)")
                        Spacer()
                        RoutePicker().frame(width: 35, height: 35).accessibilityLabel("Sortie audio AirPlay")
                        Spacer()
                        Button { showQueue = true } label: { Image(systemName: "list.bullet").font(.title3).foregroundStyle(Color.sonoraMuted) }.accessibilityLabel("File d’écoute")
                    }
                    Text("L’écoute continue lorsque tu verrouilles l’iPhone.").font(.caption).foregroundStyle(Color.sonoraMuted)
                }.padding(26)
            }.background(Color.sonoraBackground).foregroundStyle(Color.sonoraInk)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
                .sheet(isPresented: $showQueue) {
                    NavigationStack {
                        List(Array(player.queue.enumerated()), id: \.offset) { position, track in
                            Button { player.select(position); showQueue = false } label: {
                                Label(track.title, systemImage: position == player.index ? "speaker.wave.2.fill" : "music.note").foregroundStyle(position == player.index ? Color.sonoraGreen : Color.sonoraInk)
                            }
                        }.navigationTitle("File d’écoute").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showQueue = false } } }
                    }
                }
        }
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor(Color.sonoraMuted)
        view.activeTintColor = UIColor(Color.sonoraGreen)
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
