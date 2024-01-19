local skynet = require "skynet.manager"
local common_util = require "util.common_util"
local M = {}

local user = {}
user.__index = user

--每10s保存一次
function user:heart_beat()
    skynet.error(common_util.dump(self))
    local updater = {
        ["$set"] = {
            uid = self.uid,
            msg_cnt = self.msg_cnt,
        },
    }
    skynet.send(".mongodb", "lua", "update", {
        database = "gametest",
        collection = "test",
        selector = {acc = self.acc},
        update = updater,
        upsert = true,
        multi = false,
    })
    skynet.timeout(1000, function()
        self:heart_beat()
    end)
end

function user:init(data)
    self.acc = data.acc
    self.uid = data.uid
    self.msg_cnt = data.msg_cnt or 0
    skynet.timeout(1000, function()
        self:heart_beat()
    end)
end

function M.new()
    local o = {}
    setmetatable(o, user)
    return o
end

return M
