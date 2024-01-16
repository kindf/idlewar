local skynet = require "skynet"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"

local cnt = 0
local gate_fd
local function test()
    cnt = cnt + 1
    local timeout_msg = "timeout msg"
    socket.write(gate_fd, netpack.pack(timeout_msg..cnt))
    skynet.timeout(100, test)
end

local function connect_gate()
    gate_fd = socket.open("127.0.0.1", 8888)
    local msg = "kindf@password"
    socket.write(gate_fd, netpack.pack(msg))
    skynet.timeout(100, test)
end

skynet.start(function()
    local fd = socket.open("127.0.0.1", 9999)
    local token = "kindf@password"
    socket.write(fd, token)
    connect_gate()
end)

