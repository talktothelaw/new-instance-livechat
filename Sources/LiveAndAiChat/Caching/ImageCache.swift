#if canImport(UIKit)
import Foundation
import UIKit
import CryptoKit

/// Two-tier image cache used by every SwiftUI surface in the SDK that
/// renders a remote image (header logo, message bubbles, composer
/// thumbnail chips, full-screen viewer).
///
/// L1: `NSCache<NSString, UIImage>` — process-local, RAM-only, auto-evicts
///     on system memory warnings.
/// L2: `<cachesDirectory>/liveandaichat-images/<sha256(url)>` — persists
///     across launches, survives backgrounding, lives in the
///     system-managed Caches directory so iOS can reclaim space if the
///     device gets tight. Bounded to ~50MB via LRU eviction by file mtime.
///
/// Lookup order: L1 → L2 → network. Misses re-populate both tiers.
/// All mutation is serialised through the actor so cache state stays
/// consistent under SwiftUI's heavy concurrent rendering.
public actor ImageCache {

    public static let shared = ImageCache()

    /// Memory cache. Shared with the synchronous `memoryPeek` API in
    /// `CachedAsyncImage.swift` so a cached image renders on first
    /// frame without entering the actor. NSCache itself is thread-safe.
    private let memory: NSCache<NSString, UIImage> = ImageCache.staticMemory
    private let cacheDir: URL
    /// Bytes. iOS will purge `caches/` under storage pressure; this is
    /// our voluntary upper bound to keep the directory tidy.
    private let maxDiskBytes: Int64 = 50 * 1024 * 1024  // 50 MiB
    private var evictionPending = false

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDir = caches.appendingPathComponent("liveandaichat-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Best-effort image fetch with caching. Returns nil on any failure
    /// (bad URL, network error, undecodable response). Callers display a
    /// placeholder for nil.
    public func image(for url: URL) async -> UIImage? {
        let key = Self.key(for: url)
        let nsKey = key as NSString

        if let img = memory.object(forKey: nsKey) {
            return img
        }

        let diskURL = cacheDir.appendingPathComponent(key)
        if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
            memory.setObject(img, forKey: nsKey, cost: data.count)
            // Touch mtime so the LRU eviction sees this entry as recently used.
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: diskURL.path
            )
            return img
        }

        // Network fetch — out of band of the actor would be preferable for
        // throughput, but the actor isolation here is fine because the
        // expensive part (URLSession data fetch) is already concurrent
        // inside URLSession; we only block on actor reentry to write the
        // result.
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let img = UIImage(data: data) else { return nil }
            memory.setObject(img, forKey: nsKey, cost: data.count)
            try? data.write(to: diskURL, options: .atomic)
            scheduleDiskEviction()
            return img
        } catch {
            return nil
        }
    }

    /// Drop both tiers entirely. Exposed for a future "clear cache"
    /// affordance in host settings UIs.
    public func clear() async {
        memory.removeAllObjects()
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for url in contents { try? fm.removeItem(at: url) }
        }
    }

    // MARK: - Internals

    private static func key(for url: URL) -> String {
        let bytes = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Coalesced eviction trigger — fires at most once per 5s window
    /// from inside the actor. Cheap when under quota (single dir
    /// listing + size accumulation), only deletes when over.
    private func scheduleDiskEviction() {
        if evictionPending { return }
        evictionPending = true
        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await self?.evictDiskIfOver()
        }
    }

    private func evictDiskIfOver() {
        evictionPending = false
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var totalSize: Int64 = 0
        var entries: [(url: URL, mtime: Date, size: Int)] = []
        entries.reserveCapacity(contents.count)
        for url in contents {
            let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = res?.contentModificationDate ?? .distantPast
            let size = res?.fileSize ?? 0
            entries.append((url, mtime, size))
            totalSize += Int64(size)
        }
        guard totalSize > maxDiskBytes else { return }

        // LRU: drop oldest first until we're back under the limit.
        entries.sort { $0.mtime < $1.mtime }
        for entry in entries {
            if totalSize <= maxDiskBytes { break }
            try? fm.removeItem(at: entry.url)
            totalSize -= Int64(entry.size)
        }
    }
}
#endif
