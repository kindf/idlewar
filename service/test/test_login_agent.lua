local skynet = require "skynet"
local netpack = require "skynet.netpack"
local table_util = require "util.table_util"
local socketdriver = require "skynet.socketdriver"
local queue		-- message queue

local server_fd

local time_interval = 1000

local test_table = {
    func_name = "client_call_battle",
}

local function test()
    local msg = table_util.table2str(test_table)
    socketdriver.send(server_fd, netpack.pack(msg))
    skynet.timeout(time_interval, test)
end

local MSG = {}
local handler = {}

local function print_battle(t)
    for _, v in pairs(t.battle_logs) do
        skynet.error(string.format("当前回合：%s, 我方生命：%s, 敌方生命：%s, 动作类型：%s, 伤害：%s\n", v.round, v.atk_hp, v.def_hp, v.act_type, v.damage))
    end
end

function handler.message(fd, msg, sz)
    if fd ~= server_fd then
        return skynet.error("error fd msg. fd:", fd)
    end
    local m = skynet.tostring(msg, sz)
    local t = table_util.str2table(m)
    if not t then
        return skynet.error("error msg. cant not to table")
    end
    -- print_battle(t)
    skynet.error(string.format("fd:%s recv msg.", fd))
end

local function dispatch_msg(fd, msg, sz)
    if server_fd == fd then
        handler.message(fd, msg, sz)
    else
        skynet.error(string.format("Drop message from fd (%d) : %s", fd, netpack.tostring(msg,sz)))
    end
end

MSG.data = dispatch_msg

local function dispatch_queue()
    local fd, msg, sz = netpack.pop(queue)
    if fd then
        -- may dispatch even the handler.message blocked
        -- If the handler.message never block, the queue should be empty, so only fork once and then exit.
        skynet.fork(dispatch_queue)
        dispatch_msg(fd, msg, sz)

        for fd, msg, sz in netpack.pop, queue do
            dispatch_msg(fd, msg, sz)
        end
    end
end

MSG.more = dispatch_queue

function MSG.open(fd, msg)
    socketdriver.nodelay(fd)
    server_fd = fd
    handler.connect(fd, msg)
end

function MSG.close(fd)
    if fd == server_fd then
        server_fd = nil	-- close read
    end
    if handler.disconnect then
        handler.disconnect(fd)
    end
end

function MSG.error(fd, msg)
    if fd == server_fd then
        socketdriver.shutdown(fd)
        if handler.error then
            handler.error(fd, msg)
        end
    end
end

function MSG.warning(fd, size)
    if handler.warning then
        handler.warning(fd, size)
    end
end

function MSG.init(id, addr, port)
end

skynet.register_protocol {
    name = "socket",
    id = skynet.PTYPE_SOCKET,	-- PTYPE_SOCKET = 6
    unpack = function ( msg, sz )
        return netpack.filter( queue, msg, sz)
    end,
    dispatch = function (_, _, q, type, ...)
        queue = q
        if type then
            MSG[type](...)
        end
    end
}


local CMD = {}
function CMD.start(fd, subid)
    subid = subid
    socketdriver.start(fd)
    server_fd = fd
    skynet.timeout(time_interval, test)
end

skynet.start(function()
    skynet.dispatch("lua", function(_,_, command, ...)
        local f = CMD[command]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error("invalid cmd. cmd:%s", command)
        end
    end)
end)
