require "public.dump"
local skynet = require "skynet"
local socket = require "skynet.socket"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local Pb = require "pb"
local Pids = require "proto.pids"
local netpack = require "skynet.netpack"
local spack = string.pack

local CMD = {}
local account
local gateFd

local function ReceiveMessage()
    local dataLen = socket.read(gateFd, 2)
    if not dataLen then
        return Logger.Error("[ReceiveMessage] 消息接收失败")
    end
    local len = string.unpack(">I2", dataLen)
    local data = socket.read(gateFd, len)
    if not data then
        return Logger.Error("[ReceiveMessage] 消息接收失败")
    end
    local ok, err, buffMsg = xpcall(ProtocolHelper.UnpackHeader, debug.traceback, data)
    if not ok then
        return Logger.Error("[HandleServerMessage] 协议头解析失败 err:%s", err)
    end
    local protoName = Pids[err]
    local msg = Pb.decode(protoName, buffMsg)
    return msg
end

local function PackMsg(pbName, msgBody)
    local pid = Pids[pbName]
    local ret, msg = pcall(Pb.encode, pbName, msgBody)
    if not ret then
        return Logger.Error("消息编码失败 err:%s", msg)
    end
    local msg_len = #msg
    local pack = spack(">hc" .. msg_len, pid, msg)
    return pack
end

local function C2S(protoName, data, callback)
    local pack = PackMsg(protoName, data)
    socket.write(gateFd, netpack.pack(pack))
    local resp = ReceiveMessage()
    if callback then
        callback(resp)
    end
    Logger.Debug("[C2S] protocol callback resp:%s", table.dump(resp))
end

local loginToken
local function DoSomething()
    -- 检查版本
    C2S("login.c2s_check_version", { version = "ac01c22155e4a7264482d8ddc71343b5" }, function(_) end)
    -- 登录认证
    C2S("login.c2s_login_auth", { account = "test1", token = "token" }, function(resp) loginToken = resp.loginToken end)
    -- 登录游戏
    C2S("player_base.c2s_login_game", { account = "test1", loginToken = loginToken }, function(_) end)
end

local gatePort = skynet.getenv("gate_port")
function CMD.start(acc)
    account = acc
    gateFd = assert(socket.open("127.0.0.1", gatePort))
    ProtocolHelper.RegisterProtocol()
    DoSomething()
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
end)
