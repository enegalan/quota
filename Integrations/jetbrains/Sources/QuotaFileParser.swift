import Foundation
import ProviderSupport

#if canImport(FoundationXML)
import FoundationXML
#endif

/// Snapshot parsed from `AIAssistantQuotaManager2.xml`.
struct QuotaSnapshot: Equatable, Sendable {
    let used: Double
    let maximum: Double
    let available: Double
    let until: Date?
    let refillNext: Date?
    let refillDuration: String?
    let topUpUsed: Double?
    let topUpMaximum: Double?
    let topUpAvailable: Double?

    var usedPercent: Double {
        guard maximum > 0 else { return 0 }
        return (used / maximum) * Percentage.scale
    }
}

/// Reading the IDE's HTML-encoded JSON attributes out of the quota XML.
enum QuotaFileParser {
    static func parse(fileAt url: URL) throws -> QuotaSnapshot {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw JetBrainsProviderError.unreadableQuotaFile
        }
        return try parse(xml: data)
    }

    static func parse(xml data: Data) throws -> QuotaSnapshot {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data)
        } catch {
            throw JetBrainsProviderError.invalidQuotaFile
        }

        let quotaRaw = try optionValue(
            named: JetBrainsConstants.quotaInfoOptionName,
            in: document
        )
        guard let quotaRaw, !quotaRaw.isEmpty else {
            throw JetBrainsProviderError.invalidQuotaFile
        }

        let refillRaw = try? optionValue(
            named: JetBrainsConstants.nextRefillOptionName,
            in: document
        )

        return try snapshot(
            quotaInfoJSON: decodeHTMLEntities(quotaRaw),
            nextRefillJSON: refillRaw.map(decodeHTMLEntities)
        )
    }

    static func snapshot(
        quotaInfoJSON: String,
        nextRefillJSON: String?
    ) throws -> QuotaSnapshot {
        guard let quotaJSON = jsonObject(quotaInfoJSON) else {
            throw JetBrainsProviderError.invalidQuotaFile
        }

        // Prefer the monthly tariff balance; never mix it with totals that
        // include top-up credits (those inflate `maximum` and mis-pace the plan).
        let tariff = (quotaJSON["tariffQuota"] as? [String: Any]).flatMap { bucket -> [String: Any]? in
            guard double(bucket, key: "current") != nil,
                  double(bucket, key: "maximum") != nil
            else { return nil }
            return bucket
        }
        let meter = tariff ?? quotaJSON
        guard let used = double(meter, key: "current"),
              let maximum = double(meter, key: "maximum"),
              maximum > 0
        else {
            throw JetBrainsProviderError.noUsableMeter
        }
        let available = double(meter, key: "available") ?? max(0, maximum - used)

        let topUp = quotaJSON["topUpQuota"] as? [String: Any]
        let topUpMaximum = topUp.flatMap { double($0, key: "maximum") }
        let topUpAvailable = topUp.flatMap { double($0, key: "available") }
        let topUpUsed = topUp.flatMap { double($0, key: "current") }

        var refillNext: Date?
        var refillDuration: String?
        if let nextRefillJSON, let refill = jsonObject(nextRefillJSON) {
            refillNext = DayFormat.instant(fromISO8601: string(refill, key: "next") ?? "")
            let tariffInfo = refill["tariff"] as? [String: Any]
            refillDuration = string(refill, key: "duration")
                ?? string(tariffInfo ?? [:], key: "duration")
        }

        return QuotaSnapshot(
            used: used,
            maximum: maximum,
            available: available,
            until: DayFormat.instant(fromISO8601: string(quotaJSON, key: "until") ?? ""),
            refillNext: refillNext,
            refillDuration: refillDuration,
            topUpUsed: topUpUsed,
            topUpMaximum: topUpMaximum,
            topUpAvailable: topUpAvailable
        )
    }

    private static func optionValue(named name: String, in document: XMLDocument) throws -> String? {
        let path =
            "//component[@name='\(JetBrainsConstants.componentName)']/option[@name='\(name)']/@value"
        return try document.nodes(forXPath: path).first?.stringValue
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func jsonObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func string(_ json: [String: Any], key: String) -> String? {
        json[key] as? String
    }

    /// JetBrains writes numbers as strings in the XML JSON; accept both shapes.
    private static func double(_ json: [String: Any], key: String) -> Double? {
        if let value = json[key] as? Double {
            return value
        }
        if let value = json[key] as? Int {
            return Double(value)
        }
        if let value = json[key] as? NSNumber {
            return value.doubleValue
        }
        if let text = json[key] as? String {
            return Double(text)
        }
        return nil
    }
}
