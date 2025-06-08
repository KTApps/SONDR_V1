//
//  BlurEffect.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 02/07/2024.
//

import SwiftUI

struct BlurEffect: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(
            effect: UIBlurEffect(style: style)
        )
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
    }
}

#Preview {
    BlurEffect(style: .systemMaterialDark)
        .environmentObject(MockViewModel() as AuthState)
}
