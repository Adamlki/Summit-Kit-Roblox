local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

--// SERVICES
local Players           = game:GetService("Players")
local MessagingService  = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local TextService       = game:GetService("TextService")
 
--// LOAD JEKY TITLE
local JekyTitle = require(
ServerStorage:WaitForChild("JekyModules"):WaitForChild("JekyTitle")
)
 
--// AUTO CREATE REMOTE
local ChatRemote = ReplicatedStorage:FindFirstChild("SummitChatEvent")
if not ChatRemote then
    ChatRemote = Instance.new("RemoteEvent")
    ChatRemote.Name = "SummitChatEvent"
    ChatRemote.Parent = ReplicatedStorage
end
 
--// CONFIG
local TOPIC  = "SummitGlobalChat"
local SYMBOL = ""
 
local EXCLUDED_ROLES = { Streamer = true, Community = true }
 
local SPECIAL_JOIN = {
["BukanYgDiaPilih"] = "Server information : Mas Dams [KINK] has joined the server"
}
 
--==================================================
-- TEXT FILTER FUNCTION (WAJIB ROBLOX)
--==================================================
local function filterMessage(fromPlayer, message)
    local success, result = pcall(function()
        local filter = TextService:FilterStringAsync(message, fromPlayer.UserId)
        return filter:GetNonChatStringForBroadcastAsync()
    end)
 
    if success then
        return result
    else
        dWarn("Filter failed:", result)
        return nil
    end
end
 
--==================================================
local function isEligibleRole(roleName)
    if not roleName then return false end
    return not EXCLUDED_ROLES[roleName]
end
 
local function buildJoinMessage(player)
    if SPECIAL_JOIN[player.Name] then
        return SPECIAL_JOIN[player.Name]
    end
    
    local role = JekyTitle.GetRoleTitle(player)
    if not role or not isEligibleRole(role) then return nil end
    
    local displayText = JekyTitle.GetRoleDisplayText(role)
    return string.format(
    "Server information : %s [%s] has joined the server",
    player.DisplayName,
    displayText
    )
end
 
--==================================================
-- GLOBAL SUBSCRIBE
--==================================================
pcall(function()
    MessagingService:SubscribeAsync(TOPIC, function(data)
        if data and data.Data then
            ChatRemote:FireAllClients(data.Data)
        end
    end)
end)
 
--==================================================
-- HANDLE PLAYER
--==================================================
Players.PlayerAdded:Connect(function(player)
 
    task.delay(1.5, function()
 
        -- JOIN MESSAGE
        local msg = buildJoinMessage(player)
        if msg then
            ChatRemote:FireAllClients(msg)
        end
 
        -- CHAT COMMAND
        player.Chatted:Connect(function(message)
 
            local role = JekyTitle.GetRoleTitle(player)
            if not isEligibleRole(role) then return end
            if #message < 4 then return end
 
            local cmd      = message:sub(1, 2)
            local isiPesan = message:sub(4)
            if isiPesan == "" then return end
 
            -- ============================
            -- FILTER DI SINI
            -- ============================
            local filteredText = filterMessage(player, isiPesan)
            if not filteredText then return end
 
            local roleDisplay = JekyTitle.GetRoleDisplayText(role)
 
            local formatted = string.format(
            "[%s] %s %s : %s",
            roleDisplay,
            player.DisplayName,
            SYMBOL,
            filteredText
            )
 
            -- GLOBAL
            if cmd == "_G" then
                pcall(function()
                    MessagingService:PublishAsync(TOPIC, formatted)
                end)
 
                -- SERVER
            elseif cmd == "_S" then
                ChatRemote:FireAllClients(formatted)
            end
 
        end)
    end)
end)

