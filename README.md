# NewtonLab
![NEWTONLAB-ezgif com-optimize](https://github.com/user-attachments/assets/f9573e8f-355b-4ed7-a193-b66abe096243)

NewtonLab is a **VisionOS** application built with **SwiftUI** and **RealityKit**. It serves as an interactive physics laboratory where developers can experiment with various physical properties, simulate real-world behaviors in an immersive environment, and determine the optimal values for their own applications.

The primary goal of this tool is to help you feel the physics (mass, friction, restitution, air density) and visualize the results, so you can take those precise values and use them in your own RealityKit projects.

> **📢 Coming Soon:** A new article and video tutorial covering the latest implementations (Custom Models, Advanced Aerodynamics, and Wall Configuration) will be released shortly. Stay tuned!

[![Read on Medium](https://img.shields.io/badge/Medium-Story-black?logo=medium)](https://medium.com/@langellaluca00/stop-guessing-a-real-time-physics-lab-for-realitykit-developers-bf5e4d1b59c5)

## 🚀 New Features

* **Extended Object Support:**
    * **Primitives:** Box, Sphere, Cylinder, and **Cone**.
    * **Import Custom Models:** Import your own **.usdz** files to test physics on custom assets.
* **Tools:**
    * **Selection & Deletion:** Select specific objects to view/tweak their properties or delete unwanted entities from the scene.
    * **Velocity Monitoring:** Real-time speed feedback.

## 🌟 Core Features

* **Immersive Physics Sandbox:** Run simulations in a fully immersive 3D space with studio-quality lighting.
* **Mixed Reality & Virtual Modes:**
    * **Mixed:** Interact with your real-world surroundings using Scene Reconstruction (LiDAR) and Hand Tracking.
    * **Virtual:** A controlled environment with generated floors.
* **Real-time Tuning:** Instantly adjust physics properties via the UI:
    * **Mass**
    * **Restitution** (Bounciness)
    * **Static & Dynamic Friction**
* **Interaction:**
    * **Drag & Drop:** Pick up and throw objects with natural gestures.
    * **Magnify & Rotate:** Resize and rotate objects with two-handed gestures.
    * **Path Tracing:** Visualize the trajectory of moving objects in real-time.
* **Advanced Physics Tuning:**
    * **Gravity Control:** Adjust the gravitational force (e.g., simulate Moon or Mars gravity).
    * **Aerodynamics:** Toggle advanced drag calculations based on **Air Density** and object cross-sectional area.
* **Environment Control:**
    * **Wall Configuration:** Toggle boundary walls and dynamically adjust their height.
    * **Ramp Generator:** Fully adjustable ramps (Angle, Length, Width, and Rotation) to test sliding.

## 🛠 Usage for Developers

This app is designed to be a utility for your workflow.

1.  **Play & Tune:**
    * Launch the app on Apple Vision Pro (or Simulator).
    * Enter the Immersive Space (Virtual or Mixed).
    * Use the control panel to tweak physics parameters. Try increasing `Air Density` to see how it affects falling objects, or adjust `Gravity` to see how objects float.
    * Spawn primitives or click **Import** to load your own USDZ models.

2.  **Capture the Values:**
    * Once you find the behavior you like (e.g., a specific "slide" feel on a ramp), look at the values set in the UI.
    * **Pro Tip:** Tap the **"Print Values"** button in the bottom toolbar. This will log the exact configuration to the Xcode Console, so you can just copy-paste the numbers.

3.  **Implement in Your App:**
    Use the values you found (or copied from the console) in your own code:

    ```swift
    // Example: Applying values found in PhysicsLabVisionOS
    let material = PhysicsMaterialResource.generate(
        staticFriction: 0.8,  // Value from Lab
        dynamicFriction: 0.6, // Value from Lab
        restitution: 0.5      // Value from Lab
    )

    var physicsBody = PhysicsBodyComponent(
        massProperties: .init(mass: 2.5), // Value from Lab
        material: material,
        mode: .dynamic
    )
    
    // If using Advanced Drag concepts from the lab:
    physicsBody.linearDamping = 0.1 
    
    entity.components.set(physicsBody)
    ```

## 🏗 Project Structure

* **`PhysicsSceneManager.swift`**: The core logic engine. It handles RealityKit entities, physics updates, advanced drag calculations, ARKit scene reconstruction, and hand tracking.
* **`ImmersiveView.swift`**: The main SwiftUI view for the immersive space. It bridges SwiftUI state (sliders/buttons) to the `PhysicsSceneManager`.
* **`PhysicsControlView.swift`**: The dashboard UI containing sliders for Mass, Gravity, Friction, and Aerodynamics, as well as file importing and environment toggles.
* **`AppViewModel.swift`**: Holds the state of the simulation (current physics values, selected modes, UI toggles, selection state).

## ⚙️ Requirements

* **Xcode 15.0+**
* **visionOS 1.0+**
* **Apple Vision Pro** (for full AR/Hand Tracking features) or **visionOS Simulator**.

## 🤝 Contributing

Feel free to fork this project and add more complex shapes, constraints, or new physics visualizers!
