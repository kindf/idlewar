local skynet = require "skynet"
local table_util = require "util.table_util"
local M = {}

local users = {}

function M.get_user(uid)
    return users[uid]
end

function M.save_user(uid)
    local user = M.get_user(uid)
    if not user then
        return
    end
    local updater = {
        ["$set"] = user,
    }
    skynet.send(".mongodb", "lua", "update", {
        database = "gametest",
        collection = "user",
        selector = {acc = user.acc},
        update = updater,
        upsert = true,
        multi = false,
    })
    skynet.error("user save. ", table_util.dump(user))
end

--每60s保存一次
function M.heart_beat(uid)
    local user = M.get_user(uid)
    if not user then
        return
    end
    M.save_user(uid)
    --打印保存信息
    local interval = skynet.getenv("user_save_interval")
    skynet.timeout(100 * interval, function()
        M.heart_beat(uid)
    end)
end

function M.add_user(u)
    users[u.uid] = u
    local interval = skynet.getenv("user_save_interval")
    skynet.timeout(100 * interval, function()
        M.heart_beat(u.uid)
    end)
end

function M.user_logout(uid)
    local user = users[uid]
    M.save_user(uid)
    if user then
        users[uid] = nil
    end
end

function M.load_create_user_data(acc)
    local result = skynet.call(".mongodb", "lua", "find_one", {
        database = "gametest",
        collection = "user",
        query = {acc = acc},
        selector = {},
    })
    if not result then
        local uid = skynet.call(".guid", "lua", "get_new_guid")
        result = {
            acc = acc,
            uid = uid,
        }
        skynet.call(".mongodb", "lua", "insert", {
            database = "gametest",
            collection = "user",
            doc = result,
        })
    end

    return result
end


return M
