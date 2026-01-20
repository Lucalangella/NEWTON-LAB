//
//  hds.swift
//  Physics
//
//  Created by Luca Langella 1 on 20/01/26.
//

import SwiftUI

struct PhysicsControlView: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        NavigationStack {
            List {
                // --- Section 1: Live Data (Simple Text) ---
                Section("Telemetry") {
                    HStack {
                        Label("Current Speed", systemImage: "speedometer")
                        Spacer()
                        // Monospaced font keeps the numbers from "jittering"
                        Text("\(appModel.currentSpeed, specifier: "%.2f") m/s")
                            .font(.monospacedDigit(.body)())
                            .foregroundStyle(.secondary)
                    }
                }

                // --- Section 2: Actions ---
                Section("Actions") {
                    Button("Respawn Box") { appModel.triggerReset() }
                    Button("Kick Box (Apply Impulse)") { appModel.triggerImpulse() }
                }
                
                // --- Section 3: Behavior ---
                Section("Body Behavior") {
                    Picker("Mode", selection: Bindable(appModel).selectedMode) {
                        ForEach(PhysicsModeOption.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack {
                        HStack { Text("Mass"); Spacer(); Text("\(appModel.mass, specifier: "%.1f") kg") }
                        Slider(value: Bindable(appModel).mass, in: 0.1...50.0)
                    }
                }
                
                // --- Section 4: Material ---
                Section("Material (Surface)") {
                    VStack {
                        HStack { Text("Bounciness"); Spacer(); Text(String(format: "%.2f", appModel.restitution)) }
                        Slider(value: Bindable(appModel).restitution, in: 0.0...1.0)
                    }
                    
                    VStack {
                        HStack { Text("Sliding Friction"); Spacer(); Text(String(format: "%.2f", appModel.dynamicFriction)) }
                        Slider(value: Bindable(appModel).dynamicFriction, in: 0.0...1.0)
                    }
                    
                    VStack {
                        HStack { Text("Static Friction"); Spacer(); Text(String(format: "%.2f", appModel.staticFriction)) }
                        Slider(value: Bindable(appModel).staticFriction, in: 0.0...1.0)
                    }
                }
                
                // --- Section 5: Damping ---
                Section("Damping (Resistance)") {
                    VStack {
                        HStack { Text("Air Resistance"); Spacer(); Text(String(format: "%.2f", appModel.linearDamping)) }
                        Slider(value: Bindable(appModel).linearDamping, in: 0.0...5.0)
                    }
                }
            }
            .navigationTitle("Physics Lab")
        }
        .frame(width: 400, height: 1100)
    }
}

#Preview(windowStyle: .volumetric) {
    PhysicsControlView()
        .environment(AppModel())
}
