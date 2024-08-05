//
//  SettingsViewModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import Foundation

struct User: Identifiable, Codable {
    var id: String
    var fullname: String
    var email: String
    
    var initials: String {
        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: fullname) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        return ""
    }
}
