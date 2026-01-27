local skynet = require "skynet"
local timer = require "util.timer" 
local type2ActivityClass = require "gameworld.activity.activity_import"

-- 定义活动状态机状态
local ActivityState = {
    UNOPEN = 1,      -- 未开启
    OPEN = 2,          -- 开启中
    SETTLE = 3,      -- 结算中
    CLOSE = 4,        -- 已关闭
    --FORCE_CLOSE = 5 -- 强制关闭
}

-- 定义活动状态机事件
local ActivityEvent = {
    OPEN = "open",          -- 开启活动
    END = "end",            -- 结束活动
    CLOSE = "close",        -- 关闭活动
    FORCE_CLOSE = "force_close" -- 强制关闭活动
}

-- 活动状态转移表
local ActivityFsmTransition = {
    [ActivityState.UNOPEN] = {
        [ActivityEvent.OPEN] = ActivityState.OPEN
    },
    [ActivityState.OPEN] = {
        [ActivityEvent.END] = ActivityState.SETTLE,
        [ActivityEvent.FORCE_CLOSE] = ActivityState.FORCE_CLOSE
    },
    [ActivityState.SETTLE] = {
        [ActivityEvent.CLOSE] = ActivityState.CLOSE,
        [ActivityEvent.FORCE_CLOSE] = ActivityState.FORCE_CLOSE
    },
    [ActivityState.CLOSE] = {},
    [ActivityState.FORCE_CLOSE] = {}
}

local ActivityFsmEnterStateCallback = {
    [ActivityState.OPEN] = function(self) self:OnEnterOpen() end,
    [ActivityState.SETTLE] = function(self) self:OnEnterSettle() end,
    [ActivityState.CLOSE] = function(self) self:OnEnterClose() end,
    [ActivityState.FORCE_CLOSE] = function(self) self:OnEnterForceClose() end
}

local ActivityFsmExitStateCallback = {
    [ActivityState.UNOPEN] = function(self) self:OnExitUnopen() end,
    [ActivityState.OPEN] = function(self) self:OnExitOpen() end,
    [ActivityState.SETTLE] = function(self) self:OnExitSettle() end,
}

-- 活动状态机类
local ActivityFSM = class("ActivityFSM")

function ActivityFSM:Ctor(actId, actConf, mgr)
    self.actId = actId
    self.actConf = actConf
    self.mgr = mgr
    self.instance = nil
    self.timer = nil
    self.openTime, self.endTime = actConf.open:GetActivityTime()
    self.closeAfter = actConf.close_after or 0
    self.forceClose = false
    
    -- 初始化状态机
    self:InitFSM()
end

function ActivityFSM:InitFSM()
    self.fsm = {
        currentState = ActivityState.UNOPEN,
    }
end

-- 触发状态转换
function ActivityFSM:Trigger(event)
    local current = self.fsm.currentState
    local nextState = ActivityFsmTransition[current][event]
    
    if not nextState then
        LogWarning("Activity", "[ActivityFSM] Invalid transition from %s with event %s", current, event)
        return false
    end
    
    local onExit = ActivityFsmExitStateCallback[current]
    if onExit then onExit(self) end
    
    -- 更新状态
    self.fsm.currentState = nextState
    LogInfo("Activity", "[ActivityFSM] State changed: %s -> %s", current, nextState)
    
    -- 执行状态进入逻辑
    local onEnter = ActivityFsmEnterStateCallback[nextState]
    if onEnter then onEnter(self) end
    
    return true
end

-- 各状态进入/退出逻辑
function ActivityFSM:OnEnterUnopen()
    self:SetupTimer()
end

function ActivityFSM:OnExitUnopen()
    self:CancelTimer()
end

function ActivityFSM:OnEnterOpen()
    -- 检查是否有同类型活动正在开启
    local typeOpenActId = self.mgr:CheckRepeatedActivityType(self.actId)
    if typeOpenActId then
        LogWarning("Activity", "[ActivityFSM] OnEnterOpen cant open repeated type act. actId:%s, opening actId:%s", 
            self.actId, typeOpenActId)
        self:Trigger(ActivityEvent.FORCE_CLOSE)
        return
    end
    
    -- 创建活动实例
    if not self.instance then
        local actClass = type2ActivityClass[self.actConf.act_type]
        self.instance = actClass.new(self.actId, self.actConf.act_type)
        self.instance:LoadData()
        self.instance:LoadDataEnd()
    end
    
    -- 通知活动开启
    skynet.send(GetGlobalSvr(), "lua", "send2onlineall", "on_activity_open", self.actId)
    if self.instance.OnActivityOpen then
        self.instance:OnActivityOpen()
    end
    
    self:SetupTimer()
end

function ActivityFSM:OnExitOpen()
    self:CancelTimer()
end

function ActivityFSM:OnEnterSettle()
    -- 通知活动结束
    skynet.send(GetGlobalSvr(), "lua", "send2onlineall", "on_activity_end", self.actId)
    if self.instance and self.instance.OnActivityEnd then
        self.instance:OnActivityEnd()
    end
    
    self:SetupTimer()
end

function ActivityFSM:OnExitSettle()
    self:CancelTimer()
end

function ActivityFSM:OnEnterClose()
    -- 通知活动关闭
    skynet.send(GetGlobalSvr(), "lua", "send2onlineall", "on_activity_close", self.actId)
    if self.instance and self.instance.OnActivityClose then
        self.instance:OnActivityClose()
    end
end

function ActivityFSM:OnEnterForceClose()
    self.forceClose = true
    -- 通知活动强制关闭
    skynet.send(GetGlobalSvr(), "lua", "send2onlineall", "on_activity_force_close", self.actId)
    if self.instance and self.instance.OnActivityForceClose then
        self.instance:OnActivityForceClose()
    end
end

-- 定时器管理
function ActivityFSM:CancelTimer()
    if self.timer then
        self.mgr.timerInstance:Cancel(self.timer)
        self.timer = nil
    end
end

function ActivityFSM:SetupTimer()
    self:CancelTimer()
    
    local now = os.time()
    local timeToEvent = 0
    local nextEvent = nil
    
    if self.fsm.currentState == ActivityState.UNOPEN then
        timeToEvent = self.openTime - now
        nextEvent = ActivityEvent.OPEN
    elseif self.fsm.currentState == ActivityState.OPEN then
        timeToEvent = self.endTime - now
        nextEvent = self.closeAfter > 0 and ActivityEvent.END or ActivityEvent.CLOSE
    elseif self.fsm.currentState == ActivityState.SETTLE then
        timeToEvent = (self.endTime + self.closeAfter) - now
        nextEvent = ActivityEvent.CLOSE
    end

    if not nextEvent then
        return
    end

    local function timeOutFunc()
        GlobalQueue(function() 
                if self:Trigger(nextEvent) then
                    self.mgr:SaveActivityState()
                end
            end)
    end

    if timeToEvent > 0 then
        self.timer = self.mgr.timerInstance:Timeout(timeToEvent * 100, timeOutFunc)
    else
        timeOutFunc()
    end
end

-- 保存活动数据
function ActivityFSM:Save()
    if self.instance and self.instance.OnSave then
        local ok, error = skynet.pcall(self.instance.OnSave, self.instance)
        if not ok then
            LogError("Activity", "[ActivityFSM] Save error. actId:%s, error:%s", self.actId, error)
        end
    end
end

-- 获取当前状态
function ActivityFSM:GetState()
    return self.fsm.currentState
end

-- 重新加载配置
function ActivityFSM:ReloadConfig(actConf)
    local oldOpenTime, oldEndTime = self.openTime, self.endTime
    local oldCloseAfter = self.closeAfter
    
    self.actConf = actConf
    self.openTime, self.endTime = actConf.open:GetActivityTime()
    self.closeAfter = actConf.close_after or 0
    
    -- 如果时间配置有变化，重新设置定时器
    if oldOpenTime ~= self.openTime or oldEndTime ~= self.endTime or oldCloseAfter ~= self.closeAfter then
        self:SetupTimer()
    end
end

local function CalcActivityState(now, openTime, endTime, closeAfter)
    if now < openTime then
        return GameDefine.ActivityDefine.ActivityUnopenState
    elseif now < endTime then
        return GameDefine.ActivityDefine.ActivityOpenState
    elseif now < endTime + closeAfter then
        return GameDefine.ActivityDefine.ActivitySettleState
    else
        return GameDefine.ActivityDefine.ActivityCloseState
    end
end

-- 恢复状态
if skynet.getenv("activityreopen") == "true" then
    -- 测试模式下的恢复逻辑
    function ActivityFSM:RecoverState(oldData, actConf)
        local oldActData = oldData[self.actId]
        local now = os.time()
        self.openCond = GameDefine.ActivityDefine.ActivityAllowOpenState
        local openTime, endTime = actConf.open:GetActivityTime()
        local closeAfter = actConf.close_after or 0
        local newState = CalcActivityState(now, openTime, endTime, closeAfter)
        -- 状态回退 直接设置成未开启
        if newState < oldAct.state then
            oldAct.state = GameDefine.ActivityDefine.ActivityUnopenState
        end
        self:SetupTimer()
    end
else
    -- 正常模式下的恢复逻辑
    function ActivityFSM:RecoverState(oldData, actConf)
        local oldActData = oldData[self.actId]
        local now = os.time()
        self.openCond = GameDefine.ActivityDefine.ActivityAllowOpenState
        local openTime, endTime = actConf.open:GetActivityTime()
        local closeAfter = actConf.close_after or 0
        local newState = CalcActivityState(now, openTime, endTime, closeAfter)
        -- 状态回退 直接设置成未开启
        if newState < oldAct.state then
            self:Trigger(ActivityEvent.FORCE_CLOSE)
            return
        end
        self:SetupTimer()
    end
end

local ActivityMgr = class("ActivityMgr")

function ActivityMgr:Ctor()
    self.activityFSMs = {}  -- 替换原来的activities和instances
    self.timerInstance = timer.new()
end

-- 检查活动配置
function ActivityMgr:CheckActivityConfig()
end

-- 检查活动类
function ActivityMgr:CheckActivityClass()
end

-- 从数据库加载活动状态
function ActivityMgr:LoadActivity()
    return true, nil
end

-- 初始化活动管理器
function ActivityMgr:Init()
    self:CheckActivityConfig()
    self:CheckActivityClass()
    local ret, loadData = self:LoadActivity()
    assert(ret, "ActivityMgr load data error.")
    self:InitInstances(loadData or {})
    self.timerInstance:Interval(GameDefine.ActivityDefine.ActivityStateSaveInterval, function() GlobalQueue(self.SaveActivity, self) end, false)
end

-- 初始化活动实例
function ActivityMgr:InitInstances(loadData)
    for _, actConf in pairs(Data.__sortActivityOpen) do
        local actId = actConf.id
        local oldData = loadData[actId] or {}
        
        -- 创建活动状态机
        local fsm = ActivityFSM.new(actId, actConf, self)
        self.activityFSMs[actId] = fsm
        
        fsm:RecoverState(oldData, actConf)
    end
end

-- 检查是否有重复类型的活动
function ActivityMgr:CheckRepeatedActivityType(actId)
    local conf = Data.activityopen
    local selfType = conf[actId].act_type
    
    for id, fsm in pairs(self.activityFSMs) do
        local state = fsm:GetState()
        if (state == ActivityState.OPEN or state == ActivityState.SETTLE) and
           conf[id].act_type == selfType and
           id ~= actId then
            return id
        end
    end
    return nil
end

-- 重新加载配置
function ActivityMgr:ReloadConfig()
    self:CheckActivityConfig()
    
    for _, actConf in pairs(Data.__sortActivityOpen) do
        local actId = actConf.id
        local fsm = self.activityFSMs[actId]
        
        if not fsm then
            -- 新增活动
            fsm = ActivityFSM.new(actId, actConf, self)
            self.activityFSMs[actId] = fsm
        else
            -- 更新现有活动配置
            fsm:ReloadConfig(actConf)
        end
    end
end

-- 保存活动状态
function ActivityMgr:SaveActivityState()
    local saveData = {}
    for actId, fsm in pairs(self.activityFSMs) do
        saveData[actId] = {
            state = fsm:GetState(),
            forceClose = fsm.forceClose
        }
    end
    
    local ret, err = skynet.call(GetDBSvr(), "lua", "save_global", "activitydata", "activityopenstate", saveData)
    if not ret then
        LogError("Activity", "[ActivityMgr]SaveActivityState CallDB back. error:%s", tostring(err))
    end
end

-- 批量保存活动数据
function ActivityMgr:SaveActivity()
    self:SaveActivityState()
    
    local function SaveBatchCallback(succ, msg)
        if succ then
            LogInfo("Activity", "[ActivityMgr] save all activity succ.")
        else
            LogError("Activity", "[ActivityMgr]batch save failed. error:%s", msg)
        end
    end
    
    local instances = {}
    for actId, fsm in pairs(self.activityFSMs) do
        instances[actId] = fsm
    end
    
    local ok, error = gBatchMgr:CreateTask("ActivityMgr.SaveActivity", 100, 200, instances,
        function(actId) GlobalQueue(self.OnSave, self, actId) end, SaveBatchCallback)
    if not ok then
        LogError("Activity", "[ActivityMgr]batch CreateTask failed. error:%s", error)
    end
end

function ActivityMgr:OnSave(actId)
    local fsm = self.activityFSMs[actId]
    if not fsm then
        LogWarning("Activity", "[ActivityMgr] OnSave cant find FSM. actId:%s", actId)
        return
    end
    fsm:Save()
end

-- 关闭服务器
function ActivityMgr:CloseSvr()
    self:SaveActivityState()
    
    -- 取消所有定时器
    for actId, fsm in pairs(self.activityFSMs) do
        fsm:CancelTimer()
        fsm:Save()
    end
end

gActivityMgr = gActivityMgr or ActivityMgr.new()