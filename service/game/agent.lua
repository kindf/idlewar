local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local PlayerBase = require "game.agent.player_base"
local ClusterHelper = require "public.cluster_helper"
local Queue = require "skynet.queue"
local Timer = require "public.timer"
local Pids = require "proto.pids"
local CMD = ServiceHelper.CMD
CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

-- 玩家数据
local playerData = nil
local playerInit = false
local agentQueue = Queue()
local timer = timer or Timer.New()
local fd = nil
local connectionInfo = nil
local heartbeatTimerId = nil
local lastHeartbeatTime = os.time()

-- 发送消息给客户端
function CMD.SendClientMessage(protoName, msg)
    if not fd or not playerData then
        return false
    end

    local protoId = Pids[protoName]
    if not protoId then
        Logger.Error("协议不存在:%s", protoName)
        return false
    end

    local ok, err = ClusterHelper.SendClientMessage(fd, protoId, msg)
    if not ok then
        Logger.Error("发送消息失败 proto:%s, err:%s", protoName, err)
        return false
    end

    return true
end

-- 玩家进入世界
local function OnEnterWorld(isRelogin)
    if not playerData then
        Logger.Error("玩家数据为空，无法进入世界")
        return false
    end

    Logger.Info("玩家进入世界 account:%s, uid:%d, isRelogin:%s", playerData.account, playerData.uid, tostring(isRelogin))

    -- 设置心跳定时器
    heartbeatTimerId = timer:Interval(60, function()
        if playerData then
            -- 保存玩家数据
            local ok, err = pcall(PlayerBase.SavePlayerData, playerData)
            if not ok then
                Logger.Error("保存玩家数据失败 uid:%d, err:%s", playerData.uid, err)
            end

            -- 更新最后活跃时间
            playerData.lastActiveTime = os.time()

            -- 检查心跳超时（5分钟）
            if os.time() - lastHeartbeatTime > 300 then
                Logger.Warning("玩家心跳超时，准备登出 uid:%d", playerData.uid)
                CMD.Destroy("心跳超时")
            end
        end
    end, false)

    -- 发送登录成功消息给客户端
    if fd then
        ClusterHelper.SendClientMessage(fd, Pids["player_base.s2c_login_game"], {
            retCode = 0,
            uid = playerData.uid,
            account = playerData.account,
            serverTime = os.time(),
            lastLoginTime = playerData.lastLoginTime or os.time()
        })

        -- 发送欢迎消息
        skynet.timeout(100, function()
            if fd and playerData then
                ClusterHelper.SendClientMessage(fd, Pids["player_base.s2c_system_message"], {
                    message = isRelogin and "重新连接成功！" or "欢迎来到游戏世界！",
                    type = 1,
                    timestamp = os.time()
                })
            end
        end)
    end

    -- 新玩家初始化
    if not isRelogin then
        Logger.Info("新玩家初始化 account:%s, uid:%d", playerData.account, playerData.uid)

        -- 初始化玩家基础数据
        PlayerBase.InitNewPlayer(playerData)
    else
        Logger.Info("玩家重连 account:%s, uid:%d", playerData.account, playerData.uid)
    end

    return true
end

-- 启动agent
function CMD.Start(account)
    math.randomseed(os.time())
    -- 从数据库加载玩家数据
    local ret, data = skynet.call(".mongodb", "lua", "FindOne", "userdata", { account = account })
    if not ret then
        Logger.Error("加载玩家数据失败 account:%s err:%s", account, data)
        return nil
    end

    -- 如果没有数据，创建新玩家
    if not data then
        data = {
            account = account,
            uid = skynet.call(".guid", "lua", "GenUid", "userdata"),
            createTime = os.time(),
            lastLoginTime = os.time(),
            lastLogoutTime = 0,
            lastActiveTime = os.time(),
            lastSaveTime = os.time()
        }

        -- 插入新玩家数据
        local insertRet = skynet.call(".mongodb", "lua", "Insert", "userdata", data)
        if not insertRet then
            Logger.Error("创建玩家数据失败 account:%s", account)
            return nil
        end

        Logger.Info("创建新玩家 account:%s, uid:%d", account, data.uid)
    else
        -- 更新最后登录时间
        data.lastLoginTime = os.time()
        data.lastActiveTime = os.time()

        local updateRet = skynet.call(".mongodb", "lua", "Update", "userdata",
            { account = account },
            {
                ["$set"] = {
                    lastLoginTime = data.lastLoginTime,
                    lastActiveTime = data.lastActiveTime
                }
            },
            false, false)

        if not updateRet then
            Logger.Warning("更新登录时间失败 account:%s", account)
        end

        Logger.Info("玩家登录 account:%s, uid:%d", account, data.uid)
    end

    -- 注册协议处理器
    ProtocolHelper.RegisterProtocol()

    -- 初始化玩家数据
    playerInit = true
    playerData = data
    PlayerBase.Init(playerData)

    -- 进入世界
    OnEnterWorld(false)

    return data.uid
end

-- 重新启动agent（重连）
function CMD.Restart(account)
    if not playerData or playerData.account ~= account then
        Logger.Error("重连失败，账号不匹配 account:%s", account)
        return nil
    end

    Logger.Info("玩家重连 account:%s, uid:%d", account, playerData.uid)

    -- 清理旧的定时器
    if timer then
        timer:Destroy()
        timer = nil
    end

    -- 重置心跳时间
    lastHeartbeatTime = os.time()

    -- 更新最后登录时间
    playerData.lastLoginTime = os.time()
    playerData.lastActiveTime = os.time()

    local updateRet = skynet.call(".mongodb", "lua", "Update", "userdata",
        { account = account },
        {
            ["$set"] = {
                lastLoginTime = playerData.lastLoginTime,
                lastActiveTime = playerData.lastActiveTime
            }
        },
        false, false)

    if not updateRet then
        Logger.Warning("更新重连时间失败 account:%s", account)
    end

    -- 进入世界（重连）
    OnEnterWorld(true)
    return playerData.uid
end

-- 销毁agent
function CMD.Destroy(reason)
    Logger.Info("销毁agent account:%s, uid:%d, reason:%s",
        playerData and playerData.account or "unknown",
        playerData and playerData.uid or 0,
        reason or "正常退出")

    -- 清理定时器
    if timer then
        timer:Destroy()
        timer = nil
    end

    -- 保存玩家数据
    if playerData then
        playerData.lastLogoutTime = os.time()
        playerData.lastActiveTime = os.time()

        local ok, err = pcall(PlayerBase.SavePlayerData, playerData)
        if not ok then
            Logger.Error("保存玩家数据失败 uid:%d, err:%s", playerData.uid, err)
        end

        -- 更新数据库
        skynet.call(".mongodb", "lua", "Update", "userdata",
            { account = playerData.account },
            {
                ["$set"] = {
                    lastLogoutTime = playerData.lastLogoutTime,
                    lastActiveTime = playerData.lastActiveTime
                }
            },
            false, false)

        -- 通知agent_mgr玩家登出
        skynet.call(".agent_mgr", "lua", "Logout", playerData.account, playerData.uid, reason)
    end

    -- 清理数据
    playerData = nil
    playerInit = false
    fd = nil
    connectionInfo = nil
    heartbeatTimerId = nil

    return true
end

-- 设置连接信息
function CMD.SetConnectionInfo(info)
    connectionInfo = info
    if info then
        fd = info.fd
        -- 更新心跳时间
        lastHeartbeatTime = os.time()
    end
    Logger.Debug("设置连接信息 fd:%s", fd)
end

-- 获取玩家数据
function CMD.GetPlayerData()
    if not playerInit or not playerData then
        return nil
    end
    return PlayerBase.GetPlayerData()
end

-- 发送系统消息
function CMD.SendSystemMessage(message, msgType)
    if not fd or not playerData then
        return false
    end

    msgType = msgType or 1

    return CMD.SendClientMessage("player_base.s2c_system_message", {
        message = message,
        type = msgType,
        timestamp = os.time()
    })
end

-- 踢出玩家
function CMD.Kick(reason)
    if fd then
        -- 发送踢出消息
        CMD.SendClientMessage("player_base.s2c_kick", {
            reason = reason or "系统踢出",
            timestamp = os.time()
        })

        -- 延迟关闭连接
        skynet.timeout(100, function()
            if fd then
                skynet.call("gatenode", "lua", "kick_fd", fd, reason or "系统踢出")
            end
        end)
    end

    -- 销毁agent
    return CMD.Destroy(reason or "被踢出")
end

-- 处理客户端消息
function CMD.HandleClientMessage(protoId, protoBody)
    if not playerInit or not playerData then
        return false
    end

    -- 更新活跃时间
    playerData.lastActiveTime = os.time()
    lastHeartbeatTime = os.time()

    -- 交给ServiceHelper处理
    ServiceHelper.DispatchClientMessage(fd, protoId, protoBody)

    return true
end

-- 获取连接信息
function CMD.GetConnectionInfo()
    return connectionInfo
end

-- 检查是否在线
function CMD.IsOnline()
    return playerInit and playerData and fd ~= nil
end

-- 获取UID
function CMD.GetUid()
    return playerData and playerData.uid or 0
end

-- 获取账号
function CMD.GetAccount()
    return playerData and playerData.account or ""
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, command, ...)
        agentQueue(ServiceHelper.DispatchCmd, command, ...)
    end)

    Logger.Info("agent服务启动完成")
end)
