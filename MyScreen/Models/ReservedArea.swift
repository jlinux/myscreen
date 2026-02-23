import Foundation
import CoreGraphics

enum EdgePosition: String, Codable, CaseIterable {
    case left
    case right
    case top
    case bottom
}

enum SizeSpec: Codable, Equatable {
    case pixels(CGFloat)
    case percentage(CGFloat)

    func resolve(for totalLength: CGFloat) -> CGFloat {
        switch self {
        case .pixels(let px):
            return min(px, totalLength)
        case .percentage(let pct):
            return totalLength * min(max(pct, 0), 1)
        }
    }

    // Custom Codable
    enum CodingKeys: String, CodingKey {
        case type, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pixels(let v):
            try container.encode("pixels", forKey: .type)
            try container.encode(v, forKey: .value)
        case .percentage(let v):
            try container.encode("percentage", forKey: .type)
            try container.encode(v, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(CGFloat.self, forKey: .value)
        switch type {
        case "pixels":
            self = .pixels(value)
        case "percentage":
            self = .percentage(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown SizeSpec type: \(type)")
        }
    }
}

struct ReservedArea: Codable, Equatable {
    var edge: EdgePosition
    var size: SizeSpec

    static let defaultArea = ReservedArea(edge: .right, size: .percentage(0.3))
}
