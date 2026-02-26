local RetCode = {}

RetCode.SUCCESS = 1 -- 成功
RetCode.FAILED = 2 -- 失败

RetCode.PROTO_DECODE_ERROR = 101 -- 协议解析错误
RetCode.SYSTEM_ERROR = 102 -- 系统错误
RetCode.MONGODB_OPERATE_ERROR = 103 -- mongodb操作失败

-- 登录相关
RetCode.ACCOUNT_NOT_LOGIN = 201 -- 账号未登录
RetCode.CREATE_AGENT_ERROR = 202 -- 创建agent失败
RetCode.RESTART_AGENT_ERROR = 203 -- 重启agent失败
RetCode.INVALID_TOKEN = 204 -- 无效token
RetCode.ACCOUNT_NOT_EXIST = 205 -- 账号不存在
RetCode.ACCOUNT_CREATE_REPEATED = 206 -- 账号创建重复
RetCode.VERSION_NOT_CHECKED = 207 -- 版本未检测
RetCode.CHECK_VERSION_FAILED = 208 -- 版本检测失败
RetCode.GEN_UID_ERROR = 209 -- 生成uid失败

return RetCode
