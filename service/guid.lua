local skynet = require "skynet.manager"

local guid = 100000

local CMD = {}

local function heart_beat()
    local updater = {
        ["$set"] = {guid = guid}
    }
    skynet.send(".mongodb", "lua", "update", {
        database = "gametest",
        collection = "global",
        selector = {tbname = "guid"},
        update = updater,
        upsert = true,
        multi = false,
    })
    skynet.timeout(1000, heart_beat)
end

function CMD.start()
    local result = skynet.call(".mongodb", "lua", "find_one", {
        database = "gametest",
        collection = "global",
        query = {tbname = "guid"},
        selector = {},
    })
    -- 没有则插入
    if not result then
        skynet.call(".mongodb", "lua", "insert", {
            database = "gametest",
            collection = "global",
            doc = {tbname = "guid", guid = guid},
        })
    end

    guid = result.guid
    skynet.timeout(1000, heart_beat)
end

function CMD.get_new_guid()
    guid = guid + 1
    return guid
end

skynet.start(function()
    skynet.register(".guid")
    skynet.dispatch("lua", function(_, _, cmd, ...)
        local f = CMD[cmd]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error(string.format("Unknown command:%s", cmd))
        end
    end)
end)
