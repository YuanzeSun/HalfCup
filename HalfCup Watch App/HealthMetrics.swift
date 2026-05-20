//
//  HealthMetrics.swift
//  HalfCup Watch App
//

import Foundation
import HealthKit
import Observation
import SwiftUI

enum HealthMetricKind: String, CaseIterable, Identifiable {
    case hrv
    case heartRate
    case restingHeartRate
    case walkingHeartRate
    case recoveryHeartRate
    case basalEnergy
    case activeEnergy
    case stepCount
    case walkingDistance
    case vo2Max

    var id: String { rawValue }
}

struct HealthMetricReading: Identifiable, Equatable {
    let kind: HealthMetricKind
    let title: String
    let valueText: String
    let unitText: String
    let detailText: String
    let systemImage: String
    let tint: Color
    let sampleDate: Date?

    var id: String { kind.rawValue }

    static func unavailable(for definition: HealthMetricDefinition) -> HealthMetricReading {
        HealthMetricReading(
            kind: definition.kind,
            title: definition.title,
            valueText: "N/A",
            unitText: definition.unitText,
            detailText: "N/A",
            systemImage: definition.systemImage,
            tint: .secondary,
            sampleDate: nil
        )
    }
}

struct HealthMetricPoint: Identifiable, Equatable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct HealthStressSnapshot: Equatable {
    let score: Int
    let label: String
    let detail: String
    let tint: Color

    static let waiting = HealthStressSnapshot(
        score: 0,
        label: "N/A",
        detail: "HRV N/A · 心率 N/A",
        tint: .secondary
    )
}

struct HealthMetricDefinition: Identifiable {
    let kind: HealthMetricKind
    let title: String
    let unitText: String
    let systemImage: String
    let quantityIdentifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let lookbackDays: Int
    let query: HealthMetricQuery
    let formatter: (Double, Date) -> HealthMetricReading

    var id: String { kind.rawValue }

    var quantityType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: quantityIdentifier)
    }
}

enum HealthMetricQuery {
    case latest
    case todaySum
}

@Observable
final class HealthMetricsStore {
    private(set) var readings: [HealthMetricReading]
    private(set) var hrvTrend: [HealthMetricPoint] = []
    private(set) var dailyCalorieTrend: [HealthMetricPoint] = []
    private(set) var dailySleepTrend: [HealthMetricPoint] = []
    private(set) var stressSnapshot = HealthStressSnapshot.waiting
    private(set) var isLoading = false
    private(set) var statusMessage = "HRV 将自动更新"

    var hrvHistoryTrend: [HealthMetricPoint] {
        HalfCupHistoryStore.hrvSamples().map {
            HealthMetricPoint(date: $0.date, value: $0.value)
        }
    }

    var heartRateHistoryTrend: [HealthMetricPoint] {
        HalfCupHistoryStore.heartRateSamples().map {
            HealthMetricPoint(date: $0.date, value: $0.value)
        }
    }

    var dashboardReadings: [HealthMetricReading] {
        let visibleKinds: [HealthMetricKind] = [
            .heartRate,
            .restingHeartRate,
            .activeEnergy,
            .basalEnergy,
            .stepCount,
            .walkingDistance,
            .vo2Max,
            .walkingHeartRate
        ]

        return visibleKinds.compactMap { kind in
            readings.first { $0.kind == kind }
        }
    }

    @ObservationIgnored private let healthStore = HKHealthStore()

    init() {
        self.readings = Self.definitions.map { HealthMetricReading.unavailable(for: $0) }
    }

    static var preview: HealthMetricsStore {
        let store = HealthMetricsStore()
        let now = Date()
        store.readings = [
            HealthMetricReading(kind: .hrv, title: "HRV", valueText: "54", unitText: "ms", detailText: "中", systemImage: "waveform.path.ecg", tint: .cyan, sampleDate: now),
            HealthMetricReading(kind: .heartRate, title: "心率", valueText: "72", unitText: "bpm", detailText: "最近样本", systemImage: "heart.fill", tint: .pink, sampleDate: now),
            HealthMetricReading(kind: .restingHeartRate, title: "静息心率", valueText: "58", unitText: "bpm", detailText: "今日估算", systemImage: "heart.fill", tint: .pink, sampleDate: now),
            HealthMetricReading(kind: .walkingHeartRate, title: "步行心率", valueText: "91", unitText: "bpm", detailText: "自动估算", systemImage: "figure.walk", tint: .cyan, sampleDate: now),
            HealthMetricReading(kind: .recoveryHeartRate, title: "心率恢复", valueText: "32", unitText: "bpm", detailText: "运动后 1 分钟", systemImage: "arrow.down.heart.fill", tint: .green, sampleDate: now),
            HealthMetricReading(kind: .activeEnergy, title: "活动能量", valueText: "486", unitText: "kcal", detailText: "今日累计", systemImage: "flame.fill", tint: .orange, sampleDate: now),
            HealthMetricReading(kind: .basalEnergy, title: "静息能量", valueText: "1420", unitText: "kcal", detailText: "今日累计", systemImage: "leaf.fill", tint: .green, sampleDate: now),
            HealthMetricReading(kind: .stepCount, title: "步数", valueText: "8.2k", unitText: "步", detailText: "今日累计", systemImage: "shoeprints.fill", tint: .mint, sampleDate: now),
            HealthMetricReading(kind: .walkingDistance, title: "步行距离", valueText: "5.7", unitText: "km", detailText: "今日累计", systemImage: "figure.walk", tint: .cyan, sampleDate: now),
            HealthMetricReading(kind: .vo2Max, title: "最大摄氧量", valueText: "46.8", unitText: "ml/kg/min", detailText: "最近估算", systemImage: "lungs.fill", tint: .blue, sampleDate: now)
        ]
        store.hrvTrend = [46, 51, 48, 56, 54, 61, 58].enumerated().map { index, value in
            HealthMetricPoint(
                date: now.addingTimeInterval(Double(index - 6) * 60 * 60),
                value: Double(value)
            )
        }
        store.dailyCalorieTrend = [1980, 2140, 2055, 2300, 2210, 2080, 2420, 2360, 2195, 2270].enumerated().map { index, value in
            HealthMetricPoint(
                date: Calendar.current.date(byAdding: .day, value: index - 9, to: Calendar.current.startOfDay(for: now)) ?? now,
                value: Double(value)
            )
        }
        store.dailySleepTrend = [6.7, 7.2, 6.1, 8.0, 7.4, 6.9, 7.8, 5.9, 7.1, 7.6].enumerated().map { index, value in
            HealthMetricPoint(
                date: Calendar.current.date(byAdding: .day, value: index - 9, to: Calendar.current.startOfDay(for: now)) ?? now,
                value: value
            )
        }
        store.stressSnapshot = HealthStressSnapshot(score: 34, label: "中", detail: "HRV 54 ms · 心率 72 bpm", tint: .cyan)
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
            let updatedReadings = try await fetchReadings()
            let updatedTrend = try await fetchHRVTrend()
            let updatedDailyCalorieTrend = (try? await fetchDailyCalorieTrend()) ?? []
            let updatedDailySleepTrend = (try? await fetchDailySleepTrend()) ?? []
            readings = updatedReadings
            hrvTrend = updatedTrend
            dailyCalorieTrend = updatedDailyCalorieTrend
            dailySleepTrend = updatedDailySleepTrend
            stressSnapshot = makeStressSnapshot(from: updatedReadings)
            persistHistory(from: updatedReadings)
            statusMessage = "每 10 分钟自动更新"
        } catch {
            statusMessage = "N/A"
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        var readTypes = Set<HKObjectType>(Self.definitions.compactMap(\.quantityType))
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

    private func fetchReadings() async throws -> [HealthMetricReading] {
        var output: [HealthMetricReading] = []

        for definition in Self.definitions {
            guard let quantityType = definition.quantityType else {
                output.append(.unavailable(for: definition))
                continue
            }

            guard let result = try await quantityResult(for: definition, quantityType: quantityType) else {
                output.append(.unavailable(for: definition))
                continue
            }

            output.append(definition.formatter(result.value, result.date))
        }

        return output
    }

    private struct QuantityResult {
        let value: Double
        let date: Date
    }

    private func quantityResult(
        for definition: HealthMetricDefinition,
        quantityType: HKQuantityType
    ) async throws -> QuantityResult? {
        switch definition.query {
        case .latest:
            guard let sample = try await latestQuantitySample(
                for: quantityType,
                lookbackDays: definition.lookbackDays
            ) else {
                return nil
            }

            return QuantityResult(
                value: sample.quantity.doubleValue(for: definition.unit),
                date: sample.endDate
            )
        case .todaySum:
            return try await todaySum(for: quantityType, unit: definition.unit)
        }
    }

    private func latestQuantitySample(
        for quantityType: HKQuantityType,
        lookbackDays: Int
    ) async throws -> HKQuantitySample? {
        let samples = try await quantitySamples(for: quantityType, lookbackDays: lookbackDays, limit: 1)
        return samples.first
    }

    private func fetchHRVTrend() async throws -> [HealthMetricPoint] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return []
        }

        let samples = try await quantitySamples(for: quantityType, lookbackDays: 14, limit: 12)

        return samples
            .sorted { $0.endDate < $1.endDate }
            .map { sample in
                HealthMetricPoint(
                    date: sample.endDate,
                    value: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                )
            }
    }

    private func fetchDailyCalorieTrend() async throws -> [HealthMetricPoint] {
        guard let basalType = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned),
              let activeType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return []
        }

        let basal = try await dailySums(
            for: basalType,
            unit: .kilocalorie(),
            lookbackDays: 30
        )
        let active = try await dailySums(
            for: activeType,
            unit: .kilocalorie(),
            lookbackDays: 30
        )
        let dates = Set(basal.keys).union(active.keys).sorted()

        return dates.map { date in
            HealthMetricPoint(
                date: date,
                value: (basal[date] ?? 0) + (active[date] ?? 0)
            )
        }
    }

    private func fetchDailySleepTrend() async throws -> [HealthMetricPoint] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        return try await dailySleepDurations(for: sleepType, lookbackDays: 30)
            .map { date, hours in
                HealthMetricPoint(date: date, value: hours)
            }
            .sorted { $0.date < $1.date }
    }

    private func quantitySamples(
        for quantityType: HKQuantityType,
        lookbackDays: Int,
        limit: Int
    ) async throws -> [HKQuantitySample] {
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -lookbackDays,
            to: Date()
        )
        return try await quantitySamples(for: quantityType, startDate: startDate, limit: limit)
    }

    private func quantitySamples(
        for quantityType: HKQuantityType,
        startDate: Date?,
        limit: Int
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: nil,
                options: [.strictEndDate]
            )
            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierEndDate,
                ascending: false
            )
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: limit,
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
    }

    private func dailySums(
        for quantityType: HKQuantityType,
        unit: HKUnit,
        lookbackDays: Int
    ) async throws -> [Date: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let startDate = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today) ?? today
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: calendar.date(byAdding: .day, value: 1, to: today),
                options: [.strictStartDate]
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: today,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var output: [Date: Double] = [:]
                collection?.enumerateStatistics(from: startDate, to: Date()) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    output[calendar.startOfDay(for: statistics.startDate)] = sum.doubleValue(for: unit)
                }
                continuation.resume(returning: output)
            }

            healthStore.execute(query)
        }
    }

    private func dailySleepDurations(
        for sleepType: HKCategoryType,
        lookbackDays: Int
    ) async throws -> [Date: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let startDate = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: Date(),
                options: []
            )
            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierEndDate,
                ascending: true
            )
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

                let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
                let sleepSamples = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }

                var output: [Date: Double] = [:]
                for sample in sleepSamples {
                    let day = calendar.startOfDay(for: sample.endDate)
                    output[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600
                }

                continuation.resume(returning: output)
            }

            healthStore.execute(query)
        }
    }

    private func todaySum(for quantityType: HKQuantityType, unit: HKUnit) async throws -> QuantityResult? {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(
                withStart: startOfDay,
                end: Date(),
                options: [.strictStartDate]
            )
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: QuantityResult(
                        value: sum.doubleValue(for: unit),
                        date: Date()
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    private func makeStressSnapshot(from readings: [HealthMetricReading]) -> HealthStressSnapshot {
        guard let hrvReading = readings.first(where: { $0.kind == .hrv }),
              let hrv = Double(hrvReading.valueText)
        else {
            return .waiting
        }

        let heartRateText = readings.first(where: { $0.kind == .heartRate }).map {
            "\($0.valueText) \($0.unitText)"
        } ?? "N/A"
        let detail = "HRV \(Int(hrv.rounded())) ms · 心率 \(heartRateText)"

        switch hrv {
        case ..<20:
            return HealthStressSnapshot(
                score: 0,
                label: "超高",
                detail: detail,
                tint: .red
            )
        case 20..<35:
            return HealthStressSnapshot(
                score: 0,
                label: "高",
                detail: detail,
                tint: .orange
            )
        case 35..<60:
            return HealthStressSnapshot(
                score: 0,
                label: "中",
                detail: detail,
                tint: .cyan
            )
        default:
            return HealthStressSnapshot(
                score: 0,
                label: "低",
                detail: detail,
                tint: .green
            )
        }
    }

    private func persistHistory(from readings: [HealthMetricReading]) {
        for reading in readings {
            guard let value = Double(reading.valueText),
                  let sampleDate = reading.sampleDate
            else {
                continue
            }

            switch reading.kind {
            case .heartRate:
                HalfCupHistoryStore.appendHeartRate(value: value, at: sampleDate)
            case .hrv:
                HalfCupHistoryStore.appendHRV(value: value, at: sampleDate)
            case .restingHeartRate, .walkingHeartRate, .recoveryHeartRate, .basalEnergy, .activeEnergy, .stepCount, .walkingDistance, .vo2Max:
                continue
            }
        }
    }

    private static let definitions: [HealthMetricDefinition] = [
        HealthMetricDefinition(
            kind: .hrv,
            title: "HRV",
            unitText: "ms",
            systemImage: "waveform.path.ecg",
            quantityIdentifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            lookbackDays: 14,
            query: .latest
        ) { value, date in
            let state: String
            let tint: Color

            switch value {
            case ..<20:
                state = "超高"
                tint = .red
            case 20..<35:
                state = "高"
                tint = .orange
            case 35..<60:
                state = "中"
                tint = .cyan
            default:
                state = "低"
                tint = .green
            }

            return HealthMetricReading(
                kind: .hrv,
                title: "HRV",
                valueText: "\(Int(value.rounded()))",
                unitText: "ms",
                detailText: state,
                systemImage: "waveform.path.ecg",
                tint: tint,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .heartRate,
            title: "心率",
            unitText: "bpm",
            systemImage: "heart.fill",
            quantityIdentifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            lookbackDays: 1,
            query: .latest
        ) { value, date in
            HealthMetricReading(
                kind: .heartRate,
                title: "心率",
                valueText: "\(Int(value.rounded()))",
                unitText: "bpm",
                detailText: "最近样本",
                systemImage: "heart.fill",
                tint: .pink,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .restingHeartRate,
            title: "静息心率",
            unitText: "bpm",
            systemImage: "heart.fill",
            quantityIdentifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            lookbackDays: 14,
            query: .latest
        ) { value, date in
            HealthMetricReading(
                kind: .restingHeartRate,
                title: "静息心率",
                valueText: "\(Int(value.rounded()))",
                unitText: "bpm",
                detailText: "最近估算",
                systemImage: "heart.fill",
                tint: .pink,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .walkingHeartRate,
            title: "步行心率",
            unitText: "bpm",
            systemImage: "figure.walk",
            quantityIdentifier: .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: .minute()),
            lookbackDays: 30,
            query: .latest
        ) { value, date in
            HealthMetricReading(
                kind: .walkingHeartRate,
                title: "步行心率",
                valueText: "\(Int(value.rounded()))",
                unitText: "bpm",
                detailText: "自动记录",
                systemImage: "figure.walk",
                tint: .cyan,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .recoveryHeartRate,
            title: "心率恢复",
            unitText: "bpm",
            systemImage: "arrow.down.heart.fill",
            quantityIdentifier: .heartRateRecoveryOneMinute,
            unit: HKUnit.count().unitDivided(by: .minute()),
            lookbackDays: 60,
            query: .latest
        ) { value, date in
            HealthMetricReading(
                kind: .recoveryHeartRate,
                title: "心率恢复",
                valueText: "\(Int(value.rounded()))",
                unitText: "bpm",
                detailText: "运动后 1 分钟",
                systemImage: "arrow.down.heart.fill",
                tint: .green,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .basalEnergy,
            title: "静息能量",
            unitText: "kcal",
            systemImage: "leaf.fill",
            quantityIdentifier: .basalEnergyBurned,
            unit: HKUnit.kilocalorie(),
            lookbackDays: 1,
            query: .todaySum
        ) { value, date in
            HealthMetricReading(
                kind: .basalEnergy,
                title: "静息能量",
                valueText: "\(Int(value.rounded()))",
                unitText: "kcal",
                detailText: "今日累计",
                systemImage: "leaf.fill",
                tint: .green,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .activeEnergy,
            title: "活动能量",
            unitText: "kcal",
            systemImage: "flame.fill",
            quantityIdentifier: .activeEnergyBurned,
            unit: HKUnit.kilocalorie(),
            lookbackDays: 1,
            query: .todaySum
        ) { value, date in
            HealthMetricReading(
                kind: .activeEnergy,
                title: "活动能量",
                valueText: "\(Int(value.rounded()))",
                unitText: "kcal",
                detailText: "今日累计",
                systemImage: "flame.fill",
                tint: .orange,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .stepCount,
            title: "步数",
            unitText: "步",
            systemImage: "shoeprints.fill",
            quantityIdentifier: .stepCount,
            unit: HKUnit.count(),
            lookbackDays: 1,
            query: .todaySum
        ) { value, date in
            HealthMetricReading(
                kind: .stepCount,
                title: "步数",
                valueText: abbreviatedCount(value),
                unitText: "步",
                detailText: "今日累计",
                systemImage: "shoeprints.fill",
                tint: .mint,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .walkingDistance,
            title: "步行距离",
            unitText: "km",
            systemImage: "figure.walk",
            quantityIdentifier: .distanceWalkingRunning,
            unit: HKUnit.meterUnit(with: .kilo),
            lookbackDays: 1,
            query: .todaySum
        ) { value, date in
            HealthMetricReading(
                kind: .walkingDistance,
                title: "步行距离",
                valueText: String(format: "%.1f", value),
                unitText: "km",
                detailText: "今日累计",
                systemImage: "figure.walk",
                tint: .cyan,
                sampleDate: date
            )
        },
        HealthMetricDefinition(
            kind: .vo2Max,
            title: "最大摄氧量",
            unitText: "ml/kg/min",
            systemImage: "lungs.fill",
            quantityIdentifier: .vo2Max,
            unit: vo2MaxUnit,
            lookbackDays: 365,
            query: .latest
        ) { value, date in
            HealthMetricReading(
                kind: .vo2Max,
                title: "最大摄氧量",
                valueText: String(format: "%.1f", value),
                unitText: "ml/kg/min",
                detailText: "最近估算",
                systemImage: "lungs.fill",
                tint: .blue,
                sampleDate: date
            )
        }
    ]

    private static let vo2MaxUnit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo))
        .unitDivided(by: HKUnit.minute())

    private static func abbreviatedCount(_ value: Double) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", value / 10_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fk", value / 1_000)
        }

        return "\(Int(value.rounded()))"
    }
}
