import SwiftUI

struct PhysicsControlView: View {
    @Environment(AppViewModel.self) var appViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Telemetry") {
                    HStack {
                        Label("Current Speed", systemImage: "speedometer")
                        Spacer()
                        Text("\(appViewModel.currentSpeed, specifier: "%.2f") m/s")
                            .font(.monospacedDigit(.body)())
                            .foregroundStyle(.secondary)
                    }
                }
                
                

                Section("Environment") {
                    VStack {
                        HStack {
                            Text("Gravity (Y-Axis)")
                            Spacer()
                            Text(String(format: "%.1f m/s²", appViewModel.gravity))
                                .foregroundStyle(.blue)
                        }
                        Slider(value: Bindable(appViewModel).gravity, in: -20.0...0.0)
                    }
                    
                    Toggle("Show Walls", isOn: Bindable(appViewModel).showWalls)
                    
                    if appViewModel.showWalls {
                        VStack {
                            HStack {
                                Text("Wall Height")
                                Spacer()
                                Text(String(format: "%.2f m", appViewModel.wallHeight))
                                    .foregroundStyle(.blue)
                            }
                            Slider(value: Bindable(appViewModel).wallHeight, in: 0.1...2.0)
                        }
                    }
                }
                
                // Place this inside the List, perhaps after "Environment"
                Section("Inclined Plane (Ramp)") {
                    Toggle("Enable Ramp", isOn: Bindable(appViewModel).showRamp)
                    
                    if appViewModel.showRamp {
                        VStack {
                            HStack {
                                Text("Angle")
                                Spacer()
                                Text("\(appViewModel.rampAngle, specifier: "%.0f")°")
                                    .foregroundStyle(.blue)
                            }
                            // 0 to 60 degrees is usually enough for friction tests
                            Slider(value: Bindable(appViewModel).rampAngle, in: 0.0...60.0)
                        }
                        
                        VStack {
                            HStack {
                                Text("Length")
                                Spacer()
                                Text(String(format: "%.1f m", appViewModel.rampLength))
                                    .foregroundStyle(.blue)
                            }
                            Slider(value: Bindable(appViewModel).rampLength, in: 0.5...5.0)
                        }
                        
                        VStack {
                            HStack {
                                Text("Width")
                                Spacer()
                                Text(String(format: "%.1f m", appViewModel.rampWidth))
                                    .foregroundStyle(.blue)
                            }
                            Slider(value: Bindable(appViewModel).rampWidth, in: 0.5...5.0)
                        }
                        
                        VStack {
                            HStack {
                                Text("Rotation")
                                Spacer()
                                Text("\(appViewModel.rampRotation, specifier: "%.0f")°")
                                    .foregroundStyle(.blue)
                            }
                            Slider(value: Bindable(appViewModel).rampRotation, in: 0.0...360.0)
                        }
                    }
                }

                Section("Interaction") {
                    Button("Respawn Object") { appViewModel.triggerReset() }
                    
                    Toggle("Show Motion Path (Plot)", isOn: Bindable(appViewModel).showPath)
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(appViewModel.isDragging ? "HOLDING" : "IDLE")
                            .font(.caption.bold())
                            .padding(6)
                            .background(appViewModel.isDragging ? Color.green : Color.gray.opacity(0.2))
                            .foregroundColor(appViewModel.isDragging ? .black : .primary)
                            .cornerRadius(8)
                    }
                    
                    Text("Object will drop vertically on release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Body Properties") {
                    // NEW: Shape Picker
                    Picker("Shape", selection: Bindable(appViewModel).selectedShape) {
                        ForEach(ShapeOption.allCases) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack {
                        HStack { Text("Mass"); Spacer(); Text("\(appViewModel.mass, specifier: "%.1f") kg") }
                        Slider(value: Bindable(appViewModel).mass, in: 0.1...50.0)
                    }
                    
                    VStack {
                        HStack { Text("Bounciness"); Spacer(); Text(String(format: "%.2f", appViewModel.restitution)) }
                        Slider(value: Bindable(appViewModel).restitution, in: 0.0...1.0)
                    }
                    
                    VStack {
                                        HStack {
                                            Text("Static Friction")
                                            Spacer()
                                            Text(String(format: "%.2f", appViewModel.staticFriction))
                                        }
                                        Slider(value: Bindable(appViewModel).staticFriction, in: 0.0...1.0)
                                    }
                                    
                         
                                    VStack {
                                        HStack {
                                            Text("Dynamic Friction")
                                            Spacer()
                                            Text(String(format: "%.2f", appViewModel.dynamicFriction))
                                        }
                                        Slider(value: Bindable(appViewModel).dynamicFriction, in: 0.0...1.0)
                                    }
                    
                    VStack(alignment: .leading) {
                        Toggle("Advanced Aerodynamics", isOn: Bindable(appViewModel).useAdvancedDrag)
                        
                        if appViewModel.useAdvancedDrag {
                            HStack {
                                Text("Air Density")
                                Spacer()
                                Text(String(format: "%.3f kg/m³", appViewModel.airDensity))
                            }
                            Slider(value: Bindable(appViewModel).airDensity, in: 0.0...5.0)
                            
                            // Info display
                            Grid(alignment: .leading, verticalSpacing: 5) {
                                GridRow {
                                    Text("Drag Coeff (Cd):")
                                    Text(String(format: "%.2f", appViewModel.dragCoefficient))
                                }
                                GridRow {
                                    Text("Area (A):")
                                    Text(String(format: "%.3f m²", appViewModel.crossSectionalArea))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            
                        } else {
                            HStack { Text("Air Resistance (Linear)"); Spacer(); Text(String(format: "%.2f", appViewModel.linearDamping)) }
                            Slider(value: Bindable(appViewModel).linearDamping, in: 0.0...5.0)
                        }
                    }
                }
            }
            .navigationTitle("Physics Lab")
        }
    }
}

struct DraggableMenuWrapper: View {
    // Track the position of the menu
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    var body: some View {
        PhysicsControlView()
            .glassBackgroundEffect()
            // Apply the drag offset here
            .offset(x: offset.width, y: offset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Update position while dragging
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        // Save the new position when let go
                        lastOffset = offset
                    }
            )
            // Push it back in Z-space slightly so it doesn't clip your nose
            .transform3DEffect(.init(translation: .init(x: 0, y: 0, z: -400)))
    }
}

#Preview("Full App Experience", immersionStyle: .mixed) {
    ZStack { // 1. Use ZStack to layer them on top of each other
        ImmersiveView()
        
        DraggableMenuWrapper()
        // 2. Set the Size FIRST
            .frame(width: 500, height: 1500)
        
        
        // 4. Move it in 3D Space
        // Note: Z = -500 puts it roughly arm's length away.
        // -2500 is extremely far away and might make it invisible.
            .transform3DEffect(.init(translation: .init(x: 1000, y: -1000, z: -2500)))
    }
    .environment(AppViewModel())
}