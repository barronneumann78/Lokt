import SwiftUI
import UIKit
import ImageIO

struct ExerciseMediaView: View {
    let imageName: String?
    let placeholderSystemImageName: String
    var height: CGFloat
    var cornerRadius: CGFloat = 24
    var iconSize: CGFloat = 56
    var animateGIF: Bool = true
    var contentPadding: CGFloat = 12
    var maxContentWidth: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.primary.opacity(0.12),
                            Color.white.opacity(0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)

            mediaContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(contentPadding)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch mediaSource {
        case .gif(let url, let aspectRatio):
            GIFImageView(url: url, animated: true)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: maxContentWidth ?? .infinity, maxHeight: .infinity, alignment: .center)

        case .image(let uiImage):
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.medium)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxContentWidth ?? .infinity, maxHeight: .infinity, alignment: .center)

        case .placeholder:
            Image(systemName: placeholderSystemImageName)
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var mediaSource: ExerciseMediaSource {
        guard let imageName, !imageName.isEmpty else { return .placeholder }

        if let gifURL = ExerciseMediaCatalog.gifURL(for: imageName) {
            if animateGIF, let aspectRatio = GIFImageView.aspectRatio(from: gifURL) {
                return .gif(url: gifURL, aspectRatio: aspectRatio)
            }

            if let previewImage = GIFImageView.previewImage(from: gifURL) {
                return .image(previewImage)
            }
        }

        if let uiImage = UIImage(named: imageName) {
            return .image(uiImage)
        }

        return .placeholder
    }
}

struct GIFImageView: UIViewRepresentable {
    let url: URL
    var animated: Bool = true

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.image = animated ? Self.animatedImage(from: url) : Self.previewImage(from: url)
    }

    static func aspectRatio(from url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }

        return width / height
    }

    private static func animatedImage(from url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        var images: [UIImage] = []
        var totalDuration: Double = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }

            let frameDuration = frameDurationAtIndex(index, source: source)
            totalDuration += frameDuration
            images.append(UIImage(cgImage: cgImage))
        }

        guard !images.isEmpty else { return nil }
        return UIImage.animatedImage(with: images, duration: max(totalDuration, 0.1))
    }

    private static func frameDurationAtIndex(_ index: Int, source: CGImageSource) -> Double {
        let defaultFrameDuration = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultFrameDuration
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
        let frameDuration = unclampedDelay ?? delay ?? defaultFrameDuration

        return frameDuration < 0.02 ? defaultFrameDuration : frameDuration
    }

    static func previewImage(from url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

private enum ExerciseMediaSource {
    case gif(url: URL, aspectRatio: CGFloat)
    case image(UIImage)
    case placeholder
}
