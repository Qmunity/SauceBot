# SauceBot Module: Filters

Sauce = require '../sauce'
db    = require '../saucedb'

io    = require '../ioutil'
time  = require '../../common/time'
log   = require '../../common/logger'

{ # Import DTO classes
    ArrayDTO,
    ConfigDTO,
    HashDTO,
    EnumDTO
} = require '../dto'

{Module} = require '../module'

# Module description
exports.name        = 'Filters'
exports.version     = '1.4'
exports.description = 'Filters URLs, caps-lock, words and emotes'

# Module strings
exports.strings = {
    
    # Warnings
    'warning-1': 'Strike 1'
    'warning-2': 'Strike 2'
    'warning-3': 'Strike 3'
    
    # Filter messages
    'on-url'  : 'No links without permission, @1@!'
    'on-caps' : 'Watch the caps, @1@!'
    'on-emote': 'No single emotes, @1@!'
    'on-word' : 'Bad word, @1@!'
    
    # Filter names
    'list-whitelist': 'Whitelist'
    'list-blacklist': 'Blacklist'
    'list-emotes'   : 'Emotes'
    'list-badwords' : 'Badwords'
    'list-regulars' : 'Regulars'
    
    'filter-url'     : 'URL'
    'filter-caps'    : 'Caps'
    'filter-emotes'  : 'Single-emote'
    'filter-words'   : 'Bad word'
    
    # Permits
    'permit-permitted': '@1@ permitted for @2@ seconds.'
    'permit-unknown'  : '@1@? Who\'s that? Either way, they\'re permitted for @2@ seconds.'

    # Clearstrikes
    'clear-cleared'   : 'Cleared strikes for @1@.'
    'clear-no-strikes': '@1@ doesn\'t have any strikes.'
    
    # Regulars
    'regulars-added'  : 'User @1@ added to regulars list.'
    'regulars-removed': 'User @1@ removed from regulars list.'
    
    # General actions
    'action-added'    : 'Added.'
    'action-removed'  : 'Removed.'
    'action-cleared'  : 'Cleared.'
    'action-purge'    : 'Purged @1@.'
    
    # Error messages
    'err-error'     : 'Error.'
    'err-no-target' : 'No target specified.'
    'err-no-value'  : 'No value specified.'
    'err-usage'     : 'Usage: @1@'
    
    # Status
    'filter-enabled' : '@1@ filter is now enabled.'
    'filter-disabled': '@1@ filter is now disabled.'

    'ignore-enable-subs' : 'Now ignoring subscribers'
    'ignore-enable-turbo': 'Now ignoring turbo users'
    'ignore-disable-subs' : 'No longer ignoring subscribers'
    'ignore-disable-turbo': 'No longer ignoring turbo users'
    
    'filter-is-enabled' : '@1@ filter is enabled. Disable with @2@'
    'filter-is-disabled': '@1@ filter is disabled. Enable with @2@'
    
}

# Filters
filterNames = ['url', 'caps', 'words', 'emotes']

# Database tables
tableNames = ['whitelist', 'blacklist', 'badwords', 'emotes']

# Database fields
tableFields =
    whitelist: 'url'
    blacklist: 'url'
    badwords : 'word'
    emotes   : 'emote'
    
# Strikes reset time (in ms)
TIMEOUT = 3 * 60 * 60 * 1000

URL_RE = /(?:(?:(?:https?:\/\/[-a-zA-Z0-9\.]*)|(?:[-a-zA-Z0-9]+\.))[-a-zA-Z-0-9]+\.(?:[a-zA-Z]{2,})\b|(?:\w+\.(?:[a-zA-Z]{2,}\/|(com|net|org|ru))))/

reasons = new log.Logger Sauce.Logging.Root, 'reasons.log'

io.module '[Filters] Init'

# Filter module
# - Handles:
#  !whitelist add <url>
#  !whitelist remove <url>
#  !whitelist clear
#  !blacklist add <url>
#  !blacklist remove <url>
#  !blacklist clear
#  !badwords add <word>
#  !badwords remove <word>
#  !badwords clear
#  !emotes add <emote>
#  !emotes remove <emote>
#  !emotes clear 
#  !permit <user> [minutes]
#  !clearstrikes <user>
#  !filter <url/caps/words/emotes> <on/off>
#  !filter <url/caps/words/emotes>
#  !regulars add <name>
#  !regulars remove <name>
#
#
class Filters extends Module
    constructor: (@channel) ->
        super @channel

        # Filter config
        @states   = new ConfigDTO @channel, 'filterstate', filterNames
        @config   = new ConfigDTO @channel, 'filterconf', ['ignoresubs', 'ignoreturbo']

        @regulars = new ArrayDTO  @channel, 'regulars' , 'username'
        
        # Filter lists
        @lists =
            whitelist: (new ArrayDTO @channel, 'whitelist', 'url')
            blacklist: (new ArrayDTO @channel, 'blacklist', 'url')
            badwords : (new ArrayDTO @channel, 'badwords' , 'word')
            emotes   : (new ArrayDTO @channel, 'emotes'   , 'emote')
        
        # Permits (filter immunity)
        #  username: expiration time
        @permits = {}
        
        # Warnings
        #   username:
        #     strikes: number of strikes
        #     time   : time of last warning 
        @warnings = {}
        

    load:  ->
        @registerHandlers()
        
        # Load lists
        @loadTable table for table in tableNames
            
        # Load states
        @loadStates()
        @regulars.load()
        

    registerHandlers: ->
        # Register filter list commands
        for filterName, filterList of @lists
          do (filterName, filterList) =>
            # !<filterlist> add <value> - Adds value to filter list
            @regCmd "#{filterName} add"   , Sauce.Level.Mod,
                (user, args, bot, network) =>
                    @cmdFilterAdd    filterName, filterList, args, network
                    
            # !<filterlist> remove <value> - Removes value from filter list
            @regCmd "#{filterName} remove", Sauce.Level.Mod,
                (user, args, bot, network) =>
                    @cmdFilterRemove filterName, filterList, args, network

            # !<filterlist> clear - Clears the filter list
            @regCmd "#{filterName} clear" , Sauce.Level.Mod,
                (user, args, bot, network) =>
                    @cmdFilterClear  filterName, filterList, args, network
                    

        # Register filter state commands
        for filter in filterNames
          do (filter) =>
            # !filter <filtername> on - Enables filter
            @regCmd "filter #{filter}" , Sauce.Level.Mod,
                (user, args, bot, network) =>
                    @cmdFilter filter, (args[0] ? ''), network
            

        # Register misc commands
        
        @regCmd 'regulars add',    Sauce.Level.Mod, @cmdAddRegular
        @regCmd 'regulars remove', Sauce.Level.Mod, @cmdRemoveRegular
        @regCmd 'permit',          Sauce.Level.Mod, @cmdPermitUser
        @regCmd 'clearstrikes',    Sauce.Level.Mod, @cmdClearStrikes
        @regCmd 'p',               Sauce.Level.Mod, @cmdPurge

        @regCmd 'ignoresubs',  Sauce.Level.Mod, @cmdIgnoreSubs
        @regCmd 'ignoreturbo', Sauce.Level.Mod, @cmdIgnoreTurbo


        @regVar 'timeout', @varTimeout




    varTimeout: (user, args, cb) =>
        usage = 'timeout <name>[, seconds]'
        unless args[0]?
            cb usage
        else
            timeout = 600
            if args.length == 2
                timeout = parseInt args[1], 10

            @bot.timeout args[0], timeout
            cb ""


    # Filter list command handlers
    cmdFilterAdd: (name, dto, args, network) =>
        value = args[0] if args[0]?
        if value?
            dto.add value.toLowerCase()
            @bot.say "[Filter] " + @str('list-' +  name) + " - " + @str('action-added'), network
        else
            @bot.say "[Filter] " + @str('err-no-value') + ' ' + @str('err-usage', "!" + name + " add <value>"), network
    
    
    cmdFilterRemove: (name, dto, args, network) =>
        value = args[0] if args[0]?
        if value?
            dto.remove value.toLowerCase()
            @bot.say "[Filter] " + @str('list-' +  name) + " - " + @str('action-removed'), network
        else
            @bot.say "[Filter] " + @str('err-no-value') + ' ' + @str('err-usage', "!" + name + " remove <value>"), network
            
            
    cmdFilterClear: (name, dto, args, network) =>
        dto.clear()
        @bot.say "[Filter] " + @str('list-' +  name) + " - " + @str('action-cleared'), network


    # Filter state command handlers

    cmdFilter: (filter, action, network) =>
        switch action
            when 'on'
                @cmdFilterEnable filter, network
            when 'off'
                @cmdFilterDisable filter, network
            else
                @cmdFilterShow filter, network


    cmdFilterEnable: (filter, network) =>
        @states.add filter, 1
        @bot.say "[Filter] " + @str('filter-enabled', @str('filter-' + filter)), network

    
    cmdFilterDisable: (filter, network) =>
        @states.add filter, 0
        @bot.say "[Filter] " + @str('filter-disabled', @str('filter-' + filter)), network


    cmdFilterShow: (filter, network) =>
        if @states.get filter
            @bot.say "[Filter] " + @str('filter-is-enabled', @str('filter-' + filter), '!filter ' + filter + ' off'), network
        else
            @bot.say "[Filter] " + @str('filter-is-disabled', @str('filter-' + filter), '!filter ' + filter + ' on'), network
            
    
    # Misc command handlers
    
    # !regulars remove <name> - Removes a regular.
    cmdRemoveRegular: (user, args, bot, network) =>
        unless (name = args[0])?
            return @bot.say "[Filter] " + @str('err-error') + ' ' + @str('err-usage', '!regulars remove <username>'), network
            
        @removeRegular name
        @bot.say @str('regulars-removed', name), network


    # Removes a user from the regulars list.
    removeRegular: (name) ->
        name = name.toLowerCase()
        @regulars.remove name


    # Adds a user to regulars and remove existing strikes.
    addRegular: (name) ->
        name = name.toLowerCase()
        @regulars.add name
        delete @warnings[name]


    # Removes all regulars.
    clearRegulars: ->
        @regulars.clear()


    # !regulars add <name> - Adds a regular.
    cmdAddRegular: (user, args, bot, network) =>
        unless (name = args[0])?
            return @bot.say @str('err-error') + ' ' + @str('err-usage', '!regulars add <username>'), network
            
        @addRegular name
        @bot.say @str('regulars-added', name), network


    # !permit <name> - Permits a user.
    cmdPermitUser: (user, args, bot, network) =>
        permitLength = 3 * 60 # 3 minutes
        permitTime   = time.now() + permitLength
        
        if (target = args[0])?

            # Filter out bad characters and convert to lower case.
            target = (target.replace /[^a-zA-Z0-9_]+/g, '').toLowerCase()

            msg = "[Filter] " + @str('permit-permitted', target, permitLength)

            # Look for the user in our user list.
            unless @channel.hasSeen target
                msg = "[Filter] " + @str('permit-unknown', target, permitLength)
            

            oldPermit = @permits[target]

            # Update permit time and remove strikes.
            @permits[target] = permitTime
            delete @warnings[target]

            if oldPermit > time.now()
                return

            @bot.say msg, network

            # Unban after 2 seconds to avoid the spam filter.
            setTimeout =>
                @bot.unban target
            , 2000

        else
            @bot.say "[Filter] " + @str('err-no-target') + ' ' + @str('err-usage', '!permit <username>'), network


    # !clearstrikes <name> - Clears strikes from a user
    cmdClearStrikes: (user, args, bot, network) =>
        unless (target = args[0])?
            @bot.say "[Filter] " + @str('err-no-target') + ' ' + @str('err-usage', '!clearstrikes <username>'), network
            return

        target = (target.replace /[^a-zA-Z0-9_]+/g, '').toLowerCase()
        if @warnings[target]
            delete @warnings[target]
            msg = @str('clear-cleared', target)
        else
            msg = @str('clear-no-strikes', target)

        @bot.say '[Filter] ' + msg, network
    

    # !p <name> - Purges (timeout for 1 second) user
    cmdPurge: (user, args, network) =>
        unless (target = args[0])?
            @bot.say "[Filter] " + @str('err-no-target') + ' ' + @str('err-usage', '!p <username>'), network
            return

        target = (target.replace /[^a-zA-Z0-9_]+/g, '').toLowerCase()
        @bot.timeout target, 1, network
        setTimeout =>
            @bot.say "[Filter] " + @str('action-purge', target), network
        , 4000


    # !ignoreturbo [on/off] - Toggles whether to ignore turbo users
    cmdIgnoreTurbo: (user, args, bot, network) =>
        @handleIgnoreCommand user, args, 'turbo', network


    # !ignoresubs [on/off] - Toggles whether to ignore subscribers
    cmdIgnoreSubs: (user, args, bot, network) =>
        @handleIgnoreCommand user, args, 'subs', network


    handleIgnoreCommand: (user, args, key, network) ->
        unless (state = args[0])?
            if @config.get "ignore#{key}"
                @bot.say "[Filter] " + @str('filter-is-enabled', "ignore#{key}", "!ignore#{key} off"), network
            else
                @bot.say "[Filter] " + @str('filter-is-disabled', "ignore#{key}", "!ignore#{key} on"), network
            return
        
        if state is 'on'
            @config.add "ignore#{key}", 1
            @bot.say "[Filter] " + @str('ignore-enable-' + key), network

        else if state is 'off'
            @config.add "ignore#{key}", 0
            @bot.say "[Filter] " + @str('ignore-disable-' + key), network

        else
            @bot.say "[Filter] " + @str('err-usage', "!ignore#{key} on/off"), network


    # Custom update handler to avoid super messy switches.
    update: (user, action, params, res) ->
        {type} = params

        if      type is 'config'   then @actConfig                action, params, res
        else if type is 'regulars' then @actDTOList @regulars,    action, params, res
        else if type is 'filters'  then @actAllFilters            action, params, res
        else if type in tableNames then @actDTOList @lists[type], action, params, res
        else res.error "Invalid Type"


    # Handles request for all filter lists
    actAllFilters: (action, params, res) ->
        res.send
            whitelist: @lists['whitelist'].get()
            blacklist: @lists['blacklist'].get()
            badwords:  @lists['badwords' ].get()
            emotes:    @lists['emotes'   ].get()
            regulars:  @regulars.get()


    # Handles update actions for DTO array lists.
    # * dto   : The dto to alter.
    # * act   : The specified action.
    # * params: The parameter map.
    # * res   : The result callback object.
    actDTOList: (dto, act, params, res) ->
        {key, keys, val} = params

        key  = key?.toLowerCase()
        keys = keys?.toLowerCase()
        val  = val?.toLowerCase()
        
        switch act
            when 'get'
                res.send dto.get()
                
            when 'add'
                return res.error "Missing attribute: key or keys" unless key or keys
                if keys
                    try
                        data = JSON.parse keys
                        dto.add entry for entry in data
                    catch e
                        return res.error "Invalid format for keys. JSON array expected."
                else
                    dto.add key
                res.ok()
                
            when 'set'
                return res.error "Missing attribute: key" unless key
                return res.error "Missing attribute: val" unless val
                dto.remove key
                dto.add val
                res.ok()
                
            when 'remove'
                return res.error "Missing attribute: key" unless key
                dto.remove key
                res.ok()
                
            when 'clear'
                dto.clear()
                res.ok()
                
            else
                res.error 'Invalid Action'
                

    # Handles update actions for the config states.
    # * act   : The specified action.
    # * params: The parameter map.
    # * res   : The result callback object.
    actConfig: (act, params, res) ->
        switch act
            when 'get'
                res.send @states.get()
                
            when 'set'
                altered = false
                for field in filterNames when (val = params[field])?
                    val = if (parseInt val, 10) then 1 else 0
                    @states.add field, val
                    altered = true
                
                if altered
                    res.send @states.get()
                else
                    res.error "Invalid state. States: #{filterNames.join ', '}"

            else
                res.error 'Invalid Action'
          

 
    loadTable: (table) ->
        list = @lists[table]
        list.load ->
            lcdata = (data.toLowerCase() for data in list.get())
            list.data = lcdata


    loadStates: ->
        @states.load()
        

    checkFilters: (name, msg, network, msguuid) ->
        msg = msg.trim()
        lower = msg.toLowerCase()
        
        # Badword filter
        if @states.get('words')  and @containsBadword lower
            return @handleStrikes name, @str('on-word', name), true, msg, network, msguuid
            
        # Single-emote filter
        if @states.get('emotes') and @isSingleEmote lower
            return @handleStrikes name, @str('on-emote', name), false, msg, network, msguuid
            
        # Caps filter
        if @states.get('caps')   and @isMostlyCaps msg
            return @handleStrikes name, @str('on-caps', name), false, msg, network, msguuid
            
        # URL filter
        if                           @containsBadURL lower
            return @handleStrikes name, @str('on-url', name), true, msg, network, msguuid
            
            
        
    handleStrikes: (name, response, clear, msg, network, msguuid) ->
        strikes = @updateStrikes(name)
        
        strikemsg = @str ('warning-' + (if strikes < 0 then 0 else if strikes > 3 then 3 else strikes))
        
        response = "#{response} #{strikemsg}"
        
        if      strikes is 1
            # First strike: verbal warning + optional clear
            if clear
                @bot.clear name, network, msguuid
            
        else if strikes is 2
            # Second strike: 10 minute timeout
            @bot.timeout name, 60 * 10, network, msguuid
        
        else if strikes is 3
            # Third strike: 8 hour timeout
            @bot.timeout name, 8 * 60 * 60, network, msguuid
            
        else if strikes is 4
            # Fourth strike: 1 day ban
            @bot.timeout name, 24 * 60 * 60, network, msguuid

        else if strikes > 4
            # Fifth+ stike: 1 week ban
            @bot.timeout name, 7 * 24 * 60 * 60. network, msguuid
            
        reasons.timestamp @channel.name, name, response, msg
            
        return if @channel.isQuiet()
            
        # Delay the response to avoid the JTV flood filter
        setTimeout =>
            @bot.say response, network
        , 4250
    
    
    containsBadword: (msg) ->
        for word in @lists['badwords'].get()
            if msg.indexOf(word) isnt -1 then return true
    
    
    isSingleEmote: (msg) ->
        for emote in @lists['emotes'].get()
            if msg is emote then return true


    isMostlyCaps: (msg) ->
        return (msg.length > 5) and (0.55 <= getCapsRate msg)

    
    containsBadURL: (msg) ->
        return false unless URL_RE.test msg
        if @states.get 'url'
            for url in @lists['whitelist'].get()
                if msg.indexOf(url) isnt -1 then return false
            return true
        else
            for url in @lists['blacklist'].get()
                if msg.indexOf(url) isnt -1 then return true
            return false
        
    
    handle: (user, msg, network, uuid) ->
        {name, op} = user
        
        if op or @isIgnored(name) then return
        lc = name.toLowerCase()

        if (permitTime = @permits[lc])?
            if time.now() > permitTime then delete @permits[lc] else return
            
        
        @checkFilters name, msg, network, uuid
        

    isIgnored: (name) ->
        return @isRegular(name) or (@config.get('ignoresubs')  and @channel.hasRole(name, Sauce.Role.Subscriber)) or (@config.get('ignoreturbo') and @channel.hasRole(name, Sauce.Role.Turbo))


    isRegular: (name) ->
        return name.toLowerCase() in @regulars.get()
        
        
    updateStrikes: (name) ->
        name = name.toLowerCase()
        now  = Date.now()
        
        if not @warnings[name]? or @isOutOfDate @warnings[name].time, now
            @warnings[name] =
                strikes: 0
                time   : 0

        @warnings[name].time = now
        ++@warnings[name].strikes
        
        
    isOutOfDate: (time, now) ->
        return now - time > TIMEOUT
        
        
        
getCapsRate = (msg) ->
    # Yay for functional programming!
    (true for chr in msg when chr >= 'A' and chr <= 'Z').length / (msg.length * 1.0)


exports.New = (channel) ->
    new Filters channel
