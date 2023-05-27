//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Foundation
import Fluent

final class User: Model {
    // Name of the table or collection.
    static let schema = "users"

    // Unique identifier for this Planet.
    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: String
    
    @Field(key: "token")
    var token: String

    @Children(for: \.$user)
    var workspaces: [UserWorkspace]
    
    // Creates a new, empty Planet.
    init() { }

    // Creates a new Planet with all properties set.
    init(id: UUID? = nil, userID: String, token: String) {
        self.id = id
        self.userID = userID
        self.token = token
    }
}

