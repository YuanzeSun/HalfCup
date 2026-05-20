//
//  HalfCupWidgetBundle.swift
//  HalfCupWidget
//
//  Created by Luca on 2026/5/20.
//

import WidgetKit
import SwiftUI

@main
struct HalfCupWidgetBundle: WidgetBundle {
    var body: some Widget {
        HalfCupStargazingWidget()
        HalfCupMoonPlanetWidget()
        HalfCupTrainingWidget()
        HalfCupStaminaWidget()
        HalfCupHRVWidget()
        HalfCupCaffeineWidget()
        HalfCupBarometerWidget()
    }
}
