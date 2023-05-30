//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/29.
//

import Foundation
import Fluent

final class UserDevice: Model {
    static let schema = "user_devices"

    @ID(custom: "id", generatedBy: .user)
    /// Device token
    var id: String?

    @Field(key: "user_token")
    var userToken: String
    
    enum Env: String, Codable {
        case dev, test, live
    }

    @Enum(key: "env")
    var env: Env
    
    @Parent(key: "user_id")
    var user: User
    
    @Children(for: \.$device)
    var workspaces: [DeviceWorkspace]
    
    init() { }

    init(token: String, userToken: String, env: Env, userID: String) {
        self.id = token
        self.userToken = userToken
        self.env = env
        self.$user.id = userID
    }
}

