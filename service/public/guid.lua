local skynet = require "skynet.manager"

local guid = 100000
local CMD = {}

local function heart_beat()
    local updater = {
        ["$set"] = { guid = guid }
    }
    skynet.send(".mongodb", "lua", "Update", "global", { tbname = "guid" }, updater, true, false)
    skynet.timeout(1000, heart_beat)
end

function CMD.start()
    local ret, result = skynet.call(".mongodb", "lua", "FindOne", "global", { tbname = "guid" })
    -- 没有则插入
    if not ret then
        result = {}
    end

    guid = result.guid or guid
    skynet.timeout(1000, heart_beat)
end

function CMD.GenUid()
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
