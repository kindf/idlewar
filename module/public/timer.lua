local skynet = require "skynet"
local Logger = require "public.logger"
require "public.class"

local Timer = {}

function Timer.New()
    local o = {}
    o.count = 0
    o.timers = {}
    setmetatable(o, {__index = Timer})
    return o
end

-- 生成唯一定时器ID
function Timer:GenId()
    self.count = self.count + 1
    return self.count
end

-- 清除指定定时器
function Timer:Clear(timerId)
    if self.timers[timerId] then
        self.timers[timerId] = nil
    end
end

-- 设置一次性定时器
-- @param delay 延迟时间(单位: 秒)
-- @param callback 回调函数
-- @return timerId 定时器ID
function Timer:Timeout(delay, callback)
    local timerId = self:GenId()
    local function wrapper()
        if self.timers[timerId] then
            self.timers[timerId] = nil
            callback()
        end
    end
    self.timers[timerId] = skynet.timeout(delay * 100, wrapper)
    return timerId
end

-- 设置间隔定时器
-- @param interval 间隔时间(单位: 秒)
-- @param callback 回调函数
-- @param immediate 是否立即执行第一次
-- @return timerId 定时器ID
function Timer:Interval(interval, callback, immediate)
    local timerId = self:GenId()
    local function wrapper()
        local ok, err = pcall(callback)
        if not ok then
            Logger.Error("Timer callback error:%s", err)
        end
        -- 重新设置定时器
        -- self.timers[timerId] = skynet.timeout(interval, wrapper)
        self.timers[timerId] = skynet.timeout(interval * 100, function()
            if not self.timers[timerId] then return end
            wrapper()
        end)
    end
    if immediate then
        skynet.fork(wrapper)
    else
        self.timers[timerId] = skynet.timeout(interval * 100, function()
            if not self.timers[timerId] then return end
            wrapper()
        end)
    end
    return timerId
end

-- 取消定时器
function Timer:Cancel(timerId)
    self:Clear(timerId)
end

-- 清除所有定时器
function Timer:ClearAll()
    for id, _ in pairs(self.timers) do
        self:Clear(id)
    end
end

-- 析构函数
function Timer:Destroy()
    self:ClearAll()
end

return Timer
