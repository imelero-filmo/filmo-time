#if PREVIEW
import AppKit
import SwiftUI
import WidgetKit

/// Renders every widget size to PNG so the layout can be checked without the widget gallery.
@main
enum Preview {
    static let sizes: [(WidgetFamily, String, CGSize)] = [
        (.systemSmall, "small", CGSize(width: 170, height: 170)),
        (.systemMedium, "medium", CGSize(width: 364, height: 170)),
        (.systemLarge, "large", CGSize(width: 364, height: 382)),
        (.systemExtraLarge, "xl", CGSize(width: 780, height: 382)),
    ]

    static func main() {
        let dir = CommandLine.arguments.dropFirst().first ?? "."
        let demo = CommandLine.arguments.contains("--demo")
        Task { @MainActor in
            var entry = Entry(date: Date(), day: Demo.day, week: Demo.week(around: Date()))
            if !demo, let key = KeyStore.read() {
                let api = DeskTimeAPI(key: key)
                do {
                    entry = Entry(date: Date(), day: DayData.parse(try await api.get("employee", date: Date())),
                                  week: try await api.week(around: Date()))
                } catch { print("error: \(error)") }
            }
            for dark in [false, true] {
                for (family, name, size) in sizes {
                    let view = DeskTimeContent(entry: entry, family: family)
                        .padding(16)
                        .frame(width: size.width, height: size.height)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(nsColor: dark ? NSColor(white: 0.13, alpha: 1) : .white)))
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .padding(10)
                    let r = ImageRenderer(content: view)
                    r.scale = 2
                    let path = "\(dir)/\(name)\(dark ? "-dark" : "").png"
                    if let t = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
            print("ok")
            exit(0)
        }
        RunLoop.main.run()
    }
}
#endif
