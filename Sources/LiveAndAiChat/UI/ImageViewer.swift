#if canImport(UIKit)
import SwiftUI
import UIKit

/// Full-screen attachment viewer. Mirrors the Android `ImageViewer` and
/// the web SDK's overlay:
///   - Tap-to-dismiss / close button.
///   - Pinch to zoom (1× → 4×) with double-tap-to-toggle.
///   - Drag-to-pan when zoomed.
///   - Download / save-to-Photos action.
///
/// PDFs and other non-image attachments fall through to the system Files
/// app via a Share Sheet — we only render an in-line viewer for images.
struct ImageViewerView: View {
    let attachment: MessageAttachment
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var downloadState: DownloadState = .idle
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    @Environment(\.chatColors) private var colors

    enum DownloadState: Equatable {
        case idle
        case running
        case success
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isImage {
                imageContent
            } else {
                fileFallback
            }

            VStack {
                topBar
                Spacer()
                if case .success = downloadState {
                    statusToast(text: "Saved", icon: "checkmark.circle.fill", color: .green)
                } else if case .failed(let reason) = downloadState {
                    statusToast(text: reason, icon: "exclamationmark.triangle.fill", color: .red)
                }
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
    }

    private var isImage: Bool {
        if attachment.type.lowercased().hasPrefix("image/") { return true }
        let ext = (attachment.name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            Text(attachment.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)

            Spacer()

            Button(action: download) {
                Group {
                    if case .running = downloadState {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(10)
                .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download")
            .disabled(downloadState == .running)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var imageContent: some View {
        if #available(iOS 15.0, *) {
            AsyncImage(url: URL(string: attachment.url)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                case .failure:
                    failurePlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomGesture.simultaneously(with: dragGesture))
                        .onTapGesture(count: 2) { toggleZoom() }
                @unknown default:
                    failurePlaceholder
                }
            }
            .padding(.horizontal, 16)
        } else {
            failurePlaceholder
        }
    }

    private var fileFallback: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.85))
            Text(attachment.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: openExternal) {
                Text("Open with…")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
        }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.7))
            Text("Could not load image")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func statusToast(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .padding(.bottom, 32)
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposed = lastScale * value
                scale = min(max(proposed, 1.0), 4.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.001 {
                    withAnimation(.spring(response: 0.25)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3)) {
            if scale > 1.05 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func download() {
        guard let url = URL(string: attachment.url) else { return }
        downloadState = .running
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if isImage, let image = UIImage(data: data) {
                    let saver = PhotoSaver()
                    let ok = await saver.save(image)
                    await MainActor.run { downloadState = ok ? .success : .failed("Save failed") }
                } else {
                    // For PDFs etc, drop into the Share Sheet so the user
                    // can choose Files / iCloud / mail etc.
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(attachment.name)
                    try? data.write(to: tmp)
                    await MainActor.run {
                        shareItems = [tmp]
                        showShareSheet = true
                        downloadState = .idle
                    }
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                await MainActor.run {
                    if case .success = downloadState { downloadState = .idle }
                }
            } catch {
                await MainActor.run { downloadState = .failed(error.localizedDescription) }
            }
        }
    }

    private func openExternal() {
        if let url = URL(string: attachment.url) {
            UIApplication.shared.open(url)
        }
    }
}

import Photos

private actor PhotoSaver {
    func save(_ image: UIImage) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return true
        } catch {
            return false
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
