local DEFINE = require("public.define")
local Logger = require("public.logger")

-- 连接状态常量
local CONN_STATE = DEFINE.CONN_STATE
-- 状态转换规则
local STATE_TRANSITIONS = {
    [CONN_STATE.INIT] = {
        next = {
            [CONN_STATE.VERSION_CHECKED] = true,
            [CONN_STATE.CLOSED] = true
        },
        onEnter = function(session)
            Logger.Debug("Session[%s] entered INIT", session:GetId())
        end
    },
    [CONN_STATE.VERSION_CHECKED] = {
        next = {
            [CONN_STATE.LOGINING] = true,
            [CONN_STATE.CLOSED] = true
        },
        onEnter = function(session)
            session:UpdateActiveTime()
            Logger.Debug("Session[%s] version checked", session:GetId())
        end
    },
    [CONN_STATE.LOGINING] = {
        next = {
            [CONN_STATE.VERSION_CHECKED] = true,
            [CONN_STATE.AUTHED] = true,
            [CONN_STATE.CLOSED] = true
        },
        timeout = 30,
        onEnter = function(session)
            session:UpdateActiveTime()
        end
    },
    [CONN_STATE.AUTHED] = {
        next = {
            [CONN_STATE.GAMING] = true,
            [CONN_STATE.WAITING_RECONNECT] = true,
            [CONN_STATE.CLOSED] = true
        },
        onEnter = function(session)
            session:UpdateActiveTime()
            Logger.Info("Session[%s] authed for account:%s",
                session:GetId(), session.account or "nil")
        end
    },
    [CONN_STATE.GAMING] = {
        next = {
            [CONN_STATE.WAITING_RECONNECT] = true,
            [CONN_STATE.CLOSED] = true
        },
        onEnter = function(session)
            session:UpdateActiveTime()
            Logger.Info("Session[%s] gaming for uid:%s",
                session:GetId(), session.uid or "nil")
        end
    },
    [CONN_STATE.WAITING_RECONNECT] = {
        next = {
            [CONN_STATE.GAMING] = true,
            [CONN_STATE.CLOSED] = true
        },
        timeout = DEFINE.CONNECTION_RECONNECT_WINDOW,
        onEnter = function(session, reason)
            session:UpdateActiveTime()
            Logger.Info("Session[%s] waiting reconnect, reason:%s",
                session:GetId(), reason or "unknown")
        end
    },
}

return STATE_TRANSITIONS
