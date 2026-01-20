import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel
    @State private var boxEntity: ModelEntity?
    @State private var rootEntity: Entity?
    
    var body: some View {
        RealityView { content in
            // --- 1. SETUP SCENE ---
            let root = Entity()
            root.name = "Root"
            
            // Add a PhysicsSimulationComponent to the root to control gravity
            var physSim = PhysicsSimulationComponent()
            physSim.gravity = [0, -9.8, 0]
            root.components.set(physSim)
            
            content.add(root)
            self.rootEntity = root
            
            let floor = ModelEntity(
                mesh: .generatePlane(width: 4.0, depth: 4.0),
                materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.5), isMetallic: false)]
            )
            floor.position = [0, 0, -2.0]
            floor.generateCollisionShapes(recursive: false)
            floor.components.set(PhysicsBodyComponent(mode: .static))
            
            root.addChild(floor)
            
            let box = ModelEntity(
                mesh: .generateBox(size: 0.3),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            box.position = [0, 1.5, -2.0]
            box.generateCollisionShapes(recursive: false)
            
            box.components.set(InputTargetComponent(allowedInputTypes: .all))
            
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
            box.components.set(physicsBody)
            
            root.addChild(box)
            self.boxEntity = box
            
            // --- 2. SUBSCRIBE TO UPDATES ---
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                guard let box = boxEntity,
                      let motion = box.components[PhysicsMotionComponent.self] else { return }
                
                let velocity = motion.linearVelocity
                let speed = length(velocity)
                appModel.currentSpeed = speed
                
                // Update Gravity via the Component on Root
                if let root = rootEntity,
                   var physSim = root.components[PhysicsSimulationComponent.self] {
                    physSim.gravity = [0, appModel.gravity, 0]
                    root.components.set(physSim)
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
                    
                    if appModel.selectedMode == .dynamic {
                        
                        // CHANGED: Check if throwing is enabled
                        if appModel.isThrowingEnabled {
                            let currentPos = value.location3D
                            let predictedPos = value.predictedEndLocation3D
                            
                            let deltaX = Float(predictedPos.x - currentPos.x)
                            let deltaY = Float(predictedPos.y - currentPos.y)
                            let deltaZ = Float(predictedPos.z - currentPos.z)
                            
                            let strength = appModel.throwStrength
                            let throwVel = SIMD3<Float>(deltaX * strength, deltaY * strength, deltaZ * strength)
                            
                            appModel.lastThrowVector = String(format: "%.1f, %.1f, %.1f", throwVel.x, throwVel.y, throwVel.z)
                            
                            var motion = PhysicsMotionComponent()
                            motion.linearVelocity = throwVel
                            motion.angularVelocity = [Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)]
                            entity.components.set(motion)
                        } else {
                            // CHANGED: Just Drop (Zero Velocity)
                            appModel.lastThrowVector = "Dropped (0,0,0)"
                            var motion = PhysicsMotionComponent()
                            motion.linearVelocity = .zero // Dead stop
                            motion.angularVelocity = .zero
                            entity.components.set(motion)
                        }
                    }
                }
        )
        // --- EVENT HANDLERS ---
        .onChange(of: appModel.resetSignal) {
            guard let box = boxEntity else { return }
            box.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
            box.position = [0, 1.5, -2.0]
            appModel.lastThrowVector = "0.0, 0.0, 0.0"
        }
        .onChange(of: [appModel.mass, appModel.restitution, appModel.dynamicFriction, appModel.staticFriction, appModel.linearDamping] as [Float]) {
            updatePhysicsProperties()
        }
        .onChange(of: appModel.selectedMode) {
            updatePhysicsProperties()
        }
    }
    
    func updatePhysicsProperties() {
        guard let box = boxEntity else { return }
        
        let newMaterial = PhysicsMaterialResource.generate(
            staticFriction: appModel.staticFriction,
            dynamicFriction: appModel.dynamicFriction,
            restitution: appModel.restitution
        )
        
        var bodyComponent = box.components[PhysicsBodyComponent.self] ?? PhysicsBodyComponent()
        bodyComponent.massProperties.mass = appModel.mass
        bodyComponent.material = newMaterial
        bodyComponent.mode = appModel.selectedMode.rkMode
        bodyComponent.linearDamping = appModel.linearDamping
        box.components.set(bodyComponent)
        
        switch appModel.selectedMode {
        case .dynamic: break
        case .staticMode:
            box.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        case .kinematic:
            let spinSpeed: Float = 1.0
            box.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: [0, spinSpeed, 0]))
        }
    }
}
