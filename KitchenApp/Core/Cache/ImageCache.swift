import UIKit

// Two-level image cache: NSCache (memory) + file system (disk, TTL 7 days).
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskURL: URL
    private let ttl: TimeInterval = 7 * 24 * 3600

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskURL = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
        memory.countLimit = 100
        memory.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    func image(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        if let cached = memory.object(forKey: key as NSString) { return cached }
        return loadFromDisk(key: key)
    }

    func store(_ image: UIImage, for url: URL) {
        let key = cacheKey(for: url)
        memory.setObject(image, forKey: key as NSString, cost: imageCost(image))
        saveToDisk(image: image, key: key)
    }

    func prefetch(url: URL) async {
        guard image(for: url) == nil else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        store(img, for: url)
    }

    // MARK: - Disk

    private func cacheKey(for url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func diskPath(for key: String) -> URL {
        diskURL.appendingPathComponent(key)
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let path = diskPath(for: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < ttl,
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString, cost: imageCost(image))
        return image
    }

    private func saveToDisk(image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: diskPath(for: key))
    }

    private func imageCost(_ image: UIImage) -> Int {
        Int(image.size.width * image.size.height * image.scale * image.scale) * 4
    }
}
