# KituraBot
Swift, Kitura based, declarative multi-channel BOT framework

Implement KituraBot multi-channel Class and define KituraBotProtocol for implementing KituraBot channel specific templates.

Usage:

    //1. Instanciate KituraBot and implement BOT logic
    let bot = KituraBot(router: router) { (channelName: String, senderId: String, message: String) -> String? in
        //1.a Implement classic Syncronous BOT logic implementation with Watson Conversation, api.ai, wit.ai or other tools
        let responseMessage = "ECHO: \(message)"
        //1.b return immediate Syncronouse response or return nil to do not send back any Syncronous response message
        return responseMessage
    }

        
    //2. Add specific channel to the KituraBot instance
    do {
        //2.1 Add Facebook Messenger channel
        try bot.addChannel(channelName: "FacebookEcho", channel: KituraBotFacebookMessenger(appSecret: "...", validationToken: "...", pageAccessToken: "...", webHookPath: "/webhook"))
    } catch is KituraBotError {
        Log.error("Oops... something wrong on Bot Channel name")
    }
