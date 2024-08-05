//
//  LogInView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct LogInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State var email: String = ""
    @State var password: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                        .frame(height: 100)
                    
        //            MARK: PLAY BUTTON
                    Image(systemName: "play.circle.fill")
                        .resizable()
                        .frame(width: 130, height: 130)
                        .foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                    
                    Spacer()
                        .frame(height: 60)
                    
        //            MARK: USER INPUT Section
                    UserInputModel(text: $email, 
                                   title: "Email",
                                   placeholder: "name@example.com",
                                   secureField: false)
                        .foregroundColor(.white)
                    
                    Spacer()
                        .frame(height: 15)
                    
                    UserInputModel(text: $email, 
                                   title: "Password",
                                   placeholder: "******",
                                   secureField: true)
                        .foregroundColor(.white)
                    
                    Spacer()
                        .frame(height: 20)
                    
        //            MARK: LOGN IN Button
                    Button {
                        Task {
                            try await authViewModel.LogIn(withEmail: email, password: password)
                        }
                    } label: {
                        Text("LOG IN")
                            .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .frame(width: 350, height: 50)
                            .background(Color.blue)
                            .cornerRadius(20)
                    }
                    
                    Spacer()
                    
        //            MARK: SIGN UP Button
                    NavigationLink {
                        SignUpView()
                            .navigationBarBackButtonHidden(true)
                    } label: {
                        HStack {
                            Text("Don't have an Account?")
                            Text("SIGN UP")
                        }
                    }
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
            }
        }
    }
}

#Preview {
    LogInView()
}
