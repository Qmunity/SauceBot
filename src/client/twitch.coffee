
# Node.js
color      = require 'colors'
term       = require 'readline'
util       = require 'util'
fs         = require 'fs'

# Sauce
io         = require '../common/ioutil'
config     = require '../common/config'
log        = require '../common/logger'
{Channel}  = require './saucechan'

# Twitch.tv to Node.js color conversion
# * twitch: The twitch color to convert.
# = returns either the node.js equivalent, or undefined.
exports.toNodeColor = (twitch) ->
    return null unless twitch?
    CHAT_COLORS[twitch.toLowerCase()]


CHAT_COLORS = {
   darkred     : 'red'
   gray        : 'grey'
   midnightblue: 'blue'
   deeppink    : 'magenta'
   black       : 'black'
   coral       : 'cyan'
   cadetblue   : 'blue'
   yellowgreen : 'yellow'
   chocolate   : 'red'
   seagreen    : 'green'
   goldenrod   : 'yellow'
   springgreen : 'yellow'
   firebrick   : 'red'
   orangered   : 'red'
   hotpink     : 'magenta'
   dodgerblue  : 'blue'
   green       : 'green'
   blueviolet  : 'blue'
   red         : 'red'
   blue        : 'blue'
}

# Twitch Message Interface connection handler class
#
#  List of possible emits:
#  * error(source, reason)
#
class Twitch
    constructor: (@logger) ->
        # Accounts: {username: {name, pass}}
        @accounts = {}
        
        # Connections: {channelName: Channel}
        @connections = {}
        
        # Handlers: {handler: <callback>}
        @handlers = {}
        
        
    # Registers an emit-callback for this TMI.
    # * name: The emit-code to handle.
    # * callback: The callback associated with the emit.
    # Note: Any already existing handlers for that emit get removed.
    on: (name, callback) ->
        @handlers[name] = callback
        
    
    # Sends an emit to all registered handlers.
    # * name: The name of the handlers to call.
    # * data...: Arguments to call the handler with.
    emit: (name, data...) ->
        @handlers[name]?(data...)
        

    # Registers a Twitch.tv account to be used by the bot.
    # * name: Bot username. Case-sensitive.
    # * pass: Bot password.
    # = Returns the account object created.
    addAccount: (name, pass) ->
        @accounts[name.toLowerCase()] =
            name: name
            pass: pass
            

    # Returns an account object for the specified Twitch.tv account.
    # If no such account exists, undefined is returned.
    # * name: Bot username. Case-insensitive.
    getAccount: (name) ->
        @accounts[name.toLowerCase()]
        
    
    # Sets up a connection to the specified channel using the specified bot.
    # * chan: Channel name to connect to.
    # * bot: Bot name to use. Case-insensitive.
    # Note: If no such bot exists, an error is emitted.
    join: (chan, bot) ->
        unless (account = @getAccount bot)?
            return @emit 'error', 'join', 'No such bot-account!'

        key = chan.toLowerCase()
        conn = @connections[key]
        if conn?
            if conn.username isnt account.name
                conn.part()
            else
                return


        channel = @createChannel chan, account
        @connections[key] = channel

        channel.connect()
        
        
    # Removes a connection from the specified channel.
    # * chan: Channel name to disconnect from.
    part: (chan) ->
        key = chan.toLowerCase()
        
        @connections[key]?.part()
        delete @connections[key]


    # Rejoins the specified channel.
    # * chan: The name of the channel to rejoin.
    rejoin: (chan) ->
        key = chan.toLowerCase()
        return unless (conn = @connections[key])?
        conn.part()
        setTimeout ->
            conn.connect()
        , 5000

    # Rejoins all channels
    restart: (chan) ->
        for _, conn of @connections
            conn.part()

        setTimeout =>
            for _, conn of @connections
                conn.connect()
        , 5000


    getLastActivityTimes: ->
        chans = {}
        for name, conn of @connections
            chans[name] = conn.lastActive
        return chans

    
    # Completely shuts down this Twitch instance.
    close: ->
        conn.part() for _, conn of @connections
        @connections = {}

    
    # Creates a new Channel object and connects all handlers.
    # * chan: Channel name.
    # * account: Bot account to set up with.
    # = Returns the channel object created.
    createChannel: (chan, account) ->
        channel = new Channel chan, account.name, account.pass
        
        channel.on 'message', (data) =>
            {from, op, message, meta} = data
            @emit 'message', chan, from, op, message, meta
            
        channel.on 'pm', (data) =>
            {from, message} = data
            @emit 'pm', chan, from, message
            
        channel.on 'error', (data) =>
            @emit 'error', chan, ("#{key}: #{val}" for key, val of data).join(', ')
        
        channel.on 'connected', =>
            @emit 'connected', chan
            
        channel.on 'connecting', =>
            @emit 'connecting', chan
            
        channel.on 'disconnecting', =>
            @emit 'disconnecting', chan
            
        return channel

    
    getAccounts: ->
        (account for account of @accounts)

    
    getChannels: ->
        (chan for _, chan of @connections)

    
    getShortChannels: ->
        (chan.name for _, chan of @connections)
   
 
    say: (chan, msg) ->
        return unless (conn = @connections[chan.toLowerCase()])?

        @logger?.timestamp 'SAY', chan, msg
        conn.say msg
        io.irc conn.name, conn.username, msg.cyan

        
    sayRaw: (chan, msg) ->
        return unless (conn = @connections[chan.toLowerCase()])?

        @logger?.timestamp 'RAW', chan, msg
        conn.sayRaw msg
        io.irc conn.name, conn.username, msg.red
        

exports.Twitch = Twitch
