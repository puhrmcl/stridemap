import Foundation
import Compression

/// A minimal, dependency-free reader for standard ZIP archives — enough to pull activity
/// files out of a Nike / Garmin data export. Parses the central directory, then extracts
/// entries on demand, inflating DEFLATE with Apple's `Compression` framework (its
/// `COMPRESSION_ZLIB` decodes the raw DEFLATE stream ZIP uses).
///
/// Scope: standard ZIP only. ZIP64 (archives over 4 GB or with >65 535 entries) is detected
/// and reported rather than mis-parsed. Nothing is written to disk — entries are inflated in
/// memory and handed straight to a parser — so there's no path-traversal ("zip-slip") risk;
/// the caller still guards against decompression bombs via the size fields exposed here.
final class ZipArchiveReader {

    struct Entry {
        let name: String
        let compressionMethod: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        /// True for directory records (name ends with "/"), which carry no data.
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    enum ArchiveError: Error, LocalizedError {
        case notAZip
        case zip64Unsupported
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: return "This file isn't a ZIP archive."
            case .zip64Unsupported: return "This archive is too large to read (ZIP64)."
            case .corrupt(let why): return "The archive is damaged: \(why)"
            }
        }
    }

    let entries: [Entry]
    private let bytes: [UInt8]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        self.entries = try Self.readCentralDirectory(bytes)
    }

    /// Inflates one entry to its bytes. Returns nil if the entry is empty or the compression
    /// method is unsupported (only Stored and DEFLATE are handled).
    func data(for entry: Entry) -> Data? {
        guard !entry.isDirectory, entry.uncompressedSize > 0 else { return nil }
        let lo = entry.localHeaderOffset
        guard lo + 30 <= bytes.count, u32(bytes, lo) == 0x04034b50 else { return nil }
        // The local header's own name/extra lengths can differ from the central directory's.
        let nameLen = u16(bytes, lo + 26)
        let extraLen = u16(bytes, lo + 28)
        let dataStart = lo + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= bytes.count else { return nil }
        let slice = Array(bytes[dataStart ..< dataStart + entry.compressedSize])

        switch entry.compressionMethod {
        case 0:  // Stored
            return Data(slice)
        case 8:  // DEFLATE
            return Self.inflate(slice, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    // MARK: Central directory

    private static func readCentralDirectory(_ bytes: [UInt8]) throws -> [Entry] {
        guard bytes.count >= 22 else { throw ArchiveError.notAZip }

        // Find the End Of Central Directory record by scanning back from the end (its trailing
        // comment is almost always empty, so this is near-instant in practice).
        var eocd = -1
        let lowerBound = max(0, bytes.count - 22 - 0xFFFF)
        var i = bytes.count - 22
        while i >= lowerBound {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ArchiveError.notAZip }

        let count = u16(bytes, eocd + 10)
        let cdOffset = u32(bytes, eocd + 16)
        // Sentinel values mean the real numbers live in a ZIP64 record we don't parse.
        if count == 0xFFFF || cdOffset == 0xFFFFFFFF { throw ArchiveError.zip64Unsupported }
        guard cdOffset <= bytes.count else { throw ArchiveError.corrupt("bad directory offset") }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x02014b50 else { break }
            let method = u16(bytes, p + 10)
            let compressedSize = u32(bytes, p + 20)
            let uncompressedSize = u32(bytes, p + 24)
            let nameLen = u16(bytes, p + 28)
            let extraLen = u16(bytes, p + 30)
            let commentLen = u16(bytes, p + 32)
            let localOffset = u32(bytes, p + 42)
            let nameEnd = p + 46 + nameLen
            guard nameEnd <= bytes.count else { break }
            let name = String(decoding: bytes[(p + 46)..<nameEnd], as: UTF8.self)
            entries.append(Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            p = nameEnd + extraLen + commentLen
        }
        return entries
    }

    // MARK: Inflate

    private static func inflate(_ input: [UInt8], expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let produced = output.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBufferPointer { src -> Int in
                guard let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase, expectedSize,
                    srcBase, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard produced == expectedSize else { return nil }
        return output
    }

    // MARK: Little-endian readers

    private static func u16(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8)
    }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) | (Int(b[o + 1]) << 8) | (Int(b[o + 2]) << 16) | (Int(b[o + 3]) << 24)
    }
    // Instance conveniences.
    private func u16(_ b: [UInt8], _ o: Int) -> Int { Self.u16(b, o) }
    private func u32(_ b: [UInt8], _ o: Int) -> Int { Self.u32(b, o) }
}
