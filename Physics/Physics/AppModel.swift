//
//  AppModel.swift
//  Physics
//
//  Created by Luca Langella 1 on 20/01/26.
//

import SwiftUI
import Observation
import RealityKit

// --- 1. Define the State Enum (This was missing) ---
enum ImmersiveSpaceState {
    case closed
    case inTransition
    case open
}

// --- 2. Define the Physics Mode Enum ---
enum PhysicsModeOption: String, CaseIterable, Identifiable {
    case dynamic = "Dynamic"
    case staticMode = "Static"
    case kinematic = "Kinematic"
    
    var id: String { self.rawValue }
    
    // Helper to convert to RealityKit type
    var rkMode: PhysicsBodyMode {
        switch self {
        case .dynamic: return .dynamic
        case .staticMode: return .static
        case .kinematic: return .kinematic
        }
    }
}

// --- 3. The Main App Model ---
@Observable
class AppModel {
    // --- System States ---
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var resetSignal = false
    var impulseSignal = false
    
    // --- Live Data ---
        var currentSpeed: Float = 0.0 // <--- ADD THIS
    
    // --- Physics Properties ---
    // 1. Body
    var selectedMode: PhysicsModeOption = .dynamic
    var mass: Float = 1.0 // in Kilograms
    
    // 2. Material
    var staticFriction: Float = 0.5   // Grip when standing still
    var dynamicFriction: Float = 0.5  // Grip when sliding
    var restitution: Float = 0.6      // Bounciness (0.0 to 1.0)
    
    // 3. Motion Damping (Air Resistance)
    var linearDamping: Float = 0.0    // Resistance to moving forward
    var angularDamping: Float = 0.0   // Resistance to spinning
    
    func triggerReset() { resetSignal.toggle() }
    func triggerImpulse() { impulseSignal.toggle() }
}
