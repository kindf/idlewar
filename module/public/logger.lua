local skynet = require "skynet"
local Logger = {}
local sformat = string.format

function Logger.Debug(...)
    skynet.error(sformat(...))
end

function Logger.Info(...)
    skynet.error(sformat(...))
end

function Logger.Warning(...)
    skynet.error(sformat(...))
end

function Logger.Error(...)
    skynet.error(sformat(...))
    skynet.error(debug.traceback())
end

return Logger
