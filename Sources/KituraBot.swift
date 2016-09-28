//
//  KituraBot.swift
//  KituraBot
//
//  Created by Jacopo Mangiavacchi on 9/27/16.
//
//

import Foundation
import Kitura

public typealias BotInternalMessageNotificationHandler = (_ channelName: String, _ senderId: String, _ message: String) -> Void

public protocol KituraBotProtocol {
    func configure(router: Router, channelName: String, botProtocolMessageNotificationHandler: @escaping BotInternalMessageNotificationHandler)
    func sendTextMessage(recipientId: String, messageText: String)
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
    
    public typealias BotMessageNotificationHandler = (_ channelName: String, _ senderId: String, _ message: String) -> String?
    
    private let externalBotMessageNotificationHandler: BotMessageNotificationHandler
    private let router: Router
    private var channelDictionary = [String : KituraChannel]()
    
    /// Initialize a `KituraBot` instance.
    ///
    /// - Parameter router: Passed Kitura Router (to add GET and POST REST API for the webhook URI path.
    public init(router: Router, botMessageNotificationHandler: @escaping (BotMessageNotificationHandler)) {
        self.router = router
        self.externalBotMessageNotificationHandler = botMessageNotificationHandler
    }
    
    public func addChannel(channelName: String, channel: KituraBotProtocol) throws {
        guard channelDictionary[channelName] == nil else {
            throw KituraBotError.channelAlreadyExist
        }
        
        channel.configure(router: router, channelName: channelName, botProtocolMessageNotificationHandler: internalBotProtocolMessageNotificationHandler)
        
        channelDictionary[channelName] = KituraChannel(channel: channel)
    }
    
    private func internalBotProtocolMessageNotificationHandler(_ channelName: String, _ senderId: String, _ message: String)  {
        if let responseMessage = externalBotMessageNotificationHandler(channelName, senderId, message) {
            if let channel = channelDictionary[channelName]?.channel {
                channel.sendTextMessage(recipientId: senderId, messageText: responseMessage)
            }
        }
    }
}


