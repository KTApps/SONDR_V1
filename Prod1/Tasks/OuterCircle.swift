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
    let selectedOuterRadius: MarkDimension
    let cornerRadius: CGFloat
    
    @State private var pieSelection: Double?
    
    private func taskForTime(_ time: Double, tasks: [String], timeSpent: [String: Int]) -> String? {
        var cumulativeTime: Double = 0
        let timeSpentDouble = timeSpent.mapValues { Double($0) }
        let totalTime = timeSpentDouble.values.reduce(0, +)
                
        for task in tasks {
            if let taskTime = timeSpentDouble[task] {
                
                // Check if the clicked time falls within this task's range
                if time >= cumulativeTime && time < cumulativeTime + taskTime {
                    return task
                }
                
                // Update the cumulative time for the next task
                cumulativeTime += taskTime
            }
        }
        return nil
    }
    
    var body: some View {
        if let tasks = viewModel.taskData?.tasks,
           let timeSpent = viewModel.taskData?.taskTimerDictionary,
            !tasks.isEmpty, !timeSpent.isEmpty {
            Chart(tasks, id: \.self) { task in
                let isSelected = task == viewModel.selectedTask
                SectorMark(
                    angle: .value("Time Spent", timeSpent[task] ?? 0),
                    innerRadius: innerRadius,
                    outerRadius: isSelected ? selectedOuterRadius : outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
            }
            .chartAngleSelection(value: $pieSelection)
            .onChange(of: pieSelection, initial: false) { _ , newValue in
                if let newValue {
                    viewModel.selectedTask = taskForTime(newValue, tasks: tasks, timeSpent: timeSpent)
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
        return OuterCircle(innerRadius: 140, outerRadius: 170, selectedOuterRadius: 180, cornerRadius: 5)
            .environmentObject(MockViewModel() as ViewModel)
    }
}
