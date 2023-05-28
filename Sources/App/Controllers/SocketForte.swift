//
//  File.swift
//  
//
//  Created by Dove Zachary on 2023/5/25.
//

import Foundation
import Vapor
import TrickleCore
import TrickleSocketSupport

class SocketForte {
    static var shared: SocketForte = .init()

    var usersSocketPool: [UserInfo.UserData.ID : WebSocket] = [:]
    var usersEnabledStates: [UserInfo.UserData.ID : [WorkspaceData.ID : Bool]] = [:]
    var timers: [UserInfo.UserData.ID : Timer] = [:]
    
    public func register(req: Request, userInfo payload: RegisterPayload) async throws {
        if let ws = usersSocketPool[payload.userID] {
            for workspaceInfo in payload.userWorkspaces {
                // join room
                let joinRoomData = try [
                    "id": UUID().uuidString,
                    "action" : "message",
                    "path": "join_room",
                    "data" : [
                        "roomId": "workspace:\(workspaceInfo.workspaceID)",
                        "memberId": workspaceInfo.memberID,
                        "status": [ "mode" : "offline"],
                    ] as [String : Any],
                    "authorization" : payload.trickleToken,
                    "meta": ["version": "Swifty Trickle Push Notification Helper"]
                ].data()
                guard let joinRoomText = String(data: joinRoomData, encoding: .utf8) else { continue }
                try await ws.send(joinRoomText)
                
                self.usersEnabledStates[payload.userID]?.updateValue(true, forKey: workspaceInfo.workspaceID)
            }
        } else {
            usersEnabledStates[payload.userID] = [:]
            let urlString: String
            switch payload.env {
                case .dev:
                    urlString = "devwsapi.trickle.so"
                case .test:
                    urlString = "testwsapi.trickle.so"
                case .live:
                    urlString = "wsapi.trickle.so"
            }
            try await WebSocket.connect(to: "wss://\(urlString)?authToken=Bearer%20\(payload.trickleToken)", on: req.eventLoop) { ws in
                do {
                    self.configWebsocket(ws, req: req, userInfo: payload)
                    
                    // connect to server
                    let data = try [
                        "id": UUID().uuidString,
                        "action": "message",
                        "path": "connect",
                        "authorization": payload.trickleToken
                    ].data()
                    guard let connectText = String(data: data, encoding: .utf8) else { return }
                    ws.send(connectText)
                    
                    // hello interval
                    let helloData = try [
                        "id": UUID().uuidString,
                        "action" : "message",
                        "path": "connect_hello",
                        "data" : [
                            "connId": payload.userID,
                            "isVisible": true
                        ] as [String : Any]
                    ].data()
                    guard let helloText = String(data: helloData, encoding: .utf8) else { return }
                    
                    let timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { _ in
                        ws.send(helloText)
                    }
                    self.timers[payload.userID] = timer
                 
                    for workspaceInfo in payload.userWorkspaces {
                        // join room
                        let joinRoomData = try [
                            "id": UUID().uuidString,
                            "action" : "message",
                            "path": "join_room",
                            "data" : [
                                "roomId": "workspace:\(workspaceInfo.workspaceID)",
                                "memberId": workspaceInfo.memberID,
                                "status": [ "mode" : "offline"],
                            ] as [String : Any],
                            "authorization" : payload.trickleToken,
                            "meta": ["version": "Swifty Trickle Push Notification Helper"]
                        ].data()
                        guard let joinRoomText = String(data: joinRoomData, encoding: .utf8) else { continue }
                        ws.send(joinRoomText)
                        
                        self.usersEnabledStates[payload.userID]?.updateValue(true, forKey: workspaceInfo.workspaceID)
                    }

                } catch {
                    dump(error)
                }
            }
        }
    }

    public func closeSocket(userID: UserInfo.UserData.ID) {
        _ = usersSocketPool[userID]?.close()
        usersSocketPool.removeValue(forKey: userID)
    }

    public func isSocketActive(userID: UserInfo.UserData.ID) -> Bool {
        return usersSocketPool[userID] != nil
    }
    
    
//    public func muteWorkspace(userID: UserInfo.UserData.ID, workspaceID: WorkspaceData.ID) {
//        if let workspaceInfo = payload.userWorkspaces.first(where: {$0.workspaceID == workspaceID}) {
//            muteWorkspace(userID: userID, workspaceID: workspaceInfo)
//        }
//    }
    public func muteWorkspace(userID: UserInfo.UserData.ID, workspaceInfo: RegisterPayload.UserWorkspaceRepresentable) {
        do {
            // leave room
            let data = try [
                "id": UUID().uuidString,
                "action" : "message",
                "path": "leave_room",
                "data" : [
                    "roomId": "workspace:\(workspaceInfo.workspaceID)",
                    "memberId": workspaceInfo.memberID,
                    "status": [ "mode" : "offline"],
                ] as [String : Any],
            ].data()
            guard let leaveRoomText = String(data: data, encoding: .utf8) else { return }
            let ws = usersSocketPool[userID]
            ws?.send(leaveRoomText)
            self.usersEnabledStates[userID]?.updateValue(false, forKey: workspaceInfo.workspaceID)
        } catch {
            dump(error)
        }
    }
    public func unmuteWorkspace(userID: UserInfo.UserData.ID, token: String,
                                workspaceInfo: RegisterPayload.UserWorkspaceRepresentable) {
        do {
            // join room
            let data = try [
                "id": UUID().uuidString,
                "action" : "message",
                "path": "join_room",
                "data" : [
                    "roomId": "workspace:\(workspaceInfo.workspaceID)",
                    "memberId": workspaceInfo.memberID,
                    "status": [ "mode" : "offline"],
                ] as [String : Any],
                "authorization" : token,
                "meta": ["version": "Swifty Trickle Push Notification Helper"]
            ].data()
            guard let connectText = String(data: data, encoding: .utf8) else { return }
            let ws = usersSocketPool[userID]
            ws?.send(connectText)
            self.usersEnabledStates[userID]?.updateValue(true, forKey: workspaceInfo.workspaceID)
        } catch {
            dump(error)
        }
    }
    private func configWebsocket(_ ws: WebSocket, req: Request, userInfo payload: RegisterPayload) {
        usersSocketPool.updateValue(ws, forKey: payload.userID)
        // on close
        ws.onClose.whenComplete { _ in
            if self.usersSocketPool[payload.userID] != nil {
                // reestablish
                Task {
                    do {
                        try await self.register(req: req, userInfo: payload)
                    } catch {
                        self.usersSocketPool.removeValue(forKey: payload.userID)
                    }
                }
            } else {
                // close
            }
            self.timers.removeValue(forKey: payload.userID)?.invalidate()
        }
        
        // on message
        ws.onText { socket, text in
            // changeNotifyHandler
            TrickleSocketMessageHandler.shared.handleMessage(text) { event in
                if case .changeNotify(let data) = event {
                    for data in data.data ?? [] {
                        for code in data.codes {
                            switch code.value.latestChangeEvent {
                                case .trickle(let event):
                                    switch event {
                                        case .created(let event):
                                            guard self.usersEnabledStates[payload.userID]?[event.eventData.workspaceID] == true else {
                                                if let workspaceInfo = payload.userWorkspaces.first(where: {$0.workspaceID == event.eventData.workspaceID}) {
                                                    self.muteWorkspace(userID: payload.userID,
                                                                  workspaceInfo: workspaceInfo)
                                                }
                                                break
                                            }
                                            _ = req.apns.send(
                                                .init(title: "Swifty Trickle", subtitle: "\(event.eventData.trickleInfo.authorMemberInfo.name) post a new trickle."),
                                                to: payload.deviceToken
                                            )
                                        default:
                                            break
                                    }
                                case .comment(let event):
                                    switch event {
                                        case .created(let event):
                                            guard self.usersEnabledStates[payload.userID]?[event.eventData.workspaceID] == true else {
                                                if let workspaceInfo = payload.userWorkspaces.first(where: {$0.workspaceID == event.eventData.workspaceID}) {
                                                    self.muteWorkspace(userID: payload.userID,
                                                                  workspaceInfo: workspaceInfo)
                                                }
                                                break
                                            }
                                            _ = req.apns.send(
                                                .init(title: "Swifty Trickle", subtitle: "\(event.eventData.commentInfo.commentAuthor.name) leaves a comment to you."),
                                                to: payload.deviceToken
                                            )
                                        default:
                                            break
                                    }
                                default:
                                    break
                            }
                        }
                    }
                }
            }
        }
    }
}
