# KituraBot
Swift, Kitura based, declarative multi-channel BOT framework

**Warning: This is work in progress**

This KituraBot Swift Package implements KituraBot multi-channel Class and define KituraBotProtocol for implementing KituraBot channel specific templates.

It support both a traditional syncronous model as well as a full asyncronous model.

In the traditional syncronous model the Bot respond immediatly in the context of the caller webhook HTTP request.

In the async model the webhook could call an event driven system such as IBM OpenWhisk to strongly decoupling the Bot implementation logic and implement a "Long Running Conversation" model.

KituraBotFacebookMessenger is the first KituraBot plugin available for supporting Chat Bot on the Facebook Messenger channel. (https://github.com/JacopoMangiavacchi/KituraBotFacebookMessenger)

KituraBot architecture allows to plugin several channels on the same Kitura app implementing in a unique and central way the same Bot logic for different channels.

See the KituraBotFrontendEchoSample project for how to implement a simple Echo Bot woth this framework (https://github.com/JacopoMangiavacchi/KituraBotFrontendEchoSample)

## Usage

    //1. Instanciate KituraBot and implement BOT logic
    let bot = KituraBot(router: router) { (channelName: String, senderId: String, message: String) -> String? in
        
        //1.a Implement classic Syncronous BOT logic implementation with Watson Conversation, api.ai, wit.ai or other tools
        let responseMessage = "ECHO: \(message)"
        
        //3.a [Optional] Manage classic Asyncronous BOT logic implementation decoupling for example with OpenWhisk
        //let openWhiskMessage = ["channelName" : channelName, "senderId" : senderId, "message" : message]
        //whisk.fireTrigger(name: "xx", package: "xx", namespace: "xx", parameters: openWhiskMessage, callback: {(reply, error) -> Void in {}
        // OpenWhisk chain will use a specific KituraBotPushAction to send back to KituraBot in a asyncronous way the response message to send back to client
        
        //1.b return immediate Syncronouse response or return nil to do not send back any Syncronous response message
        return responseMessage
    }
            
            
    ///3.b [Optional] Activate Async Push Back cross channel functionality
    bot.exposeAsyncPush(securityToken: Configuration.pushApiSecurityToken, webHookPath: "/botPushApi") { (channelName: String, senderId: String, message: String) -> (channelName: String, message: String)? in
        //The implementation of exposePushBack method in KituraBot class will automatically expose REST interface to be called by the Async logic (i.e. KituraBotPushAction)
        
        var responseChannelName = channelName
        var responseMessage = message
        
        //3.c [Optional] implement optional logic to eventually notify back the user on different channels
        //responseChannelName = "..."
        
        ///3.d [Optional] send back Async response message
        //responseMessage = "..."
        
        //3.e return new channel and message or return nil to use the passed channel and message
        //return (responseChannelName, responseMessage)
        
        return nil
    }


    //2. Add specific channel to the KituraBot instance
    do {
        //2.1 Add Facebook Messenger channel
        try bot.addChannel(channelName: "FacebookEcho", channel: KituraBotFacebookMessenger(appSecret: Configuration.appSecret, validationToken: Configuration.validationToken, pageAccessToken: Configuration.pageAccessToken, webHookPath: "/webhook"))
        
        //2.1 Add Slack, Skype etc. channels
        //try bot.addChannel(channelName: "SlackEcho1", KituraBotSlack(slackConfig: "xxx", webHookPath: "/echo1slackcommand"))
        //try bot.addChannel(channelName: "SkypeEcho1", KituraBotSkype(skypeConfig: "xxx", webHookPath: "/echo1skypewebhook"))
        
        //2.2 Add MobileApp channel (use Push Notification for Asyncronous response message
        //try bot.addChannel(channelName: "MobileAppEcho1", KituraBotMobileApp("appSecret": "yyy-yyy-yyy", "appId": "xxx-xxx-xx", apiPath: "/echo1api")))
    } catch is KituraBotError {
        Log.error("Oops... something wrong on Bot Channel name")
    }
