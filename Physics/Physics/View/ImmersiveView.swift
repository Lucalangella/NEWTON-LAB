import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    @Environment(AppViewModel.self) var appViewModel
    
    // Scene References
    @State private var objectEntity: ModelEntity?
    @State private var rootEntity: Entity?
    @State private var traceRoot: Entity?
    @State private var rampEntity: ModelEntity?
    @State private var floorEntity: ModelEntity?
    
    // ARKit / Scene Reconstruction
    @State private var session = ARKitSession()
    @State private var sceneReconstruction = SceneReconstructionProvider()
    @State private var meshEntities = [UUID: ModelEntity]() // Track real-world mesh chunks
    
    // Logic State
    @State private var lastMarkerPosition: SIMD3<Float>? = nil
    @State private var initialDragPosition: SIMD3<Float>? = nil
    
    var body: some View {
        RealityView { content in
            // --- 1. SETUP SCENE ---
            let root = Entity()
            root.name = "Root"
            
            var physSim = PhysicsSimulationComponent()
            physSim.gravity = [0, -9.8, 0]
            root.components.set(physSim)
            
            content.add(root)
            self.rootEntity = root
            
            let traces = Entity()
            traces.name = "TraceRoot"
            root.addChild(traces)
            self.traceRoot = traces
            
            // --- VIRTUAL ENVIRONMENT ---
            let floor = ModelEntity(
                mesh: .generatePlane(width: 4.0, depth: 4.0),
                materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.5), isMetallic: false)]
            )
            floor.position = [0, 0, -2.0]
            floor.generateCollisionShapes(recursive: false)
            floor.components.set(PhysicsBodyComponent(mode: .static))
            floor.isEnabled = (appViewModel.selectedEnvironment == .virtual) // Hide if Real World
            root.addChild(floor)
            self.floorEntity = floor
            
            // ---------------------------------------------------------
            // 1. SETUP RAMP (Virtual only)
            // ---------------------------------------------------------
            let ramp = ModelEntity()
            ramp.name = "Ramp"
            ramp.position = [0, 0, -2.0]
            ramp.components.set(InputTargetComponent(allowedInputTypes: .all))
            ramp.components.set(PhysicsBodyComponent(mode: .static))
            
            let initialRadians = appViewModel.rampRotation * (Float.pi / 180.0)
            ramp.transform.rotation = simd_quatf(angle: initialRadians, axis: [0, 1, 0])
            
            // Enable only if Virtual AND Show Ramp is on
            ramp.isEnabled = (appViewModel.selectedEnvironment == .virtual && appViewModel.showRamp)
            
            root.addChild(ramp)
            self.rampEntity = ramp
            
            updateRamp()
            
            // ---------------------------------------------------------

            // --- CREATE INITIAL OBJECT ---
            let object = ModelEntity() // Empty initially
            object.name = "PhysicsObject"
            object.position = [0, 1.5, -2.0]
            
            object.components.set(InputTargetComponent(allowedInputTypes: .all))
            
            let material = PhysicsMaterialResource.generate(
                staticFriction: appViewModel.staticFriction,
                dynamicFriction: appViewModel.dynamicFriction,
                restitution: appViewModel.restitution
            )
            var physicsBody = PhysicsBodyComponent(
                massProperties: .init(mass: appViewModel.mass),
                material: material,
                mode: appViewModel.selectedMode.rkMode
            )
            physicsBody.linearDamping = appViewModel.linearDamping
            object.components.set(physicsBody)
            
            root.addChild(object)
            self.objectEntity = object
            
            updateShape()
            
            // --- 2. SUBSCRIBE TO UPDATES ---
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                guard let obj = objectEntity,
                      let motion = obj.components[PhysicsMotionComponent.self] else { return }
                
                // 1. Update Speed
                let velocity = motion.linearVelocity
                let speed = length(velocity)
                appViewModel.currentSpeed = speed
                
                // 1b. Apply Advanced Air Resistance
                if appViewModel.useAdvancedDrag {
                    if speed > 0.001 {
                        let rho = appViewModel.airDensity
                        let A = appViewModel.crossSectionalArea
                        let Cd = appViewModel.dragCoefficient
                        let dragMagnitude = 0.5 * rho * (speed * speed) * Cd * A
                        let dragForce = -velocity / speed * dragMagnitude
                        obj.addForce(dragForce, relativeTo: nil)
                    }
                }
                
                // 2. Update Gravity
                if let root = rootEntity,
                   var physSim = root.components[PhysicsSimulationComponent.self] {
                    physSim.gravity = [0, appViewModel.gravity, 0]
                    root.components.set(physSim)
                }
                
                // 3. Update Path Plotter
                if appViewModel.showPath {
                    let currentPos = obj.position(relativeTo: nil)
                    if let lastPos = lastMarkerPosition {
                        if length(currentPos - lastPos) > 0.05 {
                            addPathMarker(at: currentPos)
                            lastMarkerPosition = currentPos
                        }
                    } else {
                        lastMarkerPosition = currentPos
                    }
                }
            }
            
        } update: { content in }
        
        // --- 3. SCENE RECONSTRUCTION TASK ---
        .task {
            // Only run in Mixed Reality mode
            if appViewModel.selectedEnvironment == .mixed {
                await processSceneReconstruction()
            }
        }
        
        // --- 4. GESTURE ---
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = value.entity
                    
                    // Don't drag the room mesh!
                    if entity.name == "SceneMesh" { return }
                    
                    appViewModel.isDragging = true
                    
                    if initialDragPosition == nil {
                        initialDragPosition = entity.position(relativeTo: entity.parent)
                    }
                    guard let startPos = initialDragPosition else { return }
                    
                    if var body = entity.components[PhysicsBodyComponent.self], body.mode != .kinematic {
                        body.mode = .kinematic
                        entity.components.set(body)
                        entity.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
                    }
                    
                    let startLocParent = value.convert(value.startLocation3D, from: .local, to: entity.parent!)
                    let currentLocParent = value.convert(value.location3D, from: .local, to: entity.parent!)
                    let translation = currentLocParent - startLocParent
                    var newPos = startPos + translation
                    
                    if entity.name == "Ramp" {
                        newPos.y = 0.0
                        entity.position = newPos
                    } else {
                        // In Real World mode, we might want to allow dropping lower than the virtual floor height
                        // But let's keep a sane min height so we don't lose objects.
                        let minHeight: Float = (appViewModel.selectedEnvironment == .virtual) ? 0.16 : -1.0
                        if newPos.y < minHeight { newPos.y = minHeight }
                        entity.position = newPos
                    }
                }
                .onEnded { value in
                    let entity = value.entity
                    if entity.name == "SceneMesh" { return }
                    
                    appViewModel.isDragging = false
                    initialDragPosition = nil
                    
                    if entity.name == "Ramp" {
                        if var body = entity.components[PhysicsBodyComponent.self] {
                            body.mode = .static
                            entity.components.set(body)
                        }
                    } else {
                        if var body = entity.components[PhysicsBodyComponent.self] {
                            body.mode = appViewModel.selectedMode.rkMode
                            entity.components.set(body)
                        }
                        if appViewModel.selectedMode == .dynamic {
                            var motion = PhysicsMotionComponent()
                            motion.linearVelocity = .zero
                            motion.angularVelocity = .zero
                            entity.components.set(motion)
                        }
                    }
                }
        )
        // --- EVENT HANDLERS ---
        .onChange(of: appViewModel.resetSignal) {
            guard let obj = objectEntity else { return }
            obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
            obj.position = [0, 1.5, -2.0]
            traceRoot?.children.removeAll()
            lastMarkerPosition = nil
        }
        .onChange(of: [appViewModel.mass, appViewModel.restitution, appViewModel.dynamicFriction, appViewModel.staticFriction, appViewModel.linearDamping, appViewModel.airDensity] as [Float]) {
            updatePhysicsProperties()
        }
        .onChange(of: appViewModel.useAdvancedDrag) {
            updatePhysicsProperties()
        }
        .onChange(of: appViewModel.selectedMode) {
            updatePhysicsProperties()
        }
        .onChange(of: appViewModel.showPath) {
            if !appViewModel.showPath {
                traceRoot?.children.removeAll()
                lastMarkerPosition = nil
            }
        }
        .onChange(of: appViewModel.selectedShape) {
            updateShape()
        }
        .onChange(of: appViewModel.showRamp) {
            rampEntity?.isEnabled = (appViewModel.selectedEnvironment == .virtual && appViewModel.showRamp)
        }
        .onChange(of: [appViewModel.rampAngle, appViewModel.rampLength, appViewModel.rampWidth]) {
            updateRamp()
        }
        .onChange(of: appViewModel.rampRotation) {
            guard let ramp = rampEntity else { return }
            let radians = appViewModel.rampRotation * (Float.pi / 180.0)
            ramp.transform.rotation = simd_quatf(angle: radians, axis: [0, 1, 0])
        }
    }
    
    // MARK: - Scene Reconstruction
    func processSceneReconstruction() async {
        // Check if device supports it
        guard SceneReconstructionProvider.isSupported else {
            print("Scene Reconstruction not supported on this device.")
            return
        }
        
        do {
            // Start the session with scene reconstruction
            try await session.run([sceneReconstruction])
            print("Scene Reconstruction Session Started")
            
            // Process updates
            for await update in sceneReconstruction.anchorUpdates {
                let meshAnchor = update.anchor
                
                switch update.event {
                case .added, .updated:
                    await updateMeshEntity(for: meshAnchor)
                case .removed:
                    removeMeshEntity(for: meshAnchor)
                }
            }
        } catch {
            print("Failed to run ARKit session: \(error)")
        }
    }
    
    func updateMeshEntity(for anchor: MeshAnchor) async {
        guard let root = rootEntity else { return }
        
        // Create a ShapeResource for physics collision
        // This is the key part for physics interaction!
        // IN visionOS, this call is ASYNC.
        guard let shape = try? await ShapeResource.generateStaticMesh(from: anchor) else {
            return
        }
        
        // If we already have an entity, just update its collider/mesh
        if let existingEntity = meshEntities[anchor.id] {
            existingEntity.transform = Transform(matrix: anchor.originFromAnchorTransform)
            existingEntity.collision?.shapes = [shape]
            return
        }
        
        // Create new entity
        let entity = ModelEntity()
        entity.name = "SceneMesh"
        entity.transform = Transform(matrix: anchor.originFromAnchorTransform)
        
        // Add Physics
        entity.collision = CollisionComponent(shapes: [shape])
        entity.components.set(PhysicsBodyComponent(mode: .static))
        
        root.addChild(entity)
        meshEntities[anchor.id] = entity
    }
    
    func removeMeshEntity(for anchor: MeshAnchor) {
        if let entity = meshEntities[anchor.id] {
            entity.removeFromParent()
            meshEntities.removeValue(forKey: anchor.id)
        }
    }
    
    // MARK: - Updates
    func updateShape() {
        guard let obj = objectEntity else { return }
        
        let newMesh: MeshResource
        let newMaterial: SimpleMaterial
        
        switch appViewModel.selectedShape {
        case .box:
            newMesh = .generateBox(size: 0.3)
            newMaterial = SimpleMaterial(color: .red, isMetallic: false)
        case .sphere:
            newMesh = .generateSphere(radius: 0.15)
            newMaterial = SimpleMaterial(color: .blue, isMetallic: false)
        case .cylinder:
            newMesh = .generateCylinder(height: 0.3, radius: 0.15)
            newMaterial = SimpleMaterial(color: .green, isMetallic: false)
        }
        
        obj.model = ModelComponent(mesh: newMesh, materials: [newMaterial])
        obj.generateCollisionShapes(recursive: false)
    }
    
    func updatePhysicsProperties() {
        guard let obj = objectEntity else { return }
        
        let newMaterial = PhysicsMaterialResource.generate(
            staticFriction: appViewModel.staticFriction,
            dynamicFriction: appViewModel.dynamicFriction,
            restitution: appViewModel.restitution
        )
        
        var bodyComponent = obj.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
        bodyComponent.massProperties.mass = appViewModel.mass
        bodyComponent.material = newMaterial
        bodyComponent.mode = appViewModel.selectedMode.rkMode
        
        // If Advanced Drag is on, we apply force manually, so disable built-in linear damping
        // Otherwise use the slider value
        bodyComponent.linearDamping = appViewModel.useAdvancedDrag ? 0.0 : appViewModel.linearDamping
        
        obj.components.set(bodyComponent)
    }
    
    func updateRamp() {
        guard let ramp = rampEntity else { return }
        
        // Dimensions
        let slopeLength = appViewModel.rampLength
        let radians = appViewModel.rampAngle * (Float.pi / 180.0)
        
        // Calculate Height and Base
        let height = slopeLength * sin(radians)
        let baseLength = slopeLength * cos(radians)
        
        let width = appViewModel.rampWidth // Depth of the ramp (track width)
        
        var descriptor = MeshDescriptor(name: "wedge")
        
        // Coordinates
        let frontZ: Float = width / 2
        let backZ: Float = -width / 2
        
        // We want the slope to go from Left (High) to Right (Low)
        let leftX: Float = -baseLength / 2
        let rightX: Float = baseLength / 2
        
        let topY: Float = height
        let bottomY: Float = 0.0
        
        descriptor.positions = MeshBuffers.Positions([
            // Front Face Vertices (0, 1, 2)
            [leftX, topY, frontZ],      // 0: Top Left (High Point)
            [leftX, bottomY, frontZ],   // 1: Bottom Left (Corner)
            [rightX, bottomY, frontZ],  // 2: Bottom Right (End of Slope)
            
            // Back Face Vertices (3, 4, 5)
            [leftX, topY, backZ],       // 3: Top Left (High Point)
            [leftX, bottomY, backZ],    // 4: Bottom Left (Corner)
            [rightX, bottomY, backZ]    // 5: Bottom Right (End of Slope)
        ])
        
        descriptor.primitives = .triangles([
            // Front Face
            0, 1, 2,
            
            // Back Face (Clockwise)
            3, 5, 4,
            
            // Vertical Back Wall (Left Side)
            0, 4, 1,
            0, 3, 4,
            
            // Sloped Face (Hypotenuse Rectangle)
            0, 2, 5,
            0, 5, 3,
            
            // Bottom Face
            1, 4, 5,
            1, 5, 2
        ])
        
        if let rampMesh = try? MeshResource.generate(from: [descriptor]) {
            ramp.model = ModelComponent(
                mesh: rampMesh,
                materials: [SimpleMaterial(color: .cyan.withAlphaComponent(0.8), isMetallic: false)]
            )
            
            // Update Collision Shape (Force Convex Hull for accurate wedge shape)
            // This prevents the "invisible volume" (bounding box) issue.
            if let shape = try? ShapeResource.generateConvex(from: rampMesh) {
                ramp.collision = CollisionComponent(shapes: [shape])
            } else {
                ramp.generateCollisionShapes(recursive: false)
            }
            
            // Ensure Physics Body is Static
            // (Should be already set, but good to ensure if shape changes significantly)
            if ramp.components[PhysicsBodyComponent.self] == nil {
                ramp.components.set(PhysicsBodyComponent(mode: .static))
            }
            
            // Ensure visibility
            ramp.isEnabled = (appViewModel.selectedEnvironment == .virtual && appViewModel.showRamp)
        }
    }
    
    // MARK: - Path Plotter
    private func addPathMarker(at position: SIMD3<Float>) {
        guard let parent = traceRoot else { return }
        
        let mesh = MeshResource.generateSphere(radius: 0.005)
        let material = UnlitMaterial(color: .yellow)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        
        marker.position = position
        
        parent.addChild(marker)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppViewModel())
}