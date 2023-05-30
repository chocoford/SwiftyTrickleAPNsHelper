//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Foundation
import Fluent

final class User: Model {
    static let schema = "users"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "token")
    var token: String

    @Children(for: \.$user)
    var devices: [UserDevice]
    
    init() { }

    init(id: String, token: String) {
        self.id = id
        self.token = token
    }
}

