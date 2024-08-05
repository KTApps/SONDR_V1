//
//  Profile.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 02/07/2024.
//

import SwiftUI

struct ProfileBlurView: View {
    @EnvironmentObject var authModel: AuthViewModel
    
    var body: some View {
        ZStack {
            BlurEffect(style: .systemMaterialDark)
            Profile()
                .foregroundColor(Color.white)
        }
    }
}

#Preview {
    ProfileBlurView()
        .ignoresSafeArea()
        .environmentObject(AuthViewModel())
}
