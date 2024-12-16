//
//  TabView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 11/07/2024.
//

import SwiftUI

struct tabView: View {
    @EnvironmentObject var viewModel: ViewModel
    var body: some View {
        TabView {
            ContentView()
                .ignoresSafeArea()
                .tag(0)
            
            FeedView()
                .ignoresSafeArea()
                .tag(1)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
}
