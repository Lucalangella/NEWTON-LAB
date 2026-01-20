import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel
    @State private var boxEntity: ModelEntity?
    
    var body: some View {
        // ERROR FIX 1: Removed ", attachments" here
        RealityView { content in
            // --- 1. SETUP SCENE ---
            
            // Floor
            let floor = ModelEntity(
                mesh: .generatePlane(width: 4.0, depth: 4.0),
                materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.5), isMetallic: false)]
            )
            floor.position = [0, 0, -2.0]
            floor.generateCollisionShapes(recursive: false)
            floor.components.set(PhysicsBodyComponent(mode: .static))
            content.add(floor)
            
            // Box
            let box = ModelEntity(
                mesh: .generateBox(size: 0.3),
                materials: [SimpleMaterial(color: .red, isMetallic: false)]
            )
            box.position = [0, 1.5, -2.0]
            box.generateCollisionShapes(recursive: false)
            
            // Physics
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
            
            content.add(box)
            self.boxEntity = box
            
            // --- 2. SUBSCRIBE TO UPDATES ---
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                guard let box = boxEntity,
                      let motion = box.components[PhysicsMotionComponent.self] else { return }
                
                // ERROR FIX 2: Simplified math using length() to avoid compiler timeouts
                let velocity = motion.linearVelocity
                let speed = length(velocity)
                
                // Update the AppModel
                appModel.currentSpeed = speed
            }
            
        } update: { content in
            // ERROR FIX 3: Removed ", attachments" here as well
            // Optional updates handle here
        }
        
        // --- EVENT HANDLERS ---
        .onChange(of: appModel.resetSignal) {
            guard let box = boxEntity else { return }
            box.position = [0, 1.5, -2.0]
            // Stop movement on reset
            box.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        }
        .onChange(of: appModel.impulseSignal) {
            guard let box = boxEntity else { return }
            if appModel.selectedMode == .dynamic {
                let kickStrength: Float = 10.0 * appModel.mass
                // Kick slightly up (y: 2.0) and forward into scene (z: -kickStrength)
                box.applyLinearImpulse([0, 2.0, -kickStrength], relativeTo: nil)
            }
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
        
        // Handle logic for specific modes
        switch appModel.selectedMode {
        case .dynamic:
            break
        case .staticMode:
            // Freeze instantly
            box.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
        case .kinematic:
            // Stop falling, but spin to show it's active
            let spinSpeed: Float = 1.0
            box.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: [0, spinSpeed, 0]))
        }
    }
}
