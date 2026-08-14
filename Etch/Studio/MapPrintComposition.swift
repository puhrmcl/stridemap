import SwiftUI

/// The aggregate-print artwork: a rendered map panel (routes / choropleth / pins) above a footer
/// with a big headline count and a sparse stat row. Rendered to an image for preview and export,
/// mirroring the single-run `StudioComposition`.
struct MapPrintComposition: View {
    var panelImage: UIImage
    var footer: MapPrintFooterData

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    static var size: CGSize { CGSize(width: width, height: artHeight + 520) }

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: panelImage)
                .resizable()
                .scaledToFill()
                .frame(width: Self.width, height: Self.artHeight)
                .clipped()
            footerView
        }
        .frame(width: Self.width)
        .background(footer.ground)
    }

    private var footerView: some View {
        VStack(spacing: 20) {
            Text(footer.title.uppercased())
                .font(.system(size: 26, weight: .semibold))
                .tracking(4)
                .foregroundStyle(footer.subtle)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text(footer.heroValue)
                    .font(.system(size: 150, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(footer.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(footer.heroLabel)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(footer.accent)
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
        .frame(width: Self.width)
        .background(footer.ground)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(footer.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(footer.subtle)
        }
        .frame(maxWidth: .infinity)
    }
}
