import AppKit
import SwiftUI
import UserNotifications

// MARK: - Definitions

/// What an achievement can look at when it is evaluated (on every refresh of today).
struct AchievementContext {
    let today: DayData
    /// Today's data from the previous refresh, to notice what changed since then.
    let previous: DayData?
    let now: Date
    let week: [WeekDay]
    /// Worked hours and productivity of past days, for streaks.
    let history: [String: DaySummary]
    let popoverOpensToday: Int

    var calendar: Calendar { Calendar(identifier: .gregorian) }
    var hour: Int { calendar.component(.hour, from: now) }
    var minuteOfDay: Int { hour * 60 + calendar.component(.minute, from: now) }
    /// 1 = Sunday ... 7 = Saturday.
    var weekday: Int { calendar.component(.weekday, from: now) }
    var worked: Double { today.worked }

    /// Share of the worked time spent in apps matching `keys`.
    func share(_ keys: [String]) -> Double {
        worked > 0 ? today.seconds(matching: keys) / worked : 0
    }
}

struct DaySummary: Codable {
    var worked: Double
    var productivity: Double
}

struct Achievement: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let detail: String
    let check: (AchievementContext) -> Bool
}

private let hour: Double = 3600
/// Percentage achievements only count on a full day.
private let fullDay: Double = 7 * hour

enum AppKeys {
    static let claude = ["claude"]
    static let chatGPT = ["chatgpt", "chat.openai.com", "openai"]
    static let social = ["twitter", "x.com", "instagram", "facebook", "linkedin", "tiktok", "reddit",
                         "threads.net", "bsky.app", "mastodon"]
    static let mail = ["mail", "outlook", "spark", "superhuman"]
    static let meetings = ["zoom", "meet.google.com", "teams", "webex", "facetime", "around"]
    static let slack = ["slack"]
    static let code = ["terminal", "iterm", "xcode", "code", "cursor", "warp", "ghostty", "intellij",
                       "pycharm", "webstorm", "zed", "nova", "sublime"]
    static let figma = ["figma"]
    static let video = ["youtube", "netflix", "twitch", "primevideo", "disneyplus", "hbomax", "max.com"]
    static let music = ["spotify", "music"]
    static let amazon = ["amazon.es", "amazon.com", "amazon.co.uk"]
    static let deskTime = ["desktime.com"]
}

let allAchievements: [Achievement] = [
    // Yours
    Achievement(id: "ai-addict", emoji: "🤖", title: "AI addict",
                detail: "Más del 80 % de una jornada completa en Claude. ¿Quién trabaja para quién?") {
        $0.worked >= fullDay && $0.share(AppKeys.claude) > 0.8
    },
    Achievement(id: "aguafiestas", emoji: "🍺", title: "Aguafiestas…",
                detail: "Usaste Claude un primer viernes de mes después de las 19:00. Las cervezas no se beben solas.") { c in
        let firstFriday = c.weekday == 6 && c.calendar.component(.day, from: c.now) <= 7
        guard firstFriday, c.hour >= 19, let prev = c.previous else { return false }
        return c.today.seconds(matching: AppKeys.claude) > prev.seconds(matching: AppKeys.claude)
    },
    Achievement(id: "community-manager", emoji: "📱", title: "Community manager",
                detail: "Más de la mitad de una jornada completa en redes sociales. Seguro que era networking.") {
        $0.worked >= fullDay && $0.share(AppKeys.social) > 0.5
    },

    // Schedule
    Achievement(id: "madrugador", emoji: "🐓", title: "Madrugador",
                detail: "Empezaste antes de las 7:00. ¿Has dormido?") {
        (minutes($0.today.arrived) ?? 9999) < 7 * 60
    },
    Achievement(id: "buho", emoji: "🦉", title: "Búho nocturno",
                detail: "En línea pasadas las 23:00. El código compila mejor de noche, dicen.") {
        $0.today.isOnline && $0.hour >= 23
    },
    Achievement(id: "entrada-triunfal", emoji: "🐌", title: "Entrada triunfal",
                detail: "Llegaste tres horas tarde o más. Lo importante es llegar.") {
        guard let a = minutes($0.today.arrived), let s = minutes($0.today.workStarts) else { return false }
        return a - s >= 180
    },
    Achievement(id: "suizo", emoji: "⌚", title: "Puntualidad suiza",
                detail: "Empezaste a tu hora exacta, al minuto. Inquietante.") {
        guard let a = minutes($0.today.arrived), let s = minutes($0.today.workStarts) else { return false }
        return a == s
    },
    Achievement(id: "sin-casa", emoji: "🧟", title: "¿Tienes casa?",
                detail: "12 horas trabajadas en un día. Tu sofá te echa de menos.") {
        $0.worked >= 12 * hour
    },
    Achievement(id: "finde", emoji: "🏝️", title: "El finde es para débiles",
                detail: "Más de 4 horas trabajando en sábado o domingo.") {
        ($0.weekday == 1 || $0.weekday == 7) && $0.worked > 4 * hour
    },

    // Performance
    Achievement(id: "francotirador", emoji: "🎯", title: "Francotirador",
                detail: "98 % de productividad en una jornada completa. Ni un disparo fallado.") {
        $0.worked >= fullDay && $0.today.productivity >= 98
    },
    Achievement(id: "eficacia-100", emoji: "💯", title: "Eficacia de manual",
                detail: "Llegaste al 120 % de eficacia. DeskTime te mira con respeto.") {
        $0.today.efficiency >= 120
    },
    Achievement(id: "santo", emoji: "😇", title: "Santo varón",
                detail: "9 horas trabajadas y ni un minuto improductivo.") {
        $0.worked >= 9 * hour && $0.today.unproductiveTime < 60
    },
    Achievement(id: "lunes", emoji: "🦥", title: "Lunes, ¿eres tú?",
                detail: "Menos del 40 % de productividad en un lunes completo. Le pasa a cualquiera.") {
        $0.weekday == 2 && $0.worked >= fullDay && $0.today.productivity < 40
    },
    Achievement(id: "viernes-cohete", emoji: "🚀", title: "Viernes cohete",
                detail: "Un viernes de 10 horas al 90 % de productividad. ¿Y el afterwork?") {
        $0.weekday == 6 && $0.worked >= 10 * hour && $0.today.productivity >= 90
    },
    Achievement(id: "racha", emoji: "🔥", title: "En racha",
                detail: "10 jornadas completas seguidas por encima del 85 % de productividad.") { c in
        var streak = 0
        var day = c.calendar.startOfDay(for: c.now)
        for _ in 0..<30 {
            if let s = c.history[Fmt.ymd(day)], s.worked >= fullDay {
                guard s.productivity > 85 else { break }
                streak += 1
                if streak >= 10 { return true }
            } else if c.calendar.isDate(day, inSameDayAs: c.now) == false,
                      ![1, 7].contains(c.calendar.component(.weekday, from: day)) {
                break  // A weekday without a full day breaks the streak; weekends do not.
            }
            day = c.calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return false
    },
    Achievement(id: "maraton", emoji: "🏃", title: "Maratón",
                detail: "42,195 horas trabajadas en una semana, como los kilómetros de un maratón. Hidrátate.") {
        $0.week.reduce(0) { $0 + $1.desktime } >= 42.195 * hour
    },

    // Apps
    Achievement(id: "infiel", emoji: "💔", title: "Infiel",
                detail: "Más de media hora en Claude y en ChatGPT el mismo día. Claude lo sabe.") {
        $0.today.seconds(matching: AppKeys.claude) >= 30 * 60 && $0.today.seconds(matching: AppKeys.chatGPT) >= 30 * 60
    },
    Achievement(id: "inbox", emoji: "📬", title: "Inbox infinito",
                detail: "Más de 3 horas en el correo. Inbox cero algún día.") {
        $0.today.seconds(matching: AppKeys.mail) > 3 * hour
    },
    Achievement(id: "reunionitis", emoji: "🗣️", title: "Reunionitis",
                detail: "Más de 4 horas en videollamadas. Esto podría haber sido un email.") {
        $0.today.seconds(matching: AppKeys.meetings) > 4 * hour
    },
    Achievement(id: "slackero", emoji: "💬", title: "Slackero",
                detail: "Más de 3 horas en Slack. ¿Trabajas o chateas?") {
        $0.today.seconds(matching: AppKeys.slack) > 3 * hour
    },
    Achievement(id: "hacker", emoji: "💻", title: "Hacker de Hollywood",
                detail: "Más de 7 horas en el terminal o el editor. Estoy dentro.") {
        $0.today.seconds(matching: AppKeys.code) > 7 * hour
    },
    Achievement(id: "pixel", emoji: "🎨", title: "Pixel perfect",
                detail: "Más de 6 horas en Figma. Ese botón ya estaba centrado.") {
        $0.today.seconds(matching: AppKeys.figma) > 6 * hour
    },
    Achievement(id: "capitulo", emoji: "📺", title: "Solo un capítulo más",
                detail: "Más de 2 horas en YouTube, Netflix o Twitch. Era un tutorial, seguro.") {
        $0.today.seconds(matching: AppKeys.video) > 2 * hour
    },
    Achievement(id: "dj", emoji: "🎧", title: "DJ de oficina",
                detail: "Más de 5 horas con Spotify o Música. Pon algo bueno.") {
        $0.today.seconds(matching: AppKeys.music) > 5 * hour
    },
    Achievement(id: "prime", emoji: "🛒", title: "Prime time",
                detail: "Más de una hora en Amazon en horario laboral. Era material de oficina.") {
        $0.today.seconds(matching: AppKeys.amazon) > hour
    },
    Achievement(id: "turista", emoji: "🧭", title: "Turista digital",
                detail: "60 apps o webs distintas en un día. Concentración nivel ardilla.") {
        $0.today.apps.count >= 60
    },
    Achievement(id: "zen", emoji: "🧘", title: "Modo zen",
                detail: "Una jornada completa usando 4 apps como mucho. Paz interior.") {
        $0.worked >= fullDay && !$0.today.apps.isEmpty && $0.today.apps.count <= 4
    },

    // Meta
    Achievement(id: "hola", emoji: "👋", title: "Hola, mundo",
                detail: "Abriste Filmo Time por primera vez. Empieza la caza de logros.") { _ in true },
    Achievement(id: "miron", emoji: "👀", title: "Mirón compulsivo",
                detail: "Abriste el resumen 50 veces en un día. El tiempo no pasa más rápido por mirarlo.") {
        $0.popoverOpensToday >= 50
    },
    Achievement(id: "desktimeception", emoji: "🪞", title: "DeskTime-ception",
                detail: "Más de media hora en desktime.com mirando… tu DeskTime.") {
        $0.today.seconds(matching: AppKeys.deskTime) > 30 * 60
    },
]

extension DayData {
    /// Seconds in apps whose name matches any key. Keys with a dot are domains
    /// (exact or subdomain match); other keys match anywhere in the name.
    func seconds(matching keys: [String]) -> Double {
        apps.filter { app in
            let n = app.name.lowercased()
            return keys.contains { k in k.contains(".") ? (n == k || n.hasSuffix("." + k)) : n.contains(k) }
        }
        .reduce(0) { $0 + $1.seconds }
    }
}

// MARK: - Progress

@MainActor
final class Achievements: ObservableObject {
    struct State: Codable {
        var unlocked: [String: Date] = [:]
        var seen: Set<String> = []
        var history: [String: DaySummary] = [:]
        var opensDay = ""
        var opens = 0
    }

    @Published private(set) var state = State()
    private let persist: Bool
    private var previousToday: DayData?
    private static let url = KeyStore.fileURL.deletingLastPathComponent().appendingPathComponent("achievements.json")

    init(persist: Bool) {
        self.persist = persist
        if persist, let data = try? Data(contentsOf: Self.url),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            state = s
        }
    }

    var unseenCount: Int { state.unlocked.keys.filter { !state.seen.contains($0) }.count }

    func markAllSeen() {
        guard unseenCount > 0 else { return }
        state.seen.formUnion(state.unlocked.keys)
        save()
    }

    func popoverOpened() {
        let today = Fmt.ymd(Date())
        if state.opensDay != today { state.opensDay = today; state.opens = 0 }
        state.opens += 1
        save()
        if let t = previousToday { evaluate(today: t, week: []) }
    }

    /// Called with today's data on every refresh.
    func evaluate(today: DayData, week: [WeekDay]) {
        for d in week where !d.isFuture && d.desktime > 0 {
            state.history[Fmt.ymd(d.date)] = DaySummary(worked: d.desktime, productivity: d.productivity)
        }
        state.history[Fmt.ymd(Date())] = DaySummary(worked: today.worked, productivity: today.productivity)

        let ctx = AchievementContext(
            today: today, previous: previousToday, now: Date(), week: week, history: state.history,
            popoverOpensToday: state.opensDay == Fmt.ymd(Date()) ? state.opens : 0)
        var fresh: [Achievement] = []
        for a in allAchievements where state.unlocked[a.id] == nil && a.check(ctx) {
            state.unlocked[a.id] = Date()
            fresh.append(a)
        }
        previousToday = today
        save()
        for a in fresh { notify(a) }
    }

    /// Unlocks a sample set, for screenshots in demo mode.
    func loadDemo() {
        let ids = ["hola", "ai-addict", "madrugador", "infiel", "hacker", "reunionitis", "suizo"]
        for (i, id) in ids.enumerated() { state.unlocked[id] = Date().addingTimeInterval(Double(-i) * 86400) }
        state.seen = Set(ids.dropFirst(2))
    }

    private func save() {
        guard persist, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }

    private func notify(_ a: Achievement) {
        guard persist else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "🏆 Logro desbloqueado"
            content.subtitle = "\(a.emoji) \(a.title)"
            content.body = a.detail
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "achievement-\(a.id)", content: content, trigger: nil))
        }
    }
}

// MARK: - Tab

struct AchievementsTab: View {
    @ObservedObject var model: Achievements

    var body: some View {
        let unlocked = allAchievements
            .filter { model.state.unlocked[$0.id] != nil }
            .sorted { model.state.unlocked[$0.id]! > model.state.unlocked[$1.id]! }
        let locked = allAchievements.count - unlocked.count

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(unlocked.count)").font(.system(size: 22, weight: .semibold).monospacedDigit())
                    Text("de \(allAchievements.count) logros").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(locked) ocultos").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Theme.brand)
                            .frame(width: max(g.size.width * Double(unlocked.count) / Double(allAchievements.count), 4))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            // Snapshots cannot scroll: show one screenful.
            let shown = isSnapshotRender ? Array(unlocked.prefix(4)) : unlocked
            let hidden = isSnapshotRender ? min(locked, 1) : locked
            let rows = VStack(spacing: 4) {
                ForEach(shown) { a in
                    AchievementRow(achievement: a, date: model.state.unlocked[a.id], isNew: !model.state.seen.contains(a.id))
                }
                ForEach(0..<hidden, id: \.self) { _ in LockedRow() }
            }
            .padding(.horizontal, 12)
            if isSnapshotRender {
                rows
            } else {
                ScrollView { rows.padding(.bottom, 12) }.scrollIndicators(.never)
            }
        }
        // Opening the tab counts as having seen the new ones.
        .onDisappear { model.markAllSeen() }
    }
}

struct AchievementRow: View {
    let achievement: Achievement
    let date: Date?
    let isNew: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(achievement.emoji)
                .font(.system(size: 18))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(achievement.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if isNew { Circle().fill(Theme.brand).frame(width: 5, height: 5) }
                }
                Text(achievement.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let date {
                Text(date.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.es)))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(isNew ? 0.06 : 0)))
    }
}

struct LockedRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
                .background(Circle().strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            VStack(alignment: .leading, spacing: 1) {
                Text("???").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                Text("Logro oculto").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
    }
}

/// Tab title with a dot while there are unseen achievements.
struct AchievementsTabTitle: View {
    @ObservedObject var model: Achievements
    let selected: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text("Logros")
            if model.unseenCount > 0 {
                Text("\(model.unseenCount)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.brand))
                    .foregroundStyle(Theme.onBrand)
            }
        }
    }
}
