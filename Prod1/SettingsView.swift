//
//  SettingsView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: ViewModel
    
    var body: some View {
        if let user = viewModel.currentUser {
            List {
                Section {
                    HStack {
                        Text(user.initial)
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 70)
                            .background(Color.gray)
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(user.username)
                            Text(user.email)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("Account") {
                    
                    Button(role: .destructive) {
                        withAnimation {
                            viewModel.signOut()
                        }
                    } label: {
                        SettingsButton(image: "arrow.left.circle.fill", action: "Log off")
                    }
                    
                    Button(role: .destructive) {
                        Task {
                            try await viewModel.deleteAccount()
                        }
                    } label: {
                        SettingsButton(image: "x.circle.fill", action: "Delete Account")
                    }
                }
                .foregroundColor(.black)
            }
        } 
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        return SettingsView()
            .environmentObject(MockViewModel() as ViewModel) // Inject authViewModel as environment object
    }
}


