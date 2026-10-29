import AppKit
import Foundation
import SwiftUI

// MARK: - API key storage

/// Stores the key in a file only the user can read. The Keychain is not used:
/// an ad-hoc signed app gets a new identity on every build, so macOS kept
/// asking for Keychain access.
enum KeyStore {
    // The real home, not the sandbox container, so the widget extension finds it too.
    static let fileURL = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir))
        .appendingPathComponent("Library/Application Support/DeskTimeWidget/apikey")
    private static var cached: String?

    static func read() -> String? {
        if let cached { return cached }
        let key = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cached = key?.isEmpty == false ? key : nil
        return cached
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try Data(key.utf8).write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            cached = key
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Model

enum AppKind: Int, CaseIterable, Identifiable {
    case productive = 1, neutral = 0, unproductive = -1
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .productive: "Productivas"
        case .neutral: "Neutrales"
        case .unproductive: "Improductivas"
        }
    }
    var color: Color {
        switch self {
        case .productive: Theme.green
        case .neutral: Color.secondary
        case .unproductive: Theme.red
        }
    }
}

struct AppUsage: Identifiable {
    let id: String
    let name: String
    let isWeb: Bool
    let seconds: Double
    let kind: AppKind
}

struct ProjectUsage: Identifiable {
    let id = UUID()
    let title: String
    let task: String?
    let seconds: Double
}

struct DayData {
    var name = ""
    var isOnline = false
    var arrived: String?   // "HH:mm"
    var left: String?
    var late = false
    var productive: Double = 0
    var desktime: Double = 0
    var atWork: Double = 0
    var offline: Double = 0
    var productivity: Double = 0
    var efficiency: Double = 0
    var workStarts: String?  // "HH:mm"
    var workEnds: String?
    var profileURL: URL?
    var apps: [AppUsage] = []
    var projects: [ProjectUsage] = []
    var activeProject: ProjectUsage?

    func apps(_ kind: AppKind) -> [AppUsage] { apps.filter { $0.kind == kind } }
    func total(_ kind: AppKind) -> Double { apps(kind).reduce(0) { $0 + $1.seconds } }

    static func parse(_ j: [String: Any]) -> DayData {
        var d = DayData()
        d.name = j["name"] as? String ?? ""
        d.isOnline = bool(j["isOnline"])
        d.arrived = hhmm(j["arrived"])
        d.left = hhmm(j["left"])
        d.late = bool(j["late"])
        d.productive = num(j["productiveTime"])
        d.desktime = num(j["desktimeTime"])
        d.atWork = num(j["atWorkTime"])
        d.offline = num(j["offlineTime"])
        d.productivity = num(j["productivity"])
        d.efficiency = num(j["efficiency"])
        d.workStarts = (j["work_starts"] as? String).map { String($0.prefix(5)) }
        d.workEnds = (j["work_ends"] as? String).map { String($0.prefix(5)) }
        d.profileURL = (j["profileUrl"] as? String).flatMap(URL.init(string:))

        if let groups = j["apps"] as? [String: Any] {
            for (k, v) in groups {
                guard let kind = AppKind(rawValue: Int(k) ?? 0), let entries = v as? [String: Any] else { continue }
                for (key, raw) in entries {
                    guard let e = raw as? [String: Any] else { continue }
                    d.apps.append(AppUsage(
                        id: "\(k)-\(key)",
                        name: (e["name"] as? String) ?? (e["app"] as? String) ?? key,
                        isWeb: (e["type"] as? String) == "web",
                        seconds: num(e["duration"]),
                        kind: kind))
                }
            }
            d.apps.sort { $0.seconds > $1.seconds }
        }
        if let ps = j["projects"] as? [[String: Any]] {
            d.projects = ps.compactMap(project).sorted { $0.seconds > $1.seconds }
        }
        if let ap = j["activeProject"] as? [String: Any] {
            d.activeProject = project(ap)
        } else if let ap = (j["activeProject"] as? [[String: Any]])?.first {
            d.activeProject = project(ap)
        }
        return d
    }

    private static func project(_ p: [String: Any]) -> ProjectUsage? {
        guard let title = p["project_title"] as? String, !title.isEmpty else { return nil }
        return ProjectUsage(title: title, task: p["task_title"] as? String, seconds: num(p["duration"]))
    }
}

struct WeekDay: Identifiable {
    var id: Date { date }
    let date: Date
    var productive: Double = 0
    var desktime: Double = 0
    var productivity: Double = 0
    var efficiency: Double = 0
    var isFuture = false
    var label: String { Fmt.weekdayShort(date) }
}

func num(_ v: Any?) -> Double {
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? 0 }
    return 0
}

func bool(_ v: Any?) -> Bool {
    if let b = v as? Bool { return b }
    if let n = v as? NSNumber { return n.boolValue }
    return false
}

/// "2026-10-29 15:03:00" -> "15:03"; DeskTime sends `false` when there is no value.
func hhmm(_ v: Any?) -> String? {
    guard let s = v as? String, s.count >= 16 else { return nil }
    return String(s.dropFirst(11).prefix(5))
}

func minutes(_ hhmm: String?) -> Double? {
    guard let parts = hhmm?.split(separator: ":"), parts.count >= 2,
          let h = Double(parts[0]), let m = Double(parts[1]) else { return nil }
    return h * 60 + m
}

// MARK: - Formatting

enum Fmt {
    static let es = Locale(identifier: "es_ES")

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    static func percent(_ v: Double) -> String {
        v >= 10 || v == 0 ? "\(Int(v.rounded()))%" : String(format: "%.1f%%", v)
    }

    static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func longDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = es
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: d).capitalizedFirst
    }

    static func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = es
        f.dateFormat = "EEE"
        return f.string(from: d).replacingOccurrences(of: ".", with: "").capitalizedFirst
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

enum Theme {
    static let green = Color(red: 0.20, green: 0.74, blue: 0.42)
    static let red = Color(red: 0.93, green: 0.30, blue: 0.30)
    static let orange = Color(red: 0.98, green: 0.62, blue: 0.20)
    /// Filmo is black and white: black #0B0B0C on light backgrounds, white #F5F5F2 on dark ones.
    static let brand = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF2 / 255, alpha: 1)
            : NSColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255, alpha: 1)
    })
    /// Text drawn on top of `brand`.
    static let onBrand = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255, alpha: 1)
            : NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF2 / 255, alpha: 1)
    })

    static func score(_ v: Double) -> Color {
        v >= 70 ? green : v >= 40 ? orange : red
    }
}

// MARK: - API

enum APIError: LocalizedError {
    case noKey, unauthorized, http(Int, String?)
    var errorDescription: String? {
        switch self {
        case .noKey: "Falta tu API key de DeskTime."
        case .unauthorized: "DeskTime ha rechazado la API key."
        case .http(let code, let msg): msg ?? "DeskTime respondió con un error (\(code))."
        }
    }
}

struct DeskTimeAPI {
    let key: String

    func get(_ path: String, date: Date) async throws -> [String: Any] {
        var c = URLComponents(string: "https://desktime.com/api/v2/json/\(path)")!
        c.queryItems = [URLQueryItem(name: "date", value: Fmt.ymd(date))]
        var req = URLRequest(url: c.url!)
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if code == 401 || code == 403 { throw APIError.unauthorized }
        let message = (obj?["error"] as? [String: Any])?["description"] as? String
            ?? obj?["error"] as? String
        guard code == 200, let obj, obj["error"] == nil else { throw APIError.http(code, message) }
        return obj
    }
}

extension DeskTimeAPI {
    /// Monday-to-Sunday summary of the week containing `around`.
    func week(around: Date) async throws -> [WeekDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: around)!.start
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let now = Date()
        return try await withThrowingTaskGroup(of: WeekDay.self) { group in
            for d in days {
                group.addTask {
                    if d > now { return WeekDay(date: d, isFuture: true) }
                    let j = try await get("employee/basic", date: d)
                    return WeekDay(date: d,
                                   productive: num(j["productiveTime"]),
                                   desktime: num(j["desktimeTime"]),
                                   productivity: num(j["productivity"]),
                                   efficiency: num(j["efficiency"]))
                }
            }
            var out: [WeekDay] = []
            for try await w in group { out.append(w) }
            return out.sorted { $0.date < $1.date }
        }
    }
}

// MARK: - Branding

enum AppInfo {
    /// Display name set by build.sh, so renaming the app needs no code change.
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Filmo Time"

    /// The Filmo "F" symbol as a template image, tinted by whatever draws it.
    static let symbol: NSImage? = {
        guard let url = Bundle.main.url(forResource: "filmo-simbolo", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }()
}

struct BrandMark: View {
    var height: CGFloat = 12
    var body: some View {
        if let img = AppInfo.symbol {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: height)
        } else {
            Image(systemName: "chart.bar.fill").font(.system(size: height * 0.85, weight: .bold))
        }
    }
}

// MARK: - Insights

struct Insight: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let text: String
}

enum Insights {
    static func make(day d: DayData, isToday: Bool) -> [Insight] {
        var out: [Insight] = []
        if d.desktime == 0 {
            return [Insight(icon: "moon.zzz.fill", color: .secondary, text: "Sin actividad registrada este día.")]
        }
        if d.late, let a = d.arrived {
            let starts = d.workStarts.map { "; tu jornada empieza a las " + $0 } ?? ""
            out.append(Insight(icon: "clock.badge.exclamationmark", color: Theme.red,
                               text: "Llegaste a las \(a)\(starts)."))
        }
        if d.efficiency > 0, d.efficiency < 100 {
            let target = d.productive / (d.efficiency / 100)
            let left = target - d.productive
            out.append(Insight(icon: "target", color: Theme.brand,
                               text: isToday
                                   ? "Te faltan \(Fmt.duration(left)) productivos para el 100 % de eficacia (objetivo de \(Fmt.duration(target)))."
                                   : "Faltaron \(Fmt.duration(left)) productivos para el objetivo de \(Fmt.duration(target))."))
        }
        let unprod = d.total(.unproductive)
        if unprod >= 60 {
            let top = d.apps(.unproductive).first
            out.append(Insight(icon: "exclamationmark.triangle.fill", color: Theme.orange,
                               text: "\(Fmt.duration(unprod)) en apps improductivas" + (top.map { ", sobre todo " + $0.name } ?? "") + "."))
        }
        if let top = d.apps(.productive).first, d.productive > 0 {
            let share = top.seconds / d.productive * 100
            out.append(Insight(icon: "star.fill", color: Theme.green,
                               text: "\(top.name) es tu app principal: \(Fmt.duration(top.seconds)), el \(Int(share.rounded())) % del tiempo productivo."))
        }
        if d.productivity >= 80 {
            out.append(Insight(icon: "flame.fill", color: Theme.orange,
                               text: "Buen foco: el \(Fmt.percent(d.productivity)) de tu tiempo frente al ordenador es productivo."))
        }
        return Array(out.prefix(3))
    }
}

// MARK: - Demo data (mirrors the real page, for previews without a key)

enum Demo {
    static var day: DayData {
        var d = DayData()
        d.name = "Tu nombre"
        d.isOnline = true
        d.arrived = "15:03"
        d.late = true
        d.productive = 41 * 60
        d.desktime = 51 * 60
        d.atWork = 61 * 60
        d.productivity = 80.13
        d.efficiency = 7.67
        d.workStarts = "09:00"
        d.workEnds = "18:00"
        d.profileURL = URL(string: "https://desktime.com/app/my")
        let p: [(String, Double, Bool)] = [("Claude", 31 * 60, false), ("localhost", 5 * 60, true),
            ("demo.filmo.io", 2 * 60, true), ("Finder", 27, false), ("DeskTime", 21, false),
            ("github.com", 13, true), ("portal-demo.filmo.io", 6, true), ("claude.ai", 5, true), ("mail.google.com", 2, true)]
        let n: [(String, Double, Bool)] = [("desktime.com", 6 * 60, true), ("ZapFast", 2 * 60, false),
            ("Ajustes del Sistema", 50, false), ("Centro de notificaciones", 9, false)]
        d.apps = p.map { AppUsage(id: "p\($0.0)", name: $0.0, isWeb: $0.2, seconds: $0.1, kind: .productive) }
            + n.map { AppUsage(id: "n\($0.0)", name: $0.0, isWeb: $0.2, seconds: $0.1, kind: .neutral) }
        return d
    }

    static func week(around date: Date) -> [WeekDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: date)!.start
        let sample: [(Double, Double, Double)] = [(5.9, 7.1, 83), (6.4, 7.6, 84), (4.8, 6.5, 74), (0.68, 0.85, 80)]
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            guard i < sample.count else { return WeekDay(date: d, isFuture: d > Date()) }
            let s = sample[i]
            return WeekDay(date: d, productive: s.0 * 3600, desktime: s.1 * 3600, productivity: s.2, efficiency: s.0 / 9 * 100)
        }
    }
}

