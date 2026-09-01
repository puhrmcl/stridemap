import SwiftUI
import UIKit
import ImageIO

/// Proves the print engine end to end, on a simulator, in CI.
///
/// The banded writer hand-rolls a PNG — chunk CRCs, a zlib wrapper Apple's compressor doesn't
/// supply, an Adler-32 over scanlines, and a row order that is the reverse of the bitmap it reads
/// from. Every one of those is silently wrong-able: the file still opens in something forgiving,
/// or it opens upside down, or it decodes on a Mac and not at a print lab. There is no test target
/// in this project, so the check runs as a preview screen (`ETCH_PREVIEW=print-engine`) and reports
/// on screen, where CI already photographs it.
///
/// What it establishes: the file decodes with the system decoder at the exact size asked for, its
/// pixels land where they were drawn, and the same content written in one band and in many is
/// byte-identical.
@MainActor
struct PrintEngineCheckView: View {

    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    @State private var results: [Result] = []
    @State private var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Print engine")
                    .font(.etch(.title2, weight: .bold))
                Spacer()
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Text(results.allSatisfy(\.passed) ? "ALL PASS" : "FAIL")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(results.allSatisfy(\.passed) ? .green : .red, in: .capsule)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.etch(size: 13, weight: .semibold))
                                Text(result.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .task { await run() }
    }

    // MARK: The checks

    private func run() async {
        var out: [Result] = []
        out.append(contentsOf: decodeCheck())
        out.append(bandingCheck())
        out.append(largeSheetCheck())
        results = out
        running = false
        writeReport(out)
    }

    /// Also writes the outcome as plain text into the app's Documents directory.
    ///
    /// The screenshot is the human-readable form, but a screenshot has to travel back as base64 —
    /// four of them ran to 900 KB, which is more than a reading session can hold. A text file the
    /// runner can `cat` puts the same verdict in the job log for nothing.
    private func writeReport(_ results: [Result]) {
        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        var lines = ["print-engine \(AppInfo.changeTag)"]
        for result in results {
            lines.append("\(result.passed ? "PASS" : "FAIL")  \(result.name) — \(result.detail)")
        }
        lines.append(results.allSatisfy(\.passed) ? "RESULT: ALL PASS" : "RESULT: FAIL")
        try? lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("print-engine-report.txt"),
            atomically: true, encoding: .utf8
        )
    }

    /// A file the system decoder accepts, at the size asked for, with pixels where they were put.
    private func decodeCheck() -> [Result] {
        let width = 64, height = 40
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-decode-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let writer = try PrintFileWriter(width: width, height: height, url: url)
            // Two bands: red over the top ten rows, blue over the remaining thirty. If the row
            // order were reversed the colours would swap, which a size check alone would miss.
            try writer.append(band: solid(.red, width: width, height: 10), rows: 10)
            try writer.append(band: solid(.blue, width: width, height: 30), rows: 30)
            try writer.finish()
        } catch {
            return [Result(name: "Writes a PNG", passed: false, detail: "\(error)")]
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            let bytes = (try? Data(contentsOf: url).count) ?? 0
            return [Result(name: "System decoder accepts the file", passed: false,
                           detail: "CGImageSource refused it (\(bytes) bytes on disk)")]
        }

        var out: [Result] = []
        let sizeOK = decoded.width == width && decoded.height == height
        out.append(Result(
            name: "Decodes at the declared size", passed: sizeOK,
            detail: "wrote \(width)×\(height), decoded \(decoded.width)×\(decoded.height)"
        ))

        let top = pixel(decoded, x: width / 2, y: 3)
        let bottom = pixel(decoded, x: width / 2, y: height - 3)
        let orderOK = top.r > 200 && top.b < 60 && bottom.b > 200 && bottom.r < 60
        out.append(Result(
            name: "Scanlines run top to bottom", passed: orderOK,
            detail: "row 3 = rgb(\(top.r),\(top.g),\(top.b)) expect red · "
                  + "row \(height - 3) = rgb(\(bottom.r),\(bottom.g),\(bottom.b)) expect blue"
        ))
        return out
    }

    /// The same content, written as one band and as seven, must decode to the same pixels.
    ///
    /// Not the same *bytes*: a band boundary is an IDAT boundary, and each chunk carries its own
    /// length and CRC, so the files legitimately differ on disk. What must not differ is what
    /// comes out of the decoder — that is the claim the whole engine rests on. Bands of six over
    /// a height of forty-two also make the last one exact, and a stripe pattern means a band that
    /// landed at the wrong offset shows up as a mismatch rather than hiding inside a flat fill.
    private func bandingCheck() -> Result {
        let width = 48, height = 42
        let stripe: [UIColor] = [.systemRed, .systemGreen, .systemBlue,
                                 .systemOrange, .systemPurple, .systemTeal, .systemYellow]

        func write(bandRows: Int) -> [UInt8]? {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("engine-band-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let writer = try PrintFileWriter(width: width, height: height, url: url)
                var written = 0
                while written < height {
                    let rows = min(bandRows, height - written)
                    // Colour by absolute row, so the stripes are a property of the image rather
                    // than of how it was cut into bands.
                    let band = striped(width: width, height: rows, from: written, palette: stripe)
                    try writer.append(band: band, rows: rows)
                    written += rows
                }
                try writer.finish()
                return rgbBytes(of: url)
            } catch { return nil }
        }

        guard let single = write(bandRows: height), let many = write(bandRows: 6) else {
            return Result(name: "One band and many decode alike", passed: false,
                          detail: "a write failed")
        }
        let same = single == many && !single.isEmpty
        let differing = zip(single, many).filter { $0 != $1 }.count
        return Result(
            name: "One band and many decode alike", passed: same,
            detail: same ? "\(single.count / 3) px identical across 1×\(height) and 7×6 bands"
                         : "\(differing) of \(single.count) bytes differ"
        )
    }

    /// Decoded RGB bytes of a PNG on disk, normalised through a known bitmap layout.
    private func rgbBytes(of url: URL) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }

    /// A band of horizontal stripes coloured by absolute row.
    private func striped(width: Int, height: Int, from firstRow: Int,
                         palette: [UIColor]) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { context in
            for row in 0..<height {
                palette[(firstRow + row) % palette.count].setFill()
                context.fill(CGRect(x: 0, y: row, width: width, height: 1))
            }
        }
        return image.cgImage!
    }

    /// The size that was unreachable: a 24×36″ sheet at 300 DPI. Written for real, then decoded
    /// back — 7200 × 10800 is the number that used to make this impossible.
    private func largeSheetCheck() -> Result {
        let geometry = PrintGeometry(trimWidth: 24, trimHeight: 36)
        let width = Int(geometry.trimPixels.width)
        let height = Int(geometry.trimPixels.height)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-large-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let started = Date()
        do {
            let writer = try PrintFileWriter(width: width, height: height, url: url)
            var written = 0
            let band = solid(.orange, width: width, height: 900)
            while written < height {
                let rows = min(900, height - written)
                try writer.append(band: band, rows: rows)
                written += rows
            }
            try writer.finish()
        } catch {
            return Result(name: "24×36″ at 300 DPI", passed: false, detail: "\(error)")
        }

        let seconds = Date().timeIntervalSince(started)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? Int) ?? 0
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let decodedWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let decodedHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            return Result(name: "24×36″ at 300 DPI", passed: false,
                          detail: "wrote \(bytes) bytes but the decoder refused them")
        }
        let ok = decodedWidth == width && decodedHeight == height
        return Result(
            name: "24×36″ at 300 DPI", passed: ok,
            detail: "\(decodedWidth)×\(decodedHeight) · \(bytes / 1024) KB · "
                  + String(format: "%.1fs", seconds)
        )
    }

    // MARK: Helpers

    private func solid(_ color: UIColor, width: Int, height: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.cgImage!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            // Shift the image so the wanted pixel lands in the 1×1 context. CGContext is y-up and
            // the image's row 0 is its top, so the y offset counts from the bottom.
            context.draw(image, in: CGRect(x: CGFloat(-x), y: CGFloat(y - image.height + 1),
                                           width: CGFloat(image.width),
                                           height: CGFloat(image.height)))
        }
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }
}
