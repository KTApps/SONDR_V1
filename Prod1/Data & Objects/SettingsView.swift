//
//  SettingsView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        if let user = authViewModel.currentUser {
            List {
                
    //            MARK: PROFILE Section
                Section {
                    HStack {
                        Text(user.initials)
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(Color.gray)
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(user.fullname)
                            Text(user.email)
                        }
                    }
                }
                
    //            MARK: BUTTON Section
                Section("Account") {
                    Button {
                        authViewModel.SignOut()
                    } label: {
                        SettingsButton(image: "arrow.backward.circle.fill", action: "Sign Out")
                    }
                    
                    Button {
                        authViewModel.DeleteAccount()
                    } label: {
                        SettingsButton(image: "x.circle.fill", action: "Delete Account")
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
