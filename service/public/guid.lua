local skynet = require "skynet.manager"
local ServiceHelper = require "public.service_helper"
local CMD = ServiceHelper.CMD

local guid = 100000

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
        ServiceHelper.DispatchCmd(cmd, ...)
    end)
end)
