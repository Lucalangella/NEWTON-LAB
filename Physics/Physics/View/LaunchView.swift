import SwiftUI

struct LaunchView: View {
    @Environment(AppViewModel.self) var appViewModel
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    @State private var navigateToControls = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("Physics Lab")
                    .font(.extraLargeTitle)
                    .fontWeight(.bold)
                
                Text("Choose your environment")
                    .font(.title)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 30) {
                    // Option 1: Virtual Studio
                    Button {
                        selectMode(.virtual)
                    } label: {
                        VStack(spacing: 20) {
                            Image(systemName: "cube.transparent")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                            
                            Text("Virtual Studio")
                                .font(.headline)
                            
                            Text("Experiment with planes and ramps in a controlled void.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 200)
                        }
                        .padding(30)
                        .glassBackgroundEffect()
                    }
                    .buttonStyle(.plain)
                    
                    // Option 2: Real World
                    Button {
                        selectMode(.mixed)
                    } label: {
                        VStack(spacing: 20) {
                            Image(systemName: "table.furniture")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                            
                            Text("Real World")
                                .font(.headline)
                            
                            Text("Interact with your tables, floor, and room furniture.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 200)
                        }
                        .padding(30)
                        .glassBackgroundEffect()
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(isPresented: $navigateToControls) {
                PhysicsControlView()
            }
        }
        .onChange(of: navigateToControls) { _, isPresented in
            // If the user navigated BACK (isPresented became false), close the space.
            if !isPresented && appViewModel.immersiveSpaceState == .open {
                Task {
                    appViewModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    appViewModel.immersiveSpaceState = .closed
                }
            }
        }
    }
    
    func selectMode(_ mode: PhysicsEnvironmentMode) {
        appViewModel.selectedEnvironment = mode
        
        Task {
            // Open the immersive space
            if appViewModel.immersiveSpaceState == .closed {
                appViewModel.immersiveSpaceState = .inTransition
                switch await openImmersiveSpace(id: "PhysicsSpace") {
                case .opened:
                    appViewModel.immersiveSpaceState = .open
                    navigateToControls = true
                case .userCancelled, .error:
                    appViewModel.immersiveSpaceState = .closed
                @unknown default:
                    appViewModel.immersiveSpaceState = .closed
                }
            } else {
                // Already open, just navigate
                navigateToControls = true
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    LaunchView()
        .environment(AppViewModel())
}
