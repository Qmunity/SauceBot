# SauceBot Module: Giveaway
io    = require '../ioutil'
{Module} = require '../module'
Sauce = require '../sauce'

{ConfigDTO, HashDTO} = require '../dto'
request = require 'request'


# Basic information
exports.name        = 'Giveaway'
exports.description = 'Giveaway with random numbers'
exports.version     = '1.0'

# Specifies that this module is always active
exports.locked      = false

exports.strings     = {
    'err-usage' : 'Usage: @1@'
    'str-max-num' : 'max number'
    'err-too-low' : "The max number you've picked (@1@) is too low"
    'str-giveaway': "The giveaway has started! Pick a number between 0 and @1@"
    'str-guessed-following': "The number has been guessed by @1@ and was @2@. @1@ is following!"
    'str-guessed-not-following': "The number has been guessed by @1@ and was @2@. @1@ is NOT following!"
    'str-guessed': "The number has been guessed by @1@ and was @2@"
    'str-stop-giveaway': 'The giveaway has been stopped!'
    'sub-enabled': "Subscriber mode after correct number is now enabled"
    'sub-disabled': "Subscriber mode after correct number is now disabled"
    'follow-enabled': "Now checking if the winner is following"
    'follow-disabled': "No longer checking if the winner is following"
}


followsUrl = (user, channel) -> "https://api.twitch.tv/kraken/users/#{user}/follows/channels/#{channel}"

class GiveAway extends Module
    constructor: (@channel) ->
        super @channel

        @config = new ConfigDTO @channel, 'giveawayconf', ['submode', 'checkfollow']

        @randomNumber = 0
        @maxNumber = 0
        @config.load()
        
    load: ->
        @regCmd "giveaway start", Sauce.Level.Mod, @cmdGiveaway
        @regCmd "giveaway stop", Sauce.Level.Mod, @cmdGiveawayStop
        @regCmd "giveaway sub on", Sauce.Level.Mod, @cmdSubOn
        @regCmd "giveaway sub off", Sauce.Level.Mod, @cmdSubOff
        @regCmd "giveaway followcheck on", Sauce.Level.Mod, @cmdFollowCheckOn
        @regCmd "giveaway followcheck off", Sauce.Level.Mod, @cmdFollowCheckOff

        # Register web interface update handlers
        @regActs {
            # Giveaway.config([submode, checkfollow]*)
            'config': @actConfig
        }



    # Action handler for "config"
    # twitchAPI.config([submode|checkfollow]*)
    actConfig: (user, params, res) =>
        {submode, checkfollow} = params

        # submode - 1 or 0
        if submode?.length
            val = if (val = parseInt submode, 10) then 1 else 0
            @config.add 'submode', val


        # Seconds delay
        if checkfollow?.length
            val = if (val = parseInt checkfollow, 10) then 1 else 0
            @config.add 'checkfollow', val

        res.send @config.get()

    handle: (user, msg, network) ->
        if @maxNumber > 0
            m = /(\d+)/.exec(msg)
            if (m and parseInt(m[1], 10) == @randomNumber)
                @randomNumber = 0
                @maxNumber = 0
                if(@config.get 'checkfollow')
                    @isFollowing user, network, (isFollowing) =>
                        if isFollowing
                            @bot.say @str('str-guessed-following', user.name, m[1]), network
                        else
                            @bot.say @str('str-guessed-not-following', user.name, m[1]), network
                        if @config.get 'submode'
                            @bot.submode network
                else
                    @bot.say @str('str-guessed', user.name, m[1]), network
                    if @config.get 'submode'
                        @bot.submode network




    cmdSubOn: (user, args, bot, network) =>
        @config.add 'submode', 1
        @bot.say '[Giveaway] ' + @str('sub-enabled'), network

    cmdSubOff: (user, args, bot, network) =>
        @config.add 'submode', 0
        @bot.say '[Giveaway] ' + @str('sub-disabled'), network

    cmdFollowCheckOn: (user, args, bot, network) =>
        @config.add 'checkfollow', 1
        @bot.say '[Giveaway] ' + @str('follow-enabled'), network

    cmdFollowCheckOff: (user, args, bot, network) =>
        @config.add 'checkfollow', 0
        @bot.say '[Giveaway] ' + @str('follow-disabled'), network

    cmdGiveawayStop: (user, args, bot, network) =>
        if @maxNumber > 0
            @maxNumber = 0
            @randomNumber = 0
            @bot.say @str('str-stop-giveaway'), network

    cmdGiveaway: (user, args, bot, network) =>
        unless args[0]?
            return @bot.say @str('err-usage', '!giveaway <max number>'), network

        num = parseInt(args[0], 10)

        if num < 2 or isNaN num
            return @bot.say @str('err-too-low', num)

        @maxNumber = num 
        @randomNumber = ~~(Math.random() * num)

        io.debug "The number is: " + @randomNumber

        return @bot.say @str('str-giveaway', num), network


    isFollowing: (user, network, cb) ->
        @webFetcher user.name, (data) ->
            if data
                if data['status'] == '404'
                    cb false
                else
                    cb true
            else
                console.log data
                cb false

    webFetcher: (key, cb) ->
        url = followsUrl key.toLowerCase(), @channel.name.toLowerCase()
        request {url: url, timeout: 2000}, (err, resp, json) =>
            try
                data = JSON.parse json
                cb data
            catch err
                # Ignore
                cb()

exports.New = (channel) ->
    new GiveAway channel
