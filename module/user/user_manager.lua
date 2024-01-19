local skynet = require "skynet"
local M = {}

local users = {}

function M.get_user(uid)
    return users[uid]
end

function M.add_user(u)
    users[u.uid] = u
end

function M.load_create_user_data(acc)
    local result = skynet.call(".mongodb", "lua", "find_one", {
        database = "gametest",
        collection = "test",
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
            collection = "test",
            doc = result,
        })
    end

    return result
end


return M
