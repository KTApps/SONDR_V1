//
//  UserObject.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

//  MARK: CUSTOM DATA MODELS

struct AuthModel: Identifiable, Codable {
    let id: String
    let username: String
    let email: String
    var initial: String {
        return username.first?.uppercased() ?? ""
    }
}
