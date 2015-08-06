# SauceBot Module: Quotes

Sauce = require '../sauce'
db    = require '../saucedb'
io    = require '../ioutil'

{ConfigDTO, EnumDTO, BucketDTO} = require '../dto'

{Module} = require '../module'

# Module description
exports.name        = 'Quotes'
exports.version     = '1.0'
exports.description = 'Random quotes'
exports.locked      = false

exports.strings = {
    'err-usage': "Usage: @1@"
    'quote'    : '"@1@" - @2@'
    'no-quotes' : 'No quotes for @1@'
    'invalid-id': 'This ID is invalid'
    'edited': "Quote has been edited"
    'removed': "Quote @1@ has been removed"
}

io.module '[Quotes] Init'

class Quotes extends Module
    constructor: (@channel) ->
        super @channel
        @quoteDTO = new BucketDTO @channel, 'quotes', 'id', ['list', 'quote']
        @quotes   = {}
        @quotesId = []
        
        
    load: ->
        @registerHandlers()
        
        @quoteDTO.load =>
            @reload()

        
        # Register web interface update handlers
        @regActs {
            # Quotes.get([list])
            'get': (user, params, res) =>
                {list} = params
                if list?
                    res.send @quotes[list] ? []
                else
                    res.send Object.keys @quotes

            # Quotes.set(list, key, val)
            'set': (user, params, res) =>
                res.ok()

            # Quotes.add(list, val)
            'add': (user, params, res) =>
                res.ok()

            # Quotes.remove(list, val)
            'remove': (user, params, res) =>
                res.ok()

            # Quotes.clear(list)
            'clear': (user, params, res) =>
                res.ok()

        }
        
    reload: =>
            @quotes   = {}
            @quotesId = []
            for id, {quote, list} of @quoteDTO.data
                @quotes[list] = [] unless @quotes[list]?
                @quotes[list].push quote

                @quotesId.push {"list":list, "quote":quote, "dbid":id}

    registerHandlers: ->
        @regCmd "quote", Sauce.Level.Mod, @cmdRandomQuote
        @regCmd "quote add", Sauce.Level.Mod, @cmdAddQuote
        @regCmd "quote edit", Sauce.Level.Mod, @cmdEditQuote
        @regCmd "quote remove", Sauce.Level.Mod, @cmdRemoveQuote

        @regVar 'quote', (user, args, cb) =>
            unless (list = args[0])? and (@hasQuotes list)
                cb 'N/A'
            else
                cb @getRandomQuote list
                
                
    hasQuotes: (list)      -> @quotes[list]?.length
    numQuotes: (list)      -> @quotes[list]?.length
    getQuote : (list, idx) -> @quotes[list]?[idx]
    

    addQuote: (list, msg)  =>
        list = list.toLowerCase()
        quote = {}
        quote['chanid'] = @channel.id
        quote['list'] = list.toLowerCase()
        quote['quote'] = msg
        @quoteDTO.add null, quote


        @quotes[list] = [] unless @quotes[list]?
        @quotes[list].push msg

        @quotesId.push {"quote": msg, "list": list}

        @bot.say "Quote added"

    getRandomQuote: (list) ->
        @getQuote list.toLowerCase(), ~~ (Math.random() * @numQuotes list)
    

    cmdRandomQuote: (user, args) =>
        if args.length == 0
            #Get a random quote from a random list
            keys = Object.keys(@quotes)
            if keys == 0
                return @bot.say @str('no-quotes', 'this channel')

            list = keys[~~(Math.random() * keys.length)]
            return @bot.say @str('quote', @getRandomQuote(list), list)
        
        if args.length == 1
            if(args[0].substring(0,1) == "#")
                #ID found
                id = parseInt(args[0].substr(1), 10)-1
                unless @quotesId[id]?
                    return @bot.say @str('no-quotes', args[0])

                quote = @quotesId[id]

                @bot.say @str('quote', quote['quote'], quote['list'])
            else
                list = args[0].toLowerCase()
                unless @quotes[list]?
                    return @bot.say @str('no-quotes', list)
            
                @bot.say @str('quote', @getRandomQuote(list), list)

    cmdAddQuote: (user, args) =>
        if args.length < 2
            return @bot.say @str('err-usage', '!quote add <list> <quote>')

        list = args[0]
        args.splice(0,1)
        msg = args.join(' ')

        @addQuote(list, msg)

    cmdEditQuote: (user, args) =>
        if args.length < 3
            return @bot.say @str('err-usage', '!quote edit #<id> <newquote>')
        
        if args[0].substr(0, 1) != "#"
            return @bot.say @str('err-usage', '!quote edit #<id> <newquote>')
        
        id = parseInt(args[0].substr(1), 10)-1
        if isNaN id
            return @bot.say @str('invalid-id')

        unless @quotesId[id]?
            return @bot.say @str('no-quotes', args[0])

        quote = {}
        quote['chanid'] = @channel.id
        quote['id'] = @quotesId[id]['dbid']
        quote['list'] = @quotesId[id]['list']
        args.splice(0,1)
        quote['quote'] = args.join(' ')

        @quoteDTO.add @quotesId[id]['dbid'], quote

        @reload()

        @bot.say @str('edited')


    cmdRemoveQuote: (user, args) =>
        if args.length < 1
            return @bot.say @str('err-usage', '!quote remove #<id>')

        if args[0].substr(0, 1) != "#"
            return @bot.say @str('err-usage', '!quote remove #<id>')

        id = parseInt(args[0].substr(1))-1
        if isNaN id
            return @bot.say @str('invalid-id')

        unless @quotesId[id]?
            return @bot.say @str('no-quotes', args[0])

        quote = @quotesId[id]

        @quoteDTO.remove quote['dbid']

        @reload()

        @bot.say @str('removed', args[0])


exports.New = (channel) -> new Quotes channel
