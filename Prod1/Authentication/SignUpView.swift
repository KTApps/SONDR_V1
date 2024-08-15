//
//  SignUpView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 11/03/2024.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var viewModel: ViewModel
    
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                    .frame(height: 60)
                
                ZStack {
                    Circle()
                        .stroke(lineWidth: 25)
                        .foregroundColor(.blue)
                        .frame(height: 260)
                    
                    Circle()
                        .stroke(lineWidth: 25)
                        .foregroundColor(.blue)
                        .frame(height: 160)
                    
                    Text("SONDR")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                    .frame(height: 20)
                
                Input(text: $username, title: "username", placeHolder: "username")
                .foregroundColor(.white)
                
                Spacer()
                    .frame(height: 20)
                
                Input(text: $email, title: "Email Address", placeHolder: "name@example.com")
                .autocapitalization(/*@START_MENU_TOKEN@*/.none/*@END_MENU_TOKEN@*/)
                .foregroundColor(.white)
                
                Spacer()
                    .frame(height: 20)
                
                ZStack(alignment: .trailing) {
                    Input(text: $password,
                                title: "Password",
                                placeHolder: "********",
                                secureField: true)
                    .foregroundColor(.white)
                    
                    VStack {
                        Spacer()
                            .frame(height: 30)
                        
                        if !password.isEmpty {
                            if password.count < 6 {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundColor(.red)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                Spacer()
                    .frame(height: 30)
                
                Button {
                    Task {
                        try await viewModel.signUp(withEmail: email,
                                                   password: password,
                                                   username: username)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: 350, height: 40)
                            .foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                        Text("SIGN UP")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .disabled(!isFormValid)
                .opacity(isFormValid ? 1 : 0.5)
                
                Spacer()
                
                NavigationLink {
                    LogInView()
                        .navigationBarBackButtonHidden(true)
                } label: {
                    HStack {
                        Text("Already have an account?")
                        Text("LOG IN")
                            .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                    }
                    .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 10)
            .alert("User already exists", isPresented: $viewModel.signUpError) {
                Button("Try again") {
                    viewModel.signUpError.toggle()
                }
            }
        }
    }
}

extension SignUpView: AuthFormValidation {
    var isFormValid: Bool {
        return !username.isEmpty
        && !email.isEmpty
        && email.contains("@")
        && password.count > 5
    }
}

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        return SignUpView()
            .environmentObject(MockViewModel() as ViewModel)
    }
}
