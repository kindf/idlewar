local skynet = require "skynet"
local socket = require "skynet.socket"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"

local account_list = {}
--登录账号信息
for i = 1, 1 do
    table.insert(account_list, {
        server = "idlewar",
        acc = "test_acc"..i,
        password = "password",
        subid = nil,
    })
end

local function connect_gate(account)
    local gate_fd = socket.open("127.0.0.1", skynet.getenv("gate_port"))
    local msg = account.acc.."@"..account.subid
    socket.write(gate_fd, netpack.pack(msg))
    local test_agent = skynet.newservice("test_login_agent")
    skynet.call(test_agent, "lua", "start", gate_fd, account.subid )
end

--login认证
local function auth_login(account)
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
    account.subid = crypt.base64decode(string.sub(response, 4, -1))
end

local function connect(account)
    auth_login(account)
    connect_gate(account)
end

skynet.start(function()
    skynet.fork(function()
        for _, v in pairs(account_list) do
            connect(v)
        end
    end)
end)
