//
//  HabitDataModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 07/06/2025.
//

struct HabitDataModel: Codable {
    var habitIdArray: [String]
    var habitIdName: [String: String]
    var isHabitStriked: [String: Bool]
}
