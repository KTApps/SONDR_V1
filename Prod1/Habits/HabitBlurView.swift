//
//  BlurView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 16/02/2024.
//

import SwiftUI

struct HabitBlurView: View {
    @EnvironmentObject var authModel: AuthViewModel
    
    var body: some View {
        ZStack {
            Button(action: {
                authModel.isBlurViewVisible = false
            }) {
                BlurEffect(style: .systemMaterialDark)
            }
            HabitTracker()
                .foregroundColor(Color.white)
        }
    }
}

#Preview {
    HabitBlurView()
        .ignoresSafeArea()
        .environmentObject(AuthViewModel())
}
