local skynet = require "skynet"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"
local table_util = require("util.table_util")
local socketdriver = require "skynet.socketdriver"

local subid

local acc = "test4"

local function connect_gate()
    local gate_fd = socket.open("127.0.0.1", skynet.getenv("gate_port"))
    local msg = acc.."@"..subid
    socketdriver.send(gate_fd, netpack.pack(msg))
    skynet.sleep(100)
    local test_agent = skynet.newservice("test_login_agent")
    skynet.call(test_agent, "lua", "start", gate_fd, subid )
end

local function connect_test()
    local fd = socket.open("127.0.0.1", skynet.getenv("login_port"))
    local token = acc.."@password\n"
    socket.write(fd, token)
    local response = socket.readline(fd)
    print("response:", response)
    local str = string.sub(response, 4, -1)
    subid = crypt.base64decode(str)
    print("subid:", subid)
    connect_gate()

end

skynet.start(function()
    skynet.fork(function()
        connect_test()
    end)
end)
