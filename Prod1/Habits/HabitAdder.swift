//
//  HabitAdder.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 18/02/2024.
//

import SwiftUI

struct HabitAdder: View {
    @EnvironmentObject var viewModel: ViewModel
        
    var body: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            
            VStack {
                
//                MARK: TASK HStack
                HStack {
                    Text("Task")
                    Spacer()
                }
                .shadow(radius: 3, x: 3, y: 3)
                .padding(.horizontal, 2)
                
                TextField("Task Name", text: $viewModel.habitName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .colorInvert()
                    .shadow(radius: 5, x: 3, y: 3)
                    .autocapitalization(.none)
                
                Spacer()
                    .frame(height: 30)
                
//                MARK: SAVE Button
                Button(action: {
                    viewModel.habitAppender()
                    viewModel.habitName = ""
                }) {
                    Text("Save")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(15)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(25)
                        .shadow(radius: 5, x: 3, y: 3)
                }
                Spacer()
            }
            .padding(.top, 30)
            .padding(.horizontal, 30)
        }
    }
}

//struct HabitAdder_Previews: PreviewProvider {
//    static var previews: some View {
//        HabitAdder()
//            .foregroundColor(.black)
//            .environmentObject(AuthViewModel())
//    }
//}
