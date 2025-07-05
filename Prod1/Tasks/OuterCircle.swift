//
//  OuterCircle.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 01/07/2024.
//

import SwiftUI
import Charts

struct OuterCircle: View {
    @ObservedObject var authState: AuthState
    let innerRadius: MarkDimension
    let outerRadius: MarkDimension
    let cornerRadius: CGFloat
    
    @State private var pieSelection: Double?
    @State private var animatedOpacity: Double = 1.0
    
    var body: some View {
        if let tasks = authState.taskData?.tasks,
           let timeSpent = authState.taskData?.taskTimerDictionary,
            !tasks.isEmpty, !timeSpent.isEmpty {
            Chart(tasks, id: \.self) { task in
                SectorMark(
                    angle: .value("Time Spent", 
                        (task == authState.taskName && authState.isTimerOn) 
                        ? authState.taskTime 
                        : (timeSpent[task] ?? 0)
                    ),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
                .opacity(authState.selectedTask == nil || authState.selectedTask == task ? 1 : animatedOpacity)
            }
            .chartAngleSelection(value: $pieSelection)
            .onChange(of: pieSelection, initial: false) { _ , newValue in
                withAnimation(.easeInOut(duration: 0.5)) {
                    if let newValue {
                        authState.selectedTask = authState.taskForTime(for: newValue, tasks: tasks, timeSpent: timeSpent)
                    }
                    animatedOpacity = 0.3
                }
            }
        } else {
            Chart(authState.placeholderTasks, id: \.self) { task in
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
        return OuterCircle(authState: AuthState(), innerRadius: 140, outerRadius: 170, cornerRadius: 5)
    }
}
