//
//  ProgressBar.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 19/03/2024.
//

import SwiftUI

struct CustomProgressBar: View {
    @EnvironmentObject var viewModel: ViewModel

    var body: some View {
        ScrollView {
            Spacer()
                .frame(height: 12)
            HStack {
                Text("Select Your Task")
                Spacer()
            }
            .padding(.horizontal, 17)
            ForEach(viewModel.progressTasks.indices, id:\.self) {index in
                let item = viewModel.progressTasks[index]
                Button {
                    withAnimation {
                        viewModel.newTaskAdder(task: item)
                        viewModel.taskName = item
                        viewModel.isTaskDropDownVisible.toggle()
                        viewModel.taskTime = viewModel.resetTimer() ?? 0
                    }
                } label: {
                    ZStack(alignment: .leading) {
                        
                        Capsule()
                            .fill(Color.gray)
                            .frame(width: viewModel.maxWidth, height: 32)
                        
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: (CGFloat(viewModel.newTimeArray[item] ?? 0)), height: 32)
                        
                        HStack {
                            Spacer()
                            Text("\(item)")
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
            }
            
            Button(action: {
                viewModel.isAddTaskVisible.toggle()
            }) {
                ZStack {
                    Capsule()
                        .fill(Color.gray)
                    .frame(width: 150, height: 32)
                    
                    Text("Add Task")
                        .font(.title3)
                        .foregroundColor(Color.white)
                }
            }
            .padding(.vertical, 15)
            .sheet(isPresented:  $viewModel.isAddTaskVisible) {
                AddTask()
                    .presentationDetents([.fraction(1/4)])
            }
        }
    }
}

struct CustomProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        CustomProgressBar()
            .environmentObject(MockViewModel() as ViewModel)
    }
}
