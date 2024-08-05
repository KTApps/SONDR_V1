//
//  StartView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

import SwiftUI

struct StartView: View {
    @EnvironmentObject var viewModel: ViewModel
    
    var body: some View {
        // checks if a user is logged in or not
        Group {
            if viewModel.userSession != nil {
                tabView()
            } else {
                LogInView()
            }
        }
    }
}

#Preview {
    StartView()
}
