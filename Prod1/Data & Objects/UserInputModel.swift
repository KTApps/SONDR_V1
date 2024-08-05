//
//  UserInputModel.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct UserInputModel: View {
    @Binding var text: String
    let title: String
    let placeholder: String
    var secureField: Bool = true
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            if !secureField {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }
        }
    }
}

#Preview {
    UserInputModel(text: .constant(""), title: "Email", placeholder: "name@example.com")
}
