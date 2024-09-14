//
//  UserObject.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

//  MARK: CUSTOM DATA MODELS

import Foundation
import SwiftUI
import Firebase

struct UserObject: Identifiable, Codable {
    let id: String
    let username: String
    let email: String
    var initial: String {
        return username.first?.uppercased() ?? ""
    }
}

struct TaskData: Codable {
    var tasks: [String]
    var taskTimerDictionary: [String: Int]
}

struct ProgressData: Codable {
    var progressTasks: [String]
    var progressTimerDictionary: [String: Int]
    var taskDecimalDict: [String: Double]
    var taskMaxTime: [String: Int]
}

struct HabitData: Codable {
    var habitIdArray: [String]
    var habitIdName: [String: String]
    var isHabitStriked: [String: Bool]
}

struct Friends: Codable {
    let friends: [String]
}

struct Analytics: Codable {
    var dayTracker: [Int]
    var dayTrackerOffset: Int
    var habitStreak: Int
    var cumulativeTasks: [String: Int]
}
