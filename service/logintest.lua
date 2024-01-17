local skynet = require "skynet"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"

local cnt = 0
local gate_fd
local subid
local timeout_msg = "timeout msg"
local function test()
    cnt = cnt + 1
    socket.write(gate_fd, netpack.pack(timeout_msg..cnt))
    skynet.timeout(100, test)
end

local function connect_gate()
    gate_fd = socket.open("127.0.0.1", 8888)
    local msg = "kindf@"..subid
    socket.write(gate_fd, netpack.pack(msg))
    skynet.timeout(100, test)
end

skynet.start(function()
    local fd = socket.open("127.0.0.1", 9999)
    local token = "kindf@password\n"
    socket.write(fd, token)
    local response = socket.readline(fd)
    print("response:", response)
    local str = string.sub(response, 4, -1)
    subid = crypt.base64decode(str)
    print("subid:", subid)
    connect_gate()
end)

