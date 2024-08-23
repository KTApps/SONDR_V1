//
//  ProgressView.swift
//  Prod1
//
//  Created by Tanaka Bere on 11/02/2024.
//

import SwiftUI
import Charts
 
struct ViewYourProgress: View {
    @EnvironmentObject var viewModel: ViewModel
    
    var body: some View {
        ZStack{
            viewModel.darkGray.ignoresSafeArea()
            VStack {
                Text("Progress")
                    .foregroundColor(.white)

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
