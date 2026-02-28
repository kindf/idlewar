local ServiceHelper = require "public.service_helper"
local Logger = require "public.logger"
local CMD = ServiceHelper.CMD

function CMD.OnLogout()
    Logger.Info("PlayerBase:OnLogout")
end

local PlayerBase = {}
local playerData

function PlayerBase.Init(data)
    playerData = data
end

function PlayerBase.GetPlayerData()
    return playerData
end

function PlayerBase.GetUid()
    local data = PlayerBase.GetPlayerData()
    return data.uid
end

function PlayerBase.GetAccount()
    local data = PlayerBase.GetPlayerData()
    return data.account
end

return PlayerBase
