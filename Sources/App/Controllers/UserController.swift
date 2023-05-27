//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Fluent
import Vapor
import TrickleKit

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let users = routes.grouped("users")
        users.get("enability/:userID", use: listEnability)
        users.post("register", use: register)
        users.get(use: isActive)
        users.post("mute", use: mute)
        users.post("unmute", use: unmute)
        users.post("logout/:userID", use: logout)
    }
    
    func listEnability(req: Request) async throws -> [WorkspaceData.ID : Bool] {
        guard let userID = req.parameters.get("userID") else { throw Abort(.badRequest) }
        return SocketForte.shared.usersEnabledStates[userID] ?? [:]
    }
    
    func register(req: Request) async throws -> HTTPStatus {
        let payload = try req.content.decode(RegisterPayload.self)
        try await SocketForte.shared.register(req: req, userInfo: payload)
        return .ok
    }
    
    func isActive(req: Request) async throws -> Bool {
        guard let userID = req.parameters.get("userID") else { return false }
        return SocketForte.shared.isSocketActive(userID: userID)
    }
    
    struct MutePNPayload: Codable {
        let userID: UserInfo.UserData.ID
        let workspaceID: WorkspaceData.ID
        let memberID: MemberData.ID
    }
    
    func mute(req: Request) async throws -> HTTPStatus {
        let payload = try req.content.decode(MutePNPayload.self)
        
        SocketForte.shared.muteWorkspace(userID: payload.userID,
                                         workspaceInfo: .init(workspaceID: payload.workspaceID,
                                                              memberID: payload.memberID)
        )
        
        return .ok
    }
    
    
    struct UnmutePNPayload: Codable {
        let userID: UserInfo.UserData.ID
        let workspaceID: WorkspaceData.ID
        let memberID: MemberData.ID
        let token: String
    }
    func unmute(req: Request) async throws -> HTTPStatus {
        let payload = try req.content.decode(UnmutePNPayload.self)
        
        SocketForte.shared.unmuteWorkspace(userID: payload.userID,
                                           token: payload.token,
                                           workspaceInfo: .init(workspaceID: payload.workspaceID,
                                                                memberID: payload.memberID)
        )
        
        return .ok
    }
    
    
    
    func logout(req: Request) async throws -> HTTPStatus {
        guard let userID = req.parameters.get("userID") else { return .notFound }
        SocketForte.shared.closeSocket(userID: userID)
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
    
    struct UserWorkspaceRepresentable: Codable {
        let workspaceID: String
        let memberID: String
    }
}
