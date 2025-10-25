//
//  AddTask.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 24/03/2024.
//

import SwiftUI

struct AddTask: View {
    @ObservedObject var authState: AuthState
    
    var body: some View {
        VStack {
            TextField("Task name", text: $authState.taskString)
                .padding(10)
                .border(Color.white)
            
            Spacer()
                .frame(height: 20)
            
            Button {
                Task {
                    await authState.taskAdder()
                }
                authState.isAddTaskVisible = false
            } label: {
                ZStack {
                    /*
                    Capsule()
                        .fill(Color.gray)
                    .frame(width: 150, height: 32)
                    */
                    Text("Add Task")
                        .font(AuthState.Typography.font_1_bold)
                        .foregroundColor(Color.white)
                }
            }
            Spacer()
        }
        .padding(20)
    }
}

struct AddTask_Previews: PreviewProvider {
    static var previews: some View {
        AddTask(authState: AuthState())
    }
}
