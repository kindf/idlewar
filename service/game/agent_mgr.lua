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
local function C2SEnterGame(req, resp)
    local account = req.account
    local loginToken = req.loginToken
    resp.retCode = AgentMgr.EnterGame(account, loginToken)
    Logger.Debug("C2SEnterGame account:%s retCode:%s", account, resp.retCode)
end
ProtocolHelper.RegisterRpcHandler(Pids["player_base.c2s_enter_game"], Pids["player_base.s2c_enter_game"], C2SEnterGame)

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        ServiceHelper.DispatchCmd(cmd, subcmd, ...)
    end)
    skynet.register(".agent_mgr")
end)
