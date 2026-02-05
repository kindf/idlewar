local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local AgentMgr = require "game.agentmgr.agent_mgr"
local ProtocolHelper = require "public.protocol_helper"
local Pids = require "proto.pids"
local CMD = ServiceHelper.CMD
local Logger = require "public.logger"

CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

function CMD.start()
    ProtocolHelper.RegisterProtocol()
    AgentMgr.Init()
end

--登录认证
local function C2SLoginGame(req, resp)
    local account = req.account
    local loginToken = req.loginToken
    resp.retCode = AgentMgr.LoginGame(account, loginToken)
    Logger.Debug("C2SLoginGame account:%s retCode:%s", account, resp.retCode)
end
ProtocolHelper.RegisterRpcHandler(Pids["player_base.c2s_login_game"], Pids["player_base.s2c_login_game"], C2SLoginGame)

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        ServiceHelper.DispatchCmd(cmd, subcmd, ...)
    end)
    skynet.register(".agent_mgr")
end)
