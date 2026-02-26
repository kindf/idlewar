local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local PlayerBase = require "game.agent.player_base"
local Queue = require "skynet.queue"
local Timer = require "public.timer"
local CMD = ServiceHelper.CMD

local agentQueue = Queue()
local timer = Timer.New()
local playerDataInit = false

local function LoadPlayerData(account, uid)
    math.randomseed(os.time())
    -- 从数据库加载玩家数据
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", { account = account })
    if not ret then
        Logger.Error("加载玩家数据失败 account:%s err:%s", account, data)
        return false
    end
    assert(data.uid == uid, string.format("UID不匹配 account:%s, uid:%d, playerUid:%d", account, uid, data.uid))
    -- 更新最后登录时间
    data.lastLoginTime = os.time()
    Logger.Info("玩家登录 account:%s, uid:%d", account, data.uid)
    playerDataInit = true
    PlayerBase.Init(data)
    return true
end

local function OnLoadEnd(relogin)
end

function CMD.Start(account, uid)
    if not LoadPlayerData(account, uid) then
        return false
    end

    OnLoadEnd(false)
    return true
end

function CMD.Restart(account)
    OnLoadEnd(true)
end

-- 分发客户端消息
function CMD.DispatchClientMessage(...)
    if not playerDataInit then
        Logger.Error("尚未加载玩家数据")
        return
    end
    ServiceHelper.CMD.DispatchClientMessage(...)
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, command, ...)
        agentQueue(ServiceHelper.DispatchCmd, command, ...)
    end)
    -- 注册协议处理器
    ProtocolHelper.RegisterProtocol()
    Logger.Info("agent服务启动完成")
end)
