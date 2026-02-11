import SwiftUI
import RealityKit
import ARKit

@Observable
@MainActor
class PhysicsSceneManager {
    // MARK: - Scene Entities
    var rootEntity: Entity = Entity()
    var spawnedObjects: [ModelEntity] = []
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
    var initialRotation: simd_quatf? = nil
    
    // Velocity Tracking
    var currentDragVelocity: SIMD3<Float> = .zero
    var lastDragPosition: SIMD3<Float>? = nil
    var lastDragTime: TimeInterval = 0
    var lastSpeedUpdateTime: TimeInterval = 0
    
    // Concurrency Guard
    var isProcessingUpdate: Bool = false
    
    // Subscription
    var updateSubscription: EventSubscription?
    
    // MARK: - Setup
    func setupScene(content: RealityViewContent, viewModel: AppViewModel) {
        // Root
        rootEntity.name = "Root"
        var physSim = PhysicsSimulationComponent()
        physSim.gravity = [0, -9.8, 0]
        rootEntity.components.set(physSim)
        
        // Studio Lighting Setup
        // 1. Key Light (Main Source)
        let keyLight = DirectionalLight()
        keyLight.light.intensity = 800
        keyLight.look(at: [0, 0, -2], from: [2, 4, 2], relativeTo: nil)
        rootEntity.addChild(keyLight)
        
        // 2. Fill Light (Softens Shadows)
        let fillLight = DirectionalLight()
        fillLight.light.intensity = 600
        fillLight.look(at: [0, 0, -2], from: [-2, 2, 0], relativeTo: nil)
        rootEntity.addChild(fillLight)
        
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
            materials: [SimpleMaterial(color: .white.withAlphaComponent(CGFloat(viewModel.environmentOpacity)), isMetallic: false)]
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
        
        // Initial Object
        spawnShape(viewModel: viewModel, shape: viewModel.selectedShape)
        
        // Subscribe to updates
        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                guard !self.isProcessingUpdate else { return }
                self.isProcessingUpdate = true
                self.handleSceneUpdate(viewModel: viewModel)
                self.isProcessingUpdate = false
            }
        }
    }
    
    private func findTargetEntity(for entity: Entity) -> Entity? {
        // Walk up the hierarchy to find the root interactable entity
        var current: Entity? = entity
        while let c = current {
            if c.name == "PhysicsObject" || c.name == "Ramp" {
                return c
            }
            current = c.parent
        }
        return nil
    }
    
    func updateEnvironmentOpacity(viewModel: AppViewModel) {
        let opacity = viewModel.environmentOpacity
        let color = SimpleMaterial.Color.white.withAlphaComponent(CGFloat(opacity))
        let material = SimpleMaterial(color: color, isMetallic: false)
        
        // Update Floor
        floorEntity?.model?.materials = [material]
        
        // Update Walls (recursive update for all children in wallsRoot)
        func updateMaterials(in entity: Entity) {
            if var model = entity.components[ModelComponent.self] {
                model.materials = [material]
                entity.components.set(model)
            }
            for child in entity.children {
                updateMaterials(in: child)
            }
        }
        
        if let walls = wallsRoot {
            updateMaterials(in: walls)
        }
    }

    // MARK: - Update Logic
    func handleSceneUpdate(viewModel: AppViewModel) {
        var totalSpeed: Float = 0
        var activeCount: Int = 0
        
        for obj in spawnedObjects {
            guard let motion = obj.components[PhysicsMotionComponent.self] else { continue }
            
            // Void Check
            if obj.position(relativeTo: nil).y < -5.0 {
                obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
                obj.position = [0, 1.5, -2.0]
                lastMarkerPosition = nil
            }
            
            let velocity = motion.linearVelocity
            let speed = length(velocity)
            totalSpeed += speed
            activeCount += 1
            
            // Advanced Drag
            if viewModel.useAdvancedDrag {
                if speed > 0.001 {
                    let rho = viewModel.airDensity
                    // We'd ideally need shape-specific data for each spawned object
                    // For now using current VM values which might be slightly inaccurate for mixed shapes
                    let A = viewModel.crossSectionalArea 
                    let Cd = viewModel.dragCoefficient
                    let dragMagnitude = 0.5 * rho * (speed * speed) * Cd * A
                    let dragForce = -velocity / speed * dragMagnitude
                    obj.addForce(dragForce, relativeTo: nil)
                }
            }
            
            // Path Trace (only for the last spawned or focused? Let's do all for now if enabled)
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
        
        let avgSpeed = activeCount > 0 ? totalSpeed / Float(activeCount) : 0
        let currentTime = Date().timeIntervalSinceReferenceDate
        
        if currentTime - lastSpeedUpdateTime > 0.1 {
            if abs(viewModel.currentSpeed - avgSpeed) > 0.01 {
                 viewModel.currentSpeed = avgSpeed
            }
            lastSpeedUpdateTime = currentTime
        }
        
        // Gravity Update
        if var physSim = rootEntity.components[PhysicsSimulationComponent.self] {
            physSim.gravity = [0, viewModel.gravity, 0]
            rootEntity.components.set(physSim)
        }
    }
    
    func spawnShape(viewModel: AppViewModel, shape: ShapeOption) {
        let object: ModelEntity
        var collisionShape: ShapeResource?
        
        object = ModelEntity()
        let mesh: MeshResource
        let materialColor: SimpleMaterial.Color
        
        switch shape {
        case .box:
            mesh = .generateBox(size: 0.3)
            materialColor = .red
            collisionShape = .generateBox(size: [0.3, 0.3, 0.3])
        case .sphere:
            mesh = .generateSphere(radius: 0.15)
            materialColor = .blue
            collisionShape = .generateSphere(radius: 0.15)
                    case .cylinder:
                        mesh = .generateCylinder(height: 0.3, radius: 0.15)
                        materialColor = .green
                        collisionShape = ShapeResource.generateConvex(from: mesh)
                    case .cone:
                        mesh = .generateCone(height: 0.3, radius: 0.15)
                        materialColor = .yellow
                        collisionShape = ShapeResource.generateConvex(from: mesh)
                    }        
        object.model = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: materialColor, isMetallic: false)])
        
        if collisionShape == nil {
            object.generateCollisionShapes(recursive: false)
        }
        
        if let shapeRes = collisionShape {
            object.collision = CollisionComponent(shapes: [shapeRes])
        }
        
        object.name = "PhysicsObject"
        
        let randomOffset = SIMD3<Float>(
            Float.random(in: -0.2...0.2),
            0,
            Float.random(in: -0.2...0.2)
        )
        object.position = [0, 1.5, -2.0] + randomOffset
        
        object.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        let physMaterial = PhysicsMaterialResource.generate(
            staticFriction: viewModel.staticFriction,
            dynamicFriction: viewModel.dynamicFriction,
            restitution: viewModel.restitution
        )
        
        // Calculate Mass Properties from Shape (Crucial for correct Inertia)
        var massProps: PhysicsMassProperties
        let bounds = object.visualBounds(relativeTo: object)
        let geometricCenter = (bounds.max + bounds.min) / 2
        
        if let shapeRes = collisionShape {
            massProps = PhysicsMassProperties(shape: shapeRes, mass: viewModel.mass)
        } else if let generatedShape = object.collision?.shapes.first {
            massProps = PhysicsMassProperties(shape: generatedShape, mass: viewModel.mass)
        } else {
            massProps = .init(mass: viewModel.mass)
        }
        
        // Force Center of Mass to geometric center to prevent "wobbling back"
        massProps.centerOfMass.position = geometricCenter
        
        let initialMode: PhysicsBodyMode = (viewModel.selectedEnvironment == .mixed) ? .kinematic : viewModel.selectedMode.rkMode
        var physicsBody = PhysicsBodyComponent(
            massProperties: massProps,
            material: physMaterial,
            mode: initialMode
        )
        physicsBody.linearDamping = viewModel.linearDamping
        physicsBody.angularDamping = 0.0 // Add damping to reduce wobbling
        object.components.set(physicsBody)
        
        rootEntity.addChild(object)
        spawnedObjects.append(object)
    }
    
    func spawnCustomModel(url: URL, viewModel: AppViewModel) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let object = try ModelEntity.loadModel(contentsOf: url)
            object.name = "PhysicsObject"
            
            let randomOffset = SIMD3<Float>(
                Float.random(in: -0.2...0.2),
                0,
                Float.random(in: -0.2...0.2)
            )
            object.position = [0, 1.5, -2.0] + randomOffset
            object.components.set(InputTargetComponent(allowedInputTypes: .all))
            
            // --- Calculate bounds for accurate sizing & centering ---
            let bounds = object.visualBounds(relativeTo: object)
            let geometricCenter = (bounds.max + bounds.min) / 2
            let extents = bounds.max - bounds.min
            
            // --- Apply the selected Collision Shape ---
            switch viewModel.importCollisionShape {
            case .sphere:
                // Creates a perfect rolling sphere
                let radius = max(extents.x, extents.y, extents.z) / 2.0
                let sphereShape = ShapeResource.generateSphere(radius: radius).offsetBy(translation: geometricCenter)
                object.collision = CollisionComponent(shapes: [sphereShape])
                
            case .box:
                // Creates a perfect sliding box
                let boxShape = ShapeResource.generateBox(size: extents).offsetBy(translation: geometricCenter)
                object.collision = CollisionComponent(shapes: [boxShape])
                
            case .automatic:
                // Wraps the object in a low-poly mesh (Good for complex shapes, bad for rolling)
                object.generateCollisionShapes(recursive: true)
            }
            
            let physMaterial = PhysicsMaterialResource.generate(
                staticFriction: viewModel.staticFriction,
                dynamicFriction: viewModel.dynamicFriction,
                restitution: viewModel.restitution
            )
            
            // --- Setup Mass ---
            var massProps: PhysicsMassProperties
            if let shape = object.collision?.shapes.first {
                massProps = PhysicsMassProperties(shape: shape, mass: viewModel.mass)
            } else {
                massProps = .init(mass: viewModel.mass)
            }
            // Force Center of Mass to geometric center to stop wobbling
            massProps.centerOfMass.position = geometricCenter
            
            let initialMode: PhysicsBodyMode = (viewModel.selectedEnvironment == .mixed) ? .kinematic : viewModel.selectedMode.rkMode
            var physicsBody = PhysicsBodyComponent(
                massProperties: massProps,
                material: physMaterial,
                mode: initialMode
            )
            
            physicsBody.linearDamping = viewModel.linearDamping
            
            // IMPORTANT: Keep angular damping at 0.0 so spheres can actually roll!
            physicsBody.angularDamping = 0.0
            
            object.components.set(physicsBody)
            
            rootEntity.addChild(object)
            spawnedObjects.append(object)
        } catch {
            print("Failed to load custom model: \(error)")
        }
    }

    // MARK: - Gestures
    func handleDragChanged(value: EntityTargetValue<DragGesture.Value>, viewModel: AppViewModel) {
        guard let entity = findTargetEntity(for: value.entity) else { return }
        
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
        guard let entity = findTargetEntity(for: value.entity) else { return }
        
        viewModel.isDragging = false
        initialDragPosition = nil
        
        endInteractionIfNeeded(entity: entity, viewModel: viewModel)
        
        lastDragPosition = nil
        currentDragVelocity = .zero
    }
    
    func handleMagnifyChanged(value: EntityTargetValue<MagnifyGesture.Value>) {
        guard let entity = findTargetEntity(for: value.entity) else { return }
        if entity.name == "TraceRoot" || entity.name == "WallsRoot" || entity.name == "Ramp" { return }
        
        // Ensure kinematic during interaction
        if var body = entity.components[PhysicsBodyComponent.self], body.mode != .kinematic {
            body.mode = .kinematic
            entity.components.set(body)
            entity.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        }
        
        if initialScale == nil {
            initialScale = entity.scale
        }
        
        guard let startScale = initialScale else { return }
        let magnification = Float(value.magnification)
        entity.scale = startScale * magnification
    }
    
    func handleMagnifyEnded(value: EntityTargetValue<MagnifyGesture.Value>, viewModel: AppViewModel) {
        guard let entity = findTargetEntity(for: value.entity) else { return }
        if entity.name == "Ramp" { return }
        initialScale = nil
        endInteractionIfNeeded(entity: entity, viewModel: viewModel)
    }
    
    func handleRotateChanged(value: EntityTargetValue<RotateGesture3D.Value>) {
        guard let entity = findTargetEntity(for: value.entity) else { return }
        if entity.name == "TraceRoot" || entity.name == "WallsRoot" { return }
        
        // Ensure kinematic during interaction
        if var body = entity.components[PhysicsBodyComponent.self], body.mode != .kinematic {
            body.mode = .kinematic
            entity.components.set(body)
            entity.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        }
        
        if initialRotation == nil {
            initialRotation = entity.orientation
        }
        
        guard let startRotation = initialRotation else { return }
        
        // Convert Rotation3D to simd_quatf
        let rotation = value.rotation
        let rotationQuat = simd_quatf(rotation)
        let combined = rotationQuat * startRotation
        
        if entity.name == "Ramp" {
            // Constrain rotation to Y-axis (Up) only
            let forward = combined.act([0, 0, 1])
            let yaw = atan2(forward.x, forward.z)
            entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        } else {
            entity.orientation = combined
        }
    }
    
    func handleRotateEnded(value: EntityTargetValue<RotateGesture3D.Value>, viewModel: AppViewModel) {
        guard let entity = findTargetEntity(for: value.entity) else { return }
        initialRotation = nil
        endInteractionIfNeeded(entity: entity, viewModel: viewModel)
    }
    
    private func endInteractionIfNeeded(entity: Entity, viewModel: AppViewModel) {
        // Only return to dynamic/static if no other gestures are active for this entity
        // Note: This is a bit simplified as we don't track per-entity gesture state perfectly here,
        // but since we only have one set of initialX variables, it works for single-object interaction.
        guard initialDragPosition == nil && initialScale == nil && initialRotation == nil else { return }
        
                if entity.name == "Ramp" {
                    if var body = entity.components[PhysicsBodyComponent.self] {
                        body.mode = .static
                        entity.components.set(body)
                    }
                } else {
                    if var body = entity.components[PhysicsBodyComponent.self] {                body.mode = viewModel.selectedMode.rkMode
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
    }
    
    // MARK: - Selection
    func handleTap(value: EntityTargetValue<SpatialTapGesture.Value>, viewModel: AppViewModel) {
        guard let objectEntity = findTargetEntity(for: value.entity) as? ModelEntity else { return }
        
        // Find the root object in our spawnedObjects list
        guard let objectIndex = spawnedObjects.firstIndex(where: { $0.id == objectEntity.id }) else { return }
        let object = spawnedObjects[objectIndex]
        
        if viewModel.isDeleteMode {
            // Delete Logic
            object.removeFromParent()
            spawnedObjects.remove(at: objectIndex)
            
            // Also cleanup selection if it was selected
            if viewModel.selectedEntityIDs.contains(object.id) {
                viewModel.selectedEntityIDs.remove(object.id)
                // No need to update visuals for this object as it's gone, 
                // but might need to sync VM if it was the only selection.
            }
            return
        }
        
        guard viewModel.isSelectionMode else { return }
        
        viewModel.toggleSelection(object.id)
        updateSelectionVisuals(viewModel: viewModel)
        syncViewModelToSelection(viewModel: viewModel)
    }
    
    func updateSelectionVisuals(viewModel: AppViewModel) {
        for obj in spawnedObjects {
            // Check for existing highlight
            let highlightName = "SelectionHighlight"
            let existingHighlight = obj.findEntity(named: highlightName)
            
            if viewModel.selectedEntityIDs.contains(obj.id) {
                // Add highlight if missing
                if existingHighlight == nil {
                    let bounds = obj.visualBounds(relativeTo: obj)
                    let size = (bounds.max - bounds.min) * 1.1
                    let mesh = MeshResource.generateBox(size: size)
                    
                    let material = UnlitMaterial(color: .white.withAlphaComponent(0.3))
                    let highlight = ModelEntity(mesh: mesh, materials: [material])
                    highlight.name = highlightName
                    highlight.position = (bounds.max + bounds.min) / 2
                    highlight.components.set(OpacityComponent(opacity: 0.3))
                    obj.addChild(highlight)
                }
            } else {
                // Remove highlight if present
                if let highlight = existingHighlight {
                    highlight.removeFromParent()
                }
            }
        }
    }
    
    func syncViewModelToSelection(viewModel: AppViewModel) {
        // If one object selected, update VM values to match it.
        // If multiple, maybe don't sync (keep current VM values).
        // If none, keep current.
        
        guard viewModel.selectedEntityIDs.count == 1,
              let id = viewModel.selectedEntityIDs.first,
              let obj = spawnedObjects.first(where: { $0.id == id }) else { return }
        
        if let body = obj.components[PhysicsBodyComponent.self] {
            viewModel.mass = body.massProperties.mass
            // Material properties are harder to extract perfectly back to VM's separated friction/restitution
            // without storing them. But we can try to get them if available.
            // RK's PhysicsMaterialResource doesn't expose properties easily.
            // Strategy: We rely on the VM being the source of truth for the *next* edit.
            // So we might NOT sync back perfectly for now to avoid complexity, 
            // OR we assume standard values.
            // Ideally, we should store a metadata component on the entity with these values.
        }
    }
    
    // MARK: - Scene Modifiers
    func resetScene() {
        for obj in spawnedObjects {
            obj.removeFromParent()
        }
        spawnedObjects.removeAll()
        traceRoot?.children.removeAll()
        lastMarkerPosition = nil
    }
    
    func updateShape(viewModel: AppViewModel) {
        // No longer using single shape update for all objects, but could if needed.
        // For now, new objects are spawned with the selected shape.
    }
    
    func updatePhysicsProperties(viewModel: AppViewModel) {
        let newMaterial = PhysicsMaterialResource.generate(
            staticFriction: viewModel.staticFriction,
            dynamicFriction: viewModel.dynamicFriction,
            restitution: viewModel.restitution
        )
        
        let targets: [ModelEntity]
        if viewModel.selectedEntityIDs.isEmpty {
            targets = spawnedObjects
        } else {
            targets = spawnedObjects.filter { viewModel.selectedEntityIDs.contains($0.id) }
        }
        
        for obj in targets {
            var bodyComponent = obj.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
            
            // Update mass but keep existing calculated Center of Mass
            var massProps = bodyComponent.massProperties
            massProps.mass = viewModel.mass
            bodyComponent.massProperties = massProps
            
            bodyComponent.material = newMaterial
            bodyComponent.mode = viewModel.selectedMode.rkMode
            bodyComponent.linearDamping = viewModel.useAdvancedDrag ? 0.0 : viewModel.linearDamping
            bodyComponent.angularDamping = 0.0
            
            obj.components.set(bodyComponent)
        }
    }
    
    func updateEnvironment(viewModel: AppViewModel) {
        floorEntity?.isEnabled = (viewModel.selectedEnvironment == .virtual)
        rampEntity?.isEnabled = (viewModel.selectedEnvironment == .virtual && viewModel.showRamp)
        updateWalls(viewModel: viewModel)
        updatePhysicsProperties(viewModel: viewModel)
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
            let shape = ShapeResource.generateConvex(from: rampMesh)
            ramp.collision = CollisionComponent(shapes: [shape])
            
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
        let wallMaterial = SimpleMaterial(color: .white.withAlphaComponent(CGFloat(viewModel.environmentOpacity)), isMetallic: false)
        
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
        
        // Ceiling (Only if max height)
        if wallHeight >= 1.99 {
            // Cover the entire top including wall thickness
            let ceilingWidth = floorSize + (wallThickness * 2)
            createWall(size: [ceilingWidth, wallThickness, ceilingWidth], pos: [0, wallHeight + (wallThickness / 2), floorCenterZ])
        }
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
    
    private func findFirstMesh(in entity: Entity) -> MeshResource? {
        if let model = entity.components[ModelComponent.self]?.mesh {
            return model
        }
        for child in entity.children {
            if let found = findFirstMesh(in: child) {
                return found
            }
        }
        return nil
    }
    
    
}
