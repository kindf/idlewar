local skynet = require "skynet"
local cluster = require "skynet.cluster"
local RetCode = require "proto.retcode"
local AgentMgr = {}

local acc2Agent = {}
local uid2Agent = {}
function AgentMgr.Init()
end

function AgentMgr.LoginGame(account, loginToken)
    local loginSucc = cluster.call(".loginnode", ".login", "CheckAccountLoginSucc", account, loginToken)
    if not loginSucc then
        return RetCode.ACCOUNT_NOT_LOGIN
    end

    local agent = acc2Agent[account]
    if not agent then
        agent = skynet.newservice("agent", account)
        acc2Agent[account] = agent
        skynet.call(agent, "lua", "start")
    else
        skynet.call(agent, "lua", "restart")
    end

    return RetCode.SUCCESS
end

return AgentMgr
