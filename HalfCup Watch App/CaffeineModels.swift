//
//  CaffeineModels.swift
//  HalfCup Watch App
//

import Foundation
import Observation

struct CaffeineDose: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var milligrams: Double
    var date: Date

    init(id: UUID = UUID(), name: String, milligrams: Double, date: Date) {
        self.id = id
        self.name = name
        self.milligrams = milligrams
        self.date = date
    }
}

struct CaffeinePreset: Identifiable, Equatable {
    let id: String
    let title: String
    let milligrams: Double
    let systemImage: String

    static let defaults: [CaffeinePreset] = [
        CaffeinePreset(id: "espresso", title: "浓缩", milligrams: 80, systemImage: "bolt.fill"),
        CaffeinePreset(id: "latte", title: "拿铁", milligrams: 120, systemImage: "cup.and.saucer.fill"),
        CaffeinePreset(id: "tea", title: "茶", milligrams: 45, systemImage: "leaf.fill"),
        CaffeinePreset(id: "custom", title: "半杯", milligrams: 60, systemImage: "drop.fill")
    ]
}

struct CaffeineSnapshot: Equatable {
    let date: Date
    let activeDoseCount: Int
    let totalActiveMilligrams: Double
    let totalTodayMilligrams: Double
    let remainingMilligrams: Double
    let lowCaffeineDate: Date?
    let lastDoseName: String?

    var remainingFraction: Double {
        min(max(remainingMilligrams / CaffeineMetabolism.gaugeMaximumMilligrams, 0), 1)
    }

    var remainingMilligramsText: String {
        "\(Int(remainingMilligrams.rounded())) mg"
    }

    var lowCaffeineStatusText: String {
        guard activeDoseCount > 0 else { return "今日无咖啡因" }

        if remainingMilligrams <= CaffeineMetabolism.lowCaffeineThresholdMilligrams {
            return "已消退"
        }

        guard let lowCaffeineDate else {
            return "72 h+ 后消退"
        }

        return "\(Self.durationText(from: date, to: lowCaffeineDate)) 后消退"
    }

    private static func durationText(from startDate: Date, to endDate: Date) -> String {
        let seconds = max(endDate.timeIntervalSince(startDate), 0)
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(max(minutes, 1)) m"
        }

        if minutes == 0 {
            return "\(hours) h"
        }

        return "\(hours) h \(minutes) m"
    }
}

enum CaffeineMetabolism {
    static let defaultHalfLifeHours = 5.0
    static let lowCaffeineThresholdMilligrams = 30.0
    static let gaugeMaximumMilligrams = 500.0
    static let activeWindowHours = 48.0

    static func remainingMilligrams(
        from doses: [CaffeineDose],
        at date: Date,
        halfLifeHours: Double
    ) -> Double {
        guard halfLifeHours > 0 else { return 0 }

        let halfLifeSeconds = halfLifeHours * 60 * 60

        return doses.reduce(0) { total, dose in
            let elapsed = max(date.timeIntervalSince(dose.date), 0)
            let decay = pow(0.5, elapsed / halfLifeSeconds)
            return total + dose.milligrams * decay
        }
    }

    static func activeDoses(from doses: [CaffeineDose], at date: Date) -> [CaffeineDose] {
        let activeWindow = activeWindowHours * 60 * 60

        return doses
            .filter { dose in
                let age = date.timeIntervalSince(dose.date)
                return age >= 0 && age <= activeWindow
            }
            .sorted { $0.date > $1.date }
    }

    static func timeBelowMilligrams(
        _ targetMilligrams: Double,
        from doses: [CaffeineDose],
        at date: Date,
        halfLifeHours: Double
    ) -> Date? {
        guard !doses.isEmpty, halfLifeHours > 0 else { return nil }
        guard targetMilligrams > 0 else { return nil }

        if remainingMilligrams(from: doses, at: date, halfLifeHours: halfLifeHours) <= targetMilligrams {
            return date
        }

        let searchLimit = date.addingTimeInterval(72 * 60 * 60)
        var probeDate = date

        while probeDate <= searchLimit {
            probeDate = probeDate.addingTimeInterval(5 * 60)

            let remaining = remainingMilligrams(from: doses, at: probeDate, halfLifeHours: halfLifeHours)
            if remaining <= targetMilligrams {
                return probeDate
            }
        }

        return nil
    }
}

@Observable
final class CaffeineStore {
    var doses: [CaffeineDose] {
        didSet { persist() }
    }

    private(set) var halfLifeHours: Double

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let shouldPersist: Bool

    private enum Keys {
        static let doses = "halfCup.caffeine.doses"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shouldPersist = true
        self.doses = Self.loadDoses(from: defaults)
        self.halfLifeHours = CaffeineMetabolism.defaultHalfLifeHours

        purgeExpiredEntries()
    }

    init(previewDoses: [CaffeineDose], halfLifeHours: Double = CaffeineMetabolism.defaultHalfLifeHours) {
        self.defaults = .standard
        self.shouldPersist = false
        self.doses = previewDoses
        self.halfLifeHours = halfLifeHours
    }

    static var preview: CaffeineStore {
        let now = Date()
        return CaffeineStore(
            previewDoses: [
                CaffeineDose(name: "拿铁", milligrams: 120, date: now.addingTimeInterval(-2.2 * 60 * 60)),
                CaffeineDose(name: "茶", milligrams: 45, date: now.addingTimeInterval(-5.5 * 60 * 60))
            ]
        )
    }

    var recentDoses: [CaffeineDose] {
        doses.sorted { $0.date > $1.date }
    }

    func add(_ preset: CaffeinePreset, at date: Date = Date()) {
        doses.insert(
            CaffeineDose(name: preset.title, milligrams: preset.milligrams, date: date),
            at: 0
        )
        purgeExpiredEntries(now: date)
    }

    func remove(_ dose: CaffeineDose) {
        doses.removeAll { $0.id == dose.id }
    }

    func clearToday(at date: Date = Date()) {
        let calendar = Calendar.current
        doses.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func clearAll() {
        doses.removeAll()
    }

    func snapshot(at date: Date = Date()) -> CaffeineSnapshot {
        let activeDoses = CaffeineMetabolism.activeDoses(from: doses, at: date)
        let totalActive = activeDoses.reduce(0) { $0 + $1.milligrams }
        let remaining = CaffeineMetabolism.remainingMilligrams(
            from: activeDoses,
            at: date,
            halfLifeHours: halfLifeHours
        )
        let lowCaffeineDate = CaffeineMetabolism.timeBelowMilligrams(
            CaffeineMetabolism.lowCaffeineThresholdMilligrams,
            from: activeDoses,
            at: date,
            halfLifeHours: halfLifeHours
        )
        let todayTotal = doses
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.milligrams }

        return CaffeineSnapshot(
            date: date,
            activeDoseCount: activeDoses.count,
            totalActiveMilligrams: totalActive,
            totalTodayMilligrams: todayTotal,
            remainingMilligrams: remaining,
            lowCaffeineDate: lowCaffeineDate,
            lastDoseName: activeDoses.first?.name
        )
    }

    private func purgeExpiredEntries(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-72 * 60 * 60)
        doses.removeAll { $0.date < cutoff }
    }

    private func persist() {
        guard shouldPersist else { return }

        if let data = try? JSONEncoder().encode(doses) {
            defaults.set(data, forKey: Keys.doses)
        }

    }

    private static func loadDoses(from defaults: UserDefaults) -> [CaffeineDose] {
        guard let data = defaults.data(forKey: Keys.doses),
              let decoded = try? JSONDecoder().decode([CaffeineDose].self, from: data)
        else {
            return []
        }

        return decoded
    }
}

extension Date {
    func clockText(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    func shortDayText(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day], from: self)
        return String(format: "%02d/%02d", components.month ?? 0, components.day ?? 0)
    }
}
