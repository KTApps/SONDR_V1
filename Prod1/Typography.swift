//
//  Typography.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 06/10/2025.
//

import SwiftUI

// MARK: Typography namespace within AuthState
extension AuthState {
    enum Typography {
        static var font_1_bold_sondr: Font { .system(size: 20, weight: .bold) }
        static var font_1_bold: Font { .system(size: 17, weight: .bold) }
        static var font_1_light: Font { .system(size: 17, weight: .light) }
        static var font_2_light: Font { .system(size: 17, weight: .bold) }
        static var font_3_bold: Font { .system(size: 19, weight: .bold) }
        static var font_4_bold: Font { .system(size: 12, weight: .bold) }
        static var font_5_bold: Font { .system(size: 30, weight: .bold) }
    }
}
