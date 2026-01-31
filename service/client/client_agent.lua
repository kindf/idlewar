local skynet = require "skynet"
local socket = require "skynet.socket"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local Pb = require "pb"
local Pids = require "proto.pids"
local netpack = require "skynet.netpack"
local socketdriver = require "skynet.socketdriver"
local rpc = require "user.rpc.main"

local CMD = {}
local account

local spack = string.pack
local function PackClientMsg(pid, msgBody)
    local ret, msg = pcall(Pb.encode, Pids[pid], msgBody)
    if not ret then
        return Logger.Error("消息编码失败 err:%s", msg)
    end
    local pack = spack(">h s", pid, msg)
    Logger.Info("pid:%s, msg:%s, pack:%s", pid, msg, pack)
    return netpack.pack(pack)
end

local gatePort = skynet.getenv("gate_port")
local function ClientLogin(account)
    local gateFd = socket.open("127.0.0.1", gatePort)
    local pbName = "login.c2s_check_version"
    local pid = Pids[pbName]
    local msgBody = {version = "aaa"}
    local msg = rpc.pack_rpc(pid, Pb.encode(pbName, msgBody))
    -- local pack = PackClientMsg(pid, msgBody)
    socket.write(gateFd, netpack.pack(msg))
    -- socket.write(gateFd, pack)
end

function CMD.start(account)
    account = account
    ProtocolHelper.RegisterProtocol()
    skynet.fork(function()
        ClientLogin(account)
    end)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
end)
