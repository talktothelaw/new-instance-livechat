import Foundation

public enum ElicitationValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ElicitationValue])
    case array([ElicitationValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([ElicitationValue].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: ElicitationValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var foundationValue: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .object(let v): return v.mapValues(\.foundationValue)
        case .array(let v): return v.map(\.foundationValue)
        case .null: return NSNull()
        }
    }

    var text: String? {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        case .bool(let v): return v ? "true" : "false"
        case .object, .array, .null: return nil
        }
    }
}
