import SwiftUI

enum ChatCardLayout {
    static let maxSize = CGSize(width: 400, height: 620)
    static let margin: CGFloat = 20

    static func frame(in area: CGRect, rightToLeft: Bool) -> CGRect {
        let width = max(0, min(maxSize.width, area.width - margin * 2))
        let height = max(0, min(maxSize.height, area.height - margin * 2))
        let x = rightToLeft ? area.minX + margin : area.maxX - margin - width
        return CGRect(x: x, y: area.maxY - margin - height, width: width, height: height)
    }
}

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import SafariServices

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
        var top = host
        while let presented = top.presentedViewController { top = presented }
        let presenter = ChatPresentingController(sdk: self)
        let traits = top.traitCollection
        if traits.horizontalSizeClass == .regular, traits.verticalSizeClass == .regular {
            presenter.modalPresentationStyle = .custom
            presenter.transitioningDelegate = presenter
        } else {
            presenter.modalPresentationStyle = .fullScreen
        }
        presentedChatController = presenter
        top.present(presenter, animated: true) { [weak self] in
            self?.openChat()
        }
        presenter.presentationController?.delegate = presenter
    }
}

extension LiveAndAiChat {
    func openSecurePage(_ url: URL) {
        guard let url = ElicitationForm.secureUrl(url.absoluteString) else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(SFSafariViewController(url: url), animated: true)
    }
}

/// Wraps ``ChatScreen`` in a `UIHostingController` and owns the
/// `UIDocumentPickerViewController` we hand off to for file picking.
/// Lives only as long as the chat is on screen.
@MainActor
final class ChatPresentingController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let sdk: LiveAndAiChat
    private var hosting: UIHostingController<AnyView>!
    private var dismissalHandled = false

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
                guard let self else { return }
                self.dismissalHandled = true
                self.sdk.markClosed(reason: .closeButton, initiator: .user)
                self.dismiss(animated: true)
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

    private func closeFromBackdrop() {
        guard !dismissalHandled else { return }
        dismissalHandled = true
        sdk.markClosed(reason: .gesture, initiator: .user)
        dismiss(animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        dismissalHandled = true
        sdk.markClosed(reason: .gesture, initiator: .user)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if (isBeingDismissed || isMovingFromParent || presentingViewController == nil), !dismissalHandled {
            dismissalHandled = true
            sdk.markClosed(reason: .hostNavigation, initiator: .host)
        }
    }

    private func presentDocumentPicker() {
        let types: [UTType] = [.png, .jpeg, .webP, .gif, .pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }
}

extension ChatPresentingController: UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        ChatPanelPresentationController(presentedViewController: presented, presenting: presenting) { [weak self] in
            self?.closeFromBackdrop()
        }
    }
}

@MainActor
final class ChatPanelPresentationController: UIPresentationController {
    private let onBackdropTap: () -> Void
    private let dimmingView = UIView()
    private let panelView = UIView()
    private var keyboardTop = CGFloat.greatestFiniteMagnitude

    init(presentedViewController: UIViewController, presenting: UIViewController?, onBackdropTap: @escaping () -> Void) {
        self.onBackdropTap = onBackdropTap
        super.init(presentedViewController: presentedViewController, presenting: presenting)
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = 0.35
        panelView.layer.shadowRadius = 30
        panelView.layer.shadowOffset = CGSize(width: 0, height: 12)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    override var presentedView: UIView? { panelView }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        var area = container.bounds.inset(by: container.safeAreaInsets)
        area.size.height = max(0, min(area.maxY, keyboardTop) - area.minY)
        return ChatCardLayout.frame(in: area, rightToLeft: container.effectiveUserInterfaceLayoutDirection == .rightToLeft)
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView, let content = presentedViewController.view else { return }
        dimmingView.frame = container.bounds
        dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmingView.alpha = 0
        container.insertSubview(dimmingView, at: 0)
        panelView.frame = frameOfPresentedViewInContainerView
        content.frame = panelView.bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.layer.cornerRadius = 16
        content.layer.cornerCurve = .continuous
        content.layer.masksToBounds = true
        panelView.addSubview(content)
        animateDimming(to: 1)
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        if !completed { dimmingView.removeFromSuperview() }
    }

    override func dismissalTransitionWillBegin() {
        animateDimming(to: 0)
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed { dimmingView.removeFromSuperview() }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        panelView.frame = frameOfPresentedViewInContainerView
    }

    private func animateDimming(to alpha: CGFloat) {
        guard let coordinator = presentedViewController.transitionCoordinator else {
            dimmingView.alpha = alpha
            return
        }
        coordinator.animate(alongsideTransition: { _ in self.dimmingView.alpha = alpha })
    }

    @objc private func backdropTapped() {
        onBackdropTap()
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let container = containerView,
              let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let top = container.convert(end, from: nil).minY
        keyboardTop = top < container.bounds.maxY ? top : .greatestFiniteMagnitude
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) {
            self.panelView.frame = self.frameOfPresentedViewInContainerView
        }
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
