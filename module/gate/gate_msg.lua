local skynet = require "skynet"
local Logger = require "public.logger"
local GateMgr = require "gate.gate_mgr"
local CMD = {}

function CMD.start()
    GateMgr.Init("0.0.0.0", skynet.getenv("gate_port"))
end

function CMD.kick_fd(fd, reason)
end

function CMD.kick_uid(uid, reason)
end

function CMD.bind_agent(fd, uid, agent)
end

function CMD.SendClientMessage(fd, msg)
    GateMgr.SendClientMessage(fd, msg)
    Logger.Debug("[CMD.SendClientMessage] 发送消息 fd:%s", fd)
end

return CMD
