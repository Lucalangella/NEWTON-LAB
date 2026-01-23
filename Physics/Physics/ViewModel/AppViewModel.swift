//
//  AppViewModel.swift
//  Physics
//
//  Created by Luca Langella 1 on 20/01/26.
//

import SwiftUI
import Observation
import RealityKit

@Observable
class AppViewModel {
    // --- System States ---
    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var resetSignal = false
    
    // --- Environment ---
    var selectedEnvironment: PhysicsEnvironmentMode = .virtual
    
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
    
    // NEW: Advanced Aerodynamics
    var useAdvancedDrag: Bool = false
    var airDensity: Float = 1.225 // kg/m^3 (Standard Sea Level)
    
    // Computed helper for Drag Coefficient based on shape
    var dragCoefficient: Float {
        switch selectedShape {
        case .box: return 1.05 // Cube flat face
        case .sphere: return 0.47
        case .cylinder: return 0.82 // Approx for long cylinder side-on
        }
    }
    
    // Computed helper for Area (approx cross section)
    var crossSectionalArea: Float {
        switch selectedShape {
        case .box: return 0.3 * 0.3 // 0.09 m^2
        case .sphere: return Float.pi * pow(0.15, 2) // ~0.07 m^2
        case .cylinder: return 0.3 * 0.15 * 2 // Approx projected area (h*d) = 0.09 m^2
        }
    }
    
    func triggerReset() { resetSignal.toggle() }
    
    // NEW: Ramp Control
    var showRamp: Bool = true
    var rampAngle: Float = 10.0 // Degrees
    var rampLength: Float = 4.0 // Meters
    var rampWidth: Float = 0.5 // Meters
    var rampRotation: Float = 0.0 // Degrees (Yaw)
}
