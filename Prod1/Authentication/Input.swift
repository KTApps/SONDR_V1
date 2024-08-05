//
//  Input.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 11/03/2024.
//

import SwiftUI

struct Input: View {
    @Binding var text: String
    let title: String
    let placeHolder: String
    var secureField = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            
            if secureField {
                SecureField(placeHolder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
            } else {
                TextField(placeHolder, text: $text)
                    .textFieldStyle(CustomTextFieldStyle())
            }
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(8)
            .cornerRadius(8)
        //  Border
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 0.3)
            )
            .foregroundColor(.white) // Text color
    }
}

//#Preview {
//    Input(text: .constant(""), title: "Email Address", placeHolder: "name@example.com")
//}
