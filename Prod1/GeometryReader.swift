//
//  GeometryReader.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 10/09/2024.
//

import SwiftUI
import Combine
import UIKit

struct KeyboardResponsiveModifier: ViewModifier {
    @State private var currentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, currentHeight)
            .onAppear(perform: subscribeToKeyboardChanges)
    }

    private func subscribeToKeyboardChanges() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation {
                    self.currentHeight = keyboardFrame.height
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            withAnimation {
                self.currentHeight = 0
            }
        }
    }
}

extension View {
    func keyboardResponsive() -> some View {
        self.modifier(KeyboardResponsiveModifier())
    }
}
