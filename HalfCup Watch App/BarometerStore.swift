//
//  BarometerStore.swift
//  HalfCup Watch App
//

import CoreMotion
import Foundation
import Observation

struct BarometerPoint: Identifiable, Equatable {
    let date: Date
    let pressureHectopascals: Double
    let absoluteAltitudeMeters: Double?
    let relativeAltitudeMeters: Double?

    init(
        date: Date,
        pressureHectopascals: Double,
        absoluteAltitudeMeters: Double? = nil,
        relativeAltitudeMeters: Double? = nil
    ) {
        self.date = date
        self.pressureHectopascals = pressureHectopascals
        self.absoluteAltitudeMeters = absoluteAltitudeMeters
        self.relativeAltitudeMeters = relativeAltitudeMeters
    }

    var id: Date { date }

    var chartAltitudeMeters: Double? {
        absoluteAltitudeMeters
    }
}

@Observable
final class BarometerStore {
    static let realtimeTrendInterval: TimeInterval = 2 * 60

    private(set) var pressureHectopascals: Double?
    private(set) var absoluteAltitudeMeters: Double?
    private(set) var altitudeAccuracyMeters: Double?
    private(set) var relativeAltitudeMeters: Double?
    private(set) var pressureTrend: [BarometerPoint] = []
    private(set) var statusMessage = "等待气压数据"

    @ObservationIgnored private let altimeter = CMAltimeter()
    @ObservationIgnored private let queue = OperationQueue()
    @ObservationIgnored private var isUpdating = false
    @ObservationIgnored private var lastHistorySampleDate: Date?

    init() {
        queue.name = "HalfCup.Barometer"
        queue.qualityOfService = .utility
    }

    static var preview: BarometerStore {
        let store = BarometerStore()
        store.pressureHectopascals = 1012.8
        store.absoluteAltitudeMeters = 8.4
        store.altitudeAccuracyMeters = 2.0
        store.relativeAltitudeMeters = 1.6
        store.pressureTrend = Self.previewTrend()
        store.statusMessage = "气压/海拔实时"
        return store
    }

    var pressureText: String {
        guard let pressureHectopascals else { return "N/A" }
        return String(format: "%.1f", pressureHectopascals)
    }

    var altitudeValueText: String {
        if let absoluteAltitudeMeters {
            return String(format: "%.0f", absoluteAltitudeMeters)
        }

        guard let relativeAltitudeMeters else { return "N/A" }
        return String(format: "%+.1f", relativeAltitudeMeters)
    }

    var altitudeText: String {
        altitudeValueText == "N/A" ? "N/A" : "\(altitudeValueText) m"
    }

    var altitudeLabel: String {
        absoluteAltitudeMeters == nil && relativeAltitudeMeters != nil ? "相对高度" : "海拔"
    }

    var altitudeSourceText: String {
        absoluteAltitudeMeters == nil && relativeAltitudeMeters != nil ? "相对高度" : "绝对海拔"
    }

    var trendSampleDescription: String {
        "上方实时 · 下方 12h/10min"
    }

    var historyTrend: [BarometerPoint] {
        HalfCupHistoryStore.barometerSamples().compactMap { sample -> BarometerPoint? in
            guard let pressureHectopascals = sample.pressureHectopascals else {
                return nil
            }

            return BarometerPoint(
                date: sample.date,
                pressureHectopascals: pressureHectopascals,
                absoluteAltitudeMeters: sample.absoluteAltitudeMeters,
                relativeAltitudeMeters: sample.relativeAltitudeMeters
            )
        }
    }

    func resetSession() {
        pressureHectopascals = nil
        absoluteAltitudeMeters = nil
        altitudeAccuracyMeters = nil
        relativeAltitudeMeters = nil
        pressureTrend.removeAll()
        lastHistorySampleDate = nil
        statusMessage = "等待气压数据"
    }

    func start() {
        guard !isUpdating else { return }

        guard Self.hasMotionUsageDescription else {
            statusMessage = "请在 Info 添加运动权限说明"
            return
        }

        guard CMAltimeter.authorizationStatus() != .denied else {
            statusMessage = "气压/海拔未授权"
            return
        }

        let hasRelativeAltitude = CMAltimeter.isRelativeAltitudeAvailable()
        let hasAbsoluteAltitude = CMAltimeter.isAbsoluteAltitudeAvailable()
        guard hasRelativeAltitude || hasAbsoluteAltitude else {
            statusMessage = "此设备不支持气压计"
            return
        }

        isUpdating = true
        statusMessage = hasAbsoluteAltitude ? "气压/绝对海拔实时" : "仅相对高度"

        if hasRelativeAltitude {
            altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, error in
                guard let self else { return }

                if error != nil {
                    Task { @MainActor in
                        self.statusMessage = "N/A"
                    }
                    return
                }

                guard let data else { return }
                let pressureHectopascals = data.pressure.doubleValue * 10
                let relativeAltitudeMeters = data.relativeAltitude.doubleValue

                Task { @MainActor in
                    self.pressureHectopascals = pressureHectopascals
                    self.relativeAltitudeMeters = relativeAltitudeMeters
                    self.recordSample(
                        pressureHectopascals: pressureHectopascals,
                        absoluteAltitudeMeters: self.absoluteAltitudeMeters,
                        relativeAltitudeMeters: relativeAltitudeMeters,
                        at: Date()
                    )
                    self.statusMessage = self.absoluteAltitudeMeters == nil ? "仅相对高度" : "气压/绝对海拔实时"
                }
            }
        }

        if hasAbsoluteAltitude {
            altimeter.startAbsoluteAltitudeUpdates(to: queue) { [weak self] data, error in
                guard let self else { return }

                if error != nil {
                    Task { @MainActor in
                        self.statusMessage = "N/A"
                    }
                    return
                }

                guard let data else { return }
                let altitudeMeters = data.altitude
                let accuracyMeters = data.accuracy

                Task { @MainActor in
                    self.absoluteAltitudeMeters = altitudeMeters
                    self.altitudeAccuracyMeters = accuracyMeters
                    if let pressureHectopascals = self.pressureHectopascals {
                        self.recordSample(
                            pressureHectopascals: pressureHectopascals,
                            absoluteAltitudeMeters: altitudeMeters,
                            relativeAltitudeMeters: self.relativeAltitudeMeters,
                            at: Date()
                        )
                    }
                    self.statusMessage = "气压/绝对海拔实时"
                }
            }
        }
    }

    func stop() {
        guard isUpdating else { return }
        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
        isUpdating = false
    }

    private static var hasMotionUsageDescription: Bool {
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") as? String else {
            return false
        }

        return !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recordSample(
        pressureHectopascals: Double,
        absoluteAltitudeMeters: Double?,
        relativeAltitudeMeters: Double?,
        at date: Date
    ) {
        pressureTrend.append(
            BarometerPoint(
                date: date,
                pressureHectopascals: pressureHectopascals,
                absoluteAltitudeMeters: absoluteAltitudeMeters,
                relativeAltitudeMeters: relativeAltitudeMeters
            )
        )

        let cutoff = date.addingTimeInterval(-Self.realtimeTrendInterval)
        pressureTrend.removeAll { $0.date < cutoff }

        if shouldPersistHistorySample(at: date) {
            HalfCupHistoryStore.appendBarometer(
                pressureHectopascals: pressureHectopascals,
                absoluteAltitudeMeters: absoluteAltitudeMeters,
                relativeAltitudeMeters: relativeAltitudeMeters,
                at: date
            )
            lastHistorySampleDate = date
        }
    }

    private func shouldPersistHistorySample(at date: Date) -> Bool {
        guard let lastHistorySampleDate else { return true }
        return date.timeIntervalSince(lastHistorySampleDate) >= HalfCupHistoryStore.foregroundHistoryInterval
    }

    private static func previewTrend() -> [BarometerPoint] {
        let now = Date()
        return (0..<18).map { index in
            let offset = Double(index - 17) * 7
            let pressure = 1012.8 + sin(Double(index) / 2.6) * 2.4 + offset * 0.08
            let altitude = 8.4 + sin(Double(index) / 2.1) * 1.8 + offset * 0.04
            return BarometerPoint(
                date: now.addingTimeInterval(offset),
                pressureHectopascals: pressure,
                absoluteAltitudeMeters: altitude,
                relativeAltitudeMeters: altitude - 8.4
            )
        }
    }
}
