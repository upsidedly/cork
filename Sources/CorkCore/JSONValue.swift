import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let x = try? value.decode(Bool.self) { self = .bool(x) }
        else if let x = try? value.decode(Double.self) { self = .number(x) }
        else if let x = try? value.decode(String.self) { self = .string(x) }
        else if let x = try? value.decode([JSONValue].self) { self = .array(x) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let x): try value.encode(x)
        case .array(let x): try value.encode(x)
        case .string(let x): try value.encode(x)
        case .number(let x): try value.encode(x)
        case .bool(let x): try value.encode(x)
        case .null: try value.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue? { object?[key] }
    public var object: [String: JSONValue]? { if case .object(let x) = self { x } else { nil } }
    public var array: [JSONValue]? { if case .array(let x) = self { x } else { nil } }
    public var string: String? { if case .string(let x) = self { x } else { nil } }
    public var number: Double? { if case .number(let x) = self { x } else { nil } }
    public var bool: Bool? { if case .bool(let x) = self { x } else { nil } }

    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    public func data(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func toolResult(_ value: JSONValue) throws -> JSONValue {
        let text = String(decoding: try value.data(pretty: true), as: UTF8.self)
        return .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                        "isError": .bool(false)])
    }

    public static func toolError(_ message: String) -> JSONValue {
        .object(["content": .array([.object(["type": .string("text"), "text": .string(message)])]),
                 "isError": .bool(true)])
    }
}

public struct CorkError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public extension Dictionary where Key == String, Value == JSONValue {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key]?.string, !value.isEmpty else { throw CorkError("\(key) must be a nonempty string.") }
        return value
    }
    func optionalNumber(_ key: String, fallback: Double) throws -> Double {
        guard let value = self[key] else { return fallback }
        guard let number = value.number, number.isFinite else { throw CorkError("\(key) must be a finite number.") }
        return number
    }
    func identifiers(_ key: String = "ids") throws -> [UUID] {
        guard let values = self[key]?.array, !values.isEmpty, values.count <= 500 else { throw CorkError("\(key) must contain 1–500 item IDs.") }
        let result = try values.map { value -> UUID in
            guard let text = value.string, let id = UUID(uuidString: text) else { throw CorkError("Invalid item ID.") }
            return id
        }
        guard Set(result).count == result.count else { throw CorkError("Duplicate item IDs are not allowed.") }
        return result
    }
}
