//
//  HalfCupApp.swift
//  HalfCup Watch App
//
//  Created by Luca on 2026/5/20.
//

import CoreMotion
import Foundation
import HealthKit
import SwiftUI
import WatchKit

@main
struct HalfCup_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(HalfCupApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class HalfCupApplicationDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        HalfCupBackgroundRefreshScheduler.scheduleNext()
    }

    func applicationDidEnterBackground() {
        HalfCupBackgroundRefreshScheduler.scheduleNext()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refreshTask = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }

            Task {
                await HalfCupBackgroundSampler().recordNow()
                HalfCupBackgroundRefreshScheduler.scheduleNext()
                refreshTask.setTaskCompletedWithSnapshot(true)
            }
        }
    }
}

enum HalfCupBackgroundRefreshScheduler {
    static let preferredSampleInterval: TimeInterval = 10 * 60

    static func scheduleNext(after interval: TimeInterval = preferredSampleInterval) {
        let preferredDate = Date(timeIntervalSinceNow: interval)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error {
                HalfCupHistoryStore.setLastBackgroundError(error.localizedDescription)
            } else {
                HalfCupHistoryStore.setNextBackgroundDate(preferredDate)
            }
        }
    }
}

struct HistoricalValueSample: Codable, Equatable, Identifiable, Sendable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct HistoricalBarometerSample: Codable, Equatable, Identifiable, Sendable {
    let date: Date
    let pressureHectopascals: Double?
    let absoluteAltitudeMeters: Double?
    let relativeAltitudeMeters: Double?

    var id: Date { date }
}

enum HalfCupHistoryStore {
    static let retentionInterval: TimeInterval = 12 * 60 * 60
    static let foregroundHistoryInterval: TimeInterval = 10 * 60

    private static let suiteName = "group.com.luca.HalfCup"

    private enum Keys {
        static let heartRate = "halfCup.history.heartRate"
        static let hrv = "halfCup.history.hrv"
        static let barometer = "halfCup.history.barometer"
        static let lastBackgroundSampleAt = "halfCup.history.lastBackgroundSampleAt"
        static let nextBackgroundDate = "halfCup.history.nextBackgroundDate"
        static let lastBackgroundError = "halfCup.history.lastBackgroundError"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func heartRateSamples(now: Date = Date()) -> [HistoricalValueSample] {
        trimmedValueSamples(readValueSamples(forKey: Keys.heartRate), now: now)
    }

    static func hrvSamples(now: Date = Date()) -> [HistoricalValueSample] {
        trimmedValueSamples(readValueSamples(forKey: Keys.hrv), now: now)
    }

    static func barometerSamples(now: Date = Date()) -> [HistoricalBarometerSample] {
        trimmedBarometerSamples(readBarometerSamples(), now: now)
    }

    static func appendHeartRate(value: Double, at date: Date = Date()) {
        appendValueSample(HistoricalValueSample(date: date, value: value), forKey: Keys.heartRate)
    }

    static func appendHRV(value: Double, at date: Date = Date()) {
        appendValueSample(HistoricalValueSample(date: date, value: value), forKey: Keys.hrv)
    }

    static func appendBarometer(
        pressureHectopascals: Double?,
        absoluteAltitudeMeters: Double?,
        relativeAltitudeMeters: Double? = nil,
        at date: Date = Date()
    ) {
        guard pressureHectopascals != nil || absoluteAltitudeMeters != nil || relativeAltitudeMeters != nil else {
            return
        }

        let sample = HistoricalBarometerSample(
            date: date,
            pressureHectopascals: pressureHectopascals,
            absoluteAltitudeMeters: absoluteAltitudeMeters,
            relativeAltitudeMeters: relativeAltitudeMeters
        )
        var samples = readBarometerSamples()
        guard !samples.contains(where: { abs($0.date.timeIntervalSince(sample.date)) < 60 }) else {
            return
        }

        samples.append(sample)
        write(trimmedBarometerSamples(samples, now: Date()), forKey: Keys.barometer)
    }

    static func setLastBackgroundSampleDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Keys.lastBackgroundSampleAt)
    }

    static func setNextBackgroundDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Keys.nextBackgroundDate)
    }

    static func setLastBackgroundError(_ message: String) {
        defaults.set(message, forKey: Keys.lastBackgroundError)
    }

    private static func appendValueSample(_ sample: HistoricalValueSample, forKey key: String) {
        var samples = readValueSamples(forKey: key)
        guard !samples.contains(where: { abs($0.date.timeIntervalSince(sample.date)) < 60 }) else {
            return
        }

        samples.append(sample)
        write(trimmedValueSamples(samples, now: Date()), forKey: key)
    }

    private static func readValueSamples(forKey key: String) -> [HistoricalValueSample] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([HistoricalValueSample].self, from: data)) ?? []
    }

    private static func readBarometerSamples() -> [HistoricalBarometerSample] {
        guard let data = defaults.data(forKey: Keys.barometer) else { return [] }
        return (try? JSONDecoder().decode([HistoricalBarometerSample].self, from: data)) ?? []
    }

    private static func trimmedValueSamples(
        _ samples: [HistoricalValueSample],
        now: Date
    ) -> [HistoricalValueSample] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return samples
            .filter { $0.date >= cutoff && $0.date <= now.addingTimeInterval(60) }
            .sorted { $0.date < $1.date }
    }

    private static func trimmedBarometerSamples(
        _ samples: [HistoricalBarometerSample],
        now: Date
    ) -> [HistoricalBarometerSample] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return samples
            .filter { $0.date >= cutoff && $0.date <= now.addingTimeInterval(60) }
            .sorted { $0.date < $1.date }
    }

    private static func write<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

final class HalfCupBackgroundSampler: @unchecked Sendable {
    private let healthStore = HKHealthStore()

    func recordNow() async {
        async let health: Void = recordHealth()
        async let barometer: Void = recordBarometer()
        _ = await (health, barometer)
        HalfCupHistoryStore.setLastBackgroundSampleDate(Date())
    }

    private func recordHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        async let heartRate = latestHealthValue(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrv = latestHealthValue(
            identifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli)
        )

        if let heartRate = await heartRate {
            HalfCupHistoryStore.appendHeartRate(value: heartRate.value, at: heartRate.date)
        }

        if let hrv = await hrv {
            HalfCupHistoryStore.appendHRV(value: hrv.value, at: hrv.date)
        }
    }

    private struct HealthSample: Sendable {
        let value: Double
        let date: Date
    }

    private func latestHealthValue(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> HealthSample? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let startDate = Date().addingTimeInterval(-HalfCupHistoryStore.retentionInterval)
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
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let sample = (samples as? [HKQuantitySample])?.first
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: HealthSample(
                        value: sample.quantity.doubleValue(for: unit),
                        date: sample.endDate
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    private func recordBarometer() async {
        guard let sample = await OneShotBarometerSampler().sample(timeout: 4) else {
            return
        }

        HalfCupHistoryStore.appendBarometer(
            pressureHectopascals: sample.pressureHectopascals,
            absoluteAltitudeMeters: sample.absoluteAltitudeMeters,
            relativeAltitudeMeters: sample.relativeAltitudeMeters,
            at: sample.date
        )
    }
}

private final class OneShotBarometerSampler: @unchecked Sendable {
    private let altimeter = CMAltimeter()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HistoricalBarometerSample?, Never>?
    private var needsPressure = false
    private var needsAbsoluteAltitude = false
    private var pressureHectopascals: Double?
    private var absoluteAltitudeMeters: Double?
    private var relativeAltitudeMeters: Double?
    private var finished = false

    init() {
        queue.name = "HalfCup.BackgroundBarometer"
        queue.qualityOfService = .utility
    }

    func sample(timeout: TimeInterval) async -> HistoricalBarometerSample? {
        guard CMAltimeter.authorizationStatus() != .denied else {
            return nil
        }

        let hasRelativeAltitude = CMAltimeter.isRelativeAltitudeAvailable()
        let hasAbsoluteAltitude = CMAltimeter.isAbsoluteAltitudeAvailable()
        guard hasRelativeAltitude || hasAbsoluteAltitude else {
            return nil
        }

        needsPressure = hasRelativeAltitude
        needsAbsoluteAltitude = hasAbsoluteAltitude

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            if hasRelativeAltitude {
                altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, error in
                    guard error == nil, let data else { return }
                    self?.update(
                        pressureHectopascals: data.pressure.doubleValue * 10,
                        relativeAltitudeMeters: data.relativeAltitude.doubleValue
                    )
                }
            }

            if hasAbsoluteAltitude {
                altimeter.startAbsoluteAltitudeUpdates(to: queue) { [weak self] data, error in
                    guard error == nil, let data else { return }
                    self?.update(absoluteAltitudeMeters: data.altitude)
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish()
            }
        }
    }

    private func update(
        pressureHectopascals: Double? = nil,
        absoluteAltitudeMeters: Double? = nil,
        relativeAltitudeMeters: Double? = nil
    ) {
        lock.lock()
        if let pressureHectopascals {
            self.pressureHectopascals = pressureHectopascals
        }
        if let absoluteAltitudeMeters {
            self.absoluteAltitudeMeters = absoluteAltitudeMeters
        }
        if let relativeAltitudeMeters {
            self.relativeAltitudeMeters = relativeAltitudeMeters
        }

        let isComplete = (!needsPressure || self.pressureHectopascals != nil)
            && (!needsAbsoluteAltitude || self.absoluteAltitudeMeters != nil)
        lock.unlock()

        if isComplete {
            finish()
        }
    }

    private func finish() {
        let continuation: CheckedContinuation<HistoricalBarometerSample?, Never>?
        let sample: HistoricalBarometerSample?

        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }

        finished = true
        continuation = self.continuation
        self.continuation = nil
        sample = makeSampleLocked()
        lock.unlock()

        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
        continuation?.resume(returning: sample)
    }

    private func makeSampleLocked() -> HistoricalBarometerSample? {
        guard pressureHectopascals != nil || absoluteAltitudeMeters != nil || relativeAltitudeMeters != nil else {
            return nil
        }

        return HistoricalBarometerSample(
            date: Date(),
            pressureHectopascals: pressureHectopascals,
            absoluteAltitudeMeters: absoluteAltitudeMeters,
            relativeAltitudeMeters: relativeAltitudeMeters
        )
    }
}
