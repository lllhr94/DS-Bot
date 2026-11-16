import SwiftUI
import UIKit

/// Photos already fetched from the computer, small and full size.
@MainActor
private enum PhotoCache {
    static let store = NSCache<NSString, UIImage>()
}

/// A photo the computer keeps, shown small in a chat.
struct RemotePhoto: View {
    let chat: ChatModel
    let attachmentId: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.55)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Color(hex: 0x4A4A55))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .task(id: attachmentId) {
            let key = "small-\(attachmentId)" as NSString
            if let kept = PhotoCache.store.object(forKey: key) { image = kept; return }
            if let data = await chat.photo(attachmentId, preview: true), let loaded = UIImage(data: data) {
                PhotoCache.store.setObject(loaded, forKey: key)
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

/// One photo full screen: pinch to zoom, tap or drag down to close.
struct PhotoViewer: View {
    let chat: ChatModel
    var attachmentId: String?
    var local: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var pull: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(0.6, Double(abs(pull.height)) / 500)).ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom * pinch)
                    .offset(pull)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { pinch = $0.magnification }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    zoom = min(4, max(1, zoom * pinch))
                                    pinch = 1
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { if zoom <= 1 { pull = $0.translation } }
                            .onEnded { value in
                                if zoom <= 1, abs(value.translation.height) > 120 {
                                    dismiss()
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { pull = .zero }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { zoom = zoom > 1 ? 1 : 2.5 }
                    }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2), in: .circle)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .padding(.top, 8)
            .accessibilityLabel("关闭")
        }
        .task {
            if let local { image = UIImage(data: local); return }
            guard let attachmentId else { return }
            let small = "small-\(attachmentId)" as NSString
            let full = "full-\(attachmentId)" as NSString
            // The small one shows until the original arrives.
            image = PhotoCache.store.object(forKey: full) ?? PhotoCache.store.object(forKey: small)
            guard PhotoCache.store.object(forKey: full) == nil else { return }
            if let data = await chat.photo(attachmentId, preview: false), let loaded = UIImage(data: data) {
                PhotoCache.store.setObject(loaded, forKey: full)
                image = loaded
            }
        }
    }
}

/// The system camera, for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onDone: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            parent.onDone(image?.jpegData(compressionQuality: 0.9))
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDone(nil)
            parent.dismiss()
        }
    }
}
