//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Foundation
import Fluent

final class DeviceWorkspace: Model {
    // Name of the table or collection.
    static let schema = "device_workspaces"

    // Unique identifier for this Planet.
    @ID(key: .id)
    var id: UUID?

    // The user's workspace.
    @Field(key: "workspace_id")
    var workspaceID: String
    
    // The user's workspace.
    @Field(key: "member_id")
    var memberID: String
    
    @Parent(key: "device_token")
    var device: UserDevice
    
    // Creates a new, empty Planet.
    init() { }

    // Creates a new Planet with all properties set.
    init(id: UUID? = nil, workspaceID: String, memberID: String) {
        self.id = id
        self.workspaceID = workspaceID
        self.memberID = memberID
    }
}
