//
//  LogInView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct LogInView: View {
    @ObservedObject var authState: AuthState
    
    @State var email: String = ""
    @State var password: String = ""
    @State var eyeball: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack {
                        
            //            MARK: PLAY BUTTON
                        ZStack {
                            Circle()
                                .stroke(lineWidth: 22)
                                .foregroundColor(.blue)
                                .frame(width: geometry.size.width * 0.57)
                            
                            Circle()
                                .stroke(lineWidth: 22)
                                .foregroundColor(.blue)
                                .frame(width: geometry.size.width * 0.40)
                            
                            Text("SONDR")
                                .font(AuthState.Typography.font_1_bold_sondr)
                        }
                        
                        Spacer()
                            .frame(height: 150)
                        
            //            MARK: USER INPUT Section
                        VStack {
                            Input(text: $email,
                                  title: "Email",
                                  placeHolder: "name@example.com",
                                  secureField: false)
                                .foregroundColor(.white)
                                .font(.custom("1st_font", size: 20))
                                .fontWeight(.bold)
                            
                            Input(text: $password,
                                  title: "Password",
                                  placeHolder: "******",
                                  secureField: !eyeball)
                                .foregroundColor(.white)
                                .overlay(
                                    Button {
                                        eyeball.toggle()
                                    } label: {
                                        Image(systemName: "eye")
                                            .font(.system(size: 15))
                                            .opacity(0.5)
                                            .foregroundColor(eyeball ? Color.white : Color.red)
                                    }
                                    .padding(.top, 33)
                                    .padding(.trailing, 9),
                                    alignment: .trailing
                                )
                            
                            Spacer()
                                .frame(height: geometry.size.height * 0.05)
                            
                //            MARK: LOGN IN Button
                            Button {
                                Task {
                                    try await authState.logIn(withEmail: email, password: password)
                                }
                            } label: {
                                Text("LOG IN")
                                    .foregroundColor(.white)
                                    .font(AuthState.Typography.font_1_bold_sondr)
                            }
                            //.disabled(!isFormValid)
                            //.opacity(isFormValid ? 1 : 0.5)
                        }
                        
                        Spacer()
                        
            //            MARK: SIGN UP Button
                        NavigationLink {
                            SignUpView(authState: authState)
                                .navigationBarBackButtonHidden(true)
                        } label: {
                            HStack {
                                Text("Don't have an Account?")
                                    .font(AuthState.Typography.font_1_light)
                                Text("SIGN UP")
                                    .font(AuthState.Typography.font_1_bold)
                            }
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, geometry.size.width * 0.05)
                    .padding(.vertical, geometry.size.height * 0.05)
                    .alert("User doesn't exist", isPresented: $authState.logInError) {
                        Button("Try again") {
                            authState.logInError.toggle()
                        }
                    }
                }
                .keyboardResponsive()
            }
        }
    }
}

extension LogInView: AuthFormValidation {
    var isFormValid: Bool {
        return !email.isEmpty
        && email.contains("@")
        && password.count > 5
    }
}

struct LogInView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LogInView(authState: AuthState())
        }
    }
}
