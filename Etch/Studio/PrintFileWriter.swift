import Foundation
import UIKit
import Compression
import Accelerate

/// Writes a PNG of any size to disk without ever holding the whole image in memory.
///
/// The print pipeline's ceiling was never the printer or the composition — it was one number:
/// a 24×36″ print at 300 DPI is 7200 × 10800 pixels, and a single bitmap of that size is 311 MB
/// before CoreAnimation's working copies. `UIImage` can't carry it on a phone, so the largest and
/// most valuable size in the catalogue was unsellable and the cheapest finish in the range was
/// gated behind the same wall.
///
/// A PNG doesn't need to exist all at once. Its pixel data is a single zlib stream over scanlines
/// written top to bottom, and that stream may be split across as many `IDAT` chunks as the encoder
/// likes. So the artwork can be rendered a band at a time, each band compressed and flushed to the
/// file as its own chunk, and the peak cost becomes one band rather than one poster. Twelve bands
/// of a 24×36 hold 26 MB each.
///
/// This is a deliberate, minimal encoder: 8-bit RGB, no interlacing, filter type 0. Print files
/// are opaque, so dropping the alpha channel takes a quarter off the bytes compressed and written.
final class PrintFileWriter {

    enum WriteError: Error, LocalizedError {
        case cannotCreateFile(URL)
        case compressionFailed
        case wrongRowCount(expected: Int, written: Int)

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile(let url): return "Couldn't create \(url.lastPathComponent)."
            case .compressionFailed:         return "The print file couldn't be compressed."
            case .wrongRowCount(let e, let w): return "Print file wrote \(w) of \(e) rows."
            }
        }
    }

    let width: Int
    let height: Int
    let url: URL

    private let handle: FileHandle
    private var rowsWritten = 0
    /// Adler-32 runs over the *uncompressed* scanline bytes, so it accumulates as rows are fed in.
    private var adlerA: UInt32 = 1
    private var adlerB: UInt32 = 0
    private var stream: UnsafeMutablePointer<compression_stream>
    private var streamInitialised = false
    /// Destination for one flush of deflate output. 1 MB is comfortably larger than any band
    /// compresses to in a single pass, and the loop drains until the stream stops filling it.
    private let outputCapacity = 1 << 20
    private let outputBuffer: UnsafeMutablePointer<UInt8>

    init(width: Int, height: Int, url: URL) throws {
        precondition(width > 0 && height > 0)
        self.width = width
        self.height = height
        self.url = url

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw WriteError.cannotCreateFile(url)
        }
        self.handle = handle
        self.outputBuffer = .allocate(capacity: outputCapacity)
        self.stream = .allocate(capacity: 1)

        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else {
            outputBuffer.deallocate()
            stream.deallocate()
            try? handle.close()
            throw WriteError.compressionFailed
        }
        streamInitialised = true
        stream.pointee.dst_ptr = outputBuffer
        stream.pointee.dst_size = outputCapacity
        stream.pointee.src_size = 0

        handle.write(Data(Self.signature))
        writeChunk("IHDR", ihdr())
        // Apple's COMPRESSION_ZLIB is raw DEFLATE with no RFC-1950 wrapper, but PNG requires the
        // wrapper — so the two-byte header goes in by hand and the Adler-32 trailer follows the
        // last deflate block. 0x78 0x01 is CM=deflate, 32K window, and the check bits that make
        // the pair divisible by 31.
        pendingIDAT = Data([0x78, 0x01])
    }

    deinit {
        if streamInitialised { compression_stream_destroy(stream) }
        outputBuffer.deallocate()
        stream.deallocate()
    }

    /// Compressed bytes waiting to be written as the next IDAT chunk.
    private var pendingIDAT = Data()

    // MARK: Feeding the image

    /// Appends one band of the image, top-aligned under whatever has already been appended.
    ///
    /// `rows` is the number of scanlines this band contributes, and it is authoritative: the band
    /// is drawn into a context of exactly that height. A render can land a pixel either side of
    /// its nominal size once a point-space band height is multiplied by a fractional scale, and
    /// twelve of those roundings would leave the file short or long — a corrupt PNG. Resolving it
    /// by resampling costs a sub-pixel stretch nobody can see; resolving it by trusting the
    /// renderer costs the file.
    func append(band: CGImage, rows: Int) throws {
        let bandHeight = rows
        guard bandHeight > 0 else { return }

        // Draw the band into a context whose layout is known, rather than trusting whatever the
        // source CGImage's own bitmap layout happens to be — a CGImage from ImageRenderer may be
        // premultiplied, 16-bit, or in a wide colour space, and none of that survives a raw
        // byte read. Opaque, because the print sheet always has a ground behind it.
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil, width: width, height: bandHeight, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ), let base = context.data else { throw WriteError.compressionFailed }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: bandHeight))
        context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: bandHeight))

        // RGBA → RGB for the whole band in one Accelerate call. Done pixel-by-pixel in Swift this
        // is 6.5 million iterations per band and 78 million for a 24×36 sheet, which is the
        // difference between a print taking seconds and taking minutes.
        let rgbBytesPerRow = width * 3
        var rgb = [UInt8](repeating: 0, count: rgbBytesPerRow * bandHeight)
        try rgb.withUnsafeMutableBufferPointer { rgbBuffer in
            var source = vImage_Buffer(data: base, height: vImagePixelCount(bandHeight),
                                       width: vImagePixelCount(width), rowBytes: bytesPerRow)
            var destination = vImage_Buffer(data: rgbBuffer.baseAddress,
                                            height: vImagePixelCount(bandHeight),
                                            width: vImagePixelCount(width),
                                            rowBytes: rgbBytesPerRow)
            guard vImageConvert_RGBA8888toRGB888(&source, &destination, vImage_Flags(kvImageNoFlags))
                    == kvImageNoError else { throw WriteError.compressionFailed }
        }

        // The band as PNG scanlines: a filter byte then the row's RGB. A CGBitmapContext's row 0
        // is the *bottom* of the image while PNG scanlines run top to bottom, so the rows are
        // copied in reverse. Building the whole band at once means one call into the compressor
        // per band rather than one per scanline.
        let stride = 1 + rgbBytesPerRow
        var filtered = [UInt8](repeating: 0, count: stride * bandHeight)
        rgb.withUnsafeBufferPointer { source in
            filtered.withUnsafeMutableBufferPointer { destination in
                for output in 0..<bandHeight {
                    let input = bandHeight - 1 - output
                    destination[output * stride] = 0   // filter type: None
                    let from = source.baseAddress! + input * rgbBytesPerRow
                    let to = destination.baseAddress! + output * stride + 1
                    to.update(from: from, count: rgbBytesPerRow)
                }
            }
        }

        try feed(filtered)
        rowsWritten += bandHeight
        flushPendingIDAT()
    }

    /// Compresses a run of scanlines and folds it into the running Adler-32.
    private func feed(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            Self.adler(&adlerA, &adlerB, base, buffer.count)
            stream.pointee.src_ptr = base
            stream.pointee.src_size = buffer.count
            while stream.pointee.src_size > 0 {
                let status = compression_stream_process(stream, 0)
                guard status != COMPRESSION_STATUS_ERROR else { throw WriteError.compressionFailed }
                if stream.pointee.dst_size == 0 { drainOutput() }
            }
        }
    }

    /// Adler-32, deferring the modulo.
    ///
    /// The definition takes a remainder after every byte, which for a 24×36 sheet is 233 million
    /// divisions. 5552 is the largest run of 255s that cannot overflow a `UInt32` accumulator, so
    /// the remainder is safe to take once per block instead — the standard zlib approach, and the
    /// reason this costs nothing worth measuring.
    private static func adler(_ a: inout UInt32, _ b: inout UInt32,
                              _ bytes: UnsafePointer<UInt8>, _ count: Int) {
        var index = 0
        while index < count {
            let block = min(5552, count - index)
            for offset in index..<(index + block) {
                a &+= UInt32(bytes[offset])
                b &+= a
            }
            a %= 65521
            b %= 65521
            index += block
        }
    }

    /// Moves whatever deflate has produced into the pending chunk and resets the output window.
    private func drainOutput() {
        let produced = outputCapacity - stream.pointee.dst_size
        if produced > 0 {
            pendingIDAT.append(outputBuffer, count: produced)
        }
        stream.pointee.dst_ptr = outputBuffer
        stream.pointee.dst_size = outputCapacity
    }

    /// Writes the accumulated compressed bytes as one IDAT chunk. A PNG may carry any number of
    /// them, which is the whole reason this can stream: one chunk per band, none of them held.
    private func flushPendingIDAT() {
        drainOutput()
        guard !pendingIDAT.isEmpty else { return }
        writeChunk("IDAT", pendingIDAT)
        pendingIDAT.removeAll(keepingCapacity: true)
    }

    // MARK: Finishing

    /// Closes the deflate stream, appends the Adler-32 trailer and IEND, and returns the file.
    @discardableResult
    func finish() throws -> URL {
        guard rowsWritten == height else {
            throw WriteError.wrongRowCount(expected: height, written: rowsWritten)
        }
        stream.pointee.src_size = 0
        var status = COMPRESSION_STATUS_OK
        repeat {
            status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            guard status != COMPRESSION_STATUS_ERROR else { throw WriteError.compressionFailed }
            drainOutput()
        } while status != COMPRESSION_STATUS_END

        // The zlib trailer: Adler-32 of the uncompressed data, big-endian, inside the IDAT stream.
        let adler = (adlerB << 16) | adlerA
        pendingIDAT.append(contentsOf: [
            UInt8((adler >> 24) & 0xFF), UInt8((adler >> 16) & 0xFF),
            UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)
        ])
        writeChunk("IDAT", pendingIDAT)
        pendingIDAT.removeAll()

        writeChunk("IEND", Data())
        try handle.close()
        return url
    }

    // MARK: PNG structure

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private func ihdr() -> Data {
        var data = Data()
        data.append(bigEndian: UInt32(width))
        data.append(bigEndian: UInt32(height))
        data.append(contentsOf: [
            8,     // bit depth
            2,     // colour type 2 = truecolour RGB
            0,     // deflate
            0,     // adaptive filtering
            0      // no interlace
        ])
        return data
    }

    private func writeChunk(_ type: String, _ payload: Data) {
        var chunk = Data()
        chunk.append(bigEndian: UInt32(payload.count))
        let typeBytes = Array(type.utf8)
        chunk.append(contentsOf: typeBytes)
        chunk.append(payload)
        var crcInput = Data(typeBytes)
        crcInput.append(payload)
        chunk.append(bigEndian: CRC32.checksum(crcInput))
        handle.write(chunk)
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ])
    }
}

/// The CRC-32 every PNG chunk carries. Table built once.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
