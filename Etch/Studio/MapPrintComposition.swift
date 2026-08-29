import SwiftUI

/// The aggregate-print artwork: a rendered map panel (routes / choropleth / pins) above a footer
/// with a big headline count and a sparse stat row. Rendered to an image for preview and export,
/// mirroring the single-run `StudioComposition`.
struct MapPrintComposition: View {
    var panelImage: UIImage
    var orientation: StudioOrientation = .portrait
    var footer: MapPrintFooterData
    /// When false, the poster is the map panel alone — no title, stats, or caption.
    var showFooter: Bool = true

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    static let landscapeFooterWidth: CGFloat = 640

    static func nominalSize(_ orientation: StudioOrientation) -> CGSize {
        orientation == .landscape
            ? CGSize(width: width + landscapeFooterWidth, height: artHeight)
            : CGSize(width: width, height: artHeight + 520)
    }

    var body: some View {
        Group {
            if !showFooter {
                panel   // Map-only: the square panel is the whole poster.
            } else if orientation == .landscape {
                HStack(spacing: 0) { panel; footerView }
            } else {
                VStack(spacing: 0) { panel; footerView }
            }
        }
        .background(footer.ground)
    }

    private var panel: some View {
        Image(uiImage: panelImage)
            .resizable()
            .scaledToFill()
            .frame(width: Self.width, height: Self.artHeight)
            .clipped()
    }

    private var footerView: some View {
        VStack(spacing: 20) {
            Text(footer.title.uppercased())
                .font(.etch(size: 26, weight: .semibold))
                .tracking(4)
                .foregroundStyle(footer.subtle)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let list = footer.heroList {
                // A list of state names in place of the big number.
                VStack(spacing: 12) {
                    Text(footer.heroLabel)
                        .font(.etch(size: 22, weight: .semibold))
                        .tracking(8)
                        .foregroundStyle(footer.accent)
                    Text(list.isEmpty ? "—" : list.joined(separator: "  ·  "))
                        .font(.etch(size: 40, weight: .bold))
                        .foregroundStyle(footer.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    Text(footer.heroValue)
                        .font(.etch(size: 150, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(footer.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(footer.heroLabel)
                        .font(.etch(size: 24, weight: .semibold))
                        .tracking(8)
                        .foregroundStyle(footer.accent)
                }
            }

            Rectangle().fill(footer.subtle.opacity(0.4)).frame(width: 90, height: 2).padding(.vertical, 6)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(footer.subStats.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(footer.subtle.opacity(0.35)).frame(width: 1, height: 42)
                    }
                    stat(item.label, item.value)
                }
            }
        }
        .padding(70)
        .frame(width: orientation == .landscape ? Self.landscapeFooterWidth : Self.width,
               height: orientation == .landscape ? Self.artHeight : nil)
        .background(footer.ground)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.etch(size: 32, weight: .bold))
                .foregroundStyle(footer.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.etch(size: 15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(footer.subtle)
        }
        .frame(maxWidth: .infinity)
    }
}
