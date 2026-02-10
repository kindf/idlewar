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
local clientFd = nil

local function LoadPlayerData(account)
    math.randomseed(os.time())
    -- 从数据库加载玩家数据
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", { account = account })
    if not ret then
        Logger.Error("加载玩家数据失败 account:%s err:%s", account, data)
        return false
    end

    -- 如果没有数据，创建新玩家
    if not data then
        data = {
            account = account,
            uid = skynet.call(".guid", "lua", "GenUid", "userdata"),
            createTime = os.time(),
            lastLoginTime = os.time(),
            lastLogoutTime = 0,
        }

        -- 插入新玩家数据
        local insertRet = skynet.call(".mongodb", "lua", "Insert", "userdata", data)
        if not insertRet then
            Logger.Error("创建玩家数据失败 account:%s", account)
            return false
        end

        Logger.Info("创建新玩家 account:%s, uid:%d", account, data.uid)
    else
        -- 更新最后登录时间
        data.lastLoginTime = os.time()
        Logger.Info("玩家登录 account:%s, uid:%d", account, data.uid)
    end
    playerDataInit = true
    PlayerBase.Init(data)
    return true, data.uid
end

function CMD.Start(fd, account)
    clientFd = fd
    return LoadPlayerData(account)
end

-- 分发客户端消息
function CMD.DispatchClientMessage(...)
    if not playerDataInit then
        Logger.Error("尚未加载玩家数据")
        return
    end
    ServiceHelper.DispatchClientMessage(...)
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, command, ...)
        agentQueue(ServiceHelper.DispatchCmd, command, ...)
    end)
    -- 注册协议处理器
    ProtocolHelper.RegisterProtocol()
    Logger.Info("agent服务启动完成")
end)
