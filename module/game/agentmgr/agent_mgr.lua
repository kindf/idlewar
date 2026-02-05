local skynet = require "skynet"
local cluster = require "skynet.cluster"
local RetCode = require "proto.retcode"
local AgentMgr = {}

local acc2Agent = {}
local uid2Agent = {}
function AgentMgr.Init()
end

function AgentMgr.LoginGame(account, loginToken)
    local loginSucc = cluster.call("loginnode", ".login", "CheckAccountLoginSucc", account, loginToken)
    if not loginSucc then
        return RetCode.ACCOUNT_NOT_LOGIN
    end
    local agent = acc2Agent[account]
    local uid
    if not agent then
        agent = skynet.newservice("agent", account)
        acc2Agent[account] = agent
        uid = skynet.call(agent, "lua", "Start", account)
    else
        uid = skynet.call(agent, "lua", "Restart", account)
    end
    uid2Agent[uid] = agent
    return RetCode.SUCCESS
end

return AgentMgr
