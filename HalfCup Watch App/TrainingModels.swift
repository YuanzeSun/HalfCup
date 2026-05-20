//
//  TrainingModels.swift
//  HalfCup Watch App
//

import Foundation
import HealthKit
import Observation

enum TrainingStatusKind: String, Equatable {
    case productive = "Productive"
    case maintaining = "Maintaining"
    case peaking = "Peaking"
    case overreaching = "Overreaching"
    case detraining = "Detraining"
    case noData = "No Data"

    var subtitle: String {
        switch self {
        case .productive:
            return "负荷和恢复匹配"
        case .maintaining:
            return "维持当前体能"
        case .peaking:
            return "短期状态较好"
        case .overreaching:
            return "负荷偏高，注意恢复"
        case .detraining:
            return "训练刺激偏少"
        case .noData:
            return "等待训练记录"
        }
    }
}

struct TrainingRacePrediction: Identifiable, Equatable {
    let id: String
    let distance: String
    let timeText: String
}

struct AlertnessBlock: Identifiable, Equatable {
    let id: String
    let title: String
    let score: Int
}

struct TrainingSnapshot: Equatable {
    let status: TrainingStatusKind
    let statusDetail: String
    let load7Days: Double
    let chronicLoad: Double
    let loadRatio: Double
    let baseFitnessScore: Int
    let loadImpactScore: Int
    let intensityTrendText: String
    let primaryWorkoutEffect: String
    let aerobicEffectText: String
    let anaerobicEffectText: String
    let racePredictions: [TrainingRacePrediction]
    let staminaPercent: Int
    let staminaDetail: String
    let hillScore: Int
    let enduranceScore: Int
    let heatAltitudeText: String
    let sleepDebtHours: Double?
    let alertnessBlocks: [AlertnessBlock]

    var loadRatioText: String {
        guard loadRatio > 0 else { return "N/A" }
        return String(format: "%.2fx", loadRatio)
    }

    var sleepDebtText: String {
        guard let sleepDebtHours else { return "睡眠 N/A" }

        if sleepDebtHours < 0.5 {
            return "睡眠债很低"
        }

        return String(format: "睡眠债 %.1fh", sleepDebtHours)
    }

    var sleepDebtSummaryText: String {
        guard let sleepDebtHours else { return "睡眠 N/A" }

        if sleepDebtHours < 0.5 {
            return "睡眠债低"
        }

        return String(format: "睡眠债 %.1fh", sleepDebtHours)
    }

    var complicationLine: String {
        "\(status.rawValue) · 负荷 \(loadRatioText)"
    }

    static let waiting = TrainingSnapshot(
        status: .noData,
        statusDetail: "暂无最近训练数据",
        load7Days: 0,
        chronicLoad: 0,
        loadRatio: 0,
        baseFitnessScore: 0,
        loadImpactScore: 0,
        intensityTrendText: "N/A",
        primaryWorkoutEffect: "等待训练",
        aerobicEffectText: "有氧 N/A",
        anaerobicEffectText: "无氧 N/A",
        racePredictions: [],
        staminaPercent: 0,
        staminaDetail: "暂无估算",
        hillScore: 0,
        enduranceScore: 0,
        heatAltitudeText: "暂无",
        sleepDebtHours: nil,
        alertnessBlocks: []
    )

    static let preview = TrainingSnapshot(
        status: .productive,
        statusDetail: "7 天负荷略高于基础线",
        load7Days: 426,
        chronicLoad: 382,
        loadRatio: 1.12,
        baseFitnessScore: 72,
        loadImpactScore: 64,
        intensityTrendText: "强度上升",
        primaryWorkoutEffect: "阈值 + 有氧耐力",
        aerobicEffectText: "有氧 3.7",
        anaerobicEffectText: "无氧 1.4",
        racePredictions: [
            TrainingRacePrediction(id: "5k", distance: "5K", timeText: "23:40"),
            TrainingRacePrediction(id: "10k", distance: "10K", timeText: "49:20"),
            TrainingRacePrediction(id: "half", distance: "半马", timeText: "1:49"),
            TrainingRacePrediction(id: "marathon", distance: "全马", timeText: "3:52")
        ],
        staminaPercent: 76,
        staminaDetail: "耐力约 72 分",
        hillScore: 58,
        enduranceScore: 73,
        heatAltitudeText: "适应低",
        sleepDebtHours: 1.8,
        alertnessBlocks: [
            AlertnessBlock(id: "morning", title: "上午", score: 82),
            AlertnessBlock(id: "afternoon", title: "下午", score: 68),
            AlertnessBlock(id: "evening", title: "晚上", score: 55)
        ]
    )
}

private struct TrainingWorkout: Equatable {
    let activityType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let energyKilocalories: Double
    let distanceMeters: Double
}

private struct VO2MaxTrend: Equatable {
    let latest: Double?
    let delta: Double
}

@Observable
final class TrainingMetricsStore {
    private(set) var snapshot = TrainingSnapshot.waiting
    private(set) var isLoading = false
    private(set) var statusMessage = "训练状态将自动更新"

    @ObservationIgnored private let healthStore = HKHealthStore()

    static var preview: TrainingMetricsStore {
        let store = TrainingMetricsStore()
        store.snapshot = .preview
        store.statusMessage = "每 10 分钟自动更新"
        return store
    }

    func refresh() async {
        guard Self.hasHealthShareUsageDescription else {
            statusMessage = "请先在 Watch target 的 Info 添加健康读取说明"
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "此设备不支持 HealthKit"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await requestAuthorizationIfNeeded()
            let now = Date()
            let workouts = try await fetchWorkouts(endingAfter: now.addingTimeInterval(-35 * 24 * 60 * 60))
            let vo2Trend = try await fetchVO2MaxTrend()
            let sleepHours = try await fetchRecentSleepHours(endingAfter: now.addingTimeInterval(-7 * 24 * 60 * 60))
            let updatedSnapshot = TrainingInsightCalculator.makeSnapshot(
                workouts: workouts,
                vo2Trend: vo2Trend,
                sleepHoursLast7Days: sleepHours,
                now: now
            )
            snapshot = updatedSnapshot
            statusMessage = updatedSnapshot.status == .noData ? "未找到近 35 天训练" : "每 10 分钟自动更新"
        } catch {
            statusMessage = "N/A"
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]

        if let vo2MaxType = HKObjectType.quantityType(forIdentifier: .vo2Max) {
            readTypes.insert(vo2MaxType)
        }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleepType)
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    private static var hasHealthShareUsageDescription: Bool {
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") as? String else {
            return false
        }

        return !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let vo2MaxUnit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo))
        .unitDivided(by: HKUnit.minute())

    private func fetchWorkouts(endingAfter startDate: Date) async throws -> [TrainingWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let workoutType = HKObjectType.workoutType()
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: nil,
                options: [.strictEndDate]
            )
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    let energyType = HKQuantityType(.activeEnergyBurned)
                    return TrainingWorkout(
                        activityType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        energyKilocalories: workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
                        distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                    )
                }

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    private func fetchVO2MaxTrend() async throws -> VO2MaxTrend {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return VO2MaxTrend(latest: nil, delta: 0)
        }

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let startDate = Date().addingTimeInterval(-90 * 24 * 60 * 60)
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [.strictEndDate])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 8,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }

            healthStore.execute(query)
        }

        let unit = Self.vo2MaxUnit
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        guard let latest = values.first else {
            return VO2MaxTrend(latest: nil, delta: 0)
        }

        let baselineValues = values.dropFirst()
        let baseline = baselineValues.isEmpty ? latest : baselineValues.reduce(0, +) / Double(baselineValues.count)
        return VO2MaxTrend(latest: latest, delta: latest - baseline)
    }

    private func fetchRecentSleepHours(endingAfter startDate: Date) async throws -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: [.strictEndDate])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }

            healthStore.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        guard !asleepSamples.isEmpty else { return nil }

        return asleepSamples.reduce(0) { total, sample in
            total + sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }
    }
}

private enum TrainingInsightCalculator {
    static func makeSnapshot(
        workouts: [TrainingWorkout],
        vo2Trend: VO2MaxTrend,
        sleepHoursLast7Days: Double?,
        now: Date
    ) -> TrainingSnapshot {
        guard !workouts.isEmpty else {
            return .waiting
        }

        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let twentyEightDaysAgo = now.addingTimeInterval(-28 * 24 * 60 * 60)
        let recentWorkouts = workouts.filter { $0.endDate >= sevenDaysAgo }
        let baselineWorkouts = workouts.filter { $0.endDate >= twentyEightDaysAgo }
        let previousWorkouts = workouts.filter { $0.endDate < sevenDaysAgo && $0.endDate >= twentyEightDaysAgo }
        let load7Days = recentWorkouts.reduce(0) { $0 + trainingLoad(for: $1) }
        let chronicLoad = baselineWorkouts.reduce(0) { $0 + trainingLoad(for: $1) } / 4
        let previousWeeklyLoad = previousWorkouts.reduce(0) { $0 + trainingLoad(for: $1) } / 3
        let loadRatio = chronicLoad > 12 ? load7Days / chronicLoad : (load7Days > 0 ? 1.25 : 0)
        let baseFitnessScore = score(chronicLoad, low: 70, high: 520)
        let loadImpactScore = score(load7Days, low: 50, high: 620)
        let intensityTrendText = intensityTrend(recentWorkouts: recentWorkouts, previousWorkouts: previousWorkouts)
        let sleepDebtHours = sleepHoursLast7Days.map { max(7.5 * 7 - $0, 0) }
        let status = trainingStatus(loadRatio: loadRatio, load7Days: load7Days, chronicLoad: chronicLoad, vo2Delta: vo2Trend.delta)
        let statusDetail = statusDetail(
            status: status,
            loadRatio: loadRatio,
            load7Days: load7Days,
            previousWeeklyLoad: previousWeeklyLoad,
            vo2Delta: vo2Trend.delta
        )
        let latestWorkout = workouts.max { $0.endDate < $1.endDate }
        let effect = workoutEffect(for: latestWorkout, loadRatio: loadRatio)
        let racePredictions = racePredictions(workouts: workouts, vo2Max: vo2Trend.latest, baseFitnessScore: baseFitnessScore)
        let staminaPercent = staminaReserve(loadRatio: loadRatio, sleepDebtHours: sleepDebtHours, load7Days: load7Days)
        let enduranceMinutes = Int((Double(staminaPercent) / 100) * (45 + Double(baseFitnessScore) * 0.8))
        let hillScore = hillScore(from: baselineWorkouts)
        let enduranceScore = min(100, Int((Double(baseFitnessScore) * 0.68 + Double(loadImpactScore) * 0.32).rounded()))
        let alertnessBlocks = alertnessBlocks(staminaPercent: staminaPercent, sleepDebtHours: sleepDebtHours)

        return TrainingSnapshot(
            status: status,
            statusDetail: statusDetail,
            load7Days: load7Days,
            chronicLoad: chronicLoad,
            loadRatio: loadRatio,
            baseFitnessScore: baseFitnessScore,
            loadImpactScore: loadImpactScore,
            intensityTrendText: intensityTrendText,
            primaryWorkoutEffect: effect.primary,
            aerobicEffectText: effect.aerobic,
            anaerobicEffectText: effect.anaerobic,
            racePredictions: racePredictions,
            staminaPercent: staminaPercent,
            staminaDetail: "耐力约 \(max(enduranceMinutes, 0)) 分",
            hillScore: hillScore,
            enduranceScore: enduranceScore,
            heatAltitudeText: heatAltitudeText(workouts: baselineWorkouts),
            sleepDebtHours: sleepDebtHours,
            alertnessBlocks: alertnessBlocks
        )
    }

    private static func trainingLoad(for workout: TrainingWorkout) -> Double {
        let minutes = workout.duration / 60
        guard minutes > 0 else { return 0 }

        let kcalPerMinute = workout.energyKilocalories > 0 ? workout.energyKilocalories / minutes : 4.8
        let metabolicIntensity = min(max(kcalPerMinute / 7.5, 0.55), 1.75)
        return minutes * metabolicIntensity * activityMultiplier(for: workout.activityType)
    }

    private static func activityMultiplier(for activityType: HKWorkoutActivityType) -> Double {
        switch activityType {
        case .highIntensityIntervalTraining:
            return 1.55
        case .running:
            return 1.28
        case .cycling:
            return 1.14
        case .hiking:
            return 1.22
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return 1.08
        case .swimming:
            return 1.18
        default:
            return 1.0
        }
    }

    private static func score(_ value: Double, low: Double, high: Double) -> Int {
        guard high > low else { return 0 }
        let normalized = (value - low) / (high - low)
        return min(max(Int((normalized * 100).rounded()), 0), 100)
    }

    private static func trainingStatus(loadRatio: Double, load7Days: Double, chronicLoad: Double, vo2Delta: Double) -> TrainingStatusKind {
        guard load7Days > 20 || chronicLoad > 20 else { return .noData }

        if loadRatio < 0.58 {
            return .detraining
        }

        if loadRatio > 1.65 {
            return .overreaching
        }

        if loadRatio > 1.28 {
            return .peaking
        }

        if loadRatio >= 0.88, vo2Delta >= -0.4 {
            return .productive
        }

        return .maintaining
    }

    private static func statusDetail(
        status: TrainingStatusKind,
        loadRatio: Double,
        load7Days: Double,
        previousWeeklyLoad: Double,
        vo2Delta: Double
    ) -> String {
        let direction: String
        if load7Days > previousWeeklyLoad * 1.12 {
            direction = "负荷上升"
        } else if load7Days < previousWeeklyLoad * 0.88 {
            direction = "负荷下降"
        } else {
            direction = "负荷稳定"
        }

        if abs(vo2Delta) >= 0.3 {
            let vo2Text = vo2Delta > 0 ? "VO2max 上扬" : "VO2max 回落"
            return "\(direction) · \(vo2Text) · \(String(format: "%.2fx", loadRatio))"
        }

        return "\(direction) · \(String(format: "%.2fx", loadRatio))"
    }

    private static func intensityTrend(recentWorkouts: [TrainingWorkout], previousWorkouts: [TrainingWorkout]) -> String {
        let recent = averageIntensity(recentWorkouts)
        let previous = averageIntensity(previousWorkouts)
        guard recent > 0, previous > 0 else { return "强度待积累" }

        if recent > previous * 1.12 {
            return "强度上升"
        }

        if recent < previous * 0.88 {
            return "强度下降"
        }

        return "强度稳定"
    }

    private static func averageIntensity(_ workouts: [TrainingWorkout]) -> Double {
        let active = workouts.filter { $0.duration > 0 }
        guard !active.isEmpty else { return 0 }

        let total = active.reduce(0) { partial, workout in
            let minutes = workout.duration / 60
            let kcalPerMinute = workout.energyKilocalories > 0 ? workout.energyKilocalories / minutes : 4.8
            return partial + kcalPerMinute * activityMultiplier(for: workout.activityType)
        }
        return total / Double(active.count)
    }

    private static func workoutEffect(for workout: TrainingWorkout?, loadRatio: Double) -> (primary: String, aerobic: String, anaerobic: String) {
        guard let workout else {
            return ("等待训练", "有氧 N/A", "无氧 N/A")
        }

        let minutes = workout.duration / 60
        let load = trainingLoad(for: workout)
        let intensity = averageIntensity([workout])
        let aerobic = min(max(load / 38, 0.4), 5)
        var anaerobic = 0.5

        if workout.activityType == .highIntensityIntervalTraining || intensity > 8.8 {
            anaerobic = min(max(intensity / 2.8, 1.0), 5)
        } else if minutes < 35, intensity > 7.2 {
            anaerobic = min(max(intensity / 3.5, 0.8), 3.6)
        }

        let primary: String
        if loadRatio > 1.65 || aerobic > 4.6 {
            primary = "负荷偏高"
        } else if anaerobic >= 3.0 {
            primary = "无氧刺激"
        } else if intensity > 7.4 {
            primary = "阈值/VO2max"
        } else if minutes >= 65 {
            primary = "基础耐力"
        } else {
            primary = "有氧维持"
        }

        return (
            primary,
            String(format: "有氧 %.1f", aerobic),
            String(format: "无氧 %.1f", anaerobic)
        )
    }

    private static func racePredictions(
        workouts: [TrainingWorkout],
        vo2Max: Double?,
        baseFitnessScore: Int
    ) -> [TrainingRacePrediction] {
        let runWorkouts = workouts
            .filter { $0.activityType == .running && $0.distanceMeters >= 1_000 && $0.duration >= 5 * 60 }
            .sorted { ($0.duration / max($0.distanceMeters, 1)) < ($1.duration / max($1.distanceMeters, 1)) }
        let targets: [(String, Double)] = [
            ("5K", 5_000),
            ("10K", 10_000),
            ("半马", 21_097.5),
            ("全马", 42_195)
        ]

        if let source = runWorkouts.first {
            return targets.map { label, distance in
                let predictedSeconds = source.duration * pow(distance / source.distanceMeters, 1.06)
                return TrainingRacePrediction(id: label, distance: label, timeText: raceTimeText(predictedSeconds))
            }
        }

        guard let vo2Max else { return [] }

        let enduranceFactor = 0.88 + Double(baseFitnessScore) / 500
        let fiveKSeconds = 5_000 / max(vo2Max * 0.27 * enduranceFactor * 1_000 / 3_600, 1)
        return targets.map { label, distance in
            let predictedSeconds = fiveKSeconds * pow(distance / 5_000, 1.06)
            return TrainingRacePrediction(id: label, distance: label, timeText: raceTimeText(predictedSeconds))
        }
    }

    private static func raceTimeText(_ seconds: Double) -> String {
        let roundedSeconds = Int(seconds.rounded())
        let hours = roundedSeconds / 3600
        let minutes = (roundedSeconds % 3600) / 60
        let secs = roundedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }

        return String(format: "%d:%02d", minutes, secs)
    }

    private static func staminaReserve(loadRatio: Double, sleepDebtHours: Double?, load7Days: Double) -> Int {
        let ratioPenalty = max(loadRatio - 1.0, 0) * 34 + max(0.75 - loadRatio, 0) * 16
        let sleepPenalty = (sleepDebtHours ?? 1.2) * 5.5
        let loadPenalty = min(load7Days / 900 * 10, 10)
        return min(max(Int((92 - ratioPenalty - sleepPenalty - loadPenalty).rounded()), 5), 100)
    }

    private static func hillScore(from workouts: [TrainingWorkout]) -> Int {
        let hikingLoad = workouts
            .filter { $0.activityType == .hiking }
            .reduce(0) { $0 + trainingLoad(for: $1) }
        let runningLoad = workouts
            .filter { $0.activityType == .running }
            .reduce(0) { $0 + trainingLoad(for: $1) }
        return min(max(Int((hikingLoad / 260 * 60 + runningLoad / 900 * 40).rounded()), 0), 100)
    }

    private static func heatAltitudeText(workouts: [TrainingWorkout]) -> String {
        let outdoorLoad = workouts
            .filter { $0.activityType == .running || $0.activityType == .cycling || $0.activityType == .hiking }
            .reduce(0) { $0 + trainingLoad(for: $1) }

        switch outdoorLoad {
        case 500...:
            return "适应中"
        case 180..<500:
            return "适应低"
        default:
            return "不足"
        }
    }

    private static func alertnessBlocks(staminaPercent: Int, sleepDebtHours: Double?) -> [AlertnessBlock] {
        let debt = sleepDebtHours ?? 1.2
        let base = min(max(staminaPercent + 8 - Int(debt * 4), 20), 96)
        return [
            AlertnessBlock(id: "morning", title: "上午", score: base),
            AlertnessBlock(id: "afternoon", title: "下午", score: max(base - 12 - Int(debt * 2), 15)),
            AlertnessBlock(id: "evening", title: "晚上", score: max(base - 24 - Int(debt * 3), 10))
        ]
    }
}
