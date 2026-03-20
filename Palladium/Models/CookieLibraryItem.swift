import Foundation

struct CookieLibraryItem: Identifiable, Hashable {
    let fileName: String
    let fileURL: URL
    let modifiedDate: Date

    var id: String { fileURL.path }

    var modifiedDateText: String {
        modifiedDate.formatted(date: .abbreviated, time: .shortened)
    }
}
