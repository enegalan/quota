import Foundation

/// Failures raised while validating domain values.
///
/// Domain initialisers throw rather than clamping. A provider plugin is
/// out-of-process code, so the core cannot assume a reported percentage is
/// well formed; silently coercing an out-of-range figure into range would turn a
/// plugin bug into a wrong number the user acts on.
public enum QuotaDomainError: Error, Equatable, Sendable {
    /// A usage percentage was outside 0...100, or was not a finite number.
    case invalidPercentage(Double)

    /// A date component was outside the range its calendar permits.
    case invalidDate(year: Int, month: Int, day: Int)

    /// A period ended before it began.
    case invalidPeriod(start: Date, end: Date)

    /// A snapshot carried no buckets. A snapshot with nothing to report is not
    /// a valid measurement.
    case emptyBuckets

    /// Two buckets in one snapshot shared an identifier, so a quota could not
    /// be matched to one of them unambiguously.
    case duplicateBucketID(String)

    /// A negative value where a non-negative one is required.
    case negativeValue(String)

    /// An identifier was empty, or contained whitespace.
    case invalidIdentifier(String)

    /// A weekday weight was negative, out of the representable range, or every
    /// weight was zero, which would leave a weekly policy with nothing to
    /// divide.
    case invalidWeights

    /// A custom policy assigned a negative or non-finite percentage to a day.
    case invalidAssignment(date: String, percentage: Double)
}

extension QuotaDomainError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidPercentage(let value):
            "usage percentage \(value) is outside 0...100"
        case .invalidDate(let year, let month, let day):
            "\(year)-\(month)-\(day) is not a valid calendar date"
        case .invalidPeriod(let start, let end):
            "period end \(end) precedes period start \(start)"
        case .emptyBuckets:
            "a usage snapshot must carry at least one bucket"
        case .duplicateBucketID(let id):
            "duplicate bucket identifier '\(id)'"
        case .negativeValue(let label):
            "\(label) must not be negative"
        case .invalidIdentifier(let value):
            "'\(value)' is not a valid identifier"
        case .invalidWeights:
            "weekday weights must be non-negative, in range, and not all zero"
        case .invalidAssignment(let date, let percentage):
            "custom allocation for \(date) is not a valid percentage: \(percentage)"
        }
    }
}
