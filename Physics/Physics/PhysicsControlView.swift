import SwiftUI

struct PhysicsControlView: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        NavigationStack {
            List {
                // --- Section 1: Telemetry ---
                Section("Telemetry") {
                    HStack {
                        Label("Current Speed", systemImage: "speedometer")
                        Spacer()
                        Text("\(appModel.currentSpeed, specifier: "%.2f") m/s")
                            .font(.monospacedDigit(.body)())
                            .foregroundStyle(.secondary)
                    }
                }

                // --- Section 2: Environment ---
                Section("Environment") {
                    VStack {
                        HStack {
                            Text("Gravity (Y-Axis)")
                            Spacer()
                            Text(String(format: "%.1f m/s²", appModel.gravity))
                                .foregroundStyle(.blue)
                        }
                        Slider(value: Bindable(appModel).gravity, in: -20.0...0.0)
                    }
                }

                // --- Section 3: Gesture ---
                Section("Interaction") {
                    Button("Respawn Box") { appModel.triggerReset() }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(appModel.isDragging ? "HOLDING" : "IDLE")
                            .font(.caption.bold())
                            .padding(6)
                            .background(appModel.isDragging ? Color.green : Color.gray.opacity(0.2))
                            .foregroundColor(appModel.isDragging ? .black : .primary)
                            .cornerRadius(8)
                    }
                    
                    // CHANGED: Toggle for throwing
                    Toggle("Enable Throwing", isOn: Bindable(appModel).isThrowingEnabled)
                    
                    if appModel.isThrowingEnabled {
                        VStack {
                            HStack {
                                Text("Throw Power")
                                Spacer()
                                Text(String(format: "x%.1f", appModel.throwStrength))
                                    .foregroundStyle(.orange)
                            }
                            Slider(value: Bindable(appModel).throwStrength, in: 0.5...5.0)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Last Throw Vector")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(appModel.lastThrowVector)
                                .font(.system(.caption, design: .monospaced))
                        }
                    } else {
                        Text("Object will drop vertically on release.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // --- Section 4: Body Properties ---
                Section("Body Properties") {
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
                    
                    VStack {
                        HStack { Text("Bounciness"); Spacer(); Text(String(format: "%.2f", appModel.restitution)) }
                        Slider(value: Bindable(appModel).restitution, in: 0.0...1.0)
                    }
                    
                    VStack {
                        HStack { Text("Friction"); Spacer(); Text(String(format: "%.2f", appModel.dynamicFriction)) }
                        Slider(value: Bindable(appModel).dynamicFriction, in: 0.0...1.0)
                    }
                    
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
