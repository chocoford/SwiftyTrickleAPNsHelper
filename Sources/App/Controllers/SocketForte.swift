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
import Jobs

class SocketForte {
    static var shared: SocketForte = .init()

    var devicesSocketPool: [String : WebSocket] = [:]
    var devicesEnabledStates: [String : [WorkspaceData.ID : Bool]] = [:]
    var devicesWorkspacesInfo: [String : [RegisterPayload.UserWorkspaceRepresentable]] = [:]
    
    struct DeviceTimers {
        var helloInterval: Job? = nil
        var roomStatus: [WorkspaceData.ID : Job] = [:]
    }
    var devicesTimers: [String : DeviceTimers] = [:]
    
    
    public func register(req: Request, userInfo payload: RegisterPayload) async throws {
        if devicesSocketPool[payload.deviceToken] != nil {
            try await closeSocket(deviceToken: payload.deviceToken)
        }
        
        devicesWorkspacesInfo[payload.deviceToken] = []
        devicesEnabledStates[payload.deviceToken] = [:]
        let urlString: String
        switch payload.env {
            case .dev:
                urlString = "devwsapi.trickle.so"
            case .test:
                urlString = "testwsapi.trickle.so"
            case .live:
                urlString = "wsapi.trickle.so"
        }
        try await WebSocket.connect(to: "wss://\(urlString)?authToken=Bearer%20\(payload.trickleToken)",
                                    on: req.eventLoop) { ws in
            do {
                self.configWebsocket(ws, req: req, userInfo: payload)
                
                // connect to server
                try self.connectToServer(ws, userID: payload.userID,
                                         trickleToken: payload.trickleToken,
                                         deviceToken: payload.deviceToken)
                
            } catch {
                dump(error)
            }
        }
    }

    public func closeSocket(deviceToken: String) async throws {
        print("close socket.")
        for workspace in devicesWorkspacesInfo[deviceToken] ?? [] {
            try leaveWorkspace(deviceToken: deviceToken, workspaceInfo: workspace)
        }
        
        devicesTimers[deviceToken]?.helloInterval?.stop()
        devicesTimers[deviceToken]?.roomStatus.values.forEach({
            $0.stop()
        })
        devicesTimers.removeValue(forKey: deviceToken)
        _ = try await devicesSocketPool[deviceToken]?.close()
        devicesSocketPool.removeValue(forKey: deviceToken)
    }

    public func isSocketActive(deviceToken: String) -> Bool {
        return devicesSocketPool[deviceToken] != nil
    }
    

    public func muteWorkspace(deviceToken: String, workspaceID: String) {
        guard let workspaceInfo = devicesWorkspacesInfo[deviceToken]?.first(where: {$0.workspaceID == workspaceID}) else {
            return
        }
        do {
            // leave room
            try  leaveWorkspace(deviceToken: deviceToken, workspaceInfo: workspaceInfo)
        } catch {
            dump(error)
        }
    }
    
    public func unmuteWorkspace(deviceToken: String, token: String, workspaceInfo: RegisterPayload.UserWorkspaceRepresentable) {
        do {
            // join room
            try  joinWorkspace(trickleToken: token,
                                    deviceToken: deviceToken,
                                    workspaceInfo: workspaceInfo)
        } catch {
            dump(error)
        }
    }
    private func configWebsocket(_ ws: WebSocket, req: Request, userInfo payload: RegisterPayload) {
        devicesSocketPool.updateValue(ws, forKey: payload.deviceToken)
        // on close
        ws.onClose.whenComplete { _ in
            if self.devicesSocketPool[payload.deviceToken] != nil {
                // reestablish
                Task {
                    do {
                        try await self.register(req: req, userInfo: payload)
                    } catch {
                        self.devicesSocketPool.removeValue(forKey: payload.deviceToken)
                    }
                }
            } else {
                // close
            }
            
            self.devicesTimers[payload.deviceToken]?.helloInterval?.stop()
            self.devicesTimers[payload.deviceToken]?.roomStatus.values.forEach({
                $0.stop()
            })
            self.devicesTimers.removeValue(forKey: payload.deviceToken)
        }
        
        // on message
        ws.onText { socket, text in
            var configs: ConnectData? = nil
            // changeNotifyHandler
            TrickleSocketMessageHandler.shared.handleMessage(text) { event in
                switch event {
                    case .changeNotify(let data):
                        for data in data.data ?? [] {
                            for code in data.codes {
                                switch code.value.latestChangeEvent {
                                    case .trickle(let event):
                                        switch event {
                                            case .created(let event):
                                                guard self.devicesEnabledStates[payload.deviceToken]?[event.eventData.workspaceID] == true else {
                                                    if payload.userWorkspaces.contains(where: {$0.workspaceID == event.eventData.workspaceID}) {
                                                        Task {
                                                            self.muteWorkspace(deviceToken: payload.deviceToken, workspaceID: event.eventData.workspaceID)
                                                        }
                                                    }
                                                    break
                                                }
                                                if event.eventData.trickleInfo.authorMemberInfo.memberID != payload.userWorkspaces.first(where: {
                                                    $0.workspaceID == event.eventData.workspaceID
                                                })?.memberID {
                                                    _ = req.apns.send(
                                                        .init(title: "Swifty Trickle", body: "\(event.eventData.trickleInfo.authorMemberInfo.name) post a new trickle."),
                                                        to: payload.deviceToken
                                                    )
                                                }
                                            default:
                                                break
                                        }
                                    case .comment(let event):
                                        switch event {
                                            case .created(let event):
                                                guard self.devicesEnabledStates[payload.deviceToken]?[event.eventData.workspaceID] == true else {
                                                    if payload.userWorkspaces.contains(where: {$0.workspaceID == event.eventData.workspaceID}) {
                                                        Task {
                                                           self.muteWorkspace(deviceToken: payload.deviceToken,
                                                                                    workspaceID: event.eventData.workspaceID)
                                                        }
                                                    }
                                                    break
                                                }
                                                if event.eventData.commentInfo.commentAuthor.memberID != payload.userWorkspaces.first(where: {
                                                    $0.workspaceID == event.eventData.workspaceID
                                                })?.memberID {
                                                    _ = req.apns.send(
                                                        .init(title: "Swifty Trickle", body: "\(event.eventData.commentInfo.commentAuthor.name) leaves a comment to you."),
                                                        to: payload.deviceToken
                                                    )
                                                }
                                            default:
                                                break
                                        }
                                    default:
                                        break
                                }
                            }
                        }
                        
                    case .connectSuccess(let data):
                        guard let data = data.data?.first else {
                            print("invalid data")
                            return
                        }
                        configs = data
                        do {
                            for workspaceInfo in payload.userWorkspaces {
                                // join room
                                try self.joinWorkspace(trickleToken: payload.trickleToken,
                                                             deviceToken: payload.deviceToken,
                                                             workspaceInfo: workspaceInfo)
                            }
                            
                            // hello interval
                            let helloData = try [
                                "id": UUID().uuidString,
                                "action" : "message",
                                "path": "connect_hello",
                                "data" : [
                                    "userId": payload.userID,
                                    "isVisible": "false",
                                ] as [String : Any]
                            ].data()
                            guard let helloText = String(data: helloData, encoding: .utf8) else {
                                print("invalid helloData")
                                break
                            }
                            let job = Jobs.add(interval: (configs?.helloInterval ?? 180).seconds) {
                                ws.send(helloText)
                            }
                            self.devicesTimers[payload.deviceToken]?.helloInterval = job
                        } catch {
                            dump(error)
                        }
                        
                    case .joinRoomAck(let data):
//                        print(self.devicesWorkspacesInfo[payload.deviceToken], data.data?.first?.roomID)
                        guard let roomID = data.data?.first?.roomID,
                            let workspaceID = roomID.components(separatedBy: ":").last,
                              let memberID = self.devicesWorkspacesInfo[payload.deviceToken]?.first(where: {$0.workspaceID == workspaceID})?.memberID else { break }
                        
                        /// 开启`room_status_hello`机制
                        do {
                            let roomStatusData = try [
                                "id": UUID().uuidString,
                                "action" : "message",
                                "path": "room_status",
                                "data" : [
                                    "roomId" : roomID,
                                    "memberId" : memberID,
                                    "status" : [ "mode" : "offline" ] as [String : Any],
                                ] as [String : Any]
                            ].data()
                            guard let roomStatusText = String(data: roomStatusData, encoding: .utf8) else {
                                print("invalid helloData")
                                break
                            }
//                            DispatchQueue.main.async {
//                                let timer = Timer.scheduledTimer(withTimeInterval: Double(configs?.roomStatusHelloInterval ?? 180), repeats: true) { _ in
                            let job = Jobs.add(interval: (configs?.roomStatusHelloInterval ?? 180).seconds) {
                                print("join roomStatus")
                                ws.send(roomStatusText)
                            }
                            self.devicesTimers[payload.deviceToken]?.roomStatus[workspaceID] = job
//                            }
                        } catch {
                            dump(error)
                        }
                        
                    default:
                        break
                }
            }
        }
    }
}


extension SocketForte {
    func joinWorkspace(trickleToken: String,
                       deviceToken: String,
                       workspaceInfo: RegisterPayload.UserWorkspaceRepresentable) throws {
        
        if let index = devicesWorkspacesInfo[deviceToken]?.firstIndex(where: {$0 == workspaceInfo}) {
            devicesWorkspacesInfo[deviceToken]?[index] = workspaceInfo
        } else {
            devicesWorkspacesInfo[deviceToken]?.append(workspaceInfo)
        }
        
        let ws = devicesSocketPool[deviceToken]
        let joinRoomData = try [
            "id": UUID().uuidString,
            "action" : "message",
            "path": "join_room",
            "data" : [
                "roomId": "workspace:\(workspaceInfo.workspaceID)",
                "memberId": workspaceInfo.memberID,
                "status": [ "mode" : "offline"],
            ] as [String : Any],
            "authorization" : "Bearer \(trickleToken)",
            "meta": ["version": "Swifty Trickle Push Notification Helper"]
        ].data()
        guard let joinRoomText = String(data: joinRoomData, encoding: .utf8) else { return }
        print(joinRoomText)
        ws?.send(joinRoomText)
        
        self.devicesEnabledStates[deviceToken]?.updateValue(true, forKey: workspaceInfo.workspaceID)
    }
    
    func leaveWorkspace(deviceToken: String,
                        workspaceInfo: RegisterPayload.UserWorkspaceRepresentable) throws {
        let ws = devicesSocketPool[deviceToken]
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
        ws?.send(leaveRoomText)
        self.devicesEnabledStates[deviceToken]?
            .updateValue(false, forKey: workspaceInfo.workspaceID)
        devicesWorkspacesInfo[deviceToken]?.removeAll(where: {$0.workspaceID == workspaceInfo.workspaceID})
    }
    
    func connectToServer(_ ws: WebSocket, userID: UserInfo.UserData.ID, trickleToken: String, deviceToken: String) throws {
        let data = try [
            "id": UUID().uuidString,
            "action": "message",
            "path": "connect",
            "authorization": "Bearer \(trickleToken)"
        ].data()
        guard let connectText = String(data: data, encoding: .utf8) else { return }
        print(connectText)
        ws.send(connectText)
    }
}
