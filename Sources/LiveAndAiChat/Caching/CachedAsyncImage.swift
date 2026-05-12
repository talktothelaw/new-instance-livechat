#if canImport(UIKit)
import SwiftUI
import UIKit
import CryptoKit

/// SwiftUI view that resolves a remote image URL through `ImageCache`
/// (memory + disk) instead of the always-refetching default
/// `AsyncImage`. Same call shape as `AsyncImage` so it slots in
/// wherever the SDK currently uses one.
///
/// Reasons we didn't just keep `AsyncImage`:
///   1. `AsyncImage` (iOS 15+) has no public cache hook — every view
///      hit refires URLSession.
///   2. We support iOS 14 baseline, and `AsyncImage` is iOS 15+.
///   3. The SDK renders the same images repeatedly (org logo on every
///      screen open, message thumbnails as the list re-virtualises,
///      full-screen viewer after grid tap) — re-fetching is wasteful.
///
/// Cached hits show the image on first frame with no placeholder
/// flicker, because the memory tier is checked synchronously before
/// the view's first render via `@State` seeded from a synchronous
/// `peek`.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {

    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    let onLoaded: (() -> Void)?

    @State private var resolved: UIImage?
    @State private var failed = false

    init(
        url: URL?,
        onLoaded: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.onLoaded = onLoaded
        self.content = content
        self.placeholder = placeholder
        // Synchronously peek the memory tier so already-cached images
        // render on the first frame with no placeholder flicker. NSCache
        // is thread-safe; reading from any context is fine.
        if let url, let cached = ImageCache.memoryPeek(url: url) {
            _resolved = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let image = resolved {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: url) { _ in
            resolved = nil
            failed = false
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        guard resolved == nil, !failed, let url else { return }
        Task {
            let image = await ImageCache.shared.image(for: url)
            await MainActor.run {
                if let image {
                    resolved = image
                    onLoaded?()
                } else {
                    failed = true
                }
            }
        }
    }
}

// MARK: - Synchronous memory peek

extension ImageCache {
    /// Non-actor synchronous lookup of the memory tier only. Used by
    /// `CachedAsyncImage`'s `init` to render cached images on the first
    /// frame. Disk and network lookups still happen on the actor.
    ///
    /// Safe to call from any thread — `NSCache` is documented thread-safe
    /// and `staticMemory` is a top-level `nonisolated` reference.
    static func memoryPeek(url: URL) -> UIImage? {
        let bytes = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: bytes)
        let key = digest.map { String(format: "%02x", $0) }.joined() as NSString
        return staticMemory.object(forKey: key)
    }

    /// Shared memory cache reference accessible without entering the
    /// actor. The actor's own `memory` property writes through to this
    /// same NSCache — we publish a non-isolated handle for fast reads.
    nonisolated static let staticMemory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()
}
#endif
