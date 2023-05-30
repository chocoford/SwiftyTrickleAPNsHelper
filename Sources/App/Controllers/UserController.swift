//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Fluent
import Vapor
import TrickleCore

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("enability", ":device_token", use: listEnability)
        users.post("register", use: register)
        users.post("register_all", use: registerAll)
        users.post("broadcast", use: broadcast)
        users.get(use: isActive)
        users.post("mute", use: mute)
        users.post("unmute", use: unmute)
        users.post("logout", ":device_token", use: logout)
    }
    
    func listEnability(req: Request) async throws -> [WorkspaceData.ID : Bool] {
        guard let deviceToken = req.parameters.get("device_token") else { throw Abort(.badRequest) }
        return SocketForte.shared.devicesEnabledStates[deviceToken] ?? [:]
    }
    
    func register(req: Request) async throws -> HTTPStatus {
        let payload = try req.content.decode(RegisterPayload.self)

        let user = try await User.find(payload.userID, on: req.db) ?? User(id: payload.userID, token: payload.trickleToken)
        try await user.save(on: req.db)
        
        let device = try await UserDevice.find(payload.deviceToken, on: req.db)
        
        if let device = device {
            if device.$user.id != payload.userID {
                try await UserDevice
                    .find(payload.deviceToken, on: req.db)?
                    .$workspaces
                    .query(on: req.db)
                    .delete()
                try await SocketForte.shared.closeSocket(deviceToken: payload.deviceToken)
                device.$user.id = payload.userID
            }
            device.env = .init(rawValue: payload.env.rawValue) ?? .dev
            device.userToken = payload.trickleToken
            try await device.save(on: req.db)
        } else {
            try await UserDevice(token: payload.deviceToken,
                                 userToken: payload.trickleToken,
                                 env: .init(rawValue: payload.env.rawValue) ?? .dev,
                                 userID: payload.userID)
            
            .save(on: req.db)
        }
        
        try await SocketForte.shared.register(req: req, userInfo: payload)
        
        for workspace in payload.userWorkspaces {
            let theWorkspace = try await DeviceWorkspace
                .query(on: req.db)
                .filter(\.$workspaceID == workspace.workspaceID)
                .first()
            
            if let theWorkspace = theWorkspace {
                theWorkspace.memberID = workspace.memberID
                theWorkspace.$device.id = payload.deviceToken
                try await theWorkspace.update(on: req.db)
            } else {
                let userWorkspace = DeviceWorkspace(workspaceID: workspace.workspaceID,
                                                    memberID: workspace.memberID)
                userWorkspace.$device.id = payload.deviceToken
                try await userWorkspace.save(on: req.db)
            }
        }
        
        return .ok
    }
    
    func registerAll(req: Request) async throws -> HTTPStatus {
        guard req.remoteAddress?.ipAddress == "127.0.0.1" else { return .badGateway }

        let devices = try await UserDevice
            .query(on: req.db)
            .with(\.$workspaces)
            .all()
        
        for device in devices {
            try await SocketForte.shared.register(req: req, userInfo: .init(userID: device.$user.id,
                                                                            trickleToken: device.userToken,
                                                                            deviceToken: device.requireID(),
                                                                            userWorkspaces: device.workspaces.map{.init(workspaceID: $0.workspaceID, memberID: $0.memberID)},
                                                                            env: .init(rawValue: device.env.rawValue) ?? .dev))
        }
        
        return .ok

    }
    
    func isActive(req: Request) async throws -> Bool {
        guard let deviceToken = req.parameters.get("device_token") else { return false }
        return SocketForte.shared.isSocketActive(deviceToken: deviceToken)
    }
    
    func mute(req: Request) async throws -> HTTPStatus {
        struct MutePNPayload: Codable {
            let deviceToken: String
            let workspaceID: WorkspaceData.ID
        }
        let payload = try req.content.decode(MutePNPayload.self)
        
        try await DeviceWorkspace.query(on: req.db)
            .filter(\.$workspaceID == payload.workspaceID)
            .first()?
            .delete(on: req.db)
        
        
        SocketForte.shared.muteWorkspace(deviceToken: payload.deviceToken,
                                               workspaceID: payload.workspaceID)
        
        return .ok
    }
    
    
    func unmute(req: Request) async throws -> HTTPStatus {
        struct UnmutePNPayload: Codable {
            let deviceToken: String
            let workspaceInfo: RegisterPayload.UserWorkspaceRepresentable
            let token: String
        }
        let payload = try req.content.decode(UnmutePNPayload.self)
        
        let userWorkspace = DeviceWorkspace(workspaceID: payload.workspaceInfo.workspaceID,
                                            memberID: payload.workspaceInfo.memberID)
        userWorkspace.$device.id = payload.deviceToken
        try await userWorkspace.save(on: req.db)
        
        SocketForte.shared.unmuteWorkspace(deviceToken: payload.deviceToken,
                                                 token: payload.token,
                                                 workspaceInfo: payload.workspaceInfo
        )
        
        return .ok
    }
    
    func broadcast(req: Request) async throws -> HTTPStatus {
        guard req.remoteAddress?.ipAddress == "127.0.0.1" else { return .badGateway }
        for userDevice in try await UserDevice.query(on: req.db).all() {
            if let deviceToken = userDevice.id {
                _ = req.apns.send(.init(title: "Swifty Trickle",
                                        body: "Push Notification services updated. Please restart app to get the service."),
                                  to: deviceToken)
            }
        }
        
        return .ok
    }
    
    func logout(req: Request) async throws -> HTTPStatus {
        guard let deviceToken = req.parameters.get("device_token") else { return .notFound }
        try await UserDevice
            .find(deviceToken, on: req.db)?
            .$workspaces
            .query(on: req.db)
            .delete()
        try await UserDevice
            .find(deviceToken, on: req.db)?
            .delete(on: req.db)
        try await SocketForte.shared.closeSocket(deviceToken: deviceToken)
        
        return .ok
    }
}


struct RegisterPayload: Codable {
    let userID: String
    let trickleToken: String
    let deviceToken: String
    let userWorkspaces: [UserWorkspaceRepresentable]
    let env: Env
    
    enum Env: String, Codable {
        case dev
        case test
        case live
    }
    
    struct UserWorkspaceRepresentable: Codable, Equatable {
        let workspaceID: String
        let memberID: String
    }
}
