local skynet = require "skynet.manager"
local mongo = require "skynet.db.mongo"
local ServiceHelper = require "public.service_helper"
local Logger = require "public.logger"
local TableHelper = require "public.table_helpler"
local CMD = ServiceHelper.CMD

local client
local database = "idlewar"

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

local function Insert(collection, doc)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    c:insertOne(doc)
end

local function InsertBatch(collection, docs)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    c:batch_insert(docs)
end

local function Delete(collection, selector, single)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    c:delete(selector, single)
end

local function Drop(args)
    local db = client:getDB(database)
    local r = db:runCommand("drop", args.collection)
    return r
end

local function FindOne(collection, query, selector)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    local result = c:findOne(query, selector)
    return result
end

local function FindAll(collection, query, selector, skip, limit)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    local result = {}
    local cursor = c:find(query, selector)
    if skip ~= nil then
        cursor:skip(skip)
    end
    if limit ~= nil then
        cursor:limit(limit)
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

local function Update(collection, selector, update, upsert, multi)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    c:update(selector, update, upsert, multi)
end

function CMD.create_index(args)
    local db = client:getDB(args.database)
    local c = db:getCollection(args.collection)
    local result = c:createIndex(args.keys, args.option)
    return result
end

function CMD.run_command(args)
    local db = client:getDB(database)
    local result = db:runCommand(args)
    return result
end

function CMD.Insert(collection, doc)
    assert(collection, "collection为空")
    local ret, retData = pcall(Insert, collection, TableHelper.SerializeBsonFormat(doc))
    if not ret then
        return Logger.Error("[mongodb] Insert 插入数据失败 collection:%s, err:%s", collection, retData)
    end
    return retData
end

function CMD.Update(collection, selector, data, upsert, multi)
    assert(collection, "collection为空")
    local update = {
        ["$set"] = TableHelper.SerializeBsonFormat(data),
    }
    local ret, retData = pcall(Update, collection, selector, update, upsert, multi)
    if not ret then
        return Logger.Error("[mongodb] Update 更新数据失败 collection:%s, err:%s", collection, retData)
    end
    return retData
end

function CMD.FindOne(collection, query, selector)
    assert(collection, "collection为空")
    local ret, retData = pcall(FindOne, collection, query, selector)
    if not ret then
        return Logger.Error("[mongodb] FindOne 加载数据失败 collection:%s, err:%s", collection, retData)
    end
    return retData and TableHelper.DeserializeBsonFormat(retData) or nil
end

skynet.start(function()
    skynet.register(".mongodb")
    skynet.dispatch("lua", function(_, _, cmd, ...)
        ServiceHelper.DispatchCmd(cmd, ...)
    end)
end)
