import SwiftUI
import AppKit

/// 截图渲染与保存。渲染 SwiftUI 视图为 PNG 落盘。
enum Screenshotter {
    enum Failure: Error, LocalizedError {
        case renderFailed
        case encodeFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed: return "渲染失败"
            case .encodeFailed: return "图片编码失败"
            case .writeFailed(let m): return "写入失败：\(m)"
            }
        }
    }

    /// 渲染视图为 PNG 并保存到目录，返回文件 URL。@MainActor：ImageRenderer 需主线程。
    @MainActor
    static func save<V: View>(_ view: V, toDirectory dir: String, scale: CGFloat = 2) throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let nsImage = renderer.nsImage else { throw Failure.renderFailed }
        guard let png = pngData(from: nsImage) else { throw Failure.encodeFailed }

        let url = URL(fileURLWithPath: dir).appendingPathComponent(fileName())
        do {
            try png.write(to: url)
        } catch {
            throw Failure.writeFailed(error.localizedDescription)
        }
        return url
    }

    /// NSImage → PNG Data。
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }

    /// 文件名：ccMonitor-yyyyMMdd-HHmmss.png
    private static func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "ccMonitor-\(f.string(from: Date())).png"
    }
}
