import Foundation

/// One person's answer for one local day. Never a household total.
struct DayLog: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var personID: UUID
    /// Local calendar day, `yyyy-MM-dd`. See `DayKey`.
    var day: String
    var bucket: Bucket
    var loggedAt: Date

    init(id: UUID = UUID(), personID: UUID, day: String, bucket: Bucket, loggedAt: Date = Date()) {
        self.id = id
        self.personID = personID
        self.day = day
        self.bucket = bucket
        self.loggedAt = loggedAt
    }
}
