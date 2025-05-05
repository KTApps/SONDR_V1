//
//  OuterCircle.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 01/07/2024.
//

import SwiftUI
import Charts

struct OuterCircle: View {
    @EnvironmentObject var viewModel: ViewModel
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat
    
    @State private var pieSelection: Double?
    @State private var animatedOpacity: Double = 1.0
    
    var body: some View {
        if let tasks = viewModel.taskData?.tasks,
           let timeSpent = viewModel.taskData?.taskTimerDictionary,
            !tasks.isEmpty, !timeSpent.isEmpty {
            Chart(tasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", timeSpent[task] ?? 0),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
                .opacity(viewModel.selectedTask == nil || viewModel.selectedTask == task ? 1 : animatedOpacity)
            }
            .chartAngleSelection(value: $pieSelection)
            .onChange(of: pieSelection, initial: false) { _ , newValue in
                withAnimation(.easeInOut(duration: 0.5)) {
                    if let newValue {
                        viewModel.selectedTask = viewModel.taskForTime(for: newValue, tasks: tasks, timeSpent: timeSpent)
                    }
                    animatedOpacity = 0.3
                }
            }
        } else {
            Chart(viewModel.placeholderTasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", task),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .foregroundStyle(.gray)
                .opacity(0.3)
                .cornerRadius(cornerRadius)
            }
        }
    }
}

struct OuterCircle_Previews: PreviewProvider {
    static var previews: some View {
        return OuterCircle(innerRadius: 140, outerRadius: 170, cornerRadius: 5)
            .environmentObject(MockViewModel() as ViewModel)
    }
}
