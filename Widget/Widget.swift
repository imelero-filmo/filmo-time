import Charts
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    var day: DayData?
    var week: [WeekDay] = []
    var error: String?
    /// Sample data with no real data to show yet: drawn as grey placeholders.
    var redacted = false
}

struct Provider: TimelineProvider {
    /// macOS shows this while it redraws the widget (for example when switching
    /// desktops), so it must be the user's latest data, never the sample data.
    func placeholder(in context: Context) -> Entry {
        if let s = Snapshot.load() {
            return Entry(date: s.fetchedAt, day: s.day, week: s.week)
        }
        return Entry(date: Date(), day: Demo.day, week: Demo.week(around: Date()), redacted: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview {
            // The widget gallery shows the sample data.
            completion(Entry(date: Date(), day: Demo.day, week: Demo.week(around: Date())))
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let entry = await load()
            // Same 5-minute rhythm as the app; WidgetKit may stretch it to save battery.
            let minutes = entry.day?.isOnline == true ? 5 : 30
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(Double(minutes) * 60))))
        }
    }

    private func load() async -> Entry {
        // Prefer the app's latest fetch so every surface shows the same numbers.
        if let s = Snapshot.load(), Calendar.current.isDateInToday(s.fetchedAt),
           Date().timeIntervalSince(s.fetchedAt) < 15 * 60 {
            return Entry(date: s.fetchedAt, day: s.day, week: s.week)
        }
        // The app is not running: fetch directly.
        guard let key = KeyStore.read() else {
            return Entry(date: Date(), error: "Abre \(AppInfo.name) y pega tu API key.")
        }
        let api = DeskTimeAPI(key: key)
        do {
            async let day = api.get("employee", date: Date())
            async let week = api.week(around: Date())
            return Entry(date: Date(), day: DayData.parse(try await day), week: try await week)
        } catch {
            return Entry(date: Date(), error: error.localizedDescription)
        }
    }
}

// MARK: - Views

struct WidgetRoot: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    var body: some View { DeskTimeContent(entry: entry, family: family) }
}

struct DeskTimeContent: View {
    let entry: Entry
    let family: WidgetFamily

    var body: some View {
        Group {
            if let d = entry.day {
                switch family {
                case .systemSmall: SmallView(day: d)
                case .systemMedium: MediumView(day: d)
                case .systemExtraLarge: ExtraLargeView(day: d, week: entry.week, updated: entry.date)
                default: LargeView(day: d, week: entry.week, updated: entry.date)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Brand(online: false)
                    Spacer()
                    Image(systemName: "key.fill").foregroundStyle(Theme.brand)
                    Text(entry.error ?? "Sin datos").font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .redacted(reason: entry.redacted ? .placeholder : [])
        .widgetURL(entry.day?.profileURL ?? URL(string: "https://desktime.com/app/my"))
    }
}

struct Brand: View {
    let online: Bool
    var updated: Date?
    var body: some View {
        HStack(spacing: 5) {
            BrandMark(height: 11)
                .foregroundStyle(Theme.brand)
            Text(AppInfo.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if let updated {
                Text(Fmt.time(updated)).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Circle()
                .fill(online ? Theme.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
        }
    }
}

struct WRing: View {
    let value: Double
    var size: CGFloat = 44
    var line: CGFloat = 5
    var label: String?

    var body: some View {
        let color = Theme.brand
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: min(max(value / 100, 0.001), 1))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(Fmt.percent(value))
                .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .padding(line)
        }
        .frame(width: size, height: size)
    }
}

struct LabeledRing: View {
    let value: Double
    let title: String
    var size: CGFloat = 50
    var body: some View {
        VStack(spacing: 4) {
            WRing(value: value, size: size, line: 6)
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct BigTime: View {
    let day: DayData
    var size: CGFloat = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Tiempo trabajado").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(Fmt.duration(day.worked))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("\(Fmt.duration(day.productive)) productivo")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct Arrival: View {
    let day: DayData
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sunrise.fill").foregroundStyle(.secondary)
            Text(day.arrived ?? "—")
                .foregroundStyle(day.late ? Theme.red : .primary)
                .fontWeight(.semibold)
            if day.late { Text("tarde").foregroundStyle(Theme.red) }
        }
        .font(.system(size: 11, design: .rounded))
    }
}

struct SmallView: View {
    let day: DayData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Brand(online: day.isOnline)
            Spacer(minLength: 4)
            BigTime(day: day, size: 32)
            Spacer(minLength: 6)
            WorkBreakdown(day: day, legend: false, height: 5)
            Spacer(minLength: 6)
            Arrival(day: day)
        }
    }
}

struct MediumView: View {
    let day: DayData
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Brand(online: day.isOnline)
            }
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 12) {
                BigTime(day: day, size: 34)
                Spacer(minLength: 0)
                Arrival(day: day)
            }
            Spacer(minLength: 8)
            WorkBreakdown(day: day)
        }
    }
}

struct TopApps: View {
    let day: DayData
    let count: Int
    var bars = true

    var body: some View {
        let apps = Array(day.apps(.productive).prefix(count))
        let maxSec = apps.first?.seconds ?? 1
        VStack(alignment: .leading, spacing: bars ? 6 : 3) {
            ForEach(apps) { a in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: a.isWeb ? "globe" : "app.dashed")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(a.name).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Fmt.duration(a.seconds))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if bars {
                        GeometryReader { g in
                            Capsule().fill(Theme.brand.opacity(0.6))
                                .frame(width: max(g.size.width * a.seconds / maxSec, 3))
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
    }
}

struct LargeView: View {
    let day: DayData
    let week: [WeekDay]
    var updated = Date()
    var appCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Brand(online: day.isOnline, updated: updated)
            HStack(alignment: .center) {
                BigTime(day: day, size: 36)
                Spacer()
                LabeledRing(value: day.productivity, title: "Productividad", size: 50)
                LabeledRing(value: day.efficiency, title: "Eficacia", size: 50)
            }
            WorkBreakdown(day: day)
            HStack(spacing: 6) {
                stat("Llegada", day.arrived ?? "—", day.late ? Theme.red : .primary)
                stat("Salida", day.isOnline ? "En línea" : (day.left ?? "—"), .primary)
                stat("En el trabajo", Fmt.duration(day.atWork), .primary)
            }
            Text("APPS PRODUCTIVAS").font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            TopApps(day: day, count: appCount)
            if !week.isEmpty {
                HStack {
                    Text("ESTA SEMANA").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    Spacer()
                    Text("\(Fmt.duration(week.filter { !$0.isFuture }.reduce(0) { $0 + $1.desktime })) trabajado")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.secondary)
                WeekChart(week: week)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct WeekChart: View {
    let week: [WeekDay]
    var showAxis = false

    var body: some View {
        Chart(week) { d in
            BarMark(x: .value("Día", d.label), y: .value("Horas", d.productive / 3600))
                .foregroundStyle(Theme.brand.opacity(Calendar.current.isDateInToday(d.date) ? 1 : 0.4))
                .cornerRadius(3)
            BarMark(x: .value("Día", d.label), y: .value("Horas", max(d.desktime - d.productive, 0) / 3600))
                .foregroundStyle(Color.secondary.opacity(0.25))
                .cornerRadius(3)
        }
        .chartYAxis {
            if showAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let h = v.as(Double.self) {
                            Text(h > 0 && h < 1 ? "\(Int((h * 60).rounded()))m" : "\(Int(h))h").font(.system(size: 9))
                        }
                    }
                }
            }
        }
        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) } }
    }
}

struct ExtraLargeView: View {
    let day: DayData
    let week: [WeekDay]
    var updated = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            LargeView(day: day, week: [], updated: updated, appCount: 6)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                section("ESTA SEMANA", trailing: weekTotal)
                WeekChart(week: week, showAxis: true)
                    .frame(maxHeight: .infinity)
                section("RESUMEN", trailing: nil)
                ForEach(Insights.make(day: day, isToday: true)) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: i.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(i.color)
                            .frame(width: 14)
                        Text(i.text).font(.system(size: 11)).lineLimit(2)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(AppKind.allCases) { k in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(k.title).font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(Fmt.duration(day.total(k)))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(k == .neutral ? Color.primary : k.color)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var weekTotal: String {
        Fmt.duration(week.filter { !$0.isFuture }.reduce(0) { $0 + $1.productive })
    }

    private func section(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.5)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 10, weight: .semibold, design: .rounded)) }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Widget

struct DeskTimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DeskTimeWidget", provider: Provider()) { entry in
            WidgetRoot(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(AppInfo.name)
        .description("Tu tiempo productivo, productividad, eficacia y apps del día.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

#if !PREVIEW
@main
struct DeskTimeWidgets: WidgetBundle {
    var body: some Widget { DeskTimeWidget() }
}
#endif
