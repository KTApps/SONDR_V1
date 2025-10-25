import SwiftUI

struct SignUpView: View {
    @ObservedObject var authState: AuthState
    
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    
                    // MARK: Logo Group
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
                    
                    // MARK: Input Group
                    VStack {
                        Input(text: $username,
                              title: "Username",
                              placeHolder: "Enter your username")
                        .foregroundColor(.white)
                        
                        
                        Input(text: $email,
                              title: "Email Address",
                              placeHolder: "name@example.com")
                        .autocapitalization(.none)
                        .foregroundColor(.white)
                        
                        ZStack(alignment: .trailing) {
                            Input(text: $password,
                                  title: "Password",
                                  placeHolder: "********",
                                  secureField: true)
                            .foregroundColor(.white)
                            
                            VStack {
                                
                                if !password.isEmpty {
                                    if password.count < 6 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.callout)
                                            .opacity(0.5)
                                            .foregroundColor(.red)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.callout)
                                            .opacity(0.5)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding(.top, 28)
                            .padding(.horizontal, 10)
                        }
                        
                        Spacer()
                            .frame(height: geometry.size.width * 0.08)
                        
                        Button {
                            Task {
                                try await authState.signUp(withEmail: email,
                                                           password: password,
                                                           username: username)
                            }
                        } label: {
                            Text("SIGN UP")
                                .foregroundColor(.white)
                                .font(AuthState.Typography.font_1_bold_sondr)
                        }
                        //.disabled(!isFormValid)
                        //.opacity(isFormValid ? 1 : 0.5)
                    }
                    
                    Spacer()
                        
                    // MARK: Navigation Group
                    NavigationLink {
                        LogInView(authState: authState)
                            .navigationBarBackButtonHidden(true)
                    } label: {
                        HStack {
                            Text("Already have an account?")
                                .font(AuthState.Typography.font_1_light)
                            Text("LOG IN")
                                .font(AuthState.Typography.font_1_bold)
                        }
                        .foregroundColor(.white)
                    }
                    
                }
                .padding(.horizontal, geometry.size.width * 0.05)  // 5% horizontal padding
                .padding(.vertical, geometry.size.height * 0.05)  // 5% vertical padding
                .alert("Email already exists", isPresented: $authState.signUpError) {
                    Button("Try again") {
                        authState.signUpError.toggle()
                    }
                }
                .alert("Username is taken", isPresented: $authState.usernameExists) {
                    Button("Try again") {
                        authState.usernameExists.toggle()
                    }
                }
            }
            .keyboardResponsive()
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
        return SignUpView(authState: AuthState())
    }
}
