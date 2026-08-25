import SwiftUI
import UIKit

/// The artwork, full screen — tap the Studio preview to get here. A dark room for looking at the
/// piece: black ground, no chrome except a close button, pinch to inspect the linework and
/// double-tap to jump between fit and detail.
struct ArtworkPreviewView: View {
    let image: UIImage?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableImage(image: image)
                    .ignoresSafeArea()
            } else {
                // Only reachable if the render was cleared between tap and presentation.
                Text("Nothing to preview yet")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.18), in: .circle)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 16)
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
    }
}

/// UIScrollView does pinch-zoom and pan better than any SwiftUI reconstruction — momentum,
/// rubber-banding, and centering all come for free. The image sits in a full-size hosted
/// UIImageView (aspect-fit) so zooming stays anchored under the pinch.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 5
        scroll.minimumZoomScale = 1
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        /// Double-tap: zoom into the tapped point at 2.5×, or back out to fit.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale,
                                  height: scroll.bounds.height / scale)
                let rect = CGRect(x: point.x - size.width / 2,
                                  y: point.y - size.height / 2,
                                  width: size.width, height: size.height)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}
