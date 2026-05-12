import SwiftUI

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

/// UIKit-host glue that lets pure-UIKit apps call ``LiveAndAiChat/present(from:)``
/// without writing any SwiftUI. SwiftUI hosts should embed ``ChatScreen``
/// directly inside their own navigation stack instead.
public extension LiveAndAiChat {

    /// Present the SDK's built-in chat UI modally over the supplied view
    /// controller. Mirrors `LiveAndAiChat.openChat()` on Android, which
    /// launches a `ChatActivity`. The presented view is auto-themed from
    /// the merchant's `appearance` config the moment `getCsConfig`
    /// resolves.
    ///
    /// The host can rely on `closeChat()` (or the on-screen "X" button)
    /// to dismiss; no external dismissal hook is required.
    @MainActor
    func present(from host: UIViewController) {
        precondition(host.presentedViewController == nil, "Host already has a presented view controller.")
        let presenter = ChatPresentingController(sdk: self)
        presenter.modalPresentationStyle = .fullScreen
        host.present(presenter, animated: true) { [weak self] in
            self?.openChat()
        }
    }
}

/// Wraps ``ChatScreen`` in a `UIHostingController` and owns the
/// `UIDocumentPickerViewController` we hand off to for file picking.
/// Lives only as long as the chat is on screen.
@MainActor
final class ChatPresentingController: UIViewController {
    private let sdk: LiveAndAiChat
    private var hosting: UIHostingController<AnyView>!

    init(sdk: LiveAndAiChat) {
        self.sdk = sdk
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let screen = ChatScreen(
            sdk: sdk,
            onClose: { [weak self] in
                self?.sdk.closeChat()
                self?.dismiss(animated: true)
            },
            onPickFile: { [weak self] in
                self?.presentDocumentPicker()
            }
        )
        let host = UIHostingController(rootView: AnyView(screen))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        self.hosting = host
    }

    private func presentDocumentPicker() {
        let types: [UTType] = [.png, .jpeg, .webP, .gif, .pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }
}

extension ChatPresentingController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let mimeType = ChatPresentingController.mimeType(for: url)
                sdk.attachFile(
                    data: data,
                    name: url.lastPathComponent,
                    mimeType: mimeType,
                    previewUri: url.absoluteString
                )
            } catch {
                // Swallow — the file just won't appear in the queue.
            }
        }
    }

    static func mimeType(for url: URL) -> String {
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        return type ?? "application/octet-stream"
    }
}

#endif
