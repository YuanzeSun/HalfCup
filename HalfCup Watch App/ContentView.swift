//
//  ContentView.swift
//  HalfCup Watch App
//
//  Created by Luca on 2026/5/20.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var healthStore = HealthMetricsStore()
    @State private var caffeineStore = CaffeineStore()
    @State private var astroStore = AstroStore()
    @State private var barometerStore = BarometerStore()
    @State private var trainingStore = TrainingMetricsStore()
    @State private var now = Date()
    @State private var isCustomizingModules = false
    @AppStorage("halfCup.dashboard.moduleOrder") private var moduleOrderRaw = DashboardModule.defaultOrderRaw
    private let refreshHealthOnAppear: Bool
    private let startSensorsOnAppear: Bool

    init(
        healthStore: HealthMetricsStore = HealthMetricsStore(),
        caffeineStore: CaffeineStore = CaffeineStore(),
        astroStore: AstroStore = AstroStore(),
        barometerStore: BarometerStore = BarometerStore(),
        trainingStore: TrainingMetricsStore = TrainingMetricsStore(),
        refreshHealthOnAppear: Bool = true,
        startSensorsOnAppear: Bool = true
    ) {
        _healthStore = State(initialValue: healthStore)
        _caffeineStore = State(initialValue: caffeineStore)
        _astroStore = State(initialValue: astroStore)
        _barometerStore = State(initialValue: barometerStore)
        _trainingStore = State(initialValue: trainingStore)
        self.refreshHealthOnAppear = refreshHealthOnAppear
        self.startSensorsOnAppear = startSensorsOnAppear
    }

    private var caffeineSnapshot: CaffeineSnapshot {
        caffeineStore.snapshot(at: now)
    }

    private var moduleOrder: [DashboardModule] {
        DashboardModule.decode(moduleOrderRaw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                DashboardToolbar {
                    isCustomizingModules = true
                }

                ForEach(moduleOrder) { module in
                    moduleContent(for: module)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(HalfCupBackground())
        .sheet(isPresented: $isCustomizingModules) {
            ModuleOrderView(orderRaw: $moduleOrderRaw)
        }
        .onAppear {
            if startSensorsOnAppear {
                barometerStore.resetSession()
                barometerStore.start()
            }
            astroStore.requestLocation()
            astroStore.refreshWeather()
            astroStore.refreshTide(at: now)
            astroStore.refresh(at: now)
            syncWidgetSnapshot(forceReload: true)
        }
        .onDisappear {
            barometerStore.stop()
        }
        .task {
            guard refreshHealthOnAppear else { return }

            while !Task.isCancelled {
                await healthStore.refresh()
                await trainingStore.refresh()
                astroStore.refreshWeather()
                astroStore.refreshTide()
                syncWidgetSnapshot(forceReload: true)
                try? await Task.sleep(for: .seconds(10 * 60))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
                astroStore.refresh(at: now)
                syncWidgetSnapshot()
            }
        }
    }

    @ViewBuilder
    private func moduleContent(for module: DashboardModule) -> some View {
        switch module {
        case .stress:
            StressOverviewCard(
                healthStore: healthStore,
                snapshot: healthStore.stressSnapshot,
                fatigueSnapshot: FatigueSnapshot(
                    healthStore: healthStore,
                    trainingSnapshot: trainingStore.snapshot
                ),
                isLoading: healthStore.isLoading,
                hrvHistoryTrend: healthStore.hrvHistoryTrend,
                heartRateHistoryTrend: healthStore.heartRateHistoryTrend
            )
        case .caffeine:
            CaffeineOverviewCard(
                store: caffeineStore,
                snapshot: caffeineSnapshot
            )
        case .quickDose:
            QuickDoseGrid(store: caffeineStore, now: $now) {
                syncWidgetSnapshot(forceReload: true)
            }
        case .barometer:
            BarometerCard(store: barometerStore)
        case .stargazing:
            StargazingCard(
                forecast: astroStore.forecast,
                locationStatusMessage: astroStore.locationStatusMessage,
                weatherStatusMessage: astroStore.weatherStatusMessage,
                tideStatusMessage: astroStore.tideStatusMessage
            )
        case .moonPlanet:
            MoonPlanetCard(forecast: astroStore.forecast)
        case .trainingStatus:
            TrainingStatusCard(
                snapshot: trainingStore.snapshot,
                statusMessage: trainingStore.statusMessage,
                isLoading: trainingStore.isLoading
            )
        case .trainingEffect:
            TrainingEffectCard(snapshot: trainingStore.snapshot)
        case .raceStamina:
            RaceStaminaCard(snapshot: trainingStore.snapshot)
        case .recovery:
            RecoveryReadinessCard(snapshot: trainingStore.snapshot)
        case .healthMetrics:
            HealthMetricGrid(readings: healthStore.dashboardReadings)
        case .dailyCalories:
            DailyTrendCard(
                title: "每日卡路里",
                value: dailyCalorieSummary,
                points: healthStore.dailyCalorieTrend,
                unitText: "kcal",
                tint: .orange,
                valueFormatter: { "\(Int($0.rounded()))" }
            )
        case .dailySleep:
            DailyTrendCard(
                title: "睡眠时间",
                value: dailySleepSummary,
                points: healthStore.dailySleepTrend,
                unitText: "h",
                tint: .indigo,
                valueFormatter: { String(format: "%.1f", $0) }
            )
        }
    }

    private var dailyCalorieSummary: String {
        guard let value = healthStore.dailyCalorieTrend.last?.value else { return "N/A" }
        return "\(Int(value.rounded())) kcal"
    }

    private var dailySleepSummary: String {
        guard let value = healthStore.dailySleepTrend.last?.value else { return "N/A" }
        return String(format: "%.1f h", value)
    }

    private func syncWidgetSnapshot(forceReload: Bool = false) {
        HalfCupSharedSnapshotStore.write(
            healthStore: healthStore,
            caffeineStore: caffeineStore,
            astroStore: astroStore,
            barometerStore: barometerStore,
            trainingStore: trainingStore,
            now: now,
            forceReload: forceReload
        )
    }

}

private extension FatigueSnapshot {
    var compactText: String {
        percent.map { "疲劳 \($0)%" } ?? "疲劳 N/A"
    }
}

private enum HalfCupSharedSnapshotStore {
    private static let suiteName = "group.com.luca.HalfCup"

    private enum Keys {
        static let updatedAt = "halfCup.widget.updatedAt"
        static let lastReloadAt = "halfCup.widget.lastReloadAt"
    }

    static func write(
        healthStore: HealthMetricsStore,
        caffeineStore: CaffeineStore,
        astroStore: AstroStore,
        barometerStore: BarometerStore,
        trainingStore: TrainingMetricsStore,
        now: Date,
        forceReload: Bool = false
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        let timestamp = Date().timeIntervalSince1970
        defaults.set(timestamp, forKey: Keys.updatedAt)

        writeHRV(from: healthStore, defaults: defaults)
        writeFatigue(from: healthStore, trainingStore: trainingStore, defaults: defaults)
        writeCaffeine(from: caffeineStore.snapshot(at: now), defaults: defaults)
        writeBarometer(from: barometerStore, defaults: defaults)
        writeAstro(from: astroStore.forecast, defaults: defaults)
        writeTraining(from: trainingStore.snapshot, defaults: defaults)

        let lastReloadAt = defaults.double(forKey: Keys.lastReloadAt)
        if forceReload || timestamp - lastReloadAt >= 10 * 60 {
            WidgetCenter.shared.reloadAllTimelines()
            defaults.set(timestamp, forKey: Keys.lastReloadAt)
        }
    }

    private static func writeHRV(from store: HealthMetricsStore, defaults: UserDefaults) {
        let hrvReading = store.readings.first { $0.kind == .hrv }
        let heartRateReading = store.readings.first { $0.kind == .heartRate }
        let hrvValue = metricValueText(from: hrvReading) ?? "N/A"
        let heartRateValue = metricValueText(from: heartRateReading) ?? "心率 N/A"
        let detail = "\(store.stressSnapshot.label) · \(heartRateValue)"

        writeSummary(
            mode: "hrv",
            value: hrvValue,
            detail: detail,
            progress: nil,
            defaults: defaults
        )
    }

    private static func writeFatigue(
        from healthStore: HealthMetricsStore,
        trainingStore: TrainingMetricsStore,
        defaults: UserDefaults
    ) {
        let snapshot = FatigueSnapshot(
            healthStore: healthStore,
            trainingSnapshot: trainingStore.snapshot
        )
        let value = snapshot.percent.map { "\($0)%" } ?? "N/A"
        let detail = "\(snapshot.levelText) · \(snapshot.factorTexts.joined(separator: " · "))"
        writeSummary(
            mode: "fatigue",
            value: value,
            detail: detail,
            progress: snapshot.percent.map { bounded(Double($0) / 100) },
            defaults: defaults
        )
    }

    private static func writeCaffeine(from snapshot: CaffeineSnapshot, defaults: UserDefaults) {
        writeSummary(
            mode: "caffeine",
            value: snapshot.remainingMilligramsText,
            detail: snapshot.lowCaffeineStatusText,
            progress: bounded(snapshot.remainingFraction),
            defaults: defaults
        )
    }

    private static func writeBarometer(from store: BarometerStore, defaults: UserDefaults) {
        guard let pressure = store.pressureHectopascals else {
            writeSummary(mode: "barometer", value: "N/A", detail: store.statusMessage, progress: nil, defaults: defaults)
            return
        }

        writeSummary(
            mode: "barometer",
            value: "\(store.pressureText) hPa",
            detail: "\(store.altitudeLabel) \(store.altitudeText)",
            progress: bounded((pressure - 980) / 70),
            defaults: defaults
        )
    }

    private static func writeAstro(from forecast: AstroForecast, defaults: UserDefaults) {
        let windowValue: String
        if let start = forecast.stargazingWindow.start, let end = forecast.stargazingWindow.end {
            windowValue = "\(start.clockText(calendar: forecast.site.solarCalendar))-\(end.clockText(calendar: forecast.site.solarCalendar))"
        } else {
            windowValue = forecast.stargazingWindow.summary
        }

        let cloudText = forecast.radarFactors.first { $0.id == "cloud" }?.valueText ?? "云量 N/A"
        writeSummary(
            mode: "stargazing",
            value: windowValue,
            detail: "\(cloudText) · 月光 \(forecast.moonIlluminationPercent)%",
            progress: bounded(Double(forecast.stargazingWindow.score) / 100),
            defaults: defaults
        )

        writeSummary(
            mode: "moonPlanet",
            value: forecast.planetComplicationLine,
            detail: forecast.moonComplicationLine,
            progress: bounded(Double(forecast.moonIlluminationPercent) / 100),
            defaults: defaults
        )
    }

    private static func writeTraining(from snapshot: TrainingSnapshot, defaults: UserDefaults) {
        let hasTrainingData = snapshot.status != .noData

        writeSummary(
            mode: "training",
            value: hasTrainingData ? snapshot.status.rawValue : "N/A",
            detail: snapshot.statusDetail,
            progress: snapshot.loadRatio > 0 ? bounded(snapshot.loadRatio / 1.6) : nil,
            defaults: defaults
        )

        writeSummary(
            mode: "stamina",
            value: hasTrainingData ? "\(snapshot.staminaPercent)%" : "N/A",
            detail: hasTrainingData ? snapshot.sleepDebtText : snapshot.statusDetail,
            progress: hasTrainingData ? bounded(Double(snapshot.staminaPercent) / 100) : nil,
            defaults: defaults
        )
    }

    private static func writeSummary(
        mode: String,
        value: String,
        detail: String,
        progress: Double?,
        defaults: UserDefaults
    ) {
        let prefix = "halfCup.widget.\(mode)"
        defaults.set(value, forKey: "\(prefix).value")
        defaults.set(detail, forKey: "\(prefix).detail")

        if let progress {
            defaults.set(progress, forKey: "\(prefix).progress")
        } else {
            defaults.removeObject(forKey: "\(prefix).progress")
        }
    }

    private static func metricValueText(from reading: HealthMetricReading?) -> String? {
        guard let reading, let value = normalized(reading.valueText) else { return nil }
        let unit = reading.unitText.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? value : "\(value) \(unit)"
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "--", trimmed != "N/A" else { return nil }
        return trimmed
    }

    private static func bounded(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private enum DashboardModule: String, CaseIterable, Identifiable {
    case stress
    case caffeine
    case quickDose
    case barometer
    case stargazing
    case moonPlanet
    case trainingStatus
    case trainingEffect
    case raceStamina
    case recovery
    case healthMetrics
    case dailyCalories
    case dailySleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stress: return "压力"
        case .caffeine: return "咖啡因"
        case .quickDose: return "快速记录"
        case .barometer: return "实时气压"
        case .stargazing: return "观星"
        case .moonPlanet: return "月亮/行星"
        case .trainingStatus: return "训练状态"
        case .trainingEffect: return "训练效果"
        case .raceStamina: return "表现/体力"
        case .recovery: return "清醒度"
        case .healthMetrics: return "健康数据"
        case .dailyCalories: return "每日卡路里"
        case .dailySleep: return "睡眠时间"
        }
    }

    var iconName: String {
        switch self {
        case .stress: return "waveform.path.ecg"
        case .caffeine: return "cup.and.saucer.fill"
        case .quickDose: return "plus.circle.fill"
        case .barometer: return "barometer"
        case .stargazing: return "sparkles"
        case .moonPlanet: return "moon.stars.fill"
        case .trainingStatus: return "figure.run"
        case .trainingEffect: return "bolt.heart.fill"
        case .raceStamina: return "flag.checkered"
        case .recovery: return "bed.double.fill"
        case .healthMetrics: return "heart.text.square.fill"
        case .dailyCalories: return "flame.fill"
        case .dailySleep: return "moon.zzz.fill"
        }
    }

    static let defaultOrder: [DashboardModule] = [
        .stress,
        .caffeine,
        .quickDose,
        .barometer,
        .stargazing,
        .moonPlanet,
        .trainingStatus,
        .trainingEffect,
        .raceStamina,
        .recovery,
        .healthMetrics,
        .dailyCalories,
        .dailySleep
    ]

    static var defaultOrderRaw: String {
        encode(defaultOrder)
    }

    static func decode(_ rawValue: String) -> [DashboardModule] {
        let decoded = rawValue
            .split(separator: ",")
            .compactMap { DashboardModule(rawValue: String($0)) }
        let missing = defaultOrder.filter { !decoded.contains($0) }
        let ordered = decoded + missing
        return ordered.isEmpty ? defaultOrder : ordered
    }

    static func encode(_ modules: [DashboardModule]) -> String {
        modules.map(\.rawValue).joined(separator: ",")
    }
}

private struct ModuleOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var orderRaw: String
    @State private var modules: [DashboardModule]

    init(orderRaw: Binding<String>) {
        _orderRaw = orderRaw
        _modules = State(initialValue: DashboardModule.decode(orderRaw.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(modules.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Label(modules[index].title, systemImage: modules[index].iconName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Button {
                            moveModule(at: index, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == modules.startIndex)

                        Button {
                            moveModule(at: index, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == modules.index(before: modules.endIndex))
                    }
                }

                Button {
                    modules = DashboardModule.defaultOrder
                    persist()
                } label: {
                    Label("恢复默认顺序", systemImage: "arrow.counterclockwise")
                }
            }
            .navigationTitle("模块顺序")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func moveModule(at index: Int, direction: Int) {
        let destination = index + direction
        guard modules.indices.contains(index), modules.indices.contains(destination) else { return }
        modules.swapAt(index, destination)
        persist()
    }

    private func persist() {
        orderRaw = DashboardModule.encode(modules)
    }
}

private struct DashboardToolbar: View {
    let onCustomizeModules: () -> Void

    var body: some View {
        HStack {
            Text("HalfCup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                onCustomizeModules()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("调整模块顺序")
        }
        .padding(.horizontal, 2)
    }
}

private struct FatigueSnapshot: Equatable {
    let percent: Int?
    let levelText: String
    let detailText: String
    let factorTexts: [String]
    let tint: Color

    init(healthStore: HealthMetricsStore, trainingSnapshot: TrainingSnapshot) {
        let readings = healthStore.readings
        let hrv = Self.value(for: .hrv, in: readings)
        let heartRate = Self.value(for: .heartRate, in: readings)
        let restingHeartRate = Self.value(for: .restingHeartRate, in: readings)
        let activeEnergy = Self.value(for: .activeEnergy, in: readings)
        let hrvHistory = healthStore.hrvHistoryTrend.map(\.value)
        let hrvBaseline = Self.average(hrvHistory.suffix(12))
        var weightedScore = 0.0
        var totalWeight = 0.0
        var factors: [String] = []

        if let hrv, let hrvBaseline, hrvBaseline > 0 {
            let hrvDrop = (hrvBaseline - hrv) / max(hrvBaseline, 1)
            let score = Self.bounded(hrvDrop / 0.35)
            weightedScore += score * 0.28
            totalWeight += 0.28
            factors.append(score >= 0.45 ? "HRV偏低" : "HRV正常")
        }

        if let heartRate, let restingHeartRate, restingHeartRate > 0 {
            let rise = (heartRate - restingHeartRate) / max(restingHeartRate, 1)
            let score = Self.bounded(rise / 0.35)
            weightedScore += score * 0.22
            totalWeight += 0.22
            factors.append(score >= 0.45 ? "心率偏高" : "心率平稳")
        }

        if trainingSnapshot.loadRatio > 0 {
            let score = Self.bounded((trainingSnapshot.loadRatio - 0.85) / 0.65)
            weightedScore += score * 0.18
            totalWeight += 0.18
            factors.append("负荷 \(trainingSnapshot.loadRatioText)")
        }

        if let sleepDebtHours = trainingSnapshot.sleepDebtHours {
            let score = Self.bounded(sleepDebtHours / 3.0)
            weightedScore += score * 0.18
            totalWeight += 0.18
            factors.append(sleepDebtHours < 0.5 ? "睡眠债低" : String(format: "睡眠债%.1fh", sleepDebtHours))
        }

        if let activeEnergy {
            let score = Self.bounded((activeEnergy - 350) / 650)
            weightedScore += score * 0.14
            totalWeight += 0.14
            factors.append(activeEnergy >= 350 ? "活动偏多" : "活动较低")
        }

        guard totalWeight >= 0.35 else {
            self.percent = nil
            self.levelText = "N/A"
            self.detailText = "需要 HRV/心率或训练数据"
            self.factorTexts = ["N/A"]
            self.tint = .secondary
            return
        }

        let percent = Int((weightedScore / totalWeight * 100).rounded())
        self.percent = percent

        switch percent {
        case 75...:
            self.levelText = "超高"
            self.tint = .red
        case 55..<75:
            self.levelText = "高"
            self.tint = .orange
        case 30..<55:
            self.levelText = "中"
            self.tint = .yellow
        default:
            self.levelText = "低"
            self.tint = .green
        }

        self.detailText = "疲劳 \(percent)%"
        self.factorTexts = Array(factors.prefix(3))
    }

    private static func value(for kind: HealthMetricKind, in readings: [HealthMetricReading]) -> Double? {
        guard let text = readings.first(where: { $0.kind == kind })?.valueText else { return nil }
        if text.hasSuffix("k"), let value = Double(text.dropLast()) {
            return value * 1_000
        }

        return Double(text)
    }

    private static func average(_ values: ArraySlice<Double>) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func bounded(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct TrainingStatusCard: View {
    let snapshot: TrainingSnapshot
    let statusMessage: String
    let isLoading: Bool

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("训练状态", systemImage: "figure.run")
                            .font(.headline.weight(.semibold))

                        Text(snapshot.status.rawValue)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(statusTint)

                        Text(snapshot.statusDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(snapshot.loadRatioText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("7d/28d")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusTint: Color {
        switch snapshot.status {
        case .productive, .peaking:
            return .green
        case .maintaining:
            return .cyan
        case .overreaching:
            return .orange
        case .detraining, .noData:
            return .secondary
        }
    }
}

private struct TrainingEffectCard: View {
    let snapshot: TrainingSnapshot

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("训练效果", systemImage: "bolt.heart.fill")
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Text(snapshot.primaryWorkoutEffect)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    EffectBar(title: snapshot.aerobicEffectText, value: effectValue(from: snapshot.aerobicEffectText), tint: .green)
                    EffectBar(title: snapshot.anaerobicEffectText, value: effectValue(from: snapshot.anaerobicEffectText), tint: .orange)
                }

            }
        }
    }

    private func effectValue(from text: String) -> Double {
        let parts = text.split(separator: " ")
        guard let valueText = parts.last, let value = Double(valueText) else { return 0 }
        return min(max(value / 5, 0), 1)
    }
}

private struct RaceStaminaCard: View {
    let snapshot: TrainingSnapshot

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Label("表现预测", systemImage: "flag.checkered")
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Text("\(snapshot.staminaPercent)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(staminaTint)
                        .monospacedDigit()
                }

                if snapshot.racePredictions.isEmpty {
                    Text("需要跑步或 VO2max 数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(snapshot.racePredictions) { prediction in
                            MetricPill(title: prediction.distance, value: prediction.timeText, tint: .cyan)
                        }
                    }
                }

                Text(snapshot.staminaDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var staminaTint: Color {
        switch snapshot.staminaPercent {
        case 75...:
            return .green
        case 45..<75:
            return .yellow
        default:
            return .orange
        }
    }
}

private struct RecoveryReadinessCard: View {
    let snapshot: TrainingSnapshot

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("清醒度", systemImage: "bed.double.fill")
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Text(snapshot.sleepDebtSummaryText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                HStack(spacing: 6) {
                    ForEach(snapshot.alertnessBlocks) { block in
                        VStack(spacing: 2) {
                            Text(block.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text("\(block.score)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(alertnessTint(block.score))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func alertnessTint(_ score: Int) -> Color {
        switch score {
        case 75...:
            return .green
        case 50..<75:
            return .yellow
        default:
            return .orange
        }
    }
}

private struct EffectBar: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            ProgressView(value: value)
                .tint(tint)
                .scaleEffect(x: 1, y: 1.35, anchor: .center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DailyTrendCard: View {
    let title: String
    let value: String
    let points: [HealthMetricPoint]
    let unitText: String
    let tint: Color
    let valueFormatter: (Double) -> String

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(value)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                DailyTrendLine(
                    points: points,
                    unitText: unitText,
                    tint: tint,
                    valueFormatter: valueFormatter
                )

                Text("30天 · 每日")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct BarometerCard: View {
    let store: BarometerStore

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(store.pressureText)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .monospacedDigit()

                            Text("hPa")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text("\(store.altitudeLabel) \(store.altitudeText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(store.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    TrendPanel(title: "实时", value: store.pressureText == "N/A" ? "N/A" : "\(store.pressureText) hPa") {
                        VStack(spacing: 4) {
                            PressureTrendLine(points: store.pressureTrend, tint: .blue)
                            AltitudeTrendLine(points: store.pressureTrend, tint: .green)
                        }
                    }

                    TrendPanel(title: "12h", value: "10min") {
                        VStack(spacing: 4) {
                            PressureTrendLine(points: store.historyTrend, tint: .cyan)
                            AltitudeTrendLine(points: store.historyTrend, tint: .mint)
                        }
                    }
                }

                Text("上方为气压，下方为海拔")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
    }
}

private struct StressOverviewCard: View {
    let healthStore: HealthMetricsStore
    let snapshot: HealthStressSnapshot
    let fatigueSnapshot: FatigueSnapshot
    let isLoading: Bool
    let hrvHistoryTrend: [HealthMetricPoint]
    let heartRateHistoryTrend: [HealthMetricPoint]

    init(
        healthStore: HealthMetricsStore,
        snapshot: HealthStressSnapshot,
        fatigueSnapshot: FatigueSnapshot,
        isLoading: Bool,
        hrvHistoryTrend: [HealthMetricPoint],
        heartRateHistoryTrend: [HealthMetricPoint]
    ) {
        self.healthStore = healthStore
        self.snapshot = snapshot
        self.fatigueSnapshot = fatigueSnapshot
        self.isLoading = isLoading
        self.hrvHistoryTrend = hrvHistoryTrend
        self.heartRateHistoryTrend = heartRateHistoryTrend
    }

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                    spacing: 6
                ) {
                    StressMetricTile(
                        title: "压力",
                        value: snapshot.label,
                        tint: snapshot.tint
                    )
                    StressMetricTile(
                        title: "疲劳",
                        value: fatigueSnapshot.percent.map { "\($0)%" } ?? "N/A",
                        tint: fatigueSnapshot.tint
                    )
                    StressMetricTile(
                        title: "HRV",
                        value: currentMetricValue(.hrv),
                        tint: .cyan
                    )
                    StressMetricTile(
                        title: "心率",
                        value: currentMetricValue(.heartRate),
                        tint: .pink
                    )
                }

                VStack(spacing: 4) {
                    HRVTrendLine(points: hrvHistoryTrend, tint: .cyan)
                    HRVTrendLine(points: heartRateHistoryTrend, tint: .pink)
                }

                Text("上方为 HRV，下方为心率")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func currentMetricValue(_ kind: HealthMetricKind) -> String {
        guard let reading = healthStore.readings.first(where: { $0.kind == kind }),
              reading.valueText != "N/A"
        else {
            return "N/A"
        }

        return reading.unitText.isEmpty ? reading.valueText : "\(reading.valueText) \(reading.unitText)"
    }
}

private struct StressMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StargazingCard: View {
    let forecast: AstroForecast
    let locationStatusMessage: String
    let weatherStatusMessage: String
    let tideStatusMessage: String

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("观星", systemImage: "sparkles")
                        .font(.headline.weight(.semibold))
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
                    spacing: 5
                ) {
                    ForEach(forecast.radarFactors) { factor in
                        RadarFactorPill(factor: factor)
                    }
                }

                HStack(spacing: 6) {
                    MetricPill(
                        title: "日落",
                        value: forecast.sunset?.clockText(calendar: forecast.site.solarCalendar) ?? "N/A",
                        tint: .orange
                    )

                    MetricPill(
                        title: "日出",
                        value: forecast.sunrise?.clockText(calendar: forecast.site.solarCalendar) ?? "N/A",
                        tint: .yellow
                    )
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 12, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(forecast.site.coordinateText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)

                        if !locationStatusMessage.isEmpty {
                            Text(locationStatusMessage)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)

                    Text(weatherStatusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text("光害 N/A")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)

                    Text(tideStatusMessage)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct MoonPlanetCard: View {
    let forecast: AstroForecast

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Label("月亮/行星", systemImage: "moon.stars.fill")
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Text(forecast.moonPhaseName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(forecast.moonDetailLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    MetricPill(
                        title: "月升",
                        value: forecast.moonRise?.clockText(calendar: forecast.site.solarCalendar) ?? "N/A",
                        tint: .indigo
                    )

                    MetricPill(
                        title: "月落",
                        value: forecast.moonSet?.clockText(calendar: forecast.site.solarCalendar) ?? "N/A",
                        tint: .cyan
                    )
                }

                if !forecast.visiblePlanets.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(forecast.visiblePlanets) { planet in
                            PlanetVisibilityRow(planet: planet, calendar: forecast.site.solarCalendar)
                        }
                    }
                } else {
                    Text("行星数据 N/A · \(forecast.moonComplicationLine)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct PlanetVisibilityRow: View {
    let planet: PlanetVisibility
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(planetTint)
                .frame(width: 14)

            Text(planet.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(planet.summaryText(calendar: calendar))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var planetTint: Color {
        switch planet.name {
        case "水星":
            return .gray
        case "金星":
            return .yellow
        case "火星":
            return .red
        case "木星":
            return .orange
        case "土星":
            return .brown
        default:
            return .indigo
        }
    }
}

private struct CaffeineOverviewCard: View {
    let store: CaffeineStore
    let snapshot: CaffeineSnapshot

    var body: some View {
        HalfCupCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Label("咖啡因", systemImage: "cup.and.saucer.fill")
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Text(snapshot.remainingMilligramsText)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.yellow)
                }

                CaffeineGaugeBar(
                    value: snapshot.remainingMilligrams,
                    maximum: CaffeineMetabolism.gaugeMaximumMilligrams,
                    threshold: CaffeineMetabolism.lowCaffeineThresholdMilligrams,
                    tint: caffeineTint
                )
                .frame(height: 18)

                Text(snapshot.lowCaffeineStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                MetricPill(
                    title: "今日",
                    value: "\(Int(snapshot.totalTodayMilligrams.rounded())) mg",
                    tint: .yellow
                )
            }
        }
    }

    private var caffeineTint: Color {
        switch snapshot.remainingFraction {
        case 0.5...:
            return .yellow
        case 0.25..<0.5:
            return .orange
        default:
            return .green
        }
    }
}

private struct CaffeineGaugeBar: View {
    let value: Double
    let maximum: Double
    let threshold: Double
    let tint: Color

    private var fillFraction: CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(max(value / maximum, 0), 1))
    }

    private var thresholdFraction: CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(max(threshold / maximum, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let markerX = min(max(width * thresholdFraction, 2), max(width - 2, 2))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.18))

                Capsule()
                    .fill(tint)
                    .frame(width: width * fillFraction)

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: proxy.size.height + 4)
                    .position(x: markerX, y: proxy.size.height / 2)
            }
        }
        .accessibilityLabel("咖啡因剩余量")
        .accessibilityValue("\(Int(value.rounded())) mg")
    }
}

private struct QuickDoseGrid: View {
    let store: CaffeineStore
    @Binding var now: Date
    let onDoseChanged: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("快速记录")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(CaffeinePreset.defaults) { preset in
                    Button {
                        now = Date()
                        store.add(preset, at: now)
                        onDoseChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.yellow)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)

                                Text("\(Int(preset.milligrams)) mg")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HealthMetricGrid: View {
    let readings: [HealthMetricReading]

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("健康数据")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(readings) { reading in
                    HealthMetricTile(reading: reading)
                }
            }
        }
    }
}

private struct HealthMetricTile: View {
    let reading: HealthMetricReading

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: reading.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(reading.tint)
                    .frame(width: 14)

                Text(reading.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(reading.valueText)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(reading.unitText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(reading.detailText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(reading.tint.opacity(reading.sampleDate == nil ? 0.7 : 1))
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HRVTrendLine: View {
    let points: [HealthMetricPoint]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.06))

                if points.count >= 2 {
                    Path { path in
                        let values = points.map(\.value)
                        let minValue = values.min() ?? 0
                        let maxValue = values.max() ?? 1
                        let range = max(maxValue - minValue, 1)
                        let dateRange = chartDateRange(for: points.map(\.date))

                        for (index, point) in points.enumerated() {
                            let x = chartX(
                                for: point.date,
                                in: dateRange,
                                width: geometry.size.width
                            )
                            let normalized = (point.value - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalized))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)

                    chartLabels(
                        top: "\(Int((points.map(\.value).max() ?? 0).rounded()))",
                        start: points.first?.date,
                        end: points.last?.date
                    )
                } else {
                    Path { path in
                        let y = geometry.size.height / 2
                        path.move(to: CGPoint(x: 6, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - 6, y: y))
                    }
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .frame(height: 34)
        .accessibilityLabel("HRV 趋势")
    }

    private func chartLabels(top: String, start: Date?, end: Date?) -> some View {
        ZStack {
            Text(top)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let start, let end, end.timeIntervalSince(start) > 60 {
                HStack {
                    Text(start.clockText())
                    Spacer(minLength: 0)
                    Text(end.clockText())
                }
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.bottom, 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private struct DailyTrendLine: View {
    let points: [HealthMetricPoint]
    let unitText: String
    let tint: Color
    let valueFormatter: (Double) -> String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.06))

                if points.count >= 2 {
                    Path { path in
                        let values = points.map(\.value)
                        let minValue = values.min() ?? 0
                        let maxValue = values.max() ?? 1
                        let range = max(maxValue - minValue, max(maxValue * 0.08, 1))
                        let dateRange = chartDateRange(for: points.map(\.date))

                        for (index, point) in points.enumerated() {
                            let x = chartX(
                                for: point.date,
                                in: dateRange,
                                width: geometry.size.width
                            )
                            let normalized = (point.value - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalized))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)

                    chartLabels(
                        top: "\(valueFormatter(points.map(\.value).max() ?? 0)) \(unitText)",
                        start: points.first?.date,
                        end: points.last?.date
                    )
                } else {
                    Path { path in
                        let y = geometry.size.height / 2
                        path.move(to: CGPoint(x: 6, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - 6, y: y))
                    }
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .frame(height: 58)
        .accessibilityLabel("\(titleText) 趋势")
    }

    private var titleText: String {
        unitText == "h" ? "睡眠" : "卡路里"
    }

    private func chartLabels(top: String, start: Date?, end: Date?) -> some View {
        ZStack {
            Text(top)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 3)
                .padding(.trailing, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let start, let end, end > start {
                HStack {
                    Text(start.shortDayText())
                    Spacer(minLength: 0)
                    Text(end.shortDayText())
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.bottom, 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private struct PressureTrendLine: View {
    let points: [BarometerPoint]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.06))

                if points.count >= 2 {
                    Path { path in
                        let values = points.map(\.pressureHectopascals)
                        let minValue = values.min() ?? 0
                        let maxValue = values.max() ?? 1
                        let range = max(maxValue - minValue, 0.4)
                        let dateRange = chartDateRange(for: points.map(\.date))

                        for (index, point) in points.enumerated() {
                            let x = chartX(
                                for: point.date,
                                in: dateRange,
                                width: geometry.size.width
                            )
                            let normalized = (point.pressureHectopascals - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalized))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)

                    chartLabels(
                        top: String(format: "%.1f", points.map(\.pressureHectopascals).max() ?? 0),
                        start: points.first?.date,
                        end: points.last?.date
                    )
                } else {
                    Path { path in
                        let y = geometry.size.height / 2
                        path.move(to: CGPoint(x: 6, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - 6, y: y))
                    }
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .frame(height: 30)
        .accessibilityLabel("气压趋势")
    }

    private func chartLabels(top: String, start: Date?, end: Date?) -> some View {
        ZStack {
            Text(top)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let start, let end, end.timeIntervalSince(start) > 60 {
                HStack {
                    Text(start.clockText())
                    Spacer(minLength: 0)
                    Text(end.clockText())
                }
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.bottom, 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private struct AltitudeTrendLine: View {
    let points: [BarometerPoint]
    let tint: Color

    private var altitudePoints: [BarometerPoint] {
        points.filter { $0.chartAltitudeMeters != nil }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.06))

                if altitudePoints.count >= 2 {
                    Path { path in
                        let values = altitudePoints.compactMap(\.chartAltitudeMeters)
                        let minValue = values.min() ?? 0
                        let maxValue = values.max() ?? 1
                        let range = max(maxValue - minValue, 0.2)
                        let dateRange = chartDateRange(for: altitudePoints.map(\.date))

                        for (index, point) in altitudePoints.enumerated() {
                            guard let altitude = point.chartAltitudeMeters else { continue }

                            let x = chartX(
                                for: point.date,
                                in: dateRange,
                                width: geometry.size.width
                            )
                            let normalized = (altitude - minValue) / range
                            let y = geometry.size.height * (1 - CGFloat(normalized))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)

                    chartLabels(
                        top: "\(Int((altitudePoints.compactMap(\.chartAltitudeMeters).max() ?? 0).rounded()))m",
                        start: altitudePoints.first?.date,
                        end: altitudePoints.last?.date
                    )
                } else {
                    Path { path in
                        let y = geometry.size.height / 2
                        path.move(to: CGPoint(x: 6, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - 6, y: y))
                    }
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .frame(height: 30)
        .accessibilityLabel("海拔趋势")
    }

    private func chartLabels(top: String, start: Date?, end: Date?) -> some View {
        ZStack {
            Text(top)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let start, let end, end.timeIntervalSince(start) > 60 {
                HStack {
                    Text(start.clockText())
                    Spacer(minLength: 0)
                    Text(end.clockText())
                }
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.bottom, 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private func chartDateRange(for dates: [Date]) -> ClosedRange<Date> {
    guard let start = dates.min(), let end = dates.max(), end > start else {
        let now = Date()
        return now...now.addingTimeInterval(1)
    }

    return start...end
}

private func chartX(for date: Date, in range: ClosedRange<Date>, width: CGFloat) -> CGFloat {
    let duration = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
    let position = date.timeIntervalSince(range.lowerBound) / duration
    return width * CGFloat(min(max(position, 0), 1))
}

private struct TrendPanel<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RadarFactorPill: View {
    let factor: AstroRadarFactor

    var body: some View {
        VStack(spacing: 1) {
            Text(factor.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if factor.valueText.contains("/") {
                let parts = factor.valueText.split(separator: "/", maxSplits: 1).map(String.init)
                VStack(spacing: 0) {
                    Text(parts.first ?? factor.valueText)
                    Text(parts.count > 1 ? parts[1] : "")
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            } else {
                Text(factor.valueText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tint: Color {
        switch factor.score {
        case 70...:
            return .green
        case 45..<70:
            return .yellow
        default:
            return .orange
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(.white.opacity(0.08), in: Capsule())
    }
}

private struct HalfCupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
    }
}

private struct HalfCupBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.07, blue: 0.08),
                Color(red: 0.09, green: 0.08, blue: 0.05),
                Color(red: 0.04, green: 0.06, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView(
        healthStore: .preview,
        caffeineStore: .preview,
        astroStore: .preview,
        barometerStore: .preview,
        trainingStore: .preview,
        refreshHealthOnAppear: false
    )
}
