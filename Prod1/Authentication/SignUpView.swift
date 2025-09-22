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
                            .stroke(lineWidth: 25)
                            .foregroundColor(.blue)
                            .frame(width: geometry.size.width * 0.65, height: geometry.size.width * 0.65)  // Dynamic Circle
                        
                        Circle()
                            .stroke(lineWidth: 25)
                            .foregroundColor(.blue)
                            .frame(width: geometry.size.width * 0.45, height: geometry.size.width * 0.45)  // Dynamic Circle
                        
                        Text("SONDR")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
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
                            .frame(height: geometry.size.width * 0.05)
                        
                        Button {
                            Task {
                                try await authState.signUp(withEmail: email,
                                                           password: password,
                                                           username: username)
                            }
                        } label: {
                            Text("SIGN UP")
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
                        
                    // MARK: Navigation Group
                    NavigationLink {
                        LogInView(authState: authState)
                            .navigationBarBackButtonHidden(true)
                    } label: {
                        HStack {
                            Text("Already have an account?")
                            Text("LOG IN")
                                .fontWeight(.bold)
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
