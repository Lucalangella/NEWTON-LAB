import Foundation

enum ShapeOption: String, CaseIterable, Identifiable {
    case box = "Cube"
    case sphere = "Sphere"
    case cylinder = "Cylinder"
    case cone = "Cone"
    
    var id: String { self.rawValue }
}
