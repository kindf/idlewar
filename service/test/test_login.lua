local skynet = require "skynet"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"
local table_util = require("util.table_util")
local socketdriver = require "skynet.socketdriver"

local subid

--登录账号信息
local account = {
    server = "idlewar",
    acc = "test4",
    password = "password"
}

local function connect_gate()
    local gate_fd = socket.open("127.0.0.1", skynet.getenv("gate_port"))
    local msg = account.acc.."@"..subid
    socketdriver.send(gate_fd, netpack.pack(msg))
    skynet.sleep(100)
    local test_agent = skynet.newservice("test_login_agent")
    skynet.call(test_agent, "lua", "start", gate_fd, subid )
end

--login认证
local function auth_login()
    local fd = socket.open("127.0.0.1", skynet.getenv("login_port"))
    local response

    response = socket.readline(fd)
    local challenge = crypt.base64decode(response)

    local clientkey = crypt.randomkey()
    socket.write(fd, crypt.base64encode(crypt.dhexchange(clientkey)).."\n")

    response = socket.readline(fd)
    local serverkey = crypt.base64decode(response)

    local secret = crypt.dhsecret(serverkey, clientkey)
    local hmac = crypt.hmac64(challenge, secret)
    socket.write(fd, crypt.base64encode(hmac).."\n")

    local etoken = crypt.desencode(secret, string.format("%s@%s:%s", account.server, account.acc, account.password))
    socket.write(fd, crypt.base64encode(etoken).."\n")

    response = socket.readline(fd)
    print(response)
    subid = crypt.base64decode(string.sub(response, 4, -1))
end

skynet.start(function()
    skynet.fork(function()
        auth_login()
        connect_gate()
    end)
end)
