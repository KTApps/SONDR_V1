//
//  SettingsButton.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 15/03/2024.
//

import SwiftUI

struct SettingsButton: View {
    let image: String
    let action: String
    
    var body: some View {
        HStack {
            Image(systemName: image)
                .foregroundColor(.red)
            Text(action)
        }
        .font(.title2)
    }
}

#Preview {
    SettingsButton(image: "arrow.backward.circle.fill", action: "Sign Out")
}
