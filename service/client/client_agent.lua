require "public.dump"
local skynet = require "skynet"
local socket = require "skynet.socket"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local Pb = require "pb"
local Pids = require "proto.pids"
local netpack = require "skynet.netpack"
local RpcHelper = require "util.rpc_helper"

local CMD = {}
local account
local gateFd

local spack = string.pack

local function ReceiveMessage()
    local dataLen = socket.read(gateFd, 2)
    if not dataLen then
        return Logger.Error("消息接收失败")
    end
    local len = string.unpack(">I2", dataLen)
    local data = socket.read(gateFd, len)
    if not data then
        return Logger.Error("消息接收失败")
    end
    return data
end

local function Dispatch(protoId, protoBody)
    if not protoId then
        return Logger.Error("[Dispatch] 不存在的协议号 pid:%s", protoId)
    end

    if not Pids[protoId] then
        return Logger.Error("[Dispatch] 不存在的协议号 pid:%s", protoId)
    end

    local protoName = Pids[protoId]
    assert(protoName, "[Dispatch] 不存在的协议 protoId:" .. protoId)
    local msg = Pb.decode(protoName, protoBody)
    local handler = ProtocolHelper.GetProtocolHandler(protoId)
    Logger.Debug("[Dispatch] 协议处理函数 protoId:%s", protoId)
    local ret, err = pcall(handler.handler, msg, nil)
    if not ret then
        Logger.Error("[Dispatch] 协议处理函数失败 err:%s", err)
    end
end

function HandleServerMessage(msg)
    local ok, err, buffMsg = xpcall(RpcHelper.UnpackHeader, debug.traceback, msg)
    if not ok then
        return Logger.Error("[HandleServerMessage] 协议头解析失败 err:%s", err)
    end
    Dispatch(err, buffMsg)
end

local function MessageLoop()
    skynet.fork(function()
        while true do
            local msg = ReceiveMessage()
            if not msg then
                break
            end
            HandleServerMessage(msg)
        end
    end)
end

local function PackMsg(pbName, msgBody)
    local pid = Pids[pbName]
    local ret, msg = pcall(Pb.encode, pbName, msgBody)
    if not ret then
        return Logger.Error("消息编码失败 err:%s", msg)
    end
    local msg_len = #msg
    local pack = spack(">hc"..msg_len, pid, msg)
    return pack
end

local function C2SLoginAuth()
    local pack = PackMsg("login.c2s_login_auth", {account = "test1", token = "token"})
    socket.write(gateFd, netpack.pack(pack))
end

local function C2SCheckVersion()
    local pack = PackMsg("login.c2s_check_version", {version = "aaa"})
    socket.write(gateFd, netpack.pack(pack))
    Logger.Debug("[C2SCheckVersion] 发送协议")
end


local gatePort = skynet.getenv("gate_port")
local function DoAction()
    C2SCheckVersion()
end

function Init()
    gateFd = assert(socket.open("127.0.0.1", gatePort))
    MessageLoop()
    DoAction()
    Logger.Debug("[Init] 初始化完成")
end

function CMD.start(account)
    account = account
    ProtocolHelper.RegisterProtocol()
    Init()
end

local function S2CCheckVersion(msg)
    Logger.Debug("[S2CCheckVersion] 接受到服务器回包 msg:%s", table.dump(msg))
    C2SLoginAuth()
end
ProtocolHelper.RegisterProtocolHandler(Pids["login.s2c_check_version"], S2CCheckVersion)

local function S2CLoginAuth(msg)
    Logger.Debug("[S2CLoginAuth] 接受到服务器回包 msg:%s", table.dump(msg))
end
ProtocolHelper.RegisterProtocolHandler(Pids["login.s2c_login_auth"], S2CLoginAuth)

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
end)
