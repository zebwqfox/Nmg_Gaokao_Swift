import Foundation

enum JSONValue: Decodable, Hashable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
      var object: [String: JSONValue] = [:]
      for key in container.allKeys {
        object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
      }
      self = .object(object)
      return
    }

    if var container = try? decoder.unkeyedContainer() {
      var array: [JSONValue] = []
      while !container.isAtEnd {
        array.append(try container.decode(JSONValue.self))
      }
      self = .array(array)
      return
    }

    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else {
      self = .string(try container.decode(String.self))
    }
  }

  var foundationObject: Any {
    switch self {
    case .string(let value):
      value
    case .number(let value):
      value
    case .bool(let value):
      value
    case .object(let value):
      value.mapValues { item in
        item.foundationObject
      }
    case .array(let value):
      value.map { item in
        item.foundationObject
      }
    case .null:
      NSNull()
    }
  }

  var jsonString: String? {
    guard JSONSerialization.isValidJSONObject(foundationObject),
          let data = try? JSONSerialization.data(withJSONObject: foundationObject, options: [])
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}
