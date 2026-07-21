//
//  SpatialPosition.swift
//  SpatialMixer
//
//  Created by Joaquín Chávez on 21-02-26.
//

import AVFoundation

/// Predefined positions in 3D audio space.
///
/// Coordinate system (OpenAL right-hand):
///   +X = right,  -X = left
///   +Y = up,     -Y = down
///   -Z = front,  +Z = behind
///
/// The listener is always at the origin (0, 0, 0).
enum SpatialPosition: String, CaseIterable, Identifiable {
    case center = "Center"
    case front  = "Front"
    case left   = "Left"
    case right  = "Right"
    case behind = "Behind"
    case above  = "Above"

    var id: String { rawValue }

    var point: AVAudio3DPoint {
        switch self {
        case .center: return AVAudio3DPoint(x:  0, y: 0, z: -1)
        case .front:  return AVAudio3DPoint(x:  0, y: 0, z: -2)
        case .left:   return AVAudio3DPoint(x: -2, y: 0, z:  0)
        case .right:  return AVAudio3DPoint(x:  2, y: 0, z:  0)
        case .behind: return AVAudio3DPoint(x:  0, y: 0, z:  2)
        case .above:  return AVAudio3DPoint(x:  0, y: 2, z: -1)
        }
    }

    /// Returns a point at exactly `distance` meters from the listener in this preset's direction.
    /// Normalizes the base vector first so the parameter maps directly to real distance units.
    func scaledPoint(by distance: Float) -> AVAudio3DPoint {
        let p = point
        let magnitude = sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
        guard magnitude > 0 else { return AVAudio3DPoint(x: 0, y: 0, z: -distance) }
        let scale = distance / magnitude
        return AVAudio3DPoint(x: p.x * scale, y: p.y * scale, z: p.z * scale)
    }

    /// Short label for compact preset buttons.
    var shortLabel: String {
        switch self {
        case .center: return "C"
        case .front:  return "F"
        case .left:   return "L"
        case .right:  return "R"
        case .behind: return "B"
        case .above:  return "↑"
        }
    }
}
