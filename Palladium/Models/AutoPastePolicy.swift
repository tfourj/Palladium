import Foundation

enum AutoPastePolicy {
    // Failed and partial downloads keep their link so a retry is one tap away.
    static func shouldClearLinkField(linkText: String, finishedURL: String, resultKind: String) -> Bool {
        guard resultKind == "success" else { return false }
        return linkText.trimmingCharacters(in: .whitespacesAndNewlines) == finishedURL
    }
}
