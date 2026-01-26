import SwiftUI
import RealityKit
import ARKit

struct ImmersiveView: View {
    @Environment(AppViewModel.self) var appViewModel
    
    // Scene References
    @State private var objectEntity: ModelEntity?
    @State private var rootEntity: Entity?
    @State private var traceRoot: Entity?
    @State private var wallsRoot: Entity?
    @State private var rampEntity: ModelEntity?
    @State private var floorEntity: ModelEntity?
    
    // ARKit Providers
    @State private var session = ARKitSession()
    @State private var sceneReconstruction = SceneReconstructionProvider()
    @State private var handTracking = HandTrackingProvider()
    
    // Tracked Entities
    @State private var meshEntities = [UUID: ModelEntity]()
    @State private var fingerEntities: [HandAnchor.Chirality: ModelEntity] = [:]
    
    // Logic State
    @State private var lastMarkerPosition: SIMD3<Float>? = nil
    @State private var initialDragPosition: SIMD3<Float>? = nil
    @State private var initialScale: SIMD3<Float>? = nil
    
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
            
            // --- FINGERTIPS (Kinematic bodies to push objects) ---
            let leftFinger = createFingertip()
            let rightFinger = createFingertip()
            root.addChild(leftFinger)
            root.addChild(rightFinger)
            self.fingerEntities = [.left: leftFinger, .right: rightFinger]
            
            // --- VIRTUAL ENVIRONMENT ---
            let floor = ModelEntity(
                mesh: .generatePlane(width: 4.0, depth: 4.0),
                materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.5), isMetallic: false)]
            )
            floor.position = [0, 0, -2.0]
            floor.generateCollisionShapes(recursive: false)
            floor.components.set(PhysicsBodyComponent(mode: .static))
            floor.isEnabled = (appViewModel.selectedEnvironment == .virtual)
            root.addChild(floor)
            self.floorEntity = floor
            
            // --- WALLS ROOT ---
            let walls = Entity()
            walls.name = "WallsRoot"
            root.addChild(walls)
            self.wallsRoot = walls
            
            updateWalls()
            
            // ---------------------------------------------------------
            // SETUP RAMP
            // ---------------------------------------------------------
            let ramp = ModelEntity()
            ramp.name = "Ramp"
            ramp.position = [0, 0, -2.0]
            ramp.components.set(InputTargetComponent(allowedInputTypes: .all))
            ramp.components.set(PhysicsBodyComponent(mode: .static))
            
            let initialRadians = appViewModel.rampRotation * (Float.pi / 180.0)
            ramp.transform.rotation = simd_quatf(angle: initialRadians, axis: [0, 1, 0])
            ramp.isEnabled = (appViewModel.selectedEnvironment == .virtual && appViewModel.showRamp)
            
            root.addChild(ramp)
            self.rampEntity = ramp
            
            updateRamp()
            
            // --- CREATE INITIAL OBJECT ---
            let object = ModelEntity()
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
                
                let velocity = motion.linearVelocity
                let speed = length(velocity)
                appViewModel.currentSpeed = speed
                
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
                
                if let root = rootEntity,
                   var physSim = root.components[PhysicsSimulationComponent.self] {
                    physSim.gravity = [0, appViewModel.gravity, 0]
                    root.components.set(physSim)
                }
                
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
        
        // --- 3. ARKIT TASKS ---
        .task {
            if appViewModel.selectedEnvironment == .mixed {
                await runARKitSession()
            }
        }
        .task {
            if appViewModel.selectedEnvironment == .mixed {
                await processHandUpdates()
            }
        }
        
        // --- 4. GESTURE ---
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = value.entity
                    if entity.name == "SceneMesh" || entity.name == "Fingertip" { return }
                    
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
                        let minHeight: Float = (appViewModel.selectedEnvironment == .virtual) ? 0.16 : -1.0
                        if newPos.y < minHeight { newPos.y = minHeight }
                        entity.position = newPos
                    }
                }
                .onEnded { value in
                    let entity = value.entity
                    if entity.name == "SceneMesh" || entity.name == "Fingertip" { return }
                    
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
        .gesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = value.entity
                    if entity.name == "SceneMesh" || entity.name == "Fingertip" { return }
                    
                    if initialScale == nil {
                        initialScale = entity.scale
                    }
                    
                    guard let startScale = initialScale else { return }
                    let magnification = Float(value.magnification)
                    entity.scale = startScale * magnification
                }
                .onEnded { _ in
                    initialScale = nil
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
        .onChange(of: [appViewModel.showWalls, appViewModel.wallHeight] as [AnyHashable]) {
            updateWalls()
        }
    }
    
    // MARK: - ARKit Logic
    
    @MainActor
    func runARKitSession() async {
        guard SceneReconstructionProvider.isSupported && HandTrackingProvider.isSupported else { return }
        
        do {
            try await session.run([sceneReconstruction, handTracking])
            
            for await update in sceneReconstruction.anchorUpdates {
                let meshAnchor = update.anchor
                
                guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
                
                switch update.event {
                case .added, .updated:
                    if let entity = meshEntities[meshAnchor.id] {
                        entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                        entity.collision?.shapes = [shape]
                    } else {
                        let entity = ModelEntity()
                        entity.name = "SceneMesh"
                        entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                        entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                        entity.components.set(PhysicsBodyComponent(mode: .static))
                        
                        rootEntity?.addChild(entity)
                        meshEntities[meshAnchor.id] = entity
                    }
                case .removed:
                    meshEntities[meshAnchor.id]?.removeFromParent()
                    meshEntities.removeValue(forKey: meshAnchor.id)
                }
            }
        } catch {
            print("ARKit Session failed: \(error)")
        }
    }
    
    @MainActor
    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor
            
            guard handAnchor.isTracked,
                  let fingerTip = handAnchor.handSkeleton?.joint(.indexFingerTip),
                  fingerTip.isTracked else {
                fingerEntities[handAnchor.chirality]?.isEnabled = false
                continue
            }
            
            let transform = handAnchor.originFromAnchorTransform * fingerTip.anchorFromJointTransform
            if let entity = fingerEntities[handAnchor.chirality] {
                entity.isEnabled = true
                entity.setTransformMatrix(transform, relativeTo: nil)
            }
        }
    }
    
    private func createFingertip() -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.01),
            materials: [UnlitMaterial(color: .cyan)],
            collisionShape: .generateSphere(radius: 0.01),
            mass: 0.0
        )
        entity.name = "Fingertip"
        entity.components.set(PhysicsBodyComponent(mode: .kinematic))
        entity.components.set(OpacityComponent(opacity: 0.0)) // Invisible
        entity.isEnabled = false
        return entity
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
        bodyComponent.linearDamping = appViewModel.useAdvancedDrag ? 0.0 : appViewModel.linearDamping
        
        obj.components.set(bodyComponent)
    }
    
    func updateRamp() {
        guard let ramp = rampEntity else { return }
        
        let slopeLength = appViewModel.rampLength
        let radians = appViewModel.rampAngle * (Float.pi / 180.0)
        let height = slopeLength * sin(radians)
        let baseLength = slopeLength * cos(radians)
        let width = appViewModel.rampWidth
        
        var descriptor = MeshDescriptor(name: "wedge")
        let frontZ: Float = width / 2
        let backZ: Float = -width / 2
        let leftX: Float = -baseLength / 2
        let rightX: Float = baseLength / 2
        let topY: Float = height
        let bottomY: Float = 0.0
        
        descriptor.positions = MeshBuffers.Positions([
            [leftX, topY, frontZ], [leftX, bottomY, frontZ], [rightX, bottomY, frontZ],
            [leftX, topY, backZ], [leftX, bottomY, backZ], [rightX, bottomY, backZ]
        ])
        
        descriptor.primitives = .triangles([
            0, 1, 2, 3, 5, 4, 0, 4, 1, 0, 3, 4, 0, 2, 5, 0, 5, 3, 1, 4, 5, 1, 5, 2
        ])
        
        if let rampMesh = try? MeshResource.generate(from: [descriptor]) {
            ramp.model = ModelComponent(
                mesh: rampMesh,
                materials: [SimpleMaterial(color: .cyan.withAlphaComponent(0.8), isMetallic: false)]
            )
            if let shape = try? ShapeResource.generateConvex(from: rampMesh) {
                ramp.collision = CollisionComponent(shapes: [shape])
            } else {
                ramp.generateCollisionShapes(recursive: false)
            }
            if ramp.components[PhysicsBodyComponent.self] == nil {
                ramp.components.set(PhysicsBodyComponent(mode: .static))
            }
            ramp.isEnabled = (appViewModel.selectedEnvironment == .virtual && appViewModel.showRamp)
        }
    }
    
    func updateWalls() {
        guard let walls = wallsRoot else { return }
        walls.children.removeAll()
        
        guard appViewModel.selectedEnvironment == .virtual, appViewModel.showWalls else { return }
        
        let wallHeight = appViewModel.wallHeight
        let wallThickness: Float = 0.1
        let floorSize: Float = 4.0
        let floorCenterZ: Float = -2.0
        
        let wallMaterial = SimpleMaterial(color: .gray.withAlphaComponent(0.8), isMetallic: false)
        
        // Wall 1: Back (Z = -4.0)
        let backWall = ModelEntity(
            mesh: .generateBox(width: floorSize, height: wallHeight, depth: wallThickness),
            materials: [wallMaterial]
        )
        backWall.position = [0, wallHeight / 2, floorCenterZ - (floorSize / 2) - (wallThickness / 2)]
        backWall.generateCollisionShapes(recursive: false)
        backWall.components.set(PhysicsBodyComponent(mode: .static))
        walls.addChild(backWall)
        
        // Wall 2: Front (Z = 0.0)
        let frontWall = ModelEntity(
            mesh: .generateBox(width: floorSize, height: wallHeight, depth: wallThickness),
            materials: [wallMaterial]
        )
        frontWall.position = [0, wallHeight / 2, floorCenterZ + (floorSize / 2) + (wallThickness / 2)]
        frontWall.generateCollisionShapes(recursive: false)
        frontWall.components.set(PhysicsBodyComponent(mode: .static))
        walls.addChild(frontWall)
        
        // Wall 3: Left (X = -2.0)
        let leftWall = ModelEntity(
            mesh: .generateBox(width: wallThickness, height: wallHeight, depth: floorSize),
            materials: [wallMaterial]
        )
        leftWall.position = [-(floorSize / 2) - (wallThickness / 2), wallHeight / 2, floorCenterZ]
        leftWall.generateCollisionShapes(recursive: false)
        leftWall.components.set(PhysicsBodyComponent(mode: .static))
        walls.addChild(leftWall)
        
        // Wall 4: Right (X = 2.0)
        let rightWall = ModelEntity(
            mesh: .generateBox(width: wallThickness, height: wallHeight, depth: floorSize),
            materials: [wallMaterial]
        )
        rightWall.position = [(floorSize / 2) + (wallThickness / 2), wallHeight / 2, floorCenterZ]
        rightWall.generateCollisionShapes(recursive: false)
        rightWall.components.set(PhysicsBodyComponent(mode: .static))
        walls.addChild(rightWall)
    }
    
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