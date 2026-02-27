local DEFINE = require "public.define"
local Logger = require "public.logger"
local CONNECTION_STATUS = DEFINE.CONNECTION_STATUS

-- 状态机：定义各状态允许的操作和转换
local STATE_MACHINE = {
    [CONNECTION_STATUS.CONNECTED] = {
        allowedNext = {
            [CONNECTION_STATUS.VERSION_CHECKED] = true,
            [CONNECTION_STATUS.CLOSED] = true
        },
        allowedOperations = { "check_version" },
        onEnter = function(session)
            Logger.Debug("Session[%s] entered CONNECTED", session:GetId())
        end,
        onExit = function(session)
            Logger.Debug("Session[%s] exited CONNECTED", session:GetId())
        end
    },
    [CONNECTION_STATUS.VERSION_CHECKED] = {
        allowedNext = {
            [CONNECTION_STATUS.LOGINING] = true,
            [CONNECTION_STATUS.CLOSED] = true
        },
        allowedOperations = { "auth" },
        onEnter = function(session)
            session:UpdateActiveTime()
            Logger.Debug("Session[%s] version checked", session:GetId())
        end
    },
    [CONNECTION_STATUS.LOGINING] = {
        allowedNext = {
            [CONNECTION_STATUS.VERSION_CHECKED] = true,
            [CONNECTION_STATUS.AUTHED] = true,
            [CONNECTION_STATUS.CLOSED] = true
        },
        allowedOperations = {},
        timeout = 30, -- 登录状态超时30秒
        onEnter = function(session)
            session:UpdateActiveTime()
        end
    },
    [CONNECTION_STATUS.AUTHED] = {
        allowedNext = {
            [CONNECTION_STATUS.GAMING] = true,
            [CONNECTION_STATUS.CLOSED] = true
        },
        allowedOperations = { "enter_game" },
        onEnter = function(session)
            session:UpdateActiveTime()
            Logger.Info("Session[%s] authenticated for account:%s",
                session:GetId(), session:GetAccount())
        end
    },
    [CONNECTION_STATUS.GAMING] = {
        allowedNext = {
            [CONNECTION_STATUS.CLOSED] = true
        },
        allowedOperations = { "game_message" },
        onEnter = function(session)
            session:UpdateActiveTime()
            Logger.Info("Session[%s] entered gaming for uid:%s",
                session:GetId(), session:GetUid())
        end
    },
    [CONNECTION_STATUS.CLOSED] = {
        allowedNext = {},
        allowedOperations = {},
        onEnter = function(session, reason)
            Logger.Info("Session[%s] closed, reason:%s", session:GetId(), reason or "unknown")
        end
    }
}

return STATE_MACHINE
