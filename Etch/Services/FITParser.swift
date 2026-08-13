import Foundation
import CoreLocation

/// Parses Garmin FIT files — the native binary format of Garmin, Wahoo, COROS and Suunto
/// devices — into `ImportedActivity`. Dependency-free: it decodes just the slice of the FIT
/// protocol Etch needs — the file header, definition/data record framing, the `record`
/// messages (GPS + altitude + heart rate) and the `session` summary (distance, time, sport).
///
/// FIT stores latitude/longitude in "semicircles" and timestamps as seconds since the FIT
/// epoch (1989-12-31 UTC); both are converted here. Unknown message types are skipped by the
/// size their definition declares, so the parser stays aligned through anything it ignores.
struct FITParser: ActivityFileParser {
    static let fileExtensions = ["fit"]

    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31T00:00:00Z).
    private static let fitEpochOffset: Double = 631_065_600
    /// Semicircles → degrees: value × 180 / 2^31.
    private static let semicircleScale = 180.0 / 2_147_483_648.0

    func parse(data: Data, fileName: String) throws -> [ImportedActivity] {
        let bytes = [UInt8](data)
        guard bytes.count >= 14 else { throw ActivityFileError.corrupt("file too short") }
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, headerSize + 2 <= bytes.count else {
            throw ActivityFileError.corrupt("bad header")
        }
        // ".FIT" signature.
        guard bytes[8] == 0x2E, bytes[9] == 0x46, bytes[10] == 0x49, bytes[11] == 0x54 else {
            throw ActivityFileError.corrupt("not a FIT file")
        }
        let dataSize = Int(readRaw(bytes, 4, 4, true))
        let end = min(headerSize + dataSize, bytes.count)

        var cursor = headerSize
        var defs: [Int: Def] = [:]
        var records: [Rec] = []
        var session = Session()
        var fileCreated: Int64?
        var manufacturer: Int64?
        var lastTimestamp: Int64 = 0

        while cursor < end {
            let header = bytes[cursor]
            cursor += 1

            if header & 0x80 != 0 {
                // Compressed-timestamp data message: local type in bits 5–6, time offset 0–4.
                let localType = Int((header >> 5) & 0x03)
                let offset = Int64(header & 0x1F)
                guard let def = defs[localType] else { break }
                if lastTimestamp != 0 {
                    var ts = (lastTimestamp & ~0x1F) + offset
                    if offset < (lastTimestamp & 0x1F) { ts += 0x20 }
                    lastTimestamp = ts
                }
                guard let (values, next) = readFields(bytes, cursor, def, end) else { break }
                cursor = next
                let resolvedTimestamp = lastTimestamp
                apply(def: def, values: values, into: &records, &session, &fileCreated,
                      &manufacturer, &lastTimestamp, compressedTimestamp: resolvedTimestamp)
            } else if header & 0x40 != 0 {
                // Definition message.
                guard let (def, next) = readDefinition(bytes, cursor, hasDevData: header & 0x20 != 0, end) else { break }
                defs[Int(header & 0x0F)] = def
                cursor = next
            } else {
                // Data message.
                guard let def = defs[Int(header & 0x0F)] else { break }
                guard let (values, next) = readFields(bytes, cursor, def, end) else { break }
                cursor = next
                apply(def: def, values: values, into: &records, &session, &fileCreated,
                      &manufacturer, &lastTimestamp, compressedTimestamp: nil)
            }
        }

        guard let activity = makeActivity(records: records, session: session,
                                          fileCreated: fileCreated, manufacturer: manufacturer) else {
            throw ActivityFileError.empty
        }
        return [activity]
    }

    // MARK: Message application

    private func apply(def: Def, values: [Int: Int64],
                       into records: inout [Rec], _ session: inout Session,
                       _ fileCreated: inout Int64?, _ manufacturer: inout Int64?,
                       _ lastTimestamp: inout Int64, compressedTimestamp: Int64?) {
        switch def.global {
        case 20: // record
            var rec = Rec()
            if let lat = values[0] { rec.latitude = Double(lat) * Self.semicircleScale }
            if let lon = values[1] { rec.longitude = Double(lon) * Self.semicircleScale }
            if let alt = values[2] { rec.elevation = Double(alt) / 5.0 - 500.0 }
            else if let ealt = values[78] { rec.elevation = Double(ealt) / 5.0 - 500.0 }
            if let hr = values[3] { rec.heartRate = Double(hr) }
            if let dist = values[5] { rec.distance = Double(dist) / 100.0 }
            if let ts = values[253] { rec.time = ts; lastTimestamp = ts }
            else if let ct = compressedTimestamp { rec.time = ct }
            records.append(rec)
        case 18: // session
            if let v = values[2] { session.startTime = v }
            if let v = values[253] { session.endTimestamp = v }
            if let v = values[8] { session.timerTime = Double(v) / 1000.0 }
            if let v = values[7] { session.elapsedTime = Double(v) / 1000.0 }
            if let v = values[9] { session.distance = Double(v) / 100.0 }
            if let v = values[5] { session.sport = Int(v) }
            if let v = values[22] { session.ascent = Double(v) }
            if let v = values[16] { session.avgHeartRate = Double(v) }
            if let v = values[17] { session.maxHeartRate = Double(v) }
            if let v = values[11] { session.calories = Double(v) }
        case 0: // file_id
            if let v = values[4] { fileCreated = v }
            if let v = values[1] { manufacturer = v }
        default:
            break
        }
    }

    private func makeActivity(records: [Rec], session: Session,
                              fileCreated: Int64?, manufacturer: Int64?) -> ImportedActivity? {
        let coordinates = records.compactMap { rec -> CLLocationCoordinate2D? in
            guard let lat = rec.latitude, let lon = rec.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        let recTimes = records.compactMap(\.time)
        guard let startFit = session.startTime ?? recTimes.first ?? fileCreated else { return nil }
        let start = Date(timeIntervalSince1970: Double(startFit) + Self.fitEpochOffset)

        let trackSeconds = (recTimes.first != nil && recTimes.last != nil)
            ? Int(recTimes.last! - recTimes.first!) : 0
        let distance = session.distance ?? records.compactMap(\.distance).last ?? RouteMetrics.distance(of: coordinates)
        let moving = session.timerTime.map { Int($0) } ?? trackSeconds
        let elapsed = session.elapsedTime.map { Int($0) } ?? trackSeconds
        let origin = Self.source(forManufacturer: manufacturer)

        var activity = ImportedActivity(
            provider: origin ?? .unknown,
            externalID: "fit:\(startFit):\(Int(distance.rounded()))",
            startDate: start,
            distance: distance,
            movingTime: moving,
            elapsedTime: max(elapsed, moving),
            coordinates: coordinates
        )
        activity.originApp = origin
        activity.importMethod = .fitFile
        activity.activityType = Self.activityType(forSport: session.sport)
        activity.sportType = activity.activityType.rawValue.capitalized
        activity.elevationGain = session.ascent ?? RouteMetrics.elevationGain(of: records.compactMap(\.elevation))
        if let calories = session.calories, calories > 0 { activity.activeEnergy = calories }
        let recHR = records.compactMap(\.heartRate)
        activity.averageHeartRate = session.avgHeartRate
            ?? (recHR.isEmpty ? nil : recHR.reduce(0, +) / Double(recHR.count))
        activity.maxHeartRate = session.maxHeartRate ?? recHR.max()
        return activity
    }

    // MARK: Framing

    /// A definition message: field layout for one local message type.
    private struct Def {
        let littleEndian: Bool
        let global: Int
        let fields: [(num: Int, size: Int, baseType: Int)]
        let devFieldsSize: Int
    }

    /// One `record` message's fields of interest.
    private struct Rec {
        var latitude: Double?
        var longitude: Double?
        var elevation: Double?
        var heartRate: Double?
        var distance: Double?
        var time: Int64?
    }

    /// The `session` summary.
    private struct Session {
        var startTime: Int64?
        var endTimestamp: Int64?
        var timerTime: Double?
        var elapsedTime: Double?
        var distance: Double?
        var sport: Int?
        var ascent: Double?
        var avgHeartRate: Double?
        var maxHeartRate: Double?
        var calories: Double?
    }

    private func readDefinition(_ b: [UInt8], _ cursor: Int, hasDevData: Bool, _ end: Int) -> (Def, Int)? {
        guard cursor + 5 <= b.count else { return nil }
        let littleEndian = b[cursor + 1] == 0
        let global = Int(readRaw(b, cursor + 2, 2, littleEndian))
        let fieldCount = Int(b[cursor + 4])
        var p = cursor + 5
        var fields: [(num: Int, size: Int, baseType: Int)] = []
        fields.reserveCapacity(fieldCount)
        for _ in 0..<fieldCount {
            guard p + 3 <= b.count else { return nil }
            fields.append((num: Int(b[p]), size: Int(b[p + 1]), baseType: Int(b[p + 2])))
            p += 3
        }
        var devSize = 0
        if hasDevData {
            guard p < b.count else { return nil }
            let devCount = Int(b[p]); p += 1
            for _ in 0..<devCount {
                guard p + 3 <= b.count else { return nil }
                devSize += Int(b[p + 1])
                p += 3
            }
        }
        return (Def(littleEndian: littleEndian, global: global, fields: fields, devFieldsSize: devSize), p)
    }

    /// Reads a data message's fields into `fieldNumber → integer value`, skipping strings,
    /// floats and array remainders, and returns the cursor past the whole message.
    private func readFields(_ b: [UInt8], _ cursor: Int, _ def: Def, _ end: Int) -> ([Int: Int64], Int)? {
        var values: [Int: Int64] = [:]
        var p = cursor
        for field in def.fields {
            guard p + field.size <= b.count else { return nil }
            if let value = interpret(b, p, field.baseType, def.littleEndian) {
                values[field.num] = value
            }
            p += field.size
        }
        p += def.devFieldsSize
        guard p <= b.count else { return nil }
        return (values, p)
    }

    // MARK: Value decoding

    /// Reads a scalar field's first element as a signed 64-bit value, returning nil for FIT's
    /// per-type "invalid" sentinel (and for types Etch doesn't need — strings, floats, 64-bit).
    private func interpret(_ b: [UInt8], _ offset: Int, _ baseType: Int, _ le: Bool) -> Int64? {
        let type = baseType & 0x1F
        let size = baseSize(type)
        guard size > 0, offset + size <= b.count else { return nil }
        let raw = readRaw(b, offset, size, le)
        switch type {
        case 1: // sint8
            return raw == 0x7F ? nil : Int64(Int8(bitPattern: UInt8(raw & 0xFF)))
        case 0, 2, 13: // enum, uint8, byte
            return raw == 0xFF ? nil : Int64(raw & 0xFF)
        case 10: // uint8z
            return raw == 0 ? nil : Int64(raw & 0xFF)
        case 3: // sint16
            return raw == 0x7FFF ? nil : Int64(Int16(bitPattern: UInt16(raw & 0xFFFF)))
        case 4: // uint16
            return raw == 0xFFFF ? nil : Int64(raw & 0xFFFF)
        case 11: // uint16z
            return raw == 0 ? nil : Int64(raw & 0xFFFF)
        case 5: // sint32
            return raw == 0x7FFFFFFF ? nil : Int64(Int32(bitPattern: UInt32(raw & 0xFFFFFFFF)))
        case 6: // uint32
            return raw == 0xFFFFFFFF ? nil : Int64(raw & 0xFFFFFFFF)
        case 12: // uint32z
            return raw == 0 ? nil : Int64(raw & 0xFFFFFFFF)
        default:
            return nil
        }
    }

    private func baseSize(_ type: Int) -> Int {
        switch type {
        case 0, 1, 2, 7, 10, 13: return 1
        case 3, 4, 11: return 2
        case 5, 6, 8, 12: return 4
        case 9, 14, 15, 16: return 8
        default: return 0
        }
    }

    private func readRaw(_ b: [UInt8], _ offset: Int, _ size: Int, _ le: Bool) -> UInt64 {
        var value: UInt64 = 0
        if le {
            for i in 0..<size { value |= UInt64(b[offset + i]) << UInt64(8 * i) }
        } else {
            for i in 0..<size { value = (value << 8) | UInt64(b[offset + i]) }
        }
        return value
    }

    // MARK: Lookups

    private static func activityType(forSport sport: Int?) -> ActivityType {
        switch sport {
        case 1: return .run
        case 2: return .ride
        case 5: return .swim
        case 11: return .walk
        case 12, 13: return .ski
        case 15: return .row
        case 17: return .hike
        default: return .run     // Etch is running-first; unknown sports default to run
        }
    }

    private static func source(forManufacturer id: Int64?) -> ActivitySource? {
        switch id {
        case 1: return .garmin
        case 23: return .suunto
        case 32: return .wahoo
        default: return nil
        }
    }
}
