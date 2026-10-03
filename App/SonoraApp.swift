import SwiftUI

@main
@MainActor
struct SonoraApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = AudioPlayer()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(.sonoraGreen)
        }
    }
}
