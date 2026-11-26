import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RoweCore

/// Renders the local space/profile avatar photo (decoded from base64) or a clean monogram fallback.
struct SpaceAvatarView: View {
    let space: Space
    let size: CGFloat
    let cornerRadius: CGFloat

    init(space: Space, size: CGFloat = 24, cornerRadius: CGFloat = 7) {
        self.space = space
        self.size = size
        self.cornerRadius = cornerRadius
    }

    private var decodedImage: NSImage? {
        guard let b64 = space.avatarImageBase64,
              let data = Data(base64Encoded: b64) else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        ZStack {
            if let nsImage = decodedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#EDE7DA"), Color(hex: "#D2CBB9")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(space.name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "#1F2225"))
                    )
            }
        }
    }

    /// Opens a native macOS image picker and returns a compact 256px JPEG base64 string for fast local storage.
    @MainActor
    static func pickAvatarImageBase64() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let sourceImage = NSImage(contentsOf: url) else {
            return nil
        }

        let maxDim: CGFloat = 256
        let srcSize = sourceImage.size
        guard srcSize.width > 0, srcSize.height > 0 else { return nil }
        let scale = min(1.0, maxDim / max(srcSize.width, srcSize.height))
        let targetSize = NSSize(width: (srcSize.width * scale).rounded(), height: (srcSize.height * scale).rounded())

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: srcSize),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) else {
            return nil
        }
        return jpeg.base64EncodedString()
    }
}
