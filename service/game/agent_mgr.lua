local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local AgentMgr = require "game.agent_mgr"
local ProtocolHelper = require "public.protocol_helper"
local Pids = require "proto.pids"
local RetCode = require "proto.retcode"

local CMD = {}
CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

function CMD.start()
    AgentMgr.Init()
end

--登录认证
local function C2SLoginGame(req, resp)
    local account = req.account
    local loginToken = req.loginToken
    resp.retCode = AgentMgr.LoginGame(account, loginToken)
end
ProtocolHelper.RegisterRpcHandler(Pids["player_base.c2s_login_game"], Pids["player_base.s2c_login_game"], C2SLoginGame)

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
end)
