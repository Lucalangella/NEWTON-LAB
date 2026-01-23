import SwiftUI

@main
struct PhysicsLabApp: App {
    @State private var appViewModel = AppViewModel()
    
    // Note: We don't necessarily need 'openImmersiveSpace' if we are just using a Volume,
    // but we keep it here in case you want to expand later.
    @Environment(\.openImmersiveSpace) var openImmersiveSpace

    var body: some Scene {
        WindowGroup {
            LaunchView()
                .environment(appViewModel)
        }
        // --- 1. SET STYLE TO AUTOMATIC (Standard Window) ---
        .windowStyle(.automatic)
        // --- 2. SET SIZE ---
        .defaultSize(width: 400, height: 800)
        
        // The Immersive Space (The room around you)
        ImmersiveSpace(id: "PhysicsSpace") {
            ImmersiveView()
                .environment(appViewModel)
        }
    }
}
