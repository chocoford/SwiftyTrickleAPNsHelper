//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Foundation

extension [String : Any] {
    func data() throws -> Data {
        try JSONSerialization.data(withJSONObject: self)
    }
}
