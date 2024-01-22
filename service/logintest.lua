local skynet = require "skynet"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"
local common_util = require "util.common_util"
local table_util = require("util.table_util")

local cnt = 0
local gate_fd
local subid

local acc = "test4"
local test_table = {
    func_name = "main_fight",
    uid = 10003,
    prize_id = "item_1",
    t = {[1] = 1, [10000] = 2},
}

local function test()
    cnt = cnt + 1
    local msg = table_util.table2str(test_table)
    socket.write(gate_fd, netpack.pack(msg))
    skynet.timeout(100, test)
end

local function connect_gate()
    gate_fd = socket.open("127.0.0.1", 8888)
    local msg = acc.."@"..subid
    socket.write(gate_fd, netpack.pack(msg))
    skynet.timeout(100, test)
end

local function connect_test()
    local fd = socket.open("127.0.0.1", 9999)
    local token = acc.."@password\n"
    socket.write(fd, token)
    local response = socket.readline(fd)
    print("response:", response)
    local str = string.sub(response, 4, -1)
    subid = crypt.base64decode(str)
    print("subid:", subid)
    connect_gate()

end

local mongo = require "skynet.db.mongo"
local client

local function mongo_find_one_test(database, collection, query, selector)
    local db = client:getDB(database)
    local c = db:getCollection(collection)
    local result = c:findOne(query, selector)
    return result
end

-- test_auth("127.0.0.1", 27017, "gametest", "kindf", "ljl123456")
function test_auth(host, port, db_name, username, password)
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

skynet.start(function()
    connect_test()
end)

