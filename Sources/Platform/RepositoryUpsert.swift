import Foundation

/// One record in a list of records, put in place of whatever was filed under the
/// same key.
///
/// The single definition of an upsert across the repositories, and the reason it
/// exists: the
/// two orders of those two lines are easy to swap, and getting them wrong is
/// invisible. Appending instead of replacing leaves the old copy beside the new
/// one, and every listing then shows the same record twice — a quota edited twice
/// listed twice, a refresh overwriting the wrong pool's figure.
///
/// The key is a predicate rather than a field because two of the families here
/// are keyed by more than one thing, and a single-argument key would have to be
/// invented for them.
func upserting<Element>(
    _ record: Element,
    into records: [Element],
    replacing isTheSameRecord: (Element) -> Bool
) -> [Element] {
    var records = records
    records.removeAll(where: isTheSameRecord)
    records.append(record)
    return records
}
