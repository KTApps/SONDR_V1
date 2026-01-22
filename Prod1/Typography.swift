//
//  Typography.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 06/10/2025.
//

import SwiftUI

// MARK: Typography namespace within AuthState
// Uses Dynamic Type for responsive font scaling based on user accessibility settings
extension AuthState {
    enum Typography {
        static var font_1_bold_sondr: Font { .title2.bold() }      // ~22pt, scales with Dynamic Type
        static var font_1_bold: Font { .headline }                  // ~17pt bold, scales with Dynamic Type
        static var font_1_light: Font { .body }                     // ~17pt light, scales with Dynamic Type
        static var font_2_light: Font { .headline }                 // ~17pt bold, scales with Dynamic Type
        static var font_3_bold: Font { .title3.bold() }            // ~19pt, scales with Dynamic Type
        static var font_4_bold: Font { .caption.bold() }           // ~12pt, scales with Dynamic Type
        static var font_5_bold: Font { .largeTitle.bold() }        // ~30pt, scales with Dynamic Type
    }
}
