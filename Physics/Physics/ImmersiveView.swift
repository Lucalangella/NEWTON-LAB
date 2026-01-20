import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel
    
    // Scene References
    @State private var objectEntity: ModelEntity? // Renamed from boxEntity for clarity
    @State private var rootEntity: Entity?
    @State private var traceRoot: Entity?
    
    // Logic State
    @State private var lastMarkerPosition: SIMD3<Float>? = nil
    
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
            
            let floor = ModelEntity(
                mesh: .generatePlane(width: 4.0, depth: 4.0),
                materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.5), isMetallic: false)]
            )
            floor.position = [0, 0, -2.0]
            floor.generateCollisionShapes(recursive: false)
            floor.components.set(PhysicsBodyComponent(mode: .static))
            root.addChild(floor)
            
            // --- CREATE INITIAL OBJECT ---
            let object = ModelEntity() // Empty initially
            object.position = [0, 1.5, -2.0]
            
            // Basic Components
            object.components.set(InputTargetComponent(allowedInputTypes: .all))
            
            // Initial Physics Setup
            let material = PhysicsMaterialResource.generate(
                staticFriction: appModel.staticFriction,
                dynamicFriction: appModel.dynamicFriction,
                restitution: appModel.restitution
            )
            var physicsBody = PhysicsBodyComponent(
                massProperties: .init(mass: appModel.mass),
                material: material,
                mode: appModel.selectedMode.rkMode
            )
            physicsBody.linearDamping = appModel.linearDamping
            object.components.set(physicsBody)
            
            root.addChild(object)
            self.objectEntity = object
            
            // Apply the initial shape
            updateShape()
            
            // --- 2. SUBSCRIBE TO UPDATES ---
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                guard let obj = objectEntity,
                      let motion = obj.components[PhysicsMotionComponent.self] else { return }
                
                // 1. Update Speed
                let velocity = motion.linearVelocity
                let speed = length(velocity)
                appModel.currentSpeed = speed
                
                // 2. Update Gravity
                if let root = rootEntity,
                   var physSim = root.components[PhysicsSimulationComponent.self] {
                    physSim.gravity = [0, appModel.gravity, 0]
                    root.components.set(physSim)
                }
                
                // 3. Update Path Plotter
                if appModel.showPath {
                    let currentPos = obj.position(relativeTo: nil)
                    
                    if let lastPos = lastMarkerPosition {
                        let distance = length(currentPos - lastPos)
                        if distance > 0.05 { // 5 cm threshold
                            addPathMarker(at: currentPos)
                            lastMarkerPosition = currentPos
                        }
                    } else {
                        lastMarkerPosition = currentPos
                    }
                }
            }
            
        } update: { content in }
        
        // --- 3. GESTURE ---
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = value.entity
                    appModel.isDragging = true
                    
                    if var body = entity.components[PhysicsBodyComponent.self] {
                        body.mode = .kinematic
                        entity.components.set(body)
                    }
                    
                    var newPos = value.convert(value.location3D, from: .local, to: entity.parent!)
                    if newPos.y < 0.16 { newPos.y = 0.16 }
                    entity.position = newPos
                    
                    entity.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
                }
                .onEnded { value in
                    let entity = value.entity
                    appModel.isDragging = false
                    
                    if var body = entity.components[PhysicsBodyComponent.self] {
                        body.mode = appModel.selectedMode.rkMode
                        entity.components.set(body)
                    }
                    
                    // Force Drop
                    if appModel.selectedMode == .dynamic {
                        var motion = PhysicsMotionComponent()
                        motion.linearVelocity = .zero
                        motion.angularVelocity = .zero
                        entity.components.set(motion)
                    }
                }
        )
        // --- EVENT HANDLERS ---
        .onChange(of: appModel.resetSignal) {
            guard let obj = objectEntity else { return }
            obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
            obj.position = [0, 1.5, -2.0]
            
            traceRoot?.children.removeAll()
            lastMarkerPosition = nil
        }
        .onChange(of: [appModel.mass, appModel.restitution, appModel.dynamicFriction, appModel.staticFriction, appModel.linearDamping] as [Float]) {
            updatePhysicsProperties()
        }
        .onChange(of: appModel.selectedMode) {
            updatePhysicsProperties()
        }
        .onChange(of: appModel.showPath) {
            if !appModel.showPath {
                traceRoot?.children.removeAll()
                lastMarkerPosition = nil
            }
        }
        // NEW: Shape Change
        .onChange(of: appModel.selectedShape) {
            updateShape()
        }
    }
    
    // MARK: - Updates
    func updateShape() {
        guard let obj = objectEntity else { return }
        
        // 1. Generate new Mesh and Material
        // We use a different color for each shape to make it visually distinct
        let newMesh: MeshResource
        let newMaterial: SimpleMaterial
        
        switch appModel.selectedShape {
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
        
        // 2. Apply Mesh
        obj.model = ModelComponent(mesh: newMesh, materials: [newMaterial])
        
        // 3. Regenerate Collision Shape (Critical for physics!)
        // 'recursive: false' is fine since it's a single primitive
        obj.generateCollisionShapes(recursive: false)
        
        // Note: We don't need to re-add the physics body component;
        // RealityKit will use the new collision shape automatically for the existing body.
    }
    
    func updatePhysicsProperties() {
        guard let obj = objectEntity else { return }
        
        let newMaterial = PhysicsMaterialResource.generate(
            staticFriction: appModel.staticFriction,
            dynamicFriction: appModel.dynamicFriction,
            restitution: appModel.restitution
        )
        
        var bodyComponent = obj.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
        bodyComponent.massProperties.mass = appModel.mass
        bodyComponent.material = newMaterial
        bodyComponent.mode = appModel.selectedMode.rkMode
        bodyComponent.linearDamping = appModel.linearDamping
        obj.components.set(bodyComponent)
        
        switch appModel.selectedMode {
        case .dynamic: break
        case .staticMode:
            obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        case .kinematic:
            let spinSpeed: Float = 1.0
            obj.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: [0, spinSpeed, 0]))
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
