//
//  ProgressBar.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 19/03/2024.
//

import SwiftUI

struct ProgressBar: View {
    @ObservedObject var authState: AuthState

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Spacer()
                    .frame(height: geometry.size.height * 0.01)
                HStack {
                    Text("Select Your Task")
                        .font(AuthState.Typography.font_1_bold)
                    Spacer()
                }
                .padding(.horizontal, geometry.size.width * 0.04)
                .padding(.vertical, geometry.size.height * 0.04)
                
                ForEach(authState.progressTasks.indices, id:\.self) {index in
                    let item = authState.progressTasks[index]
                    Button {
                        withAnimation {
                            Task {
                                await authState.newTaskAdder(task: item)
                                await authState.taskTimeCaller(for: item)
                            }
                            authState.taskName = item
                            authState.isTaskDropDownVisible.toggle()
                            authState.taskTime = authState.resetTimer() ?? 0
                        }
                    } label: {
                        ZStack(alignment: .leading) {
                            
                            Capsule()
                                .fill(Color.gray)
                                .frame(width: geometry.size.width * (authState.maxWidth/370), height: geometry.size.height * 0.07)
                            
                            Capsule()
                                .fill(Color.blue)
                                .frame(
                                    width: (authState.newTimeArray[item] ?? 0) > 0 ?
                                        max(
                                            geometry.size.width * ((CGFloat(authState.newTimeArray[item] ?? 0))/370),
                                            geometry.size.width * (authState.maxWidth/370) * 0.07
                                        ) : 0,
                                    height: geometry.size.height * 0.07
                                )
                            
                            HStack {
                                Spacer()
                                Text("\(item)")
                                    .font(AuthState.Typography.font_1_bold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, geometry.size.width * 0.04)
                    .padding(.bottom, geometry.size.height * 0.03)
                }
                
                Button(action: {
                    authState.taskString = "" // Clear the task input field
                    authState.isAddTaskVisible.toggle()
                }) {
                    ZStack {
                        /*
                        Capsule()
                            .fill(Color.gray)
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.07)
                        */
                        Text("Add Task")
                            .font(AuthState.Typography.font_1_bold)
                            .foregroundColor(Color.white)
                    }
                }
                .padding(.vertical, geometry.size.height * 0.03)
                .sheet(isPresented:  $authState.isAddTaskVisible) {
                    AddTask(authState: authState)
                        .presentationDetents([.fraction(1/4)])
                }
            }
        }
    }
}

struct ProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        ProgressBar(authState: AuthState())
    }
}
