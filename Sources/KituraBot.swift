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


//Return back to the channel the Sync Response Message eventually returned by the caller bot logic
public typealias BotInternalMessageNotificationHandler = (_ channelName: String, _ senderId: String, _ message: String, _ context: [String: Any]?) -> (message: String, context:[String: Any]?)?

public protocol KituraBotProtocol {
    func configure(router: Router, channelName: String, botProtocolMessageNotificationHandler: @escaping BotInternalMessageNotificationHandler)
    func sendTextMessage(recipientId: String, messageText: String, context: [String: Any]?)
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

    public typealias SyncNotificationHandler = (_ channelName: String, _ senderId: String, _ message: String, _ context: [String: Any]?) -> (message: String, context: [String: Any]?)?
    public typealias PushNotificationHandler = (_ channelName: String, _ senderId: String, _ message: String, _ context: [String: Any]?) -> (channelName: String, message: String, context: [String: Any]?)?
    
    private let syncBotMessageNotificationHandler: SyncNotificationHandler
    private var pushBotMessageNotificationHandler: PushNotificationHandler?
    
    private var securityToken: String?
    private let router: Router
    private var channelDictionary = [String : KituraChannel]()
    
    /// Initialize a `KituraBot` instance.
    ///
    /// - Parameter router: Passed Kitura Router (to add GET and POST REST API for the webhook URI path.
    public init(router: Router, botMessageNotificationHandler: @escaping (SyncNotificationHandler)) {
        self.router = router
        self.syncBotMessageNotificationHandler = botMessageNotificationHandler
    }
    
    public func addChannel(channelName: String, channel: KituraBotProtocol) throws {
        guard channelDictionary[channelName] == nil else {
            throw KituraBotError.channelAlreadyExist
        }
        
        channel.configure(router: router, channelName: channelName, botProtocolMessageNotificationHandler: internalBotProtocolMessageNotificationHandler)
        
        channelDictionary[channelName] = KituraChannel(channel: channel)
    }
    
    // Return to the caller the optionl Syncronous Response Message returned by the caller bot logic
    private func internalBotProtocolMessageNotificationHandler(_ channelName: String, _ senderId: String, _ message: String, _ context: [String: Any]?) -> (message: String, context: [String: Any]?)? {
        return syncBotMessageNotificationHandler(channelName, senderId, message, context)
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
                    
                    //Call pushBotMessageNotificationHandler to verify channel and message
                    if let (newChannelName, newMessage, newContext) = pushBotMessageNotificationHandler?(channelName, recipientId, messageText, context) {
                        finalChannelName = newChannelName
                        finalMessage = newMessage
                        context = newContext
                    }
                    
                    //SEND MESSAGE TO THE channel
                    if let channel = channelDictionary[finalChannelName]?.channel {
                        channel.sendTextMessage(recipientId: recipientId, messageText: finalMessage, context: context)
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
}


