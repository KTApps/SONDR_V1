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
        Chart(viewModel.calendarData?.tasks ?? [], id:\.self) { task in
            SectorMark(
                angle: .value("Time Spent", viewModel.calendarData?.taskTimerDictionary[task] ?? 0),
                innerRadius: innerRadius,
                outerRadius: outerRadius,
                angularInset: 1
            )
            .cornerRadius(cornerRadius)
        }
    }
}

//struct OuterCircle_Previews: PreviewProvider {
//    static var previews: some View {
//        let authModel = AuthViewModel()
//        
//        return OuterCircle(innerRadius: 140, outerRadius: 170, cornerRadius: 5)
//            .environmentObject(authModel)
//    }
//}
