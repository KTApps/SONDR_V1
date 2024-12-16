//
//  StorageRef(Extension).swift
//  Prod1
//
//  Created by Kelvin Mahaja on 24/08/2024.
//

import SwiftUI
import Foundation
import FirebaseStorage

extension StorageReference {
    func getData(maxSize: Int64) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            self.getData(maxSize: maxSize) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "UnknownError", code: -1, userInfo: nil))
                }
            }
        }
    }
}
