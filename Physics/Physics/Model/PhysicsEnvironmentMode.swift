import Foundation

enum PhysicsEnvironmentMode: String, CaseIterable, Identifiable {
    case virtual = "Virtual Studio"
    case mixed = "Real World"
    
    var id: String { self.rawValue }
}
