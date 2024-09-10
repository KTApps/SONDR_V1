//
//  LogInView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct LogInView: View {
    @EnvironmentObject var viewModel: ViewModel
    
    @State var email: String = ""
    @State var password: String = ""
    @State var eyeball: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                        .frame(height: 100)
                    
        //            MARK: PLAY BUTTON
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 25)
                            .foregroundColor(.blue)
                            .frame(height: 280)
                        
                        Circle()
                            .stroke(lineWidth: 25)
                            .foregroundColor(.blue)
                            .frame(height: 180)
                        
                        Text("SONDR")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                        .frame(height: 60)
                    
        //            MARK: USER INPUT Section
                    Input(text: $email, 
                          title: "Email",
                          placeHolder: "name@example.com",
                          secureField: false)
                        .foregroundColor(.white)
                    
                    Spacer()
                        .frame(height: 15)
                    
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
                            print("week index is: ", viewModel.weekDayIndexCounter)
                            print("current day is: ", viewModel.currentDayOfWeek)
                        } label: {
                            VStack {
                                Spacer()
                                    .frame(height: 30)
                                
                                Image(systemName: "eye")
                                    .font(.callout)
                                    .foregroundColor(eyeball ? Color.white : Color.red)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    
                    Spacer()
                        .frame(height: 20)
                    
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
                            .frame(width: 350, height: 50)
                            .background(Color.blue)
                            .cornerRadius(20)
                    }
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1 : 0.5)
                    
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

extension LogInView: AuthFormValidation {
    var isFormValid: Bool {
        return !email.isEmpty
        && email.contains("@")
        && password.count > 5
    }
}

struct LogInView_Previews: PreviewProvider {
    static var previews: some View {
        return LogInView()
            .environmentObject(MockViewModel() as ViewModel)
    }
}
