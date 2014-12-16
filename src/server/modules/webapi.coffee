# SauceBot Module: Giveaway
io    = require '../ioutil'
{Module} = require '../module'
Sauce = require '../sauce'

{ConfigDTO, HashDTO} = require '../dto'
http = require 'http'


# Basic information
exports.name        = 'WebAPI'
exports.description = 'WebAPI for having the bot do multiple things'
exports.version     = '0.1'

# Specifies that this module is always active
exports.locked      = false

exports.strings     = {
}

class WebAPI extends Module
    constructor: (@channel) ->
        super @channel

        #@config = new ConfigDTO @channel, 'giveawayconf', ['submode', 'checkfollow']

        #@config.load()
        
    load: ->

        @regVar 'api', @varAPI
        # Register web interface update handlers
    
    
    varAPI: (user, args, cb) =>
        usage = "Usage: $(api <web> [,arguments,...])"
        unless args[0]?
            cb usage
        else
            url = args[0]

            if args.length > 1
                args.splice(0,1)
                url +="?user=" + user.name
                if user.op
                    url+="&op=true"

                for arg in args
                    url += "&args[]=" + arg.trim()

            @webFetcher url, (json) =>
                if !json
                    return
                if json.length > 0
                    for action in json
                        console.log(action)
                        if action['action'] == 'return'
                            cb(action['message'])
                        if action['action'] == 'submode'
                            @bot.submode()
                        if action['action'] == 'nosubmode'
                            @bot.unsubmode()
                        if action['action'] == 'timeout'
                            @bot.timeout action['user'], action['time']
                        if action['action'] == 'slowmode'
                            @bot.slow action['seconds']
                        if action['action'] == 'noslowmode'
                            @bot.unslowmode()
                else
                    cb("N/A")

    

    webFetcher: (url, cb) ->
        console.log url
        http.get url, (res) ->
            data = ''
            res.on 'data', (chunk) =>
                data += chunk.toString()

            res.on 'end', () =>
                console.log data
                json  = JSON.parse data
                cb json

exports.New = (channel) ->
    new WebAPI channel
