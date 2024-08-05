//
//  ImageConverter.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 21/07/2024.
//

import SwiftUI
import UIKit

// Function to convert SwiftUI Image to Data
func convertImageToData(image: UIImage) -> Data? {
    return image.jpegData(compressionQuality: 1.0)
}

