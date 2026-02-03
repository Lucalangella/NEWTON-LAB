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
    var sunEntity: ModelEntity?
    var mainSunLight: DirectionalLight?
    
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
        keyLight.isEnabled = viewModel.showSun
        rootEntity.addChild(keyLight)
        self.mainSunLight = keyLight
        
        // 2. Fill Light (Softens Shadows)
        let fillLight = DirectionalLight()
        fillLight.light.intensity = 600
        fillLight.look(at: [0, 0, -2], from: [-2, 2, 0], relativeTo: nil)
        rootEntity.addChild(fillLight)
        
        content.add(rootEntity)
        
        // Ensure Sun is initialized if needed
        updateSunVisibility(viewModel: viewModel)
        
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
    
    func updateSunVisibility(viewModel: AppViewModel) {
        if viewModel.showSun {
            if sunEntity == nil {
                spawnSun(viewModel: viewModel)
            }
            sunEntity?.isEnabled = true
            mainSunLight?.isEnabled = true
            updateSunProperties(viewModel: viewModel)
        } else {
            sunEntity?.isEnabled = false
            mainSunLight?.isEnabled = false
        }
    }
    
    func updateSunProperties(viewModel: AppViewModel) {
        guard let light = mainSunLight else { return }
        // Update Light Intensity
        light.light.intensity = viewModel.sunIntensity
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

    private func spawnSun(viewModel: AppViewModel) {
        // Remove existing if any (safety)
        if let existing = sunEntity {
            existing.removeFromParent()
        }
        
        let sun: ModelEntity
        if let loadedModel = try? ModelEntity.loadModel(named: "Sun") {
            sun = loadedModel
        } else {
            // Fallback to sphere if USDZ fails
            sun = ModelEntity(
                mesh: .generateSphere(radius: 0.15),
                materials: [UnlitMaterial(color: .yellow)]
            )
        }
        
        sun.name = "Sun"
        sun.position = [0.5, 1.5, -1.0]
        
        // Physics for dragging
        sun.components.set(PhysicsBodyComponent(mode: .kinematic))
        sun.components.set(InputTargetComponent(allowedInputTypes: .all))
        sun.generateCollisionShapes(recursive: true)
        
        rootEntity.addChild(sun)
        self.sunEntity = sun
    }

    // MARK: - Update Logic
    func handleSceneUpdate(viewModel: AppViewModel) {
        // Update Sun Light Direction
        if let sun = sunEntity, let light = mainSunLight {
            // Light points from Sun to Origin (or Center of Scene roughly [0, 0, -2])
            light.look(at: [0, 0, -2], from: sun.position, relativeTo: nil)
        }
        
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
        
        if shape == .pin {
            if let loadedModel = try? ModelEntity.loadModel(named: "Pin") {
                object = loadedModel
                // Generate Convex Hull from the actual mesh for accurate inertia/collision
                if let mesh = findFirstMesh(in: object) {
                    let convex = ShapeResource.generateConvex(from: mesh)
                    collisionShape = convex
                } else {
                    object.generateCollisionShapes(recursive: true)
                }
            } else {
                print("Failed to load Pin.usdz")
                return
            }
        } else {
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
            case .pin: return
            }
            
            object.model = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: materialColor, isMetallic: false)])
            
            if collisionShape == nil {
                object.generateCollisionShapes(recursive: false)
            }
        }
        
        if let shapeRes = collisionShape {
            object.collision = CollisionComponent(shapes: [shapeRes])
        }
        
        object.name = "PhysicsObject"
        object.position = [0, 1.5, -2.0]
        object.components.set(InputTargetComponent(allowedInputTypes: .all))
        
        let physMaterial = PhysicsMaterialResource.generate(
            staticFriction: viewModel.staticFriction,
            dynamicFriction: viewModel.dynamicFriction,
            restitution: viewModel.restitution
        )
        
        // Calculate Mass Properties from Shape (Crucial for correct Inertia)
        var massProps: PhysicsMassProperties
        if let shapeRes = collisionShape {
            massProps = PhysicsMassProperties(shape: shapeRes, mass: viewModel.mass)
        } else {
             massProps = .init(mass: viewModel.mass)
        }
        
        // Apply Center of Mass adjustment (Generic for all shapes)
        // Uses visual bounds to determine height range
        let bounds = object.visualBounds(relativeTo: object)
        let height = bounds.max.y - bounds.min.y
        let targetY = bounds.min.y + (height * viewModel.centerOfMassFactor)
        massProps.centerOfMass = (position: [0, targetY, 0], orientation: simd_quatf(angle: 0, axis: [0, 1, 0]))
        
        let initialMode: PhysicsBodyMode = (viewModel.selectedEnvironment == .mixed) ? .kinematic : viewModel.selectedMode.rkMode
        var physicsBody = PhysicsBodyComponent(
            massProperties: massProps,
            material: physMaterial,
            mode: initialMode
        )
        physicsBody.linearDamping = viewModel.linearDamping
        object.components.set(physicsBody)
        
        rootEntity.addChild(object)
        spawnedObjects.append(object)
    }

    // MARK: - Gestures
    func handleDragChanged(value: EntityTargetValue<DragGesture.Value>, viewModel: AppViewModel) {
        let entity = value.entity
        if entity.name == "SceneMesh" || entity.name == "Fingertip" || entity.name == "Root" { return }
        
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
        if entity.name == "SceneMesh" || entity.name == "Fingertip" || entity.name == "Root" { return }
        
        viewModel.isDragging = false
        initialDragPosition = nil
        
        if entity.name == "Ramp" {
            if var body = entity.components[PhysicsBodyComponent.self] {
                body.mode = .static
                entity.components.set(body)
            }
        } else if entity.name == "Sun" {
            if var body = entity.components[PhysicsBodyComponent.self] {
                body.mode = .kinematic
                entity.components.set(body)
                entity.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
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
        if entity.name == "SceneMesh" || entity.name == "Fingertip" || entity.name == "Root" || entity.name == "TraceRoot" || entity.name == "WallsRoot" { return }
        
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
    
    // MARK: - Selection
    func handleTap(value: EntityTargetValue<SpatialTapGesture.Value>, viewModel: AppViewModel) {
        let entity = value.entity
        
        // Check if entity is one of our spawned objects (or a child of one)
        // Find the root object in our spawnedObjects list
        guard let objectIndex = spawnedObjects.firstIndex(where: { $0.id == entity.id }) else { return }
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
                    let mesh = MeshResource.generateBox(size: 0.35) // Slightly larger than standard box
                    // Adjust size based on shape? For prototype, fixed box or dynamic bounding box.
                    // Let's just use a simple white wireframe-ish effect via material or opacity.
                    // Simplest: Add a slightly larger semi-transparent shell.
                    let material = UnlitMaterial(color: .white.withAlphaComponent(0.3))
                    let highlight = ModelEntity(mesh: mesh, materials: [material])
                    highlight.name = highlightName
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
        sunEntity?.removeFromParent()
        sunEntity = nil
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
            bodyComponent.massProperties.mass = viewModel.mass
            bodyComponent.material = newMaterial
            bodyComponent.mode = viewModel.selectedMode.rkMode
            bodyComponent.linearDamping = viewModel.useAdvancedDrag ? 0.0 : viewModel.linearDamping
            
            // Update Center of Mass
            let bounds = obj.visualBounds(relativeTo: obj)
            let height = bounds.max.y - bounds.min.y
            let targetY = bounds.min.y + (height * viewModel.centerOfMassFactor)
            bodyComponent.massProperties.centerOfMass = (position: [0, targetY, 0], orientation: simd_quatf(angle: 0, axis: [0, 1, 0]))
            
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
