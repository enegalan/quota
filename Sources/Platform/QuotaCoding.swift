import Foundation

extension JSONEncoder {
    /// The one encoder used for everything that reaches disk.
    ///
    /// Dates are encoded as seconds since the reference date rather than the
    /// default deferred-to-date string, because a snapshot's timestamp has to
    /// round trip exactly: a reading's age decides whether the interface calls
    /// it stale, and a timestamp that loses precision is a reading that changes
    /// age every time it is loaded.
    static let quota: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    /// The decoder matching `JSONEncoder.quota`.
    static let quota: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
