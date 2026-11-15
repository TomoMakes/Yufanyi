import CoreGraphics
import CoreImage

/// 没命中时，把同一帧换一种处理再认一次（2026-11-14）。
/// Money Parasite 的粉色描边细字，原图 129 句只对上 18 句；反色后 56 句，
/// 加上灰度提对比度、缩小一半共 80 句。只在预翻译没命中时用，
/// 结果必须整句对上库才采用，所以不会多出错配。
nonisolated enum LiveImageVariants {
    typealias Maker = @Sendable (CGImage) -> CGImage?

    /// 按实测救回句数排的先后
    static let all: [Maker] = [inverted, grayContrast, halved]

    private static let context = CIContext(options: [.cacheIntermediates: false])

    private static func render(_ image: CIImage) -> CGImage? {
        let extent = image.extent.integral
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        return context.createCGImage(image, from: extent)
    }

    /// 反色：深色底上的浅色描边字，反过来读得最准
    static let inverted: Maker = { image in
        render(CIImage(cgImage: image).applyingFilter("CIColorInvert"))
    }

    /// 去色并拉高对比度：彩色描边变成干净的黑白边
    static let grayContrast: Maker = { image in
        render(CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0, kCIInputContrastKey: 1.6,
        ]))
    }

    /// 缩小一半：字特别大时，细笔画缩小后反而连成整笔
    static let halved: Maker = { image in
        render(CIImage(cgImage: image).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: 0.5, kCIInputAspectRatioKey: 1.0,
        ]))
    }
}
