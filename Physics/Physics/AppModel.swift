//
//  AppModel.swift
//  Physics
//
//  Created by Luca Langella 1 on 20/01/26.
//

import SwiftUI
import Observation
import RealityKit

enum ImmersiveSpaceState {
    case closed
    case inTransition
    case open
}

// NEW: Shape Options
enum ShapeOption: String, CaseIterable, Identifiable {
    case box = "Cube"
    case sphere = "Sphere"
    case cylinder = "Cylinder"
    
    var id: String { self.rawValue }
}

enum PhysicsModeOption: String, CaseIterable, Identifiable {
    case dynamic = "Dynamic"
    case staticMode = "Static"
    case kinematic = "Kinematic"
    
    var id: String { self.rawValue }
    
    var rkMode: PhysicsBodyMode {
        switch self {
        case .dynamic: return .dynamic
        case .staticMode: return .static
        case .kinematic: return .kinematic
        }
    }
}

@Observable
class AppModel {
    // --- System States ---
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var resetSignal = false
    
    // --- Live Data ---
    var currentSpeed: Float = 0.0
    
    // --- Interaction ---
    var isDragging: Bool = false
    var showPath: Bool = false
    
    // --- Physics Properties ---
    var selectedShape: ShapeOption = .box // Default
    var selectedMode: PhysicsModeOption = .dynamic
    
    var mass: Float = 1.0
    var gravity: Float = -9.8
    var staticFriction: Float = 0.5
    var dynamicFriction: Float = 0.5
    var restitution: Float = 0.6
    var linearDamping: Float = 0.1
    
    func triggerReset() { resetSignal.toggle() }
    
    // NEW: Ramp Control
        var showRamp: Bool = false
        var rampAngle: Float = 0.0 // Degrees
    
    
}
