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
