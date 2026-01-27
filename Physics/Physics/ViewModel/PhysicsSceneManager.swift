import SwiftUI
import RealityKit
import ARKit

@Observable
class PhysicsSceneManager {
    // MARK: - Scene Entities
    var rootEntity: Entity = Entity()
    var objectEntity: ModelEntity?
    var traceRoot: Entity?
    var wallsRoot: Entity?
    var rampEntity: ModelEntity?
    var floorEntity: ModelEntity?
    
    // MARK: - ARKit
    var session = ARKitSession()
    var sceneReconstruction = SceneReconstructionProvider()
    var handTracking = HandTrackingProvider()
    
    var meshEntities = [UUID: ModelEntity]()
    var fingerEntities: [HandAnchor.Chirality: ModelEntity] = [:]
    
    // MARK: - Logic State
    var lastMarkerPosition: SIMD3<Float>? = nil
    var initialDragPosition: SIMD3<Float>? = nil
    var initialScale: SIMD3<Float>? = nil
    
    // Velocity Tracking
    var currentDragVelocity: SIMD3<Float> = .zero
    var lastDragPosition: SIMD3<Float>? = nil
    var lastDragTime: TimeInterval = 0
    
    // Subscription
    var updateSubscription: EventSubscription?
    
    // MARK: - Setup
    func setupScene(content: RealityViewContent, viewModel: AppViewModel) {
        // Root
        rootEntity.name = "Root"
        var physSim = PhysicsSimulationComponent()
        physSim.gravity = [0, -9.8, 0]
        rootEntity.components.set(physSim)
        content.add(rootEntity)
        
        // Traces
        let traces = Entity()
        traces.name = "TraceRoot"
        rootEntity.addChild(traces)
        self.traceRoot = traces
        
        // Fingertips
        let leftFinger = createFingertip()
        let rightFinger = createFingertip()
        rootEntity.addChild(leftFinger)
        rootEntity.addChild(rightFinger)
        self.fingerEntities = [.left: leftFinger, .right: rightFinger]
        
        // Virtual Floor
        let floor = ModelEntity(
            mesh: .generatePlane(width: 4.0, depth: 4.0),
            materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.5), isMetallic: false)]
        )
        floor.position = [0, 0, -2.0]
        floor.generateCollisionShapes(recursive: false)
        floor.components.set(PhysicsBodyComponent(mode: .static))
        floor.isEnabled = (viewModel.selectedEnvironment == .virtual)
        rootEntity.addChild(floor)
        self.floorEntity = floor
        
        // Walls
        let walls = Entity()
        walls.name = "WallsRoot"
        rootEntity.addChild(walls)
        self.wallsRoot = walls
        updateWalls(viewModel: viewModel)
        
        // Ramp
        let ramp = ModelEntity()
        ramp.name = "Ramp"
        ramp.position = [0, 0, -2.0]
        ramp.components.set(InputTargetComponent(allowedInputTypes: .all))
        ramp.components.set(PhysicsBodyComponent(mode: .static))
        
        let initialRadians = viewModel.rampRotation * (Float.pi / 180.0)
        ramp.transform.rotation = simd_quatf(angle: initialRadians, axis: [0, 1, 0])
        ramp.isEnabled = (viewModel.selectedEnvironment == .virtual && viewModel.showRamp)
        rootEntity.addChild(ramp)
        self.rampEntity = ramp
        updateRamp(viewModel: viewModel)
        
        // Object
        let object = ModelEntity()
        object.name = "PhysicsObject"
        object.position = [0, 1.5, -2.0]
        object.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        let material = PhysicsMaterialResource.generate(
            staticFriction: viewModel.staticFriction,
            dynamicFriction: viewModel.dynamicFriction,
            restitution: viewModel.restitution
        )
        
        let initialMode: PhysicsBodyMode = (viewModel.selectedEnvironment == .mixed) ? .kinematic : viewModel.selectedMode.rkMode
        var physicsBody = PhysicsBodyComponent(
            massProperties: .init(mass: viewModel.mass),
            material: material,
            mode: initialMode
        )
        physicsBody.linearDamping = viewModel.linearDamping
        object.components.set(physicsBody)
        
        rootEntity.addChild(object)
        self.objectEntity = object
        updateShape(viewModel: viewModel)
        
        // Subscribe to updates
        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.handleSceneUpdate(viewModel: viewModel)
        }
    }
    
    // MARK: - Update Logic
    func handleSceneUpdate(viewModel: AppViewModel) {
        guard let obj = objectEntity,
              let motion = obj.components[PhysicsMotionComponent.self] else { return }
        
        // Void Check
        if obj.position(relativeTo: nil).y < -5.0 {
            obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
            obj.position = [0, 1.5, -2.0]
            lastMarkerPosition = nil
        }
        
        let velocity = motion.linearVelocity
        let speed = length(velocity)
        
        // Update ViewModel (Dispatch to main thread if needed, but @Observable handles it usually)
        // Since this is high frequency, we should be careful. 
        // For now, updating directly. If stutter occurs, throttle this.
        if abs(viewModel.currentSpeed - speed) > 0.01 {
             DispatchQueue.main.async {
                 viewModel.currentSpeed = speed
             }
        }
        
        // Advanced Drag
        if viewModel.useAdvancedDrag {
            if speed > 0.001 {
                let rho = viewModel.airDensity
                let A = viewModel.crossSectionalArea
                let Cd = viewModel.dragCoefficient
                let dragMagnitude = 0.5 * rho * (speed * speed) * Cd * A
                let dragForce = -velocity / speed * dragMagnitude
                obj.addForce(dragForce, relativeTo: nil)
            }
        }
        
        // Gravity Update
        if var physSim = rootEntity.components[PhysicsSimulationComponent.self] {
            physSim.gravity = [0, viewModel.gravity, 0]
            rootEntity.components.set(physSim)
        }
        
        // Path Trace
        if viewModel.showPath {
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
    
    // MARK: - Gestures
    func handleDragChanged(value: EntityTargetValue<DragGesture.Value>, viewModel: AppViewModel) {
        let entity = value.entity
        if entity.name == "SceneMesh" || entity.name == "Fingertip" { return }
        
        viewModel.isDragging = true
        
        if initialDragPosition == nil {
            initialDragPosition = entity.position(relativeTo: entity.parent)
            lastDragPosition = nil
            currentDragVelocity = .zero
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
        
        // Velocity Calculation
        let currentTime = Date().timeIntervalSinceReferenceDate
        if let lastPos = lastDragPosition {
            let dt = Float(currentTime - lastDragTime)
            if dt > 0.005 {
                let instantaneousVelocity = (newPos - lastPos) / dt
                currentDragVelocity = (currentDragVelocity * 0.6) + (instantaneousVelocity * 0.4)
            }
        }
        lastDragPosition = newPos
        lastDragTime = currentTime
        
        if entity.name == "Ramp" {
            newPos.y = 0.0
            entity.position = newPos
        } else {
            let minHeight: Float = (viewModel.selectedEnvironment == .virtual) ? 0.16 : -1.0
            if newPos.y < minHeight { newPos.y = minHeight }
            entity.position = newPos
        }
    }
    
    func handleDragEnded(value: EntityTargetValue<DragGesture.Value>, viewModel: AppViewModel) {
        let entity = value.entity
        if entity.name == "SceneMesh" || entity.name == "Fingertip" { return }
        
        viewModel.isDragging = false
        initialDragPosition = nil
        
        if entity.name == "Ramp" {
            if var body = entity.components[PhysicsBodyComponent.self] {
                body.mode = .static
                entity.components.set(body)
            }
        } else {
            if var body = entity.components[PhysicsBodyComponent.self] {
                body.mode = viewModel.selectedMode.rkMode
                entity.components.set(body)
            }
            if viewModel.selectedMode == .dynamic {
                var motion = PhysicsMotionComponent()
                
                let timeSinceLastUpdate = Date().timeIntervalSinceReferenceDate - lastDragTime
                if timeSinceLastUpdate > 0.1 {
                    motion.linearVelocity = .zero
                } else {
                    motion.linearVelocity = currentDragVelocity
                }
                
                motion.angularVelocity = .zero
                entity.components.set(motion)
            }
        }
        
        lastDragPosition = nil
        currentDragVelocity = .zero
    }
    
    func handleMagnifyChanged(value: EntityTargetValue<MagnifyGesture.Value>) {
        let entity = value.entity
        if entity.name == "SceneMesh" || entity.name == "Fingertip" { return }
        
        if initialScale == nil {
            initialScale = entity.scale
        }
        
        guard let startScale = initialScale else { return }
        let magnification = Float(value.magnification)
        entity.scale = startScale * magnification
    }
    
    func handleMagnifyEnded() {
        initialScale = nil
    }
    
    // MARK: - Scene Modifiers
    func resetScene() {
        guard let obj = objectEntity else { return }
        obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        obj.position = [0, 1.5, -2.0]
        traceRoot?.children.removeAll()
        lastMarkerPosition = nil
    }
    
    func updateShape(viewModel: AppViewModel) {
        guard let obj = objectEntity else { return }
        let newMesh: MeshResource
        let newMaterial: SimpleMaterial
        
        switch viewModel.selectedShape {
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
    
    func updatePhysicsProperties(viewModel: AppViewModel) {
        guard let obj = objectEntity else { return }
        
        let newMaterial = PhysicsMaterialResource.generate(
            staticFriction: viewModel.staticFriction,
            dynamicFriction: viewModel.dynamicFriction,
            restitution: viewModel.restitution
        )
        
        var bodyComponent = obj.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
        bodyComponent.massProperties.mass = viewModel.mass
        bodyComponent.material = newMaterial
        bodyComponent.mode = viewModel.selectedMode.rkMode
        bodyComponent.linearDamping = viewModel.useAdvancedDrag ? 0.0 : viewModel.linearDamping
        
        obj.components.set(bodyComponent)
    }
    
    func updateRamp(viewModel: AppViewModel) {
        guard let ramp = rampEntity else { return }
        
        let slopeLength = viewModel.rampLength
        let radians = viewModel.rampAngle * (Float.pi / 180.0)
        let height = slopeLength * sin(radians)
        let baseLength = slopeLength * cos(radians)
        let width = viewModel.rampWidth
        
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
            ramp.isEnabled = (viewModel.selectedEnvironment == .virtual && viewModel.showRamp)
        }
    }
    
    func updateWalls(viewModel: AppViewModel) {
        guard let walls = wallsRoot else { return }
        walls.children.removeAll()
        
        guard viewModel.selectedEnvironment == .virtual, viewModel.showWalls else { return }
        
        let wallHeight = viewModel.wallHeight
        let wallThickness: Float = 0.1
        let floorSize: Float = 4.0
        let floorCenterZ: Float = -2.0
        let wallMaterial = SimpleMaterial(color: .gray.withAlphaComponent(0.8), isMetallic: false)
        
        // Wall Helpers
        func createWall(size: SIMD3<Float>, pos: SIMD3<Float>) {
            let wall = ModelEntity(
                mesh: .generateBox(size: size),
                materials: [wallMaterial]
            )
            wall.position = pos
            wall.generateCollisionShapes(recursive: false)
            wall.components.set(PhysicsBodyComponent(mode: .static))
            walls.addChild(wall)
        }
        
        // Back
        createWall(size: [floorSize, wallHeight, wallThickness], pos: [0, wallHeight / 2, floorCenterZ - (floorSize / 2) - (wallThickness / 2)])
        // Front
        createWall(size: [floorSize, wallHeight, wallThickness], pos: [0, wallHeight / 2, floorCenterZ + (floorSize / 2) + (wallThickness / 2)])
        // Left
        createWall(size: [wallThickness, wallHeight, floorSize], pos: [-(floorSize / 2) - (wallThickness / 2), wallHeight / 2, floorCenterZ])
        // Right
        createWall(size: [wallThickness, wallHeight, floorSize], pos: [(floorSize / 2) + (wallThickness / 2), wallHeight / 2, floorCenterZ])
    }
    
    func addPathMarker(at position: SIMD3<Float>) {
        guard let parent = traceRoot else { return }
        let mesh = MeshResource.generateSphere(radius: 0.005)
        let material = UnlitMaterial(color: .yellow)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.position = position
        parent.addChild(marker)
    }
    
    // MARK: - ARKit Processing
    @MainActor
    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            let meshAnchor = update.anchor
            guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
            
            switch update.event {
            case .added:
                let entity = ModelEntity()
                entity.name = "SceneMesh"
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                entity.components.set(InputTargetComponent())
                entity.physicsBody = PhysicsBodyComponent(mode: .static)
                rootEntity.addChild(entity)
                meshEntities[meshAnchor.id] = entity
            case .updated:
                guard let entity = meshEntities[meshAnchor.id] else { continue }
                entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                entity.collision?.shapes = [shape]
            case .removed:
                meshEntities[meshAnchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: meshAnchor.id)
            }
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
        entity.components.set(OpacityComponent(opacity: 0.0))
        entity.isEnabled = false
        return entity
    }
}
