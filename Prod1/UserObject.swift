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

struct CalendarData: Codable {
    var tasks: [String]
    var taskDecimalDict: [String: Double]
    var taskPercentageDict: [String: Int]
    var taskTimerDictionary: [String: Int]
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
}

struct PostData: Identifiable, Hashable {
    let id: String
    let userId: String
    let dayOfYear: Int
    let image: UIImage
    let timestamp: Timestamp
    let username: String
    let caption: String
    var initial: String {
        return username.first?.uppercased() ?? ""
    }
    let likeCount: Int
    var likes: [String: Bool]
    let commentsData: [CommentsData]
}

struct CommentsData: Identifiable, Hashable {
    let id: String
    let userId: String
    let timestamp: Timestamp
    let username: String
    var initial: String {
        return username.first?.uppercased() ?? ""
    }
    let comment: String
}
