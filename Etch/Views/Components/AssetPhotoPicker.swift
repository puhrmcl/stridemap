import SwiftUI
import PhotosUI

/// A Photos picker that returns the picked images' **library identifiers** (`PHAsset.localIdentifier`),
/// not raw data — so a chosen photo can be appended to `Run.photoReferences` and thus appears both
/// in Etch Studio and in the run's activity details (which read the same array).
///
/// SwiftUI's `PhotosPicker` yields opaque `PhotosPickerItem`s with no stable asset id; a
/// `PHPickerViewController` configured with the shared photo library does expose `assetIdentifier`,
/// which is what we persist.
struct AssetPhotoPicker: UIViewControllerRepresentable {
    /// How many photos may be picked at once.
    var selectionLimit: Int = 3
    /// Called with the picked assets' local identifiers (empty if the user cancels).
    var onPick: ([String]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([String]) -> Void
        init(onPick: @escaping ([String]) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            onPick(results.compactMap { $0.assetIdentifier })
        }
    }
}
