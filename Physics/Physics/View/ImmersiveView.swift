import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    @Environment(AppViewModel.self) var appViewModel
    @State private var sceneManager = PhysicsSceneManager()
    
    var body: some View {
        RealityView { content in
            sceneManager.setupScene(content: content, viewModel: appViewModel)
        } update: { content in
            // Updates are handled via sceneManager methods triggered by .onChange
        }
        // --- ARKit Lifecycle ---
        .task(id: appViewModel.selectedEnvironment) {
            if appViewModel.selectedEnvironment == .mixed {
                guard SceneReconstructionProvider.isSupported && HandTrackingProvider.isSupported else { return }
                
                do {
                    try await sceneManager.session.run([sceneManager.sceneReconstruction, sceneManager.handTracking])
                    
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await sceneManager.processReconstructionUpdates()
                        }
                        group.addTask {
                            await sceneManager.processHandUpdates()
                        }
                    }
                } catch {
                    print("ARKit Session failed: \(error)")
                }
            } else {
                sceneManager.session.stop()
                // Cleanup AR entities
                for entity in sceneManager.meshEntities.values {
                    entity.removeFromParent()
                }
                sceneManager.meshEntities.removeAll()
                for entity in sceneManager.fingerEntities.values {
                    entity.isEnabled = false
                }
            }
        }
        // --- Gestures ---
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    sceneManager.handleDragChanged(value: value, viewModel: appViewModel)
                }
                .onEnded { value in
                    sceneManager.handleDragEnded(value: value, viewModel: appViewModel)
                }
        )
        .gesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    sceneManager.handleMagnifyChanged(value: value)
                }
                .onEnded { _ in
                    sceneManager.handleMagnifyEnded()
                }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    sceneManager.handleTap(value: value, viewModel: appViewModel)
                }
        )
        // --- Event Listeners ---
        .onChange(of: appViewModel.resetSignal) {
            sceneManager.resetScene()
        }
        .onChange(of: appViewModel.isSelectionMode) { _, newValue in
            print("Selection Mode Changed: \(newValue)")
            if !newValue {
                appViewModel.clearSelection()
                Task {
                    sceneManager.updateSelectionVisuals(viewModel: appViewModel)
                }
            }
        }
        .onChange(of: [appViewModel.mass, appViewModel.restitution, appViewModel.dynamicFriction, appViewModel.staticFriction, appViewModel.linearDamping, appViewModel.airDensity] as [Float]) {
            sceneManager.updatePhysicsProperties(viewModel: appViewModel)
        }
        .onChange(of: appViewModel.useAdvancedDrag) {
            sceneManager.updatePhysicsProperties(viewModel: appViewModel)
        }
        .onChange(of: appViewModel.selectedMode) {
            sceneManager.updatePhysicsProperties(viewModel: appViewModel)
        }
        .onChange(of: appViewModel.showPath) {
            if !appViewModel.showPath {
                sceneManager.traceRoot?.children.removeAll()
                sceneManager.lastMarkerPosition = nil
            }
        }
        .onChange(of: appViewModel.spawnSignal) {
            if let shape = appViewModel.spawnSignal {
                sceneManager.spawnShape(viewModel: appViewModel, shape: shape)
                appViewModel.spawnSignal = nil // Reset signal
            }
        }
        .onChange(of: appViewModel.selectedEnvironment) {
            sceneManager.updateEnvironment(viewModel: appViewModel)
        }
        .onChange(of: appViewModel.showRamp) {
            sceneManager.rampEntity?.isEnabled = (appViewModel.selectedEnvironment == .virtual && appViewModel.showRamp)
        }
        .onChange(of: [appViewModel.rampAngle, appViewModel.rampLength, appViewModel.rampWidth]) {
            sceneManager.updateRamp(viewModel: appViewModel)
        }
        .onChange(of: appViewModel.rampRotation) {
            guard let ramp = sceneManager.rampEntity else { return }
            let radians = appViewModel.rampRotation * (Float.pi / 180.0)
            ramp.transform.rotation = simd_quatf(angle: radians, axis: [0, 1, 0])
        }
        .onChange(of: [appViewModel.showWalls, appViewModel.wallHeight] as [AnyHashable]) {
            sceneManager.updateWalls(viewModel: appViewModel)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppViewModel())
}