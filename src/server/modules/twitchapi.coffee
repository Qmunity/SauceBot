# SauceBot Module: Twitch API

Sauce = require '../sauce'
db    = require '../saucedb'
io    = require '../ioutil'

request = require 'request'
util    = require 'util'

# Static imports
{ConfigDTO, HashDTO} = require '../dto'
{Cache, WebCache   } = require '../cache'
{Module            } = require '../module'
{TokenJar          } = require '../../common/oauth'


# Module description
exports.name        = 'TwitchAPI'
exports.version     = '1.1'
exports.description = 'TwitchTV API'

exports.strings = {
    'show-game'   : '@1@ is playing @2@'
    'show-viewers': 'There are currently @1@ viewers!'
    'show-views'  : 'This channel has been viewed @1@ times!'
    'show-title'  : '@1@'
    'show-followers' : 'This channel has @1@ followers'
    'show-hosts'  : 'This channel has @1@ hosts'

    'status-enabled' : 'Show Hosts is now enabled.'
    'status-disabled': 'Show Hosts is now disabled.'

    'config-secs'     : 'Hostshow minimum delay set to @1@ seconds.'
    'str-hosted'      : 'Thanks @1@ for hosting us for @2@ viewers!'
}

# Set up oauth jar to access the twitch API
oauth = new TokenJar Sauce.API.Twitch, Sauce.API.TwitchToken

# Set up caches for ttv(twitch.tv) and jtv(justin.tv) API calls
ttvstreamcache = new Cache (key, cb) ->
    oauth.get "/streams/#{key}", (resp, body) ->
        cb body

# Set up caches for ttv(twitch.tv) and jtv(justin.tv) API calls
ttvcache = new Cache (key, cb) ->
    oauth.get "/channels/#{key}", (resp, body) ->
        cb body

hostUrl = (key) -> "http://chatdepot.twitch.tv/rooms/#{key}/hosts"


strip = (msg) -> msg.replace /[^a-zA-Z0-9_]/g, ''

class TwitchAPI extends Module
    load: ->
        @config = new ConfigDTO @channel, 'twitchapiconf', ['hosts', 'seconds']
        @registerHandlers()
    
        @registerTimer()
        @oldHosts = []
        @config.load()
        
    registerHandlers: ->

        @regCmd "game",    Sauce.Level.Mod, @cmdGame
        @regCmd "viewers", Sauce.Level.Mod, @cmdViewers
        @regCmd "follows", Sauce.Level.Mod, @cmdFollows
        @regCmd "title",   Sauce.Level.Mod, @cmdTitle
        @regCmd "sbfollow", Sauce.Level.Owner, @cmdFollow
        @regCmd "followme", Sauce.Level.Owner, @cmdFollowMe
        @regCmd "showhosts on",  Sauce.Level.Mod, @cmdHostShowEnable
        @regCmd "showhosts off", Sauce.Level.Mod, @cmdHostShowDisable
        @regCmd "showhosts seconds", Sauce.Level.Mod, @cmdHostShowSeconds

        @regVar 'jtv', @varJTV

    
        # Register web interface update handlers
        @regActs {
            # TwitchApi.config([showhosts]*)
            'config': @actConfig
        }



    # Action handler for "config"
    # twitchAPI.config([showhosts|seconds]*)
    actConfig: (user, params, res) =>
        {hosts, seconds} = params

        # showhosts - 1 or 0
        if showhosts?.length
            val = if (val = parseInt state, 10) then 1 else 0
            @config.add 'hosts', val


        # Seconds delay
        if seconds?.length
            val = parseInt seconds, 10
            @config.add 'seconds', if isNaN val then 180 else val

        res.send @config.get()

    registerTimer: =>

        setTimeout @checkHosts, @config.get('seconds') * 1000


    checkHosts: =>
        if @config.get 'hosts'
            @getHosts @channel.name.toLowerCase(), (data) =>
                newChannels = []
                for newChannel in data
                    if !(newChannel['host'] in @oldHosts)
                        #now. Get the viewers of said channels
                        @getViewers newChannel['host'], (viewers) =>
                            @bot.say @str('str-hosted', newChannel['host'], viewers)
                    
                    newChannels.push(newChannel['host'])

                @oldHosts = newChannels

        @registerTimer()

    save: ->
        @config.save()

    # !showHost on - Enable host show
    cmdHostShowEnable: (user, args) =>
        @config.add('hosts', 1)
        @bot.say '[HostShow] ' + @str('status-enabled')

    # !showHost off - Disable host show
    cmdHostShowDisable: (user, args) =>
        @config.add('hosts', 0)
        @bot.say '[HostShow] ' + @str('status-disabled')

    # !showHost seconds - How long the polling should last
    cmdHostShowSeconds: (user, args) =>
        @config.add 'seconds', parseInt(args[0], 10) if args[0]?
        @bot.say '[HostShow] ' + @str('config-secs', @config.get 'seconds')


    # !game - Print current game.
    cmdGame: (user, args) =>
        @getGame @channel.name, (game) =>
            @bot.say '[Game] ' + @str('show-game', @channel.name, game)
            

    # !viewers - Print number of viewers.
    cmdViewers: (user, args) =>
        @getViewers @channel.name, (viewers) =>
            @bot.say "[Viewers] " + @str('show-viewers', viewers)
            

    # !title - Print current title.
    cmdTitle: (user, args) =>
        @getTitle @channel.name, (title) =>
            @bot.say "[Title] " + @str('show-title', title)


    cmdFollows: (user, args, bot) =>
        @getFollows @channel.name, (follows) =>
            bot.say "[Follows] " + @str('show-follows', follows)


    # !sbfollow <username> - Follows the channel (globals only)
    cmdFollow: (user, args) =>
        return unless user.global

        name = args[0]
        if name = @followUser(name)
            @bot.say "Followed #{name}"
        else
            @bot.say "Usage: !sbfollow <username>"


    # !followme - Follows channel
    cmdFollowMe: (user, args) =>
        if @followUser(user.name)
            @bot.say "Followed #{user.name}"
        else
            @bot.say "Invalid username. Please contact a SauceBot administrator."


    followUser: (name) ->
        name = name.trim()
        name = name.replace(/[^a-zA-Z0-9_]+/g, '')
        return unless name
        
        io.debug "Following #{name}"
        oauth.put "/users/saucebot/follows/channels/#{name}", (resp, body) ->
            io.debug "Followed #{name}"
        return name
           

    # $(jtv game|viewers|views|title [, <channel>])
    varJTV: (user, args, cb) =>
        usage = '[jtv game|viewers|views|follows|title [, <channel>]]'
        unless args[0]?
            cb usage
        else
            chan = if args[1]? then strip(args[1]) else @channel.name
            switch args[0]
                when 'game'      then @getGame      chan, cb
                when 'viewers'   then @getViewers   chan, cb
                when 'views'     then @getViews     chan, cb
                when 'title'     then @getTitle     chan, cb
                when 'follows'   then @getFollows   chan, cb
                when 'hosts'     then @getNumHosts  chan, cb
                else cb usage
         
         
    getGame: (chan, cb) ->
        @getTTVData chan, (data) ->
            cb (data["game"] ? "N/A")
            
            

    getViewers: (chan, cb) ->
        @getTTVStreamData chan, (data) ->
            cb ((data["stream"] ? {})["viewers"] ? "N/A")
            
    getFollows: (chan, cb) ->
        @getTTVData chan, (data) ->
            cb(data["followers"] ? "N/A")

    getTitle: (chan, cb) ->
        @getTTVData chan, (data) ->
            cb (data["status"] ? "N/A")
            
            
    getTTVStreamData: (chan, cb) ->
        ttvstreamcache.get chan.toLowerCase(), (data) ->
            cb data ? {}


    getTTVData: (chan, cb) ->
        ttvcache.get chan.toLowerCase(), (data) ->
            cb data ? {}

    getHosts: (chan, cb) ->
        @webFetcher chan.toLowerCase(), (data) ->
            if data
                cb data['hosts'] ? {}

    getNumHosts: (chan, cb) ->
        @webFetcher chan.toLowerCase(), (data) ->
            data = data?['hosts']
            l = Object.keys(data).length
            cb l

    
    webFetcher: (key, cb) ->
        url = hostUrl key
        request {url: url, timeout: 2000}, (err, resp, json) =>
            try
                data = JSON.parse json
                cb data
            catch err
                # Ignore
                cb()


exports.New = (channel) -> new TwitchAPI channel
