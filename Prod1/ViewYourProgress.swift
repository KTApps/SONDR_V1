//
//  ProgressView.swift
//  Prod1
//
//  Created by Tanaka Bere on 11/02/2024.
//

import SwiftUI
import Charts
 
struct ViewYourProgress: View {
    @ObservedObject var authState: AuthState
    
    var body: some View {
        GeometryReader { geometry in
            ZStack{
                authState.darkGray.ignoresSafeArea()
                VStack {
                    Text("SONDR")
                        .font(AuthState.Typography.font_1_bold)
                        .foregroundColor(.white)

                    Spacer()
                        .frame(height: geometry.size.height * 0.025)
                    
                    CalendarView(authState: authState)
                    
                    Spacer()
                }
                .padding(.vertical, geometry.size.height * 0.035)
            }
        }
    }
}

struct ViewYourProgress_Previews: PreviewProvider {
    static var previews: some View {
        return ViewYourProgress(authState: AuthState())
    }
}
