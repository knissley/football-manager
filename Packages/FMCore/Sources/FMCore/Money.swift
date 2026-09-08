/// An amount of money, in whole dollars.
///
/// Integer-backed rather than floating point. Cap arithmetic is checked by
/// players against numbers they can add up themselves, and a contract that
/// reconciles to within a rounding error is a contract that looks broken.
/// `Int64` in dollars covers the largest plausible figure by many orders of
/// magnitude, and can go negative because cap space routinely does.
public struct Money: Sendable, Hashable, Comparable, Codable {

    public var dollars: Int64

    public init(dollars: Int64) {
        self.dollars = dollars
    }

    public static let zero = Money(dollars: 0)

    /// Convenience for readable test and fixture values: `.millions(12.5)`.
    ///
    /// Rounds to the nearest dollar. Not for use inside cap arithmetic, which
    /// stays in integers throughout.
    public static func millions(_ value: Double) -> Money {
        Money(dollars: Rounding.toNearest(value * 1_000_000))
    }

    public var isNegative: Bool { dollars < 0 }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.dollars < rhs.dollars }
    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(dollars: lhs.dollars + rhs.dollars)
    }
    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(dollars: lhs.dollars - rhs.dollars)
    }
    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }
    public static prefix func - (value: Money) -> Money { Money(dollars: -value.dollars) }

    public static func * (lhs: Money, rhs: Int64) -> Money { Money(dollars: lhs.dollars * rhs) }

    /// Scale by a fraction, rounding to the nearest dollar.
    ///
    /// Used for percentage rules such as the franchise tag's 120% floor. The
    /// rounding is explicit so the result is reproducible rather than
    /// dependent on where a `Double` happened to land.
    public func scaled(by factor: Double) -> Money {
        Money(dollars: Rounding.toNearest(Double(dollars) * factor))
    }
}

extension Money: AdditiveArithmetic {}

extension Money: CustomStringConvertible {
    /// Formatted with integer arithmetic rather than `String(format:)`, because
    /// `FMCore` imports no frameworks at all — not even Foundation.
    public var description: String {
        let sign = dollars < 0 ? "-" : ""
        let magnitude = dollars.magnitude

        guard magnitude >= 1_000_000 else { return "\(sign)$\(magnitude)" }

        let millions = magnitude / 1_000_000
        let thousandths = (magnitude % 1_000_000) / 1_000
        var fraction = "\(thousandths)"
        while fraction.count < 3 { fraction = "0" + fraction }
        return "\(sign)$\(millions).\(fraction)M"
    }
}

extension Sequence where Element == Money {
    public func total() -> Money {
        reduce(Money.zero, +)
    }
}
