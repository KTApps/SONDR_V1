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
        Chart(viewModel.taskData?.tasks ?? [], id: \.self) { task in
            if let timeSpent = viewModel.taskData?.taskTimerDictionary[task] {
                SectorMark(
                    angle: .value("Time Spent", timeSpent),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
                .cornerRadius(cornerRadius)
            } else {
                // Handle case where taskTimerDictionary doesn't contain the task
                SectorMark(
                    angle: .value("Time Spent", 0), // Fallback value
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    angularInset: 1
                )
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
