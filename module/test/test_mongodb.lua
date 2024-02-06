local table_util = require("util.table_util")

local M = {}

local mongo = require "skynet.db.mongo"
local client

function M.mongo_find_one_test(database, collection, query, selector)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    local result = c:findOne(query, selector)
    return result
end

-- test_auth("127.0.0.1", 27017, "gametest", "kindf", "ljl123456")
function M.test_auth(host, port, db_name, username, password)
    local ok, err, ret
    local c = mongo.client({
        host = host,
        port = tonumber(port),
        username = username,
        password = password,
    })
    local db = c[db_name]

    -- ok, err, ret = db.test:safe_insert({a = 1, b = 2});
    local coll = db:getCollection("test")
    ret = coll:findOne({}, {})
    print(table_util.dump(ret))
    -- assert(ok and ret and ret.n == 1, err)
end

return M
