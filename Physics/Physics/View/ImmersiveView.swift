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
        .modifier(ARLifecycleModifier(sceneManager: sceneManager, appViewModel: appViewModel))
        .modifier(SceneEventsModifier(sceneManager: sceneManager, appViewModel: appViewModel))
        .modifier(PhysicsPropertiesModifier(sceneManager: sceneManager, appViewModel: appViewModel))
        .modifier(EnvironmentSettingsModifier(sceneManager: sceneManager, appViewModel: appViewModel))
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
                .simultaneously(with: RotateGesture3D().targetedToAnyEntity())
                .onChanged { value in
                    if let magnifyValue = value.first {
                        sceneManager.handleMagnifyChanged(value: magnifyValue)
                    }
                    if let rotateValue = value.second {
                        sceneManager.handleRotateChanged(value: rotateValue)
                    }
                }
                .onEnded { value in
                    if let magnifyValue = value.first {
                        sceneManager.handleMagnifyEnded(value: magnifyValue, viewModel: appViewModel)
                    }
                    if let rotateValue = value.second {
                        sceneManager.handleRotateEnded(value: rotateValue, viewModel: appViewModel)
                    }
                }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    sceneManager.handleTap(value: value, viewModel: appViewModel)
                }
        )
    }
}

// MARK: - Modifiers

struct ARLifecycleModifier: ViewModifier {
    var sceneManager: PhysicsSceneManager
    @Bindable var appViewModel: AppViewModel
    
    func body(content: Content) -> some View {
        content.task(id: appViewModel.selectedEnvironment) {
            if appViewModel.selectedEnvironment == .mixed {
                guard SceneReconstructionProvider.isSupported && HandTrackingProvider.isSupported else { return }
                do {
                    try await sceneManager.session.run([sceneManager.sceneReconstruction, sceneManager.handTracking])
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await sceneManager.processReconstructionUpdates() }
                        group.addTask { await sceneManager.processHandUpdates() }
                    }
                } catch {
                    print("ARKit Session failed: \(error)")
                }
            } else {
                sceneManager.session.stop()
                for entity in sceneManager.meshEntities.values { entity.removeFromParent() }
                sceneManager.meshEntities.removeAll()
                for entity in sceneManager.fingerEntities.values { entity.isEnabled = false }
            }
        }
    }
}

struct SceneEventsModifier: ViewModifier {
    var sceneManager: PhysicsSceneManager
    @Bindable var appViewModel: AppViewModel
    
    func body(content: Content) -> some View {
        content
            .onChange(of: appViewModel.resetSignal) {
                sceneManager.resetScene()
            }
            .onChange(of: appViewModel.spawnSignal) {
                if let shape = appViewModel.spawnSignal {
                    sceneManager.spawnShape(viewModel: appViewModel, shape: shape)
                    appViewModel.spawnSignal = nil
                }
            }
            .onChange(of: appViewModel.spawnCustomModelSignal) {
                if let url = appViewModel.spawnCustomModelSignal {
                    sceneManager.spawnCustomModel(url: url, viewModel: appViewModel)
                    appViewModel.spawnCustomModelSignal = nil
                }
            }
            .onChange(of: appViewModel.isSelectionMode) { _, newValue in
                if !newValue {
                    appViewModel.clearSelection()
                    Task { sceneManager.updateSelectionVisuals(viewModel: appViewModel) }
                }
            }
    }
}

struct PhysicsPropertiesModifier: ViewModifier {
    var sceneManager: PhysicsSceneManager
    @Bindable var appViewModel: AppViewModel
    
    func body(content: Content) -> some View {
        content
            .onChange(of: [appViewModel.mass, appViewModel.restitution, appViewModel.dynamicFriction, appViewModel.staticFriction, appViewModel.linearDamping, appViewModel.airDensity, appViewModel.environmentOpacity] as [Float]) {
                sceneManager.updatePhysicsProperties(viewModel: appViewModel)
                sceneManager.updateEnvironmentOpacity(viewModel: appViewModel)
            }
            .onChange(of: appViewModel.useAdvancedDrag) {
                sceneManager.updatePhysicsProperties(viewModel: appViewModel)
            }
            .onChange(of: appViewModel.selectedMode) {
                sceneManager.updatePhysicsProperties(viewModel: appViewModel)
            }
    }
}

struct EnvironmentSettingsModifier: ViewModifier {
    var sceneManager: PhysicsSceneManager
    @Bindable var appViewModel: AppViewModel
    
    func body(content: Content) -> some View {
        content
            .onChange(of: appViewModel.showPath) {
                if !appViewModel.showPath {
                    sceneManager.traceRoot?.children.removeAll()
                    sceneManager.lastMarkerPosition = nil
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
