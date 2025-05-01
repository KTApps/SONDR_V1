//
//  ProgressBar.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 19/03/2024.
//

import SwiftUI

struct ProgressBar: View {
    @EnvironmentObject var viewModel: ViewModel

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Spacer()
                    .frame(height: geometry.size.height * 0.01)
                HStack {
                    Text("Select Your Task")
                        .font(.system(size: geometry.size.width * 0.04))
                    Spacer()
                }
                .padding(.horizontal, geometry.size.width * 0.04)
                .padding(.vertical, geometry.size.height * 0.04)
                
                ForEach(viewModel.progressTasks.indices, id:\.self) {index in
                    let item = viewModel.progressTasks[index]
                    Button {
                        withAnimation {
                            Task {
                                await viewModel.newTaskAdder(task: item)
                            }
                            viewModel.taskName = item
                            viewModel.isTaskDropDownVisible.toggle()
                            viewModel.taskTime = viewModel.resetTimer() ?? 0
                        }
                    } label: {
                        ZStack(alignment: .leading) {
                            
                            Capsule()
                                .fill(Color.gray)
                                .frame(width: geometry.size.width * (viewModel.maxWidth/370), height: geometry.size.height * 0.07)
                            
                            Capsule()
                                .fill(Color.blue)
                                .frame(
                                    width: (viewModel.newTimeArray[item] ?? 0) > 0 ?
                                        max(
                                            geometry.size.width * ((CGFloat(viewModel.newTimeArray[item] ?? 0))/370),
                                            geometry.size.width * (viewModel.maxWidth/370) * 0.07
                                        ) : 0,
                                    height: geometry.size.height * 0.07
                                )
                            
                            HStack {
                                Spacer()
                                Text("\(item)")
                                    .font(.system(size: geometry.size.width * 0.05))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, geometry.size.width * 0.04)
                    .padding(.bottom, geometry.size.height * 0.03)
                }
                
                Button(action: {
                    viewModel.taskString = "" // Clear the task input field
                    viewModel.isAddTaskVisible.toggle()
                }) {
                    ZStack {
                        Capsule()
                            .fill(Color.gray)
                            .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.07)
                        
                        Text("Add Task")
                            .font(.system(size: geometry.size.width * 0.05))
                            .foregroundColor(Color.white)
                    }
                }
                .padding(.vertical, geometry.size.height * 0.03)
                .sheet(isPresented:  $viewModel.isAddTaskVisible) {
                    AddTask()
                        .presentationDetents([.fraction(1/4)])
                }
            }
        }
    }
}

struct ProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        ProgressBar()
            .environmentObject(MockViewModel() as ViewModel)
    }
}
