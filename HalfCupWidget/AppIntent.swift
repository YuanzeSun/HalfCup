//
//  AppIntent.swift
//  HalfCupWidget
//
//  Created by Luca on 2026/5/20.
//

import WidgetKit
import AppIntents

enum HalfCupComplicationMode: String, AppEnum {
    case stargazing
    case moonPlanet
    case training
    case stamina
    case hrv
    case caffeine
    case barometer

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "HalfCup 显示")
    }

    static var caseDisplayRepresentations: [HalfCupComplicationMode: DisplayRepresentation] {
        [
            .stargazing: DisplayRepresentation(title: "观星窗口"),
            .moonPlanet: DisplayRepresentation(title: "月亮/行星"),
            .training: DisplayRepresentation(title: "训练状态"),
            .stamina: DisplayRepresentation(title: "体力/睡眠债"),
            .hrv: DisplayRepresentation(title: "HRV 压力"),
            .caffeine: DisplayRepresentation(title: "咖啡因"),
            .barometer: DisplayRepresentation(title: "实时气压")
        ]
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "HalfCup 表盘" }
    static var description: IntentDescription { "选择 HalfCup 在表盘上显示的摘要。" }

    @Parameter(title: "显示内容", default: .stargazing)
    var mode: HalfCupComplicationMode
}
