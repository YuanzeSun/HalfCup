//
//  HalfCupWidget.swift
//  HalfCupWidget
//
//  Created by Luca on 2026/5/20.
//

import SwiftUI
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HalfCupEntry {
        HalfCupEntry(date: Date(), configuration: ConfigurationAppIntent(), summary: .placeholder)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> HalfCupEntry {
        HalfCupEntry(date: Date(), configuration: configuration, summary: HalfCupComplicationSummary.make(for: configuration.mode, at: Date()))
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<HalfCupEntry> {
        let currentDate = Date()
        let entries = stride(from: 0, through: 12 * 60, by: 15).compactMap { minuteOffset in
            Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate).map { entryDate in
                HalfCupEntry(
                    date: entryDate,
                    configuration: configuration,
                    summary: HalfCupComplicationSummary.make(for: configuration.mode, at: entryDate)
                )
            }
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<ConfigurationAppIntent>] {
        [
            AppIntentRecommendation(intent: .stargazing, description: "观星窗口"),
            AppIntentRecommendation(intent: .moonPlanet, description: "月亮/行星"),
            AppIntentRecommendation(intent: .training, description: "训练状态"),
            AppIntentRecommendation(intent: .stamina, description: "体力/睡眠债"),
            AppIntentRecommendation(intent: .hrv, description: "HRV 压力"),
            AppIntentRecommendation(intent: .caffeine, description: "咖啡因"),
            AppIntentRecommendation(intent: .barometer, description: "实时气压")
        ]
    }
}

struct HalfCupEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let summary: HalfCupComplicationSummary
}

struct HalfCupModeProvider: TimelineProvider {
    let mode: HalfCupComplicationMode

    func placeholder(in context: Context) -> HalfCupEntry {
        HalfCupEntry(date: Date(), configuration: .fixed(mode), summary: .make(for: mode, at: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (HalfCupEntry) -> Void) {
        let date = Date()
        completion(HalfCupEntry(date: date, configuration: .fixed(mode), summary: .make(for: mode, at: date)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HalfCupEntry>) -> Void) {
        let currentDate = Date()
        let entries = stride(from: 0, through: 12 * 60, by: 15).compactMap { minuteOffset in
            Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate).map { entryDate in
                HalfCupEntry(
                    date: entryDate,
                    configuration: .fixed(mode),
                    summary: HalfCupComplicationSummary.make(for: mode, at: entryDate)
                )
            }
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct HalfCupComplicationSummary: Equatable {
    let title: String
    let value: String
    let detail: String
    let symbolName: String
    let tint: Color
    let progress: Double?

    static let placeholder = HalfCupComplicationSummary(
        title: "HalfCup",
        value: "N/A",
        detail: "打开 app 获取数据",
        symbolName: "sparkles",
        tint: .cyan,
        progress: nil
    )

    static func make(for mode: HalfCupComplicationMode, at date: Date) -> HalfCupComplicationSummary {
        if let summary = HalfCupSharedWidgetStore.summary(for: mode) {
            return summary
        }

        switch mode {
        case .stargazing:
            return HalfCupComplicationSummary(
                title: "观星",
                value: "N/A",
                detail: "需 app 实时数据",
                symbolName: "sparkles",
                tint: .secondary,
                progress: nil
            )
        case .moonPlanet:
            return HalfCupComplicationSummary(
                title: "天体",
                value: "N/A",
                detail: "需真实星历源",
                symbolName: "moon.stars.fill",
                tint: .secondary,
                progress: nil
            )
        case .training:
            return HalfCupComplicationSummary(
                title: "训练",
                value: "N/A",
                detail: "需 app 同步",
                symbolName: "figure.run",
                tint: .secondary,
                progress: nil
            )
        case .stamina:
            return HalfCupComplicationSummary(
                title: "体力",
                value: "N/A",
                detail: "暂未实现",
                symbolName: "battery.75percent",
                tint: .secondary,
                progress: nil
            )
        case .hrv:
            return HalfCupComplicationSummary(
                title: "HRV",
                value: "N/A",
                detail: "需 app 同步",
                symbolName: "waveform.path.ecg",
                tint: .secondary,
                progress: nil
            )
        case .caffeine:
            return HalfCupComplicationSummary(
                title: "咖啡因",
                value: "N/A",
                detail: "需 app 同步",
                symbolName: "cup.and.saucer.fill",
                tint: .secondary,
                progress: nil
            )
        case .barometer:
            return HalfCupComplicationSummary(
                title: "气压",
                value: "N/A",
                detail: "需 app 实时传感器",
                symbolName: "barometer",
                tint: .secondary,
                progress: nil
            )
        }
    }
}

private enum HalfCupSharedWidgetStore {
    private static let suiteName = "group.com.luca.HalfCup"
    private static let updatedAtKey = "halfCup.widget.updatedAt"

    static func summary(for mode: HalfCupComplicationMode) -> HalfCupComplicationSummary? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.double(forKey: updatedAtKey) > 0
        else {
            return nil
        }

        let prefix = "halfCup.widget.\(mode.rawValue)"
        guard let value = validText(defaults.string(forKey: "\(prefix).value")) else {
            return nil
        }

        return HalfCupComplicationSummary(
            title: metadata(for: mode).title,
            value: value,
            detail: validText(defaults.string(forKey: "\(prefix).detail")) ?? "打开 app 更新",
            symbolName: metadata(for: mode).symbolName,
            tint: tint(for: mode, progress: progress(from: defaults, prefix: prefix)),
            progress: progress(from: defaults, prefix: prefix)
        )
    }

    private static func metadata(for mode: HalfCupComplicationMode) -> (title: String, symbolName: String) {
        switch mode {
        case .stargazing:
            return ("观星", "sparkles")
        case .moonPlanet:
            return ("天体", "moon.stars.fill")
        case .training:
            return ("训练", "figure.run")
        case .stamina:
            return ("体力", "battery.75percent")
        case .hrv:
            return ("HRV", "waveform.path.ecg")
        case .caffeine:
            return ("咖啡因", "cup.and.saucer.fill")
        case .barometer:
            return ("气压", "barometer")
        }
    }

    private static func tint(for mode: HalfCupComplicationMode, progress: Double?) -> Color {
        switch mode {
        case .stargazing:
            guard let progress else { return .cyan }
            return progress >= 0.7 ? .green : (progress >= 0.45 ? .yellow : .orange)
        case .moonPlanet:
            return .indigo
        case .training:
            guard let progress else { return .orange }
            return progress <= 0.95 ? .green : (progress <= 1 ? .yellow : .orange)
        case .stamina:
            guard let progress else { return .green }
            return progress >= 0.65 ? .green : (progress >= 0.35 ? .yellow : .orange)
        case .hrv:
            guard let progress else { return .pink }
            return progress <= 0.4 ? .green : (progress <= 0.7 ? .yellow : .orange)
        case .caffeine:
            guard let progress else { return .yellow }
            return progress <= 0.25 ? .green : (progress <= 0.5 ? .orange : .yellow)
        case .barometer:
            return .cyan
        }
    }

    private static func progress(from defaults: UserDefaults, prefix: String) -> Double? {
        guard let value = defaults.object(forKey: "\(prefix).progress") as? Double else {
            return nil
        }

        return min(max(value, 0), 1)
    }

    private static func validText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "--"
        else {
            return nil
        }

        return trimmed
    }
}

struct HalfCupWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HalfCupEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            rectangularView
        }
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(entry.summary.tint.opacity(0.18))

                Image(systemName: entry.summary.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.summary.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.summary.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(entry.summary.value)
                    .font(.headline.weight(.bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text(entry.summary.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
    }

    private var circularView: some View {
        Gauge(value: entry.summary.progress ?? 0.5, in: 0...1) {
            Image(systemName: entry.summary.symbolName)
        } currentValueLabel: {
            Text(shortValue)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.58)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(entry.summary.tint)
        .widgetAccentable()
    }

    private var inlineView: some View {
        Label("\(entry.summary.title) \(entry.summary.value)", systemImage: entry.summary.symbolName)
            .widgetAccentable()
    }

    private var cornerView: some View {
        VStack(spacing: 1) {
            Image(systemName: entry.summary.symbolName)
            Text(shortValue)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .widgetAccentable()
    }

    private var shortValue: String {
        if entry.summary.value.count <= 5 {
            return entry.summary.value
        }

        if let first = entry.summary.value.split(separator: " ").first {
            return String(first)
        }

        return entry.summary.title
    }
}

struct HalfCupWidget: Widget {
    let kind: String = "HalfCupWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HalfCup")
        .description("显示咖啡因、HRV、气压、训练状态、体力、观星窗口或月亮/行星摘要。")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct HalfCupStargazingWidget: Widget {
    let kind = "HalfCupStargazingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .stargazing)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("观星窗口")
        .description("显示今晚最佳观测时间、云量与月光条件。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

struct HalfCupMoonPlanetWidget: Widget {
    let kind = "HalfCupMoonPlanetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .moonPlanet)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("月亮/行星")
        .description("显示月亮高度方位、可见行星和下一次升起时间。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

struct HalfCupTrainingWidget: Widget {
    let kind = "HalfCupTrainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .training)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("训练状态")
        .description("显示训练负荷状态与近期趋势。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

struct HalfCupStaminaWidget: Widget {
    let kind = "HalfCupStaminaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .stamina)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("体力/睡眠债")
        .description("显示剩余体力估计和睡眠债。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

struct HalfCupHRVWidget: Widget {
    let kind = "HalfCupHRVWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .hrv)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HRV 压力")
        .description("显示当前 HRV 压力摘要。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

struct HalfCupCaffeineWidget: Widget {
    let kind = "HalfCupCaffeineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .caffeine)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("咖啡因")
        .description("显示咖啡因剩余量与低咖啡因时间。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

struct HalfCupBarometerWidget: Widget {
    let kind = "HalfCupBarometerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HalfCupModeProvider(mode: .barometer)) { entry in
            HalfCupWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("实时气压")
        .description("显示当前气压估计和趋势状态。")
        .supportedFamilies(HalfCupWidgetFamilies.all)
    }
}

private enum HalfCupWidgetFamilies {
    static let all: [WidgetFamily] = [
        .accessoryRectangular,
        .accessoryCircular,
        .accessoryInline,
        .accessoryCorner
    ]
}

private extension Date {
    func clockText(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

extension ConfigurationAppIntent {
    fileprivate static func fixed(_ mode: HalfCupComplicationMode) -> ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.mode = mode
        return intent
    }

    fileprivate static var stargazing: ConfigurationAppIntent {
        fixed(.stargazing)
    }

    fileprivate static var moonPlanet: ConfigurationAppIntent {
        fixed(.moonPlanet)
    }

    fileprivate static var training: ConfigurationAppIntent {
        fixed(.training)
    }

    fileprivate static var stamina: ConfigurationAppIntent {
        fixed(.stamina)
    }

    fileprivate static var hrv: ConfigurationAppIntent {
        fixed(.hrv)
    }

    fileprivate static var caffeine: ConfigurationAppIntent {
        fixed(.caffeine)
    }

    fileprivate static var barometer: ConfigurationAppIntent {
        fixed(.barometer)
    }
}

#Preview(as: .accessoryRectangular) {
    HalfCupWidget()
} timeline: {
    HalfCupEntry(date: .now, configuration: .stargazing, summary: .make(for: .stargazing, at: .now))
    HalfCupEntry(date: .now, configuration: .training, summary: .make(for: .training, at: .now))
}

#Preview(as: .accessoryCircular) {
    HalfCupWidget()
} timeline: {
    HalfCupEntry(date: .now, configuration: .moonPlanet, summary: .make(for: .moonPlanet, at: .now))
}
