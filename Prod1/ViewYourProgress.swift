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
        ZStack{
            authState.darkGray.ignoresSafeArea()
            VStack {
                Text("SONDR")
                    .font(AuthState.Typography.font_1_bold)
                    .foregroundColor(.white)

                Spacer()
                    .frame(height: 20)
                
                CalendarView(authState: authState)
                
                Spacer()
            }
            .padding(.vertical, 30)
        }
    }
}

struct ViewYourProgress_Previews: PreviewProvider {
    static var previews: some View {
        return ViewYourProgress(authState: AuthState())
    }
}
