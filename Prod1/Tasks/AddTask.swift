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
        GeometryReader { geometry in
            VStack {
                TextField("Task name", text: $authState.taskString)
                    .padding(geometry.size.width * 0.025)
                    .border(Color.white)
                
                Spacer()
                    .frame(height: geometry.size.height * 0.08)
                
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
            .padding(geometry.size.width * 0.05)
        }
    }
}

struct AddTask_Previews: PreviewProvider {
    static var previews: some View {
        AddTask(authState: AuthState())
    }
}
