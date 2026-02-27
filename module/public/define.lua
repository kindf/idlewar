local Define = {}

-- agent 状态
Define.AGENT_STATE = {
    ONLINE_AGENT_STATE = 1,  -- 在线
    OFFLINE_AGENT_STATE = 2, -- 离线
}

Define.AGENT_SAVE_INTERVAL = 10

Define.CONNECTION_STATUS = {
    INIT = 1,              -- 初始
    VERSION_CHECKED = 2,   -- 版本已验证
    LOGINING = 3,          -- 登录中
    AUTHED = 4,            -- 已认证
    GAMING = 5,            -- 游戏中
    WAITING_RECONNECT = 6, -- 等待重连
    CLOSED = 7,            -- 已关闭
}

Define.CONN_STATE = {
    INIT              = 1, -- 初始连接
    VERSION_CHECKED   = 2, -- 版本已验证
    LOGINING          = 3, -- 登录中
    AUTHED            = 4, -- 已认证
    GAMING            = 5, -- 游戏中
    WAITING_RECONNECT = 6, -- 等待重连
    CLOSED            = 7, -- 已关闭
}

Define.CONNECTION_RECONNECT_WINDOW = 60 -- 重连窗口（秒）
Define.TOKEN_EXPIRE_TIME = 300          -- Token过期时间（秒）
Define.HEARTBEAT_TIMEOUT = 30           -- 心跳超时（秒）
Define.SESSION_CLEANUP_INTERVAL = 300   -- Session清理间隔（秒）

Define.TOKEN_EXPIRE_TIME = 300          -- Token过期时间（秒）
Define.SESSION_TIMEOUT = 600            -- Session超时时间（秒）

Define.AGENT_STATE = {
    LOADING      = 1, -- 数据加载中
    ONLINE       = 2, -- 在线
    GAMING       = 3, -- 游戏中
    RECONNECTING = 4, -- 重连中
    FROZEN       = 5, -- 冻结
    OFFLINE      = 6, -- 离线
    CLEANUP      = 7, -- 清理中
}

Define.AGENT_CLEANUP_DELAY = 500    -- 清理延迟（毫秒）
Define.MAX_RECONNECT_ATTEMPTS = 3   -- 最大重连次数
Define.AGENT_CONNECT_TIMEOUT = 3000 -- Agent连接超时（毫秒）

return Define
