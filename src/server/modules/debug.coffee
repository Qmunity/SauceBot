# SauceBot Debugging Module

io    = require '../ioutil'
Sauce = require '../sauce'
db    = require '../saucedb'

{Module  } = require '../module'
{TokenJar} = require '../../common/oauth'

# Module metadata
exports.name        = 'Debug'
exports.version     = '1.0'
exports.description = 'Debugging utilities'
exports.ignore      = 1
exports.locked      = 1

io.module '[Debug] Init'

oauth = new TokenJar Sauce.API.Twitch, Sauce.API.TwitchToken

class Debug extends Module
    load: ->
        global = Sauce.Level.Owner + 1

        @regCmd 'dbg reload', global, (user, args, bot, network) =>
            unless (moduleName = args[0])?
                return @bot.say "Usage: !dbg reload <module name>", network

            @bot.say "Reloading #{moduleName}", network
            @channel.reloadModule moduleName

        @regCmd 'dbg unload', global, (user, args, bot, network) =>
            unless (moduleName = args[0])?
                return @bot.say "Usage: !dbg unload <module name>", network

            db.removeChanData @channel.id, 'module', 'module', moduleName, =>
                @bot.say "Unloading #{moduleName}", network
                @channel.loadChannelModules()

        @regCmd 'dbg load', global, (user, args, bot, network) =>
            unless (moduleName = args[0])?
                return @bot.say "Usage: !dbg load <module name>", network

            db.addChanData @channel.id, 'module', ['module', 'state'], [[moduleName, 1]], =>
               @bot.say "Module #{moduleName} loaded", network
               @channel.loadChannelModules()

        @regCmd 'dbg all', global, (user, args) =>
            @cmdModules()
            @cmdTriggers()
            @cmdVars()

        @regCmd 'dbg modules', global, (user, args) =>
            @cmdModules()

        @regCmd 'dbg triggers', global, (user, args) =>
            @cmdTriggers()

        @regCmd 'dbg vars', global, (user, args) =>
            @cmdVars()

        @regCmd 'dbg oauth', global, (user, args) =>
            @cmdOauth()

        @regCmd 'dbg commercial', global, (user, args) =>
            @cmdCommercial()


    cmdModules: (user, args, bot, network) ->
        @bot.say ("#{m.name}#{if not m.loaded then '[?]' else ''}" for m in @channel.modules).join(' '), network


    cmdTriggers: (user, args, bot, network) ->
        @bot.say "Triggers for #{@channel.name}:", network
        @bot.say "[#{t.oplevel}]#{t.pattern}", network for t in @channel.triggers


    cmdVars: (user, args, bot, network) ->
        @bot.say "Variables for #{@channel.name}:", network
        @bot.say "#{v.module} - #{k}", network for k, v of @channel.vars.handlers


    cmdOauth: (user, args, bot, network)->
        oauth.get '/user', (resp, body) =>
            io.debug body
            if body['display_name']?
                @bot.say "Authenticated as #{body['display_name']}", network
            else
                @bot.say "Not authenticated.", network


    cmdCommercial: (user, args, bot, network) ->
        oauth.post "/channels/#{@channel.name}/commercial", (resp, body) =>
            @bot.say "Commercial: #{(resp?.headers?.status) ? resp.statusCode}", network


exports.New = (channel) -> new Debug channel

