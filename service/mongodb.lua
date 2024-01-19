local skynet = require "skynet.manager"
local mongo = require "skynet.db.mongo"

local client
local CMD = {}

function CMD.connect(host, port, username, pwd)
    client = mongo.client({
        host = host,
        port = tonumber(port),
        username = username,
        password = pwd,
    })
end

function CMD.disconnect()
    client:disconnect()
end

function CMD.insert(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    c:insert(args.doc)
end

function CMD.insert_batch(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    c:batch_insert(args.docs)
end

function CMD.delete(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    c:delete(args.selector, args.single)
end

function CMD.drop(args)
    local db = client:getDB(args.database)
    local r = db:runCommand("drop", args.collection)
    return r
end

function CMD.find_one(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    local result = c:findOne(args.query, args.selector)
    return result
end

function CMD.find_all(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    local result = {}
    local cursor = c:find(args.query, args.selector)
    if args.skip ~= nil then
        cursor:skip(args.skip)
    end
    if args.limit ~= nil then
        cursor:limit(args.limit)
    end
    while cursor:hasNext() do
        local document = cursor:next()
        table.insert(result, document)
    end
    cursor:close()
    if #result > 0 then
        return result
    end
end

function CMD.update(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    c:update(args.selector, args.update, args.upsert, args.multi)
end

function CMD.create_index(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    local result = c:createIndex(args.keys, args.option)
    return result
end

function CMD.run_command(args)
    local db = client:getDB(args.database)
    local result = db:runCommand(args)
    return result
end

skynet.start(function()
    skynet.register(".mongodb")
    skynet.dispatch("lua", function(_, _, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error(string.format("Unknown command:%s", cmd))
        end
    end)
end)
