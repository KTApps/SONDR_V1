//
//  StartView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 12/03/2024.
//

import SwiftUI

struct StartView: View {
    @EnvironmentObject var authState: AuthState
    
    var body: some View {
        // checks if a user is logged in or not
        Group {
            if authState.userSession != nil {
                ContentView()
            } else {
                LogInView()
            }
        }
    }
}

#Preview {
    StartView()
}
