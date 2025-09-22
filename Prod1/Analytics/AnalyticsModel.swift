//
//  AnalyticsModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 07/06/2025.
//

struct AnalyticsModel: Codable {
    var dayTracker: [Int]
    var dayTrackerOffset: Int
    var habitStreak: Int
    var cumulativeTasks: [String: Int]
}
