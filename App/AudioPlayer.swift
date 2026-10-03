import AVFoundation
import MediaPlayer
import UIKit
import Combine

@MainActor
final class AudioPlayer: ObservableObject {
    enum RepeatMode: Int, CaseIterable {
        case off, all, one
        var label: String { self == .off ? "Désactivée" : self == .all ? "Toute la file" : "Ce titre" }
    }
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var wantsPlayback = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var error: String?
    @Published private(set) var warning: String?
    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    private let player = AVQueuePlayer()
    private var originalQueue: [Track] = []
    private var itemIndices: [ObjectIdentifier: Int] = [:]
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchToken: UUID?
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var notifications: [NSObjectProtocol] = []
    private var activeItemID: ObjectIdentifier?
    private var resumeAfterInterruption = false
    private var artwork: UIImage?
    private var artworkTrackID: String?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updatePlaybackState() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in self?.interrupted(type: type, options: options) }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, current != nil else { return }
                load(index: index, autoplay: wantsPlayback, position: elapsed, refresh: true)
            }
        })
        configureCommands()
    }

    func play(_ tracks: [Track], startingAt position: Int = 0) {
        guard tracks.indices.contains(position) else { return }
        originalQueue = tracks; queue = tracks; shuffle = false
        load(index: position, autoplay: true)
    }

    func select(_ position: Int) { guard queue.indices.contains(position) else { return }; load(index: position, autoplay: true) }
    func toggle() {
        if error != nil { retry() }
        else if wantsPlayback { pause() }
        else { resume() }
    }
    func pause() { wantsPlayback = false; resumeAfterInterruption = false; player.pause(); updatePlaybackState() }
    func resume() {
        guard current != nil else { return }
        wantsPlayback = true
        if player.currentItem == nil && !isLoading { load(index: index, autoplay: true); return }
        do { try activateSession(); player.play() }
        catch { self.error = "Impossible d’activer la sortie audio."; wantsPlayback = false }
        updatePlaybackState()
    }
    func retry() { load(index: index, autoplay: true, position: elapsed, refresh: true) }
    func seek(to seconds: Double) {
        guard seconds.isFinite, duration > 0 else { return }
        elapsed = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        publishNowPlaying()
    }
    func previous() {
        if elapsed > 3 { seek(to: 0) } else { select(max(0, index - 1)) }
    }
    func next() {
        guard !queue.isEmpty else { return }
        let target: Int
        if index + 1 < queue.count { target = index + 1 }
        else if repeatMode == .all { target = 0 }
        else { return }
        let items = player.items()
        if items.count > 1, itemIndices[ObjectIdentifier(items[1])] == target {
            wantsPlayback = true; player.advanceToNextItem(); player.play()
        } else { select(target) }
    }
    func cycleRepeat() {
        repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off
        rebuildUpcoming()
    }
    func toggleShuffle() {
        guard !isLoading, let current else { return }
        shuffle.toggle()
        if shuffle {
            var others = queue
            others.remove(at: index)
            queue = [current] + others.shuffled(); index = 0
        } else {
            queue = originalQueue; index = queue.firstIndex { $0.id == current.id } ?? 0
        }
        if let item = player.currentItem { itemIndices[ObjectIdentifier(item)] = index }
        rebuildUpcoming()
    }

    private func load(index newIndex: Int, autoplay: Bool, position: Double = 0, refresh: Bool = false) {
        guard queue.indices.contains(newIndex) else { return }
        loadTask?.cancel(); prefetchTask?.cancel(); prefetchTask = nil; prefetchToken = nil
        generation = UUID(); let token = generation
        let track = queue[newIndex]
        isLoading = true; wantsPlayback = autoplay; error = nil; warning = nil
        index = newIndex; elapsed = position; duration = track.duration ?? 0
        player.pause(); player.removeAllItems(); itemIndices.removeAll()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await YouTubeRepository.shared.audio(track.id, refresh: refresh)
                guard !Task.isCancelled, generation == token else { return }
                try activateSession()
                let item = AVPlayerItem(url: audio.url)
                item.preferredForwardBufferDuration = 30
                itemIndices[ObjectIdentifier(item)] = newIndex
                player.insert(item, after: nil)
                if position > 0 { await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                guard generation == token, !Task.isCancelled else { return }
                isLoading = false
                if wantsPlayback { player.play() }
                currentItemChanged()
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                isLoading = false; wantsPlayback = false
                self.error = (error as? SonoraError)?.localizedDescription ?? "Lecture indisponible. Vérifie la connexion et touche Réessayer."
                updatePlaybackState()
            }
        }
    }

    private func currentItemChanged() {
        guard let item = player.currentItem, let position = itemIndices[ObjectIdentifier(item)] else {
            updatePlaybackState(); return
        }
        let itemID = ObjectIdentifier(item)
        if activeItemID != itemID {
            activeItemID = itemID
            elapsed = 0
            duration = queue[position].duration ?? 0
        }
        index = position; error = nil; warning = nil
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let status = observed.status
            let observedID = ObjectIdentifier(observed)
            Task { @MainActor in
                guard let self, let active = player.currentItem, ObjectIdentifier(active) == observedID else { return }
                if status == .failed {
                    isLoading = false; wantsPlayback = false; player.pause()
                    error = "Le flux audio a expiré ou est indisponible. Touche Réessayer."
                } else if status == .readyToPlay { isLoading = false }
                updateProgress(); updatePlaybackState()
            }
        }
        let activeIDs = Set(player.items().map(ObjectIdentifier.init))
        itemIndices = itemIndices.filter { activeIDs.contains($0.key) }
        updateProgress(); loadArtwork(); scheduleNext()
    }

    private func nextIndex(after position: Int) -> Int? {
        if repeatMode == .one { return position }
        if position + 1 < queue.count { return position + 1 }
        return repeatMode == .all && !queue.isEmpty ? 0 : nil
    }
    private func rebuildUpcoming() {
        prefetchTask?.cancel(); prefetchTask = nil; prefetchToken = nil
        for item in player.items().dropFirst() { player.remove(item); itemIndices.removeValue(forKey: ObjectIdentifier(item)) }
        scheduleNext(); publishNowPlaying()
    }
    private func scheduleNext() {
        guard prefetchToken == nil, player.items().count < 2,
              let tail = player.items().last, let tailIndex = itemIndices[ObjectIdentifier(tail)],
              let following = nextIndex(after: tailIndex) else { return }
        let sourceID = generation; let token = UUID(); prefetchToken = token
        let track = queue[following]
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            defer { if prefetchToken == token { prefetchToken = nil; prefetchTask = nil } }
            do {
                let source = try await YouTubeRepository.shared.audio(track.id)
                guard !Task.isCancelled, sourceID == generation,
                      player.items().contains(where: { $0 === tail }) else { return }
                let item = AVPlayerItem(url: source.url)
                item.preferredForwardBufferDuration = 30
                guard player.canInsert(item, after: tail) else { return }
                itemIndices[ObjectIdentifier(item)] = following
                player.insert(item, after: tail)
            } catch is CancellationError { }
            catch { if sourceID == generation { warning = "Le titre suivant n’a pas pu être préparé. Le bouton Suivant permet de réessayer." } }
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
    private func updatePlaybackState() {
        isPlaying = player.timeControlStatus == .playing
        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate && wantsPlayback { isLoading = true }
        else if player.currentItem?.status == .readyToPlay { isLoading = false }
        if player.currentItem == nil && !isLoading { wantsPlayback = false }
        publishNowPlaying()
    }
    private func updateProgress() {
        let seconds = player.currentTime().seconds
        if seconds.isFinite { elapsed = max(0, seconds) }
        let length = player.currentItem?.duration.seconds ?? 0
        if length.isFinite && length > 0 { duration = length }
        publishNowPlaying()
    }
    private func publishNowPlaying() {
        guard let track = current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if artworkTrackID == track.id, let image = artwork { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = index + 1 < queue.count || repeatMode == .all
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = duration > 0
    }
    private func loadArtwork() {
        guard let track = current, artworkTrackID != track.id else { return }
        artwork = nil; artworkTrackID = track.id
        guard let url = track.artwork else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
            guard let self, current?.id == track.id else { return }
            artwork = image; publishNowPlaying()
        }
    }
    private func interrupted(type: UInt?, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue {
            resumeAfterInterruption = wantsPlayback
            player.pause(); updatePlaybackState()
        } else if type == AVAudioSession.InterruptionType.ended.rawValue {
            if resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { resume() }
            resumeAfterInterruption = false
        }
    }
    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = position.positionTime
            Task { @MainActor in self?.seek(to: seconds) }; return .success
        }
    }
}
