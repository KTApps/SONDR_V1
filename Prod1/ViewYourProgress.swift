//
//  ProgressView.swift
//  Prod1
//
//  Created by Tanaka Bere on 11/02/2024.
//

import SwiftUI
import Charts
 
struct ViewYourProgress: View {
    @State private var count: Int = 7
    
    var body: some View {
        ZStack{
            Color.gray.ignoresSafeArea()
            VStack {
                Text("Progress")
                    .foregroundColor(.black)

                Spacer()
                    .frame(height: 0)
                
                CalendarView()
                
                Spacer()
            }
            .padding(.vertical, 30)
        }
    }
}

struct ViewYourProgress_Previews: PreviewProvider {
    static var previews: some View {
        return ViewYourProgress()
            .environmentObject(MockViewModel() as ViewModel)
    }
}
