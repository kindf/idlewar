local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local AgentMgr = require "game.agentmgr.agent_mgr"
local ProtocolHelper = require "public.protocol_helper"
local Pids = require "proto.pids"
local CMD = ServiceHelper.CMD
local Logger = require "public.logger"

CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

-- 初始化
function CMD.start()
    ProtocolHelper.RegisterProtocol()
    AgentMgr.Init()
    Logger.Info("AgentMgr 初始化完成")
end


-- 注册协议处理器
local function C2SLoginGame(req, resp)
    local account = req.account
    local loginToken = req.loginToken
    resp.retCode = AgentMgr.LoginGame(account, loginToken)
    Logger.Debug("C2SLoginGame account:%s retCode:%s", account, resp.retCode)
end
ProtocolHelper.RegisterRpcHandler(Pids["player_base.c2s_login_game"], Pids["player_base.s2c_login_game"], C2SLoginGame)


-- 导出命令
CMD.GetOnlinePlayers = AgentMgr.GetOnlinePlayers
CMD.KickPlayer = AgentMgr.KickPlayer
CMD.GetagentInfo = AgentMgr.GetagentInfo
CMD.SendMessageToPlayer = AgentMgr.SendMessageToPlayer
CMD.BroadcastMessage = AgentMgr.BroadcastMessage
CMD.CleanupOfflinePlayers = AgentMgr.CleanupOfflinePlayers
CMD.HeartbeatCheck = AgentMgr.HeartbeatCheck
CMD.BindConnection = AgentMgr.BindConnection
CMD.Logout = AgentMgr.Logout

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        ServiceHelper.DispatchCmd(cmd, subcmd, ...)
    end)
    skynet.register(".agent_mgr")
end)
