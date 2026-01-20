import SwiftUI

struct PhysicsControlView: View {
    @Environment(AppModel.self) var appModel

    var body: some View {
        NavigationStack {
            List {
                Section("Telemetry") {
                    HStack {
                        Label("Current Speed", systemImage: "speedometer")
                        Spacer()
                        Text("\(appModel.currentSpeed, specifier: "%.2f") m/s")
                            .font(.monospacedDigit(.body)())
                            .foregroundStyle(.secondary)
                    }
                }
                
                

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
                
                // Place this inside the List, perhaps after "Environment"
                Section("Inclined Plane (Ramp)") {
                    Toggle("Enable Ramp", isOn: Bindable(appModel).showRamp)
                    
                    if appModel.showRamp {
                        VStack {
                            HStack {
                                Text("Angle")
                                Spacer()
                                Text("\(appModel.rampAngle, specifier: "%.0f")°")
                                    .foregroundStyle(.blue)
                            }
                            // 0 to 60 degrees is usually enough for friction tests
                            Slider(value: Bindable(appModel).rampAngle, in: 0.0...60.0)
                        }
                    }
                }

                Section("Interaction") {
                    Button("Respawn Object") { appModel.triggerReset() }
                    
                    Toggle("Show Motion Path (Plot)", isOn: Bindable(appModel).showPath)
                    
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
                    
                    Text("Object will drop vertically on release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Body Properties") {
                    // NEW: Shape Picker
                    Picker("Shape", selection: Bindable(appModel).selectedShape) {
                        ForEach(ShapeOption.allCases) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    
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
                                        HStack {
                                            Text("Static Friction")
                                            Spacer()
                                            Text(String(format: "%.2f", appModel.staticFriction))
                                        }
                                        Slider(value: Bindable(appModel).staticFriction, in: 0.0...1.0)
                                    }
                                    
                         
                                    VStack {
                                        HStack {
                                            Text("Dynamic Friction")
                                            Spacer()
                                            Text(String(format: "%.2f", appModel.dynamicFriction))
                                        }
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
