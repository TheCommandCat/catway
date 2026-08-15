import CoreGraphics
import Foundation

struct RawSpace: Decodable, Equatable, Sendable {
    let index: Int
    let label: String
    let windows: [Int]
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case index
        case label
        case windows
        case hasFocus = "has-focus"
    }
}

struct RawWindow: Decodable, Equatable, Sendable {
    let app: String
    let space: Int
}

struct WorkspaceModel: Identifiable, Encodable, Equatable, Sendable {
    let index: Int
    let label: String
    let isFocused: Bool
    let windowCount: Int
    let apps: [String]

    var id: Int { index }
    var isOccupied: Bool { windowCount > 0 }

    var displayLabel: String {
        if label.count == 2, label.first == "N", let digit = label.last, digit.isNumber {
            return String(digit)
        }
        return label.isEmpty ? String(index) : label
    }
}

enum WorkspaceCatalog {
    static func make(spaces: [RawSpace], windows: [RawWindow], occupiedOnly: Bool = true) -> [WorkspaceModel] {
        let appsBySpace = Dictionary(grouping: windows, by: \.space)
        let models = spaces.map { space in
            let apps = Array(Set((appsBySpace[space.index] ?? []).map(\.app))).sorted()
            return WorkspaceModel(
                index: space.index,
                label: space.label,
                isFocused: space.hasFocus,
                windowCount: space.windows.count,
                apps: apps
            )
        }
        return occupiedOnly ? models.filter(\.isOccupied) : models
    }
}

enum RadialLayout {
    static let stayRadius: CGFloat = 42
    static let activationDistance: CGFloat = 18

    static func angle(for offset: Int, count: Int) -> CGFloat {
        -.pi / 2 + (2 * .pi * CGFloat(offset) / CGFloat(max(count, 1)))
    }

    static func nodeSize(for count: Int) -> CGFloat {
        count > 12 ? 72 : (count > 9 ? 82 : (count > 6 ? 94 : 112))
    }

    static func nearestIndex(
        pointer: CGPoint,
        gestureOrigin: CGPoint,
        visualCenter: CGPoint,
        count: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        if hypot(pointer.x - visualCenter.x, pointer.y - visualCenter.y) <= stayRadius {
            return nil
        }

        let dx = pointer.x - gestureOrigin.x
        let dy = pointer.y - gestureOrigin.y
        guard hypot(dx, dy) > activationDistance else { return nil }

        let pointerAngle = atan2(dy, dx)
        return (0 ..< count).min { lhs, rhs in
            angularDistance(pointerAngle, angle(for: lhs, count: count))
                < angularDistance(pointerAngle, angle(for: rhs, count: count))
        }
    }

    private static func angularDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 2 * .pi)
        return min(difference, 2 * .pi - difference)
    }
}
