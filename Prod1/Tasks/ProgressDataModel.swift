//
//  ProgressDataModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 07/06/2025.
//

struct ProgressDataModel: Codable {
    var progressTasks: [String]
    var progressTimerDictionary: [String: Int]
    var taskDecimalDict: [String: Double]
    var taskMaxTime: [String: Int]
}
