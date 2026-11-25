import Foundation

/// Arithmetic with + - * / % ^ and parentheses.
public enum Calculator {
  /// Nil unless the whole input is one valid expression containing a binary operator,
  /// so plain numbers and app names never show a result.
  public static func evaluate(_ input: String) -> Double? {
    // Japanese IMEs often type full-width digits and operators.
    let halfWidth = input.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? input
    var parser = Parser(Array(halfWidth.filter { !$0.isWhitespace }))
    guard let value = parser.expression(), parser.isAtEnd, parser.sawBinaryOperator,
      value.isFinite
    else { return nil }
    return value
  }

  public static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...10)).grouping(.never))
  }
}

private struct Parser {
  let characters: [Character]
  var position = 0
  var sawBinaryOperator = false

  init(_ characters: [Character]) { self.characters = characters }

  var isAtEnd: Bool { position == characters.count }

  // expression := term (("+" | "-") term)*
  mutating func expression() -> Double? {
    guard var value = term() else { return nil }
    while let op = consume(oneOf: "+-") {
      guard let rhs = term() else { return nil }
      value = op == "+" ? value + rhs : value - rhs
    }
    return value
  }

  // term := unary (("*" | "/" | "%") unary)*
  mutating func term() -> Double? {
    guard var value = unary() else { return nil }
    while let op = consume(oneOf: "*/%×÷") {
      guard let rhs = unary() else { return nil }
      switch op {
      case "*", "×": value *= rhs
      case "/", "÷": value /= rhs
      default: value = value.truncatingRemainder(dividingBy: rhs)
      }
    }
    return value
  }

  // unary := ("-" | "+") unary | power, so -2^2 is -(2^2).
  mutating func unary() -> Double? {
    if let sign = consume(oneOf: "+-") {
      return unary().map { sign == "-" ? -$0 : $0 }
    }
    return power()
  }

  // power := primary ("^" unary)?, right-associative.
  mutating func power() -> Double? {
    guard let base = primary() else { return nil }
    guard consume(oneOf: "^") != nil else { return base }
    return unary().map { Foundation.pow(base, $0) }
  }

  // primary := number | "(" expression ")"
  mutating func primary() -> Double? {
    if consume(oneOf: "(") != nil {
      guard let value = expression(), consume(oneOf: ")") != nil else { return nil }
      return value
    }
    let start = position
    while position < characters.count, characters[position].isASCII,
      characters[position].isNumber || characters[position] == "."
    {
      position += 1
    }
    return Double(String(characters[start..<position]))
  }

  private mutating func consume(oneOf candidates: String) -> Character? {
    guard position < characters.count, candidates.contains(characters[position]) else {
      return nil
    }
    let character = characters[position]
    // A sign right after an operator or "(" is unary; everything else here is binary.
    if position > 0, !"+-*/%^(×÷".contains(characters[position - 1]), "+-*/%^×÷".contains(character)
    {
      sawBinaryOperator = true
    }
    position += 1
    return character
  }
}
