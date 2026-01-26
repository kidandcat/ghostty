import AppKit
import Combine
import SwiftUI

/// Manages thumbnail preview generation for terminal surfaces displayed in the tab sidebar.
/// Updates previews at a throttled rate (~5fps) to balance responsiveness with performance.
class TabPreviewManager: ObservableObject {
    /// Target FPS for preview updates (throttled to reduce GPU/CPU usage)
    static let targetFPS: Double = 5.0
    private let updateInterval: TimeInterval = 1.0 / targetFPS

    /// How long a terminal must be idle before it "needs attention" (in seconds)
    static let idleThreshold: TimeInterval = 5.0

    /// Preview images keyed by surface ID
    @Published private(set) var previews: [UUID: NSImage] = [:]

    /// Surfaces that need attention (idle for more than idleThreshold seconds)
    @Published private(set) var needsAttention: Set<UUID> = []

    /// The surfaces being tracked for preview generation
    private var surfaces: [Ghostty.SurfaceView] = []

    /// Timer for throttled updates
    private var updateTimer: Timer?

    /// Preview thumbnail size
    private(set) var thumbnailSize: CGSize

    /// Background queue for preview generation
    private let previewQueue = DispatchQueue(label: "com.ghostty.tabPreviewManager", qos: .userInitiated)

    /// Track surfaces that have never had a successful capture for retry logic
    private var failedCaptures: Set<UUID> = []

    /// Maximum retries for initial capture
    private let maxInitialRetries = 10

    /// Last content hash for each surface (to detect changes)
    private var lastContentHash: [UUID: Int] = [:]

    /// Timestamp of last content change for each surface
    private var lastChangeTime: [UUID: Date] = [:]

    /// Initializes the preview manager with a specified thumbnail width.
    /// - Parameter thumbnailWidth: The width of generated thumbnails in points. Height is calculated to maintain aspect ratio.
    init(thumbnailWidth: CGFloat = 180) {
        // Use 16:10 aspect ratio typical for terminal windows
        self.thumbnailSize = CGSize(width: thumbnailWidth, height: thumbnailWidth * 0.625)
    }

    /// Starts tracking the given surfaces for preview generation.
    /// - Parameter surfaces: The surfaces to generate previews for.
    func startTracking(surfaces: [Ghostty.SurfaceView]) {
        self.surfaces = surfaces
        startUpdateTimer()
        // Generate initial previews immediately
        updatePreviews()
    }

    /// Stops tracking all surfaces and invalidates the update timer.
    func stopTracking() {
        updateTimer?.invalidate()
        updateTimer = nil
        surfaces = []
    }

    /// Updates the list of tracked surfaces without restarting the timer.
    /// - Parameter surfaces: The new list of surfaces to track.
    func updateSurfaces(_ surfaces: [Ghostty.SurfaceView]) {
        self.surfaces = surfaces
        // Remove data for surfaces that no longer exist
        let surfaceIds = Set(surfaces.map { $0.id })
        previews = previews.filter { surfaceIds.contains($0.key) }
        lastContentHash = lastContentHash.filter { surfaceIds.contains($0.key) }
        lastChangeTime = lastChangeTime.filter { surfaceIds.contains($0.key) }
        needsAttention = needsAttention.intersection(surfaceIds)
    }

    /// Clears the "needs attention" state for a surface (e.g., when user selects it)
    func clearNeedsAttention(for surfaceId: UUID) {
        needsAttention.remove(surfaceId)
        // Reset the change time so it doesn't immediately trigger again
        lastChangeTime[surfaceId] = Date()
    }

    // MARK: - Private Methods

    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updatePreviews()
        }
        // Add to common run loop mode so timer fires during UI interactions
        if let timer = updateTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func updatePreviews() {
        // Capture surfaces on main thread since they're NSViews
        let surfacesToCapture = surfaces

        previewQueue.async { [weak self] in
            guard let self = self else { return }

            var newPreviews: [UUID: NSImage] = [:]
            var stillFailed: Set<UUID> = []
            var contentHashes: [UUID: Int] = [:]

            for surface in surfacesToCapture {
                // Must capture screenshot on main thread
                var screenshot: NSImage?
                DispatchQueue.main.sync {
                    // Try primary screenshot method
                    screenshot = surface.screenshot()

                    // If primary method fails and we don't have a preview yet, try fallback
                    if screenshot == nil && self.previews[surface.id] == nil {
                        screenshot = self.captureViaLayer(surface)
                    }
                }

                // Use full resolution screenshot for better quality
                if let fullImage = screenshot {
                    newPreviews[surface.id] = fullImage
                    // Compute a hash of the image to detect changes
                    contentHashes[surface.id] = self.computeImageHash(fullImage)
                } else if self.previews[surface.id] == nil {
                    // Track surfaces that still don't have a preview
                    stillFailed.insert(surface.id)
                }
            }

            DispatchQueue.main.async {
                let now = Date()
                var updatedNeedsAttention = self.needsAttention

                // Only update changed previews to minimize UI updates
                for (id, image) in newPreviews {
                    self.previews[id] = image
                    self.failedCaptures.remove(id)

                    // Check if content changed
                    let newHash = contentHashes[id] ?? 0
                    let oldHash = self.lastContentHash[id] ?? 0

                    if newHash != oldHash {
                        // Content changed - update hash and timestamp
                        self.lastContentHash[id] = newHash
                        self.lastChangeTime[id] = now
                        // No longer needs attention since it's active
                        updatedNeedsAttention.remove(id)
                    } else {
                        // Content unchanged - check if idle long enough
                        if let lastChange = self.lastChangeTime[id] {
                            let idleTime = now.timeIntervalSince(lastChange)
                            if idleTime >= Self.idleThreshold {
                                updatedNeedsAttention.insert(id)
                            }
                        } else {
                            // First time seeing this surface, initialize timestamp
                            self.lastChangeTime[id] = now
                        }
                    }
                }

                // Update needs attention set
                self.needsAttention = updatedNeedsAttention

                // Update failed captures set
                self.failedCaptures = stillFailed
            }
        }
    }

    /// Computes a simple hash of the image content for change detection
    private func computeImageHash(_ image: NSImage) -> Int {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return 0
        }

        // Sample a grid of pixels to create a fast hash
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0 && height > 0 else { return 0 }

        var hash = 0
        // Sample a 4x4 grid of pixels
        let stepX = max(1, width / 4)
        let stepY = max(1, height / 4)

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                if let color = bitmap.colorAt(x: x, y: y) {
                    // Combine RGB values into hash
                    let r = Int(color.redComponent * 255)
                    let g = Int(color.greenComponent * 255)
                    let b = Int(color.blueComponent * 255)
                    hash = hash &* 31 &+ r &+ g &+ b
                }
            }
        }

        return hash
    }

    /// Fallback capture method using layer rendering
    private func captureViaLayer(_ view: NSView) -> NSImage? {
        guard let layer = view.layer else { return nil }
        let size = view.bounds.size
        guard size.width > 0 && size.height > 0 else { return nil }

        let scale = view.window?.backingScaleFactor ?? 2.0
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }

        let cgContext = context.cgContext
        cgContext.scaleBy(x: scale, y: scale)
        layer.render(in: cgContext)

        let image = NSImage(size: size)
        image.addRepresentation(bitmapRep)
        return image
    }

    /// Creates a scaled-down thumbnail from the full-size image.
    /// - Parameter image: The source image to scale down.
    /// - Returns: A thumbnail image, or nil if scaling fails.
    private func createThumbnail(from image: NSImage) -> NSImage? {
        let sourceSize = image.size
        guard sourceSize.width > 0 && sourceSize.height > 0 else { return nil }

        // Calculate scale to fit within thumbnail size while maintaining aspect ratio
        let scaleX = thumbnailSize.width / sourceSize.width
        let scaleY = thumbnailSize.height / sourceSize.height
        let scale = min(scaleX, scaleY)

        let targetSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1.0
        )

        thumbnail.unlockFocus()
        return thumbnail
    }

    deinit {
        stopTracking()
    }
}
