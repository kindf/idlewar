local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local PlayerBase = require "game.agent.player_base"
local Queue = require "skynet.queue"
local CMD = ServiceHelper.CMD
CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

local function OnEnterWorld(isRelogin)
end

function CMD.Start(account)
    math.randomseed(os.time())
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", {account = account})
    if not ret then
        Logger.Error("加载数据失败 account:%s err:%s", account, data)
        return
    end
    if not data then
        data = {
            account = account,
            uid = skynet.call(".guid", "lua", "GenId", "userdata"),
        }
    end
    ProtocolHelper.RegisterProtocol()
    PlayerBase.Init(data)
    OnEnterWorld(false)
    return data.uid
end

function CMD.Restart(account)
    local data = PlayerBase.GetPlayerData()
    assert(data.account == account, "account不匹配")
    OnEnterWorld(true)
    return data.uid
end

function CMD.Destroy()
end

local agentQueue = Queue()
skynet.start(function()
    skynet.dispatch("lua", function(_,_, command, ...)
        agentQueue(ServiceHelper.DispatchCmd(command, ...))
    end)
end)
