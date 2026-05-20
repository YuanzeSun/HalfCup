//
//  HalfCup_Watch_AppTests.swift
//  HalfCup Watch AppTests
//
//  Created by Luca on 2026/5/20.
//

import Foundation
import Testing
@testable import HalfCup_Watch_App

struct HalfCup_Watch_AppTests {
    @Test func caffeineDoseDecaysByHalfLife() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let dose = CaffeineDose(name: "Coffee", milligrams: 120, date: start)

        let remaining = CaffeineMetabolism.remainingMilligrams(
            from: [dose],
            at: start.addingTimeInterval(5 * 60 * 60),
            halfLifeHours: 5
        )

        #expect(abs(remaining - 60) < 0.01)
    }

    @Test func lowCaffeineThresholdUsesAbsoluteMilligrams() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let espresso = CaffeineDose(name: "Espresso", milligrams: 80, date: start)
        let latte = CaffeineDose(name: "Latte", milligrams: 160, date: start)

        let espressoLow = CaffeineMetabolism.timeBelowMilligrams(
            30,
            from: [espresso],
            at: start,
            halfLifeHours: 5
        )
        let latteLow = CaffeineMetabolism.timeBelowMilligrams(
            30,
            from: [latte],
            at: start,
            halfLifeHours: 5
        )

        #expect(espressoLow != nil)
        #expect(latteLow == espressoLow?.addingTimeInterval(5 * 60 * 60))
    }

    @Test func snapshotTotalsTodayAndActiveRemaining() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = CaffeineStore(
            previewDoses: [
                CaffeineDose(name: "Espresso", milligrams: 80, date: now.addingTimeInterval(-60 * 60)),
                CaffeineDose(name: "Tea", milligrams: 40, date: now.addingTimeInterval(-4 * 60 * 60))
            ],
            halfLifeHours: 5
        )

        let snapshot = store.snapshot(at: now)

        #expect(snapshot.activeDoseCount == 2)
        #expect(snapshot.totalTodayMilligrams == 120)
        #expect(snapshot.remainingMilligrams < 120)
        #expect(snapshot.lowCaffeineDate != nil)
    }
}
