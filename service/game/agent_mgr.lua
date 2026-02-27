local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local AgentMgr = require "game.agentmgr.agent_mgr"
local ProtocolHelper = require "public.protocol_helper"
local CMD = ServiceHelper.CMD
local Logger = require "public.logger"

-- 初始化
function CMD.start()
    ProtocolHelper.RegisterProtocol()
    AgentMgr:Init()
    Logger.Info("AgentMgr 初始化完成")
end

function CMD.KickPlayer(account, reason)
    AgentMgr:KickPlayer(account, reason)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        ServiceHelper.DispatchCmd(cmd, subcmd, ...)
    end)
    skynet.register(".agent_mgr")
end)
