//
//  Lobby.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 14/03/2024.
//

import SwiftUI

struct Lobby: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.userSession != nil {
                ContentView()
            } else {
                LogInView()
            }
        }
    }
}

#Preview {
    Lobby()
}
