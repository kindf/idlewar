local Define = {}

-- agent 状态
Define.AGENT_STATE = {
    ONLINE_AGENT_STATE = 1,  -- 在线
    OFFLINE_AGENT_STATE = 2, -- 离线
}

Define.AGENT_SAVE_INTERVAL = 10

Define.CONNECTION_STATUS = {
    CONNECTED = 1,
    VERSION_CHECKED = 2,
    LOGINING = 3,
    AUTHED = 4,
    GAMING = 5,
    CLOSED = 6,
}

Define.TOKEN_EXPIRE_TIME = 300 -- Token过期时间（秒）
Define.SESSION_TIMEOUT = 600   -- Session超时时间（秒）

return Define
