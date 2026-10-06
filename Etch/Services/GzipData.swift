import Foundation
import Compression

/// Gzip (RFC 1952) decoding, for activity files that arrive compressed.
///
/// This exists because of one specific, silent failure. A Strava bulk export — the only way to
/// get years of history that predate the phone's Health store — ships its activities as a mix of
/// `.gpx`, `.gpx.gz`, `.fit` and `.fit.gz`. A reader that handles only the uncompressed pair sees
/// `pathExtension == "gz"`, skips the file, and reports nothing wrong, so someone who imports
/// their whole running life is told Etch found no activities in it.
///
/// Apple's Compression framework decodes raw DEFLATE — its `COMPRESSION_ZLIB` is RFC 1951 here,
/// not the RFC 1950 wrapper the name suggests — so the gzip envelope is removed by hand: parse
/// the variable-length header, drop the 8-byte CRC/size trailer, inflate what is left.
enum GzipData {

    static let magic: [UInt8] = [0x1f, 0x8b]

    static func isGzipped(_ data: Data) -> Bool {
        let head = Array(data.prefix(2))
        return head.count == 2 && head[0] == magic[0] && head[1] == magic[1]
    }

    /// Inflates a gzip member, or nil if it is not gzip, is truncated, or exceeds `limit`.
    ///
    /// `limit` is a decompression-bomb guard: a few kilobytes of gzip can claim to expand to
    /// gigabytes, and the import path reads whole files into memory.
    static func inflate(_ data: Data, limit: Int) -> Data? {
        let bytes = [UInt8](data)
        // 10-byte minimum header plus the 8-byte trailer; anything shorter cannot be a member.
        guard bytes.count > 18, bytes[0] == magic[0], bytes[1] == magic[1], bytes[2] == 8 else {
            return nil
        }

        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {                                  // FEXTRA
            guard index + 2 <= bytes.count else { return nil }
            index += 2 + (Int(bytes[index]) | (Int(bytes[index + 1]) << 8))
        }
        if flags & 0x08 != 0 {                                  // FNAME, zero-terminated
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 {                                  // FCOMMENT, zero-terminated
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }                     // FHCRC
        guard index < bytes.count - 8 else { return nil }

        let payload = Array(bytes[index..<(bytes.count - 8)])
        // ISIZE: the uncompressed length mod 2^32, little-endian, in the last four bytes. Trusted
        // only as a buffer hint — it is attacker-controlled, so it is clamped, and a member that
        // fills the buffer exactly is retried larger rather than silently truncated.
        let end = bytes.count
        let isize = Int(bytes[end - 4]) | (Int(bytes[end - 3]) << 8)
            | (Int(bytes[end - 2]) << 16) | (Int(bytes[end - 1]) << 24)

        // The ordinary path: a usable ISIZE sizes the buffer exactly, in one decode.
        if isize > 0, isize <= limit {
            return decode(payload, capacity: isize)
        }

        // ISIZE is zero, or claims more than the cap allows. Grow until the output stops filling
        // the buffer — the only evidence available that it was not truncated — and refuse at the
        // cap rather than return a half a file that would parse as a corrupt one.
        var capacity = min(limit, max(payload.count * 8, 64 * 1024))
        while true {
            guard let output = decode(payload, capacity: capacity) else { return nil }
            if output.count < capacity { return output }
            if capacity >= limit { return nil }
            capacity = min(limit, capacity * 4)
        }
    }

    /// Strips a `.gz` suffix and inflates, or returns the input untouched when it is not gzipped.
    /// Named by content rather than extension: an export can carry a gzipped file whose name has
    /// lost its suffix, and the format sniffing downstream reads bytes, not names.
    static func unwrap(name: String, data: Data, limit: Int) -> (name: String, data: Data) {
        guard isGzipped(data), let inflated = inflate(data, limit: limit) else {
            return (name, data)
        }
        let stripped = (name as NSString).pathExtension.lowercased() == "gz"
            ? (name as NSString).deletingPathExtension
            : name
        return (stripped, inflated)
    }

    private static func decode(_ payload: [UInt8], capacity: Int) -> Data? {
        guard capacity > 0 else { return nil }
        var output = Data(count: capacity)
        let produced = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return payload.withUnsafeBufferPointer { source -> Int in
                guard let sourceBase = source.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard produced > 0 else { return nil }
        // Re-wrapped rather than returned as a slice: a slice keeps the parent's indices, and the
        // parsers downstream read absolute offsets (the FIT header is bytes 8...11).
        return Data(output.prefix(produced))
    }
}
