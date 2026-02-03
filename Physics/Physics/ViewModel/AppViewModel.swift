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
    var showSun: Bool = false
    var sunIntensity: Float = 800.0
    var environmentOpacity: Float = 0.5
    var spawnSignal: ShapeOption? = nil
    var spawnCustomModelSignal: URL? = nil
    var showFileImporter: Bool = false
    
    // --- Selection Mode ---
    var isSelectionMode: Bool = false {
        didSet { if isSelectionMode { isDeleteMode = false } }
    }
    var isDeleteMode: Bool = false {
        didSet { if isDeleteMode { isSelectionMode = false } }
    }
    var selectedEntityIDs: Set<UInt64> = []
    
    func toggleSelection(_ id: UInt64) {
        if selectedEntityIDs.contains(id) {
            selectedEntityIDs.remove(id)
        } else {
            selectedEntityIDs.insert(id)
        }
    }
    
    func clearSelection() {
        selectedEntityIDs.removeAll()
    }
    
    // --- Environment ---
    var selectedEnvironment: PhysicsEnvironmentMode = .virtual
    var showWalls: Bool = false
    var wallHeight: Float = 0.5
    
    // --- Live Data ---
    var currentSpeed: Float = 0.0
    
    // --- Interaction ---
    var isDragging: Bool = false
    var showPath: Bool = false
    
    // --- Physics Properties ---
    var selectedShape: ShapeOption = .box // Default
    var selectedMode: PhysicsModeOption = .dynamic
    
    var mass: Float = 1.0
    var gravity: Float = -9.81
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
        case .cone: return 0.50 // Drag for a cone point-forward
        }
    }
    
    // Computed helper for Area (approx cross section)
    var crossSectionalArea: Float {
        switch selectedShape {
        case .box: return 0.3 * 0.3 // 0.09 m^2
        case .sphere: return Float.pi * pow(0.15, 2) // ~0.07 m^2
        case .cylinder: return 0.3 * 0.15 * 2 // Approx projected area (h*d) = 0.09 m^2
        case .cone: return Float.pi * pow(0.15, 2) // Base area
        }
    }
    
    func triggerReset() { resetSignal.toggle() }
    
    // NEW: Ramp Control
    var showRamp: Bool = false
    var rampAngle: Float = 10.0 // Degrees
    var rampLength: Float = 4.0 // Meters
    var rampWidth: Float = 0.5 // Meters
    var rampRotation: Float = 180.0 // Degrees (Yaw)
    
    // MARK: - Developer Tools
    func printConfiguration() {
        print("---------------------------------")
        print("PHYSICS SETTINGS:")
        print("Mass: \(mass)")
        print("Gravity: \(gravity)")
        print("Static Friction: \(staticFriction)")
        print("Dynamic Friction: \(dynamicFriction)")
        print("Restitution: \(restitution)")
        print("Linear Damping: \(linearDamping)")
        print("Air Density: \(airDensity)")
        print("Shape: \(selectedShape.rawValue)")
        print("---------------------------------")
    }
}