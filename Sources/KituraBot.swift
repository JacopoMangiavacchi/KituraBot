//
//  KituraBot.swift
//  KituraBot
//
//  Created by Jacopo Mangiavacchi on 9/27/16.
//
//

import Foundation
import Kitura
import SwiftyJSON
import LoggerAPI


public typealias KituraBotContext = [String: Any]

//KituraBot User structure
//A user id is unique per channel
public struct KituraBotUser {
    public let userId: String
    public let channel: String
    
    public init(userId: String, channel: String) {
        self.userId = userId
        self.channel = channel
    }
}


//KituraBot Message Type enumn
public enum KituraBotMessageType : Int {
    case request
    case response
}

//KituraBot Message structure
public struct KituraBotMessage {
    public let messageId: String
    public let timestamp: Date
    public let messageType: KituraBotMessageType
    public let user: KituraBotUser
    public let messageText: String
    public let context: KituraBotContext?
    
    //TODO: Add default
    public init(messageType: KituraBotMessageType, user: KituraBotUser, messageText: String, context: KituraBotContext?) {
        self.messageId = UUID().uuidString
        self.timestamp = Date()
        
        self.messageType = messageType
        self.user = user
        self.messageText = messageText
        self.context = context
    }
}


//KituraBot Message Store Protocol for KituraBotMessageStore plugins
public protocol KituraBotMessageStoreProtocol {
    func addMessage(_ message: KituraBotMessage)
    func getMessage(messageId: String) -> KituraBotMessage?
    //TODO: Pass KituraBotUser (channel + userid)
    func getMessageAll(user: KituraBotUser) -> [KituraBotMessage]
    func getMessageAll(fromMessageId: String, user: KituraBotUser) -> [KituraBotMessage]
    func getMessageAll(fromDate: String, user: KituraBotUser) -> [KituraBotMessage]
}


//KituraBot Message Response structure
public struct KituraBotMessageResponse {
    public let messageText: String
    public let context:KituraBotContext?
    
    public init(messageText: String, context:KituraBotContext?) {
        self.messageText = messageText
        self.context = context
    }
}


//Return back to the channel the Sync Response Message eventually returned by the caller bot logic
public typealias BotInternalMessageNotificationHandler = (_ message: KituraBotMessage) -> KituraBotMessageResponse?

public protocol KituraBotProtocol {
    func configure(router: Router, channelName: String, botProtocolMessageNotificationHandler: @escaping BotInternalMessageNotificationHandler)
    func sendMessage(_ message: KituraBotMessage)
}

public enum KituraBotError: Error {
    case channelAlreadyExist
}



// MARK KituraBot

/// Implement a declarative, multi channel ChatBot framework.
/// It allows to register a central Handler to implement the BOT logic
/// and plug in several chatbot channels.
public class KituraBot {
    private struct KituraChannel {
        let channel: KituraBotProtocol
    }

    public typealias SyncNotificationHandler = (_ message: KituraBotMessage) -> KituraBotMessageResponse?
    public typealias PushNotificationHandler = (_ message: KituraBotMessage) -> (channelName: String, message: KituraBotMessageResponse)?
    
    private let syncBotMessageNotificationHandler: SyncNotificationHandler
    private var pushBotMessageNotificationHandler: PushNotificationHandler?
    
    private var securityToken: String?
    private let router: Router
    private var channelDictionary = [String : KituraChannel]()
    
    private let messageStore: KituraBotMessageStoreProtocol?
    private let getToken: String
    
    
    /// Initialize a `KituraBot` instance.
    ///
    /// - Parameter router: Passed Kitura Router (to add GET and POST REST API for the webhook URI path.
    public init(router: Router, messageStore: KituraBotMessageStoreProtocol?, getPath: String, getToken: String, botMessageNotificationHandler: @escaping (SyncNotificationHandler)) {
        self.router = router
        self.messageStore = messageStore
        self.getToken = getToken
        
        self.syncBotMessageNotificationHandler = botMessageNotificationHandler
        
        //Expose router handler for GET API to be called by client to get messages
        router.get("\(getPath)/:messageId/token/:tokenId", handler: getMessageHandler)
        
        //Expose router handler for getting list of messages
        //TODO: Add user level authentication
        router.get("\(getPath)/channel/:channelId/user/:userId/token/:tokenId", handler: getMessageAllHandler)
        router.get("\(getPath)/channel/:channelId/user/:userId/fromId/:fromId/token/:tokenId", handler: getMessagesFromIdHandler)
        router.get("\(getPath)/channel/:channelId/user/:userId/fromDate/:fromDate/token/:tokenId", handler: getMessagesFromDateHandler)
    }
    
    public func addChannel(channelName: String, channel: KituraBotProtocol) throws {
        guard channelDictionary[channelName] == nil else {
            throw KituraBotError.channelAlreadyExist
        }
        
        channel.configure(router: router, channelName: channelName, botProtocolMessageNotificationHandler: internalBotProtocolMessageNotificationHandler)
        
        channelDictionary[channelName] = KituraChannel(channel: channel)
    }
    
    // Return to the caller the optionl Syncronous Response Message returned by the caller bot logic
    private func internalBotProtocolMessageNotificationHandler(_ message: KituraBotMessage) -> KituraBotMessageResponse? {
        
        //Save the message received on Message Store
        messageStore?.addMessage(message)
        
        if let messageToReturn = syncBotMessageNotificationHandler(message) {
            //Save the message to sand back on Message Store
            let messageReturned = KituraBotMessage(messageType: .response, user: message.user, messageText: messageToReturn.messageText, context: messageToReturn.context)
            
            messageStore?.addMessage(messageReturned)
            
            return messageToReturn
        }
        
        return nil
    }
    
    public func exposeAsyncPush(securityToken: String, webHookPath: String = "/BotPushBack", pushNotificationHandler: @escaping (PushNotificationHandler)) {
        self.pushBotMessageNotificationHandler = pushNotificationHandler
        self.securityToken = securityToken
        
        //Expose router handler for PUSH API to be called by some backend asyncronous bot implementation logic
        router.post(webHookPath, handler: sendMessageHandler)
    }
    
    
    /// Exposed API to Send Message to the Bot client.
    /// Used for Asyncronous Bot notifications.
    ///
    /// JSON Payload
    /// {
    ///     "channel" : "xxx",
    ///     "recipientId" : "xxx",
    ///     "messageText" : "xxx",
    ///     "securityToken" : "xxx"
    ///     "context" : {}
    /// }
    
    private func sendMessageHandler(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        print("POST - send message")
        Log.debug("POST - send message")
        
        var data = Data()
        if try request.read(into: &data) > 0 {
            let json = JSON(data: data)
            if let channelName = json["channel"].string, let recipientId = json["recipientId"].string, let messageText = json["messageText"].string, let passedSecurityToken = json["securityToken"].string {
                if passedSecurityToken == securityToken {
                    var finalChannelName = channelName
                    var finalMessage = messageText
                    
                    var context = json["context"].dictionaryObject
                    
                    let user = KituraBotUser(userId: recipientId, channel: channelName)
                    let messageToPush = KituraBotMessage(messageType: .response, user: user, messageText: finalMessage, context: context)
                    
                    //Call pushBotMessageNotificationHandler to verify channel and message
                    if let (newChannelName, messageResponse) = pushBotMessageNotificationHandler?(messageToPush) {
                        finalChannelName = newChannelName
                        finalMessage = messageResponse.messageText
                        context = messageResponse.context
                    }
                    
                    //SEND MESSAGE TO THE channel
                    if let channel = channelDictionary[finalChannelName]?.channel {
                        //Save the asyn message to sand back on Message Store
                        let user = KituraBotUser(userId: recipientId, channel: channelName)
                        let messageToFinallyPush = KituraBotMessage(messageType: .response, user: user, messageText: finalMessage, context: context)
                        
                        messageStore?.addMessage(messageToFinallyPush)
                        channel.sendMessage(messageToFinallyPush)
                    }
                    
                    try response.status(.OK).end()
                }
                else {
                    Log.debug("Passed pageAccessToken do not match")
                    print("Passed pageAccessToken do not match")
                    
                    try response.status(.badRequest).end()
                }
            }
            else {
                Log.debug("Send message received NO VALID JSON")
                print("Send message received NO VALID JSON")
                
                try response.status(.badRequest).end()
            }
        }
        else {
            Log.debug("Send message received NO BODY")
            print("Send message received NO BODY")
            
            try response.status(.badRequest).end()
        }
    }
    
    private func getMessageJSON(_ message: KituraBotMessage) -> JSON {
        var jsonDictionary:[String : Any] = ["messageText" : message.messageText, "messageId" : message.messageId]  //add date, channel
        
        let dateFor = DateFormatter()
        dateFor.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        jsonDictionary["timestamp"] = dateFor.string(from: message.timestamp)

        switch message.messageType {
        case .request:
            jsonDictionary["direction"] = ">"
        case .response:
            jsonDictionary["direction"] = "<"
        }
        
        //jsonDictionary["userId"] = message.user.userId
        //jsonDictionary["channel"] = message.user.channel       

        if let context = message.context {
            jsonDictionary["context"] = context
        }
        
        return JSON(jsonDictionary)
    }


    /// Exposed API to Receive Message context and details
    /// Get a single message
    /// "\(getPath)/:messageId/token/:tokenId"
    /// i.e. http://localhost:8090/message/123/token/1234
    private func getMessageHandler(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let token = request.parameters["tokenId"], token == getToken else {
            Log.debug("Passed GET token do not match")
            print("Passed GET token do not match")
            
            try response.status(.badRequest).end()
            return
        }
        
        if let messageId = request.parameters["messageId"], let message = messageStore?.getMessage(messageId: messageId) {
            try response.status(.OK).send(json: getMessageJSON(message)).end()
            return
        }

        try response.status(.badRequest).end()
    }

    
    
    /// Exposed API to Receive Message context and details
    /// Get a single message
    /// "\(getPath)/channel/:channelId/user/:userId/token/:tokenId"
    /// i.e. http://localhost:8090/message/channel/channel1/user/123/token/1234
    private func getMessageAllHandler(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let token = request.parameters["tokenId"], token == getToken else {
            Log.debug("Passed GET token do not match")
            print("Passed GET token do not match")
            
            try response.status(.badRequest).end()
            return
        }
        
        if let userId = request.parameters["userId"], let channelName = request.parameters["channelId"] {
            let user = KituraBotUser(userId: userId, channel: channelName)
            
            if let messageArray: [KituraBotMessage] = messageStore?.getMessageAll(user: user) {
                let messageJsonArray = messageArray.map { getMessageJSON($0) }
                
                try response.status(.OK).send(json: JSON(messageJsonArray)).end()
                return
            }
        }
        
        try response.status(.badRequest).end()
    }
    
    
    /// Exposed API to Receive Message context and details
    /// Get all messages from a particualr messageId
    /// "\(getPath)/channel/:channelId/user/:userId/fromId/:fromId/token/:tokenId"
    /// i.e. http://localhost:8090/message/channel/channel1/user/123/fromId/123/token/1234
    private func getMessagesFromIdHandler(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let token = request.parameters["tokenId"], token == getToken else {
            Log.debug("Passed GET token do not match")
            print("Passed GET token do not match")
            
            try response.status(.badRequest).end()
            return
        }
        
        if let userId = request.parameters["userId"], let channelName = request.parameters["channelId"] {
            let user = KituraBotUser(userId: userId, channel: channelName)
            
            if let fromId = request.parameters["fromId"], let messageArray: [KituraBotMessage] = messageStore?.getMessageAll(fromMessageId: fromId, user: user) {
                let messageJsonArray = messageArray.map { getMessageJSON($0) }
                
                try response.status(.OK).send(json: JSON(messageJsonArray)).end()
                return
            }
        }
        
        try response.status(.badRequest).end()
    }

    
    /// Exposed API to Receive Message context and details
    /// Get all messages from a particualr date
    /// "\(getPath)/channel/:channelId/user/:userId/fromDate/:fromDate/token/:tokenId"
    /// http://localhost:8090/message/channel/channel1/user/123/fromDate/123/token/1234
    private func getMessagesFromDateHandler(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let token = request.parameters["tokenId"], token == getToken else {
            Log.debug("Passed GET token do not match")
            print("Passed GET token do not match")
            
            try response.status(.badRequest).end()
            return
        }
        
        if let userId = request.parameters["userId"], let channelName = request.parameters["channelId"] {
            let user = KituraBotUser(userId: userId, channel: channelName)
        
            if let fromDate = request.parameters["fromDate"], let messageArray: [KituraBotMessage] = messageStore?.getMessageAll(fromDate: fromDate, user: user) {
                let messageJsonArray = messageArray.map { getMessageJSON($0) }
                
                try response.status(.OK).send(json: JSON(messageJsonArray)).end()
                return
            }
        }
        
        try response.status(.badRequest).end()
    }
}


