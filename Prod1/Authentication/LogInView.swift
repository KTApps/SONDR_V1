//
//  LogInView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct LogInView: View {
    @EnvironmentObject var viewModel: AuthState
    
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
                                .stroke(lineWidth: 25)
                                .foregroundColor(.blue)
                                .frame(width: geometry.size.width * 0.65, height: geometry.size.width * 0.65)
                            
                            Circle()
                                .stroke(lineWidth: 25)
                                .foregroundColor(.blue)
                                .frame(width: geometry.size.width * 0.45, height: geometry.size.width * 0.45)
                            
                            Text("SONDR")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
            //            MARK: USER INPUT Section
                        VStack {
                            Input(text: $email,
                                  title: "Email",
                                  placeHolder: "name@example.com",
                                  secureField: false)
                                .foregroundColor(.white)
                            
                            ZStack(alignment: .trailing) {
                                if eyeball {
                                    Input(text: $password,
                                          title: "Password",
                                          placeHolder: "******",
                                          secureField: false)
                                        .foregroundColor(.white)
                                } else {
                                    Input(text: $password,
                                          title: "Password",
                                          placeHolder: "******",
                                          secureField: true)
                                        .foregroundColor(.white)
                                }
                                
                                Button {
                                    eyeball.toggle()
                                } label: {
                                    VStack {
                                        Spacer()
                                            .frame(height: geometry.size.height * 0.03)
                                        
                                        Image(systemName: "eye")
                                            .font(.system(size: 15))
                                            .opacity(0.5)
                                            .foregroundColor(eyeball ? Color.white : Color.red)
                                    }
                                }
                                .padding(.top, 7)
                                .padding(.horizontal, 9)
                            }
                            
                            Spacer()
                                .frame(height: geometry.size.height * 0.05)
                            
                //            MARK: LOGN IN Button
                            Button {
                                Task {
                                    try await viewModel.logIn(withEmail: email, password: password)
                                }
                            } label: {
                                Text("LOG IN")
                                    .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .frame(width: geometry.size.width * 0.85, height: 50)
                                    .background(Color.blue)
                                    .cornerRadius(20)
                            }
                            .disabled(!isFormValid)
                            .opacity(isFormValid ? 1 : 0.5)
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
                    .padding(.horizontal, geometry.size.width * 0.05)
                    .padding(.vertical, geometry.size.height * 0.05)
                    .alert("User doesn't exist", isPresented: $viewModel.logInError) {
                        Button("Try again") {
                            viewModel.logInError.toggle()
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
            LogInView()
                .environmentObject(MockViewModel() as AuthState)
        }
    }
}
