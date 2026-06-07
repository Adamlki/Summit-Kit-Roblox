local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
 
Players.CharacterAutoLoads = false
Players.RespawnTime        = 2
 
local JekyDataStore  = require(ServerStorage.JekyModules:WaitForChild("JekyDataStore"))
local JekyConfig     = require(ServerStorage.JekyModules:WaitForChild("JekyConfig"))
local JekyTitle      = require(ServerStorage.JekyModules:WaitForChild("JekyTitle"))
local JekyGlobalData = require(ServerStorage.JekyModules:WaitForChild("JekyGlobalData"))
 
local CHECKPOINT_TOUCH_COOLDOWN = JekyConfig.TOUCH_COOLDOWN or 0.3
local TELEPORT_TOUCH_COOLDOWN   = 0.5
local SPAWN_IMMUNITY_TIME       = JekyConfig.SPAWN_IMMUNITY_TIME or 3
 
task.spawn(function()
    JekyDataStore:Initialize()
    task.wait(1)
    JekyGlobalData:Initialize()
    task.wait(0.5)
    JekyConfig:LoadValues()
end)
 
local JekyEvents = ReplicatedStorage:FindFirstChild("JekyEvents")
if not JekyEvents then
    JekyEvents        = Instance.new("Folder")
    JekyEvents.Name   = "JekyEvents"
    JekyEvents.Parent = ReplicatedStorage
end
 
local function getOrCreateRE(name)
    local ev = JekyEvents:FindFirstChild(name)
    if not ev then ev = Instance.new("RemoteEvent"); ev.Name = name; ev.Parent = JekyEvents end
    return ev
end
local function getOrCreateBE(name)
    local ev = JekyEvents:FindFirstChild(name)
    if not ev then ev = Instance.new("BindableEvent"); ev.Name = name; ev.Parent = JekyEvents end
    return ev
end
local function getOrCreateBF(name)
    local ev = JekyEvents:FindFirstChild(name)
    if not ev then ev = Instance.new("BindableFunction"); ev.Name = name; ev.Parent = JekyEvents end
    return ev
end
local function getOrCreateRF(name)
    local ev = JekyEvents:FindFirstChild(name)
    if not ev then ev = Instance.new("RemoteFunction"); ev.Name = name; ev.Parent = JekyEvents end
    return ev
end
 
local CP_CheckpointUpdated       = getOrCreateRE("CP_CheckpointUpdated")
local CP_PlayerTouched           = getOrCreateRE("CP_PlayerTouched")
local CP_PartColorUpdate         = getOrCreateRE("CP_PartColorUpdate")
local CP_RequestResetToBC        = getOrCreateRE("CP_RequestResetToBC")
local CP_SkippedWarning          = getOrCreateRE("CP_SkippedWarning")
local CP_RequestTeleportToLastCP = getOrCreateRE("CP_RequestTeleportToLastCP")
local CP_Internal_ServerLBUpdate = getOrCreateBE("CP_Internal_ServerLBUpdate")
local CP_Internal_GlobalLBUpdate = getOrCreateBE("CP_Internal_GlobalLBUpdate")
local CP_Internal_GetServerLB    = getOrCreateBF("CP_Internal_GetServerLB")
local CP_Internal_GetGlobalLB    = getOrCreateBF("CP_Internal_GetGlobalLB")
local GetPlayerRole              = getOrCreateRF("GetPlayerRole")
local API_SetSummitValue         = getOrCreateRF("API_SetSummitValue")
local API_SetApexValue           = getOrCreateRF("API_SetApexValue")
local API_GetCurrentValues       = getOrCreateRF("API_GetCurrentValues")
local API_SetSkipMode            = getOrCreateRF("API_SetSkipMode")
 
-- Model name ↔ internal ID mapping
local MODEL_TO_INTERNAL = { SUMMIT = "Summit", BIGSUMMIT = "ApexSummit" }
local INTERNAL_TO_MODEL = { Summit = "SUMMIT", ApexSummit = "BIGSUMMIT" }
 
local PlayerRoundState       = {}
local PlayerVisited          = {}
local PlayerLastTouch        = {}
local PlayerSpawnImmunity    = {}
local PlayerLastSummitReward = {}
local PlayerSummitLock       = {}
local PlayerRespawnLocation  = {}
local PlayerCharacterState   = {}
local PlayerBCNotified       = {}
local PlayerLoadLock         = {}
local PlayerSetupActive      = {}
 
local ServerLeaderboard = {}
local GlobalLeaderboard = {}
 
GetPlayerRole.OnServerInvoke = function(player)
    return JekyTitle.GetRoleTitle(player)
end
 
API_GetCurrentValues.OnServerInvoke = function(player)
    local role = JekyTitle.GetRoleTitle(player)
    if not JekyConfig:HasCommandAccess(role, "_Value") then
        return { success = false, message = "No permission" }
    end
    return {
    success        = true,
    Summit         = JekyConfig:GetSummitValue(),
    ApexSummit     = JekyConfig:GetApexValue(),
    SkipCheckpoint = JekyConfig:GetSkipCheckpointMode(),
    }
end
 
API_SetSummitValue.OnServerInvoke = function(player, newValue)
    local role = JekyTitle.GetRoleTitle(player)
    if not JekyConfig:HasCommandAccess(role, "_Value") then return { success = false, message = "No permission" } end
    if type(newValue) ~= "number" or newValue < 0 then return { success = false, message = "Invalid value" } end
    if JekyConfig:SetSummitValue(newValue) then
        task.wait(0.5); JekyConfig:LoadValues()
        return { success = true, message = "Summit updated to " .. newValue }
    end
    return { success = false, message = "Failed" }
end
 
API_SetApexValue.OnServerInvoke = function(player, newValue)
    local role = JekyTitle.GetRoleTitle(player)
    if not JekyConfig:HasCommandAccess(role, "_Value") then return { success = false, message = "No permission" } end
    if type(newValue) ~= "number" or newValue < 0 then return { success = false, message = "Invalid value" } end
    if JekyConfig:SetApexValue(newValue) then
        task.wait(0.5); JekyConfig:LoadValues()
        return { success = true, message = "Apex updated to " .. newValue }
    end
    return { success = false, message = "Failed" }
end
 
API_SetSkipMode.OnServerInvoke = function(player, skipMode)
    local role = JekyTitle.GetRoleTitle(player)
    if not JekyConfig:HasCommandAccess(role, "_Value") then return { success = false, message = "No permission" } end
    if type(skipMode) ~= "boolean" then return { success = false, message = "Must be boolean" } end
    if JekyConfig:SetSkipCheckpointMode(skipMode) then
        return { success = true, message = "Skip mode = " .. tostring(skipMode) }
    end
    return { success = false, message = "Failed" }
end
 
local function getCheckpointFolder()
    local jeky = workspace:FindFirstChild("AllPartSummitkitJeky")
    if not jeky then return nil end
    return jeky:FindFirstChild("Checkpoint")
end
 
local function getCheckpointModel(checkpointId)
    local cpFolder = getCheckpointFolder()
    if not cpFolder then return nil end
    local modelName = INTERNAL_TO_MODEL[checkpointId] or checkpointId
    return cpFolder:FindFirstChild(modelName)
end
 
local function getSpawnLocation(checkpointId)
    local model = getCheckpointModel(checkpointId)
    if model then
        local sp = model:FindFirstChildOfClass("SpawnLocation")
        if sp then return sp end
    end
    if checkpointId ~= "BC" then
        return getSpawnLocation("BC")
    end
    local def = Instance.new("SpawnLocation")
    def.Name     = "BC_Fallback"
    def.Position = Vector3.new(0, 10, 0)
    def.Anchored = true
    def.Size     = Vector3.new(10, 1, 10)
    def.Parent   = workspace
    return def
end
 
-- Returns Destinasi part — only used for non-SUMMIT/BIGSUMMIT checkpoints and BC
local function getDestinasi(checkpointId)
    -- SUMMIT and BIGSUMMIT no longer have Destinasi
    if checkpointId == "Summit" or checkpointId == "ApexSummit" then return nil end
    local model = getCheckpointModel(checkpointId)
    if not model then return nil end
    return model:FindFirstChild("Destinasi")
end
 
local lbUpdateQueued = false
local function updateServerLeaderboard()
    if lbUpdateQueued then return end
    lbUpdateQueued = true
    task.delay(1.5, function()
        lbUpdateQueued = false
        local data = {}
        for _, p in ipairs(Players:GetPlayers()) do
            local ls = p:FindFirstChild("leaderstats")
            if ls then
                local summit = ls:FindFirstChild("Summit")
                local cp     = ls:FindFirstChild("Checkpoint")
                if summit and cp then
                    table.insert(data, {
                    UserId      = p.UserId,
                    Username    = p.Name,
                    DisplayName = p.DisplayName,
                    Summit      = tonumber(summit.Value) or 0,
                    Checkpoint  = cp.Value,
                    IsOnline    = true,
                    })
                end
            end
        end
        table.sort(data, function(a, b)
            if a.Summit == b.Summit then return a.Username < b.Username end
            return a.Summit > b.Summit
        end)
        ServerLeaderboard = data
        CP_Internal_ServerLBUpdate:Fire(data)
    end)
end
 
local function updateGlobalLeaderboard()
    local ok, data = JekyDataStore:GetGlobalLeaderboard(100)
    if ok and data then
        GlobalLeaderboard = data
        CP_Internal_GlobalLBUpdate:Fire(data)
    end
end
 
CP_Internal_GetServerLB.OnInvoke = function() return ServerLeaderboard end
CP_Internal_GetGlobalLB.OnInvoke = function() return GlobalLeaderboard end
 
local function safeLoadCharacter(player)
    if not player or not player.Parent then return false end
    local uid = player.UserId
    if PlayerLoadLock[uid] then return false end
    PlayerLoadLock[uid]       = true
    PlayerCharacterState[uid] = "loading"
    local ok = pcall(function() player:LoadCharacter() end)
        if not ok then
            PlayerCharacterState[uid] = "dead"
        end
        task.delay(3, function()
            PlayerLoadLock[uid] = nil
        end)
        return ok
    end
    
    local function ensureLeaderstats(player)
        local ls = player:FindFirstChild("leaderstats")
        if not ls then
            ls        = Instance.new("Folder")
            ls.Name   = "leaderstats"
            ls.Parent = player
        end
        local cp = ls:FindFirstChild("Checkpoint")
        if not cp then
            cp        = Instance.new("StringValue")
            cp.Name   = "Checkpoint"
            cp.Value  = "BC"
            cp.Parent = ls
        end
        local summit = ls:FindFirstChild("Summit")
        if not summit then
            summit        = Instance.new("IntValue")
            summit.Name   = "Summit"
            summit.Value  = 0
            summit.Parent = ls
        end
        return cp, summit
    end
    
    local function teleportToCheckpoint(character, checkpointId)
        if not character or not character.Parent then return false end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return false end
        
        -- For SUMMIT/BIGSUMMIT use SpawnLocation only (no Destinasi)
        local target
        if checkpointId == "Summit" or checkpointId == "ApexSummit" then
            target = getSpawnLocation(checkpointId)
        else
            target = getDestinasi(checkpointId) or getSpawnLocation(checkpointId)
        end
        if not target then return false end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            task.wait(0.5)
            hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then return false end
        end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return false end
        
        if humanoid.Health <= 0 then
            humanoid.Health = humanoid.MaxHealth
            task.wait(0.1)
        end
        
        local range   = JekyConfig.SPAWN_RANDOM_RANGE or 5
        local offsetY = JekyConfig.SPAWN_OFFSET_Y    or 5
        local spawnPos = target.Position + Vector3.new(
        math.random(-range, range),
        offsetY,
        math.random(-range, range)
        )
        
        local ok = pcall(function()
            if character and character.Parent then
                hrp.CFrame                     = CFrame.new(spawnPos)
                hrp.AssemblyLinearVelocity     = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity    = Vector3.new(0, 0, 0)
            end
        end)
        
        if ok then
            task.wait(0.05)
            if humanoid and humanoid.Parent then
                humanoid.Health = humanoid.MaxHealth
            end
        end
        
        return ok
    end
    
    local function updateCheckpoint(player, newCheckpoint, isTouch)
        local cpLS, _ = ensureLeaderstats(player)
        local oldCheckpoint = cpLS.Value
        cpLS.Value = newCheckpoint
        
        local uid = player.UserId
        PlayerRespawnLocation[uid] = newCheckpoint
        if not PlayerVisited[uid] then PlayerVisited[uid] = {} end
        PlayerVisited[uid][newCheckpoint] = true
        
        -- Backfill previous checkpoints to prevent missing CP bugs at Summit
        local cpNum = tonumber(string.match(newCheckpoint, "^CP(%d+)$"))
        if cpNum then
            for i = 1, cpNum - 1 do
                PlayerVisited[uid]["CP" .. i] = true
            end
        end
        PlayerVisited[uid]["BC"] = true
        
        local spawnLoc = getSpawnLocation(newCheckpoint)
        if spawnLoc then player.RespawnLocation = spawnLoc end
        
        CP_CheckpointUpdated:FireClient(player, newCheckpoint, oldCheckpoint)
        
        task.spawn(function()
            local profile = JekyDataStore:GetProfile(uid)
            if profile then
                JekyDataStore:UpdateCheckpoint(uid, newCheckpoint)
                pcall(function()
                    if JekyDataStore.UpdateVisitedCheckpoints then
                        JekyDataStore:UpdateVisitedCheckpoints(uid, PlayerVisited[uid])
                    else
                        profile.CheckpointData.VisitedCheckpoints = PlayerVisited[uid]
                    end
                end)
                JekyDataStore:SaveProfile(uid, false)
            end
        end)
        
        if isTouch then task.spawn(updateServerLeaderboard) end
    end
    
    local function resetPlayer(player)
        local uid = player.UserId
        PlayerRoundState[uid]       = false
        PlayerVisited[uid]          = { BC = true }
        PlayerLastSummitReward[uid] = nil
        PlayerSummitLock[uid]       = nil
        PlayerRespawnLocation[uid]  = "BC"
        PlayerCharacterState[uid]   = "alive"
        PlayerBCNotified[uid]       = nil
        PlayerLastTouch[uid]        = 0
        
        if player.Character then
            player.Character:SetAttribute("LastCPTouch", 0)
        end
        
        updateCheckpoint(player, "BC", false)
        CP_PartColorUpdate:FireClient(player, nil, "reset")
        CP_PartColorUpdate:FireClient(player, "BC", "visited")
        CP_CheckpointUpdated:FireClient(player, "BC", "reset")
    end
    
    local function resetAndTeleportToBC(player)
    if not player or not player.Parent then return end
    local uid = player.UserId
    
    resetPlayer(player)
    
    local bcSpawn = getSpawnLocation("BC")
    if bcSpawn then player.RespawnLocation = bcSpawn end
    
    -- Jeda waktu (task.wait) dihapus agar teleport instan dan mencegah bug
    if player.Character then
        teleportToCheckpoint(player.Character, "BC")
    end
end
    
    local function getHighestCPNumber()
        local cpFolder = getCheckpointFolder()
        if not cpFolder then return 0 end
        local maxCP = 0
        for _, child in ipairs(cpFolder:GetChildren()) do
            if child:IsA("Model") then
                local n = tonumber(string.match(child.Name, "^CP(%d+)$"))
                if n and n > maxCP then maxCP = n end
            end
        end
        return maxCP
    end
    
    local function getMissingCheckpoint(uid)
        if not PlayerVisited[uid] then return 1 end
        local highest = getHighestCPNumber()
        if highest == 0 then return nil end
        for i = 1, highest do
            if not PlayerVisited[uid]["CP" .. i] then return i end
        end
        return nil
    end
    
    local function awardSummit(player, summitType)
        local _, summitLS = ensureLeaderstats(player)
        local uid = player.UserId
        if PlayerSummitLock[uid] then return end
        PlayerSummitLock[uid] = true
        
        local base  = JekyConfig.SUMMIT_REWARDS[summitType] or 0
        local total = base
        
        local last = PlayerLastSummitReward[uid]
        if last and last.type == summitType and (os.clock() - last.time) < 5 then
            PlayerSummitLock[uid] = nil
            return
        end
        
        PlayerLastSummitReward[uid] = { type = summitType, time = os.clock() }
        summitLS.Value = summitLS.Value + total
        
        CP_PlayerTouched:FireClient(player, {
        CheckpointId = summitType,
        IsSummit     = true,
        SummitValue  = total,
        IsNewRound   = false,
        })
        
        task.spawn(function()
            local profile = JekyDataStore:GetProfile(uid)
            if profile then
                JekyDataStore:UpdateSummit(uid, total)
                JekyDataStore:SaveProfile(uid, false)
                JekyDataStore:UpdateGlobalLeaderboardEntry(uid, player.Name, summitLS.Value)
            end
            updateServerLeaderboard()
            updateGlobalLeaderboard()
        end)
        
        task.delay(2, function() PlayerSummitLock[uid] = nil end)
        end
            
            local function getCPNumber(player)
                local cpLS = ensureLeaderstats(player)
                local v = cpLS.Value
                if v == "BC" then return 0 end
                return tonumber(string.match(v, "^CP(%d+)$")) or 0
            end
            
            local function getCPString(num)
                return num == 0 and "BC" or ("CP" .. num)
            end
            
            local function areCharactersWelded(charA, charB)
                for _, part in ipairs(charA:GetDescendants()) do
                    if part:IsA("WeldConstraint") or part:IsA("Weld") or part:IsA("Motor6D") then
                        local p0, p1 = part.Part0, part.Part1
                        if p0 and p1 then
                            if (charA:IsAncestorOf(p0) and charB:IsAncestorOf(p1))
                                or (charA:IsAncestorOf(p1) and charB:IsAncestorOf(p0)) then
                                return true
                            end
                        end
                    end
                end
                return false
            end
            
            local function getMinCPInGroup(player)
                local character = player.Character
                local minCP     = getCPNumber(player)
                if not character then return minCP end
                for _, other in ipairs(Players:GetPlayers()) do
                    if other == player then continue end
                    local otherChar = other.Character
                    if not otherChar then continue end
                    if areCharactersWelded(character, otherChar) then
                        local n = getCPNumber(other)
                        if n < minCP then minCP = n end
                    end
                end
                return minCP
            end
            
            local function setupCheckpointSystem()
                local summitkitFolder = workspace:WaitForChild("AllPartSummitkitJeky", 10)
                if not summitkitFolder then return end
                local checkpointFolder = summitkitFolder:WaitForChild("Checkpoint", 10)
                if not checkpointFolder then return end
                
                -- Set Destinasi parts transparent — only for non-SUMMIT/BIGSUMMIT models
                for _, model in ipairs(checkpointFolder:GetChildren()) do
                    if model:IsA("Model") then
                        local mn = model.Name
                        if mn ~= "SUMMIT" and mn ~= "BIGSUMMIT" then
                            local destinasi = model:FindFirstChild("Destinasi")
                            if destinasi and destinasi:IsA("BasePart") then
                                destinasi.Transparency = 1
                                destinasi.CanTouch     = true
                            end
                        end
                    end
                end
                
                local function onCheckpointTouch(modelName, hit)
                    local character = hit.Parent
                    if not character then return end
                    
                    -- FAST DEBOUNCE: Cek di level karakter sebelum memanggil API berat
                    local now = os.clock()
                    local lastCharTouch = character:GetAttribute("LastCPTouch") or 0
                    if now - lastCharTouch < CHECKPOINT_TOUCH_COOLDOWN then return end
                    character:SetAttribute("LastCPTouch", now)
                    
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if not humanoid or humanoid.Health <= 0 then return end
                    local player = Players:GetPlayerFromCharacter(character)
                    if not player then return end
                    
                    local uid = player.UserId
                    if PlayerSpawnImmunity[uid] and now < PlayerSpawnImmunity[uid] then return end
                    if PlayerLastTouch[uid] and (now - PlayerLastTouch[uid]) < CHECKPOINT_TOUCH_COOLDOWN then return end
                    PlayerLastTouch[uid] = now
                    
                    local checkpointId = MODEL_TO_INTERNAL[modelName] or modelName
                    
                    local cpLS, _ = ensureLeaderstats(player)
                    local currentCP = cpLS.Value
                    
                    if checkpointId == "BC" then
                        -- FIX SPAM: Jika sudah di BC dan sedang main, jangan update datastore terus menerus
                        if currentCP == "BC" and PlayerRoundState[uid] then return end

                        if not PlayerBCNotified[uid] then
                            PlayerBCNotified[uid] = true
                            CP_PlayerTouched:FireClient(player, { CheckpointId = "BC", IsSummit = false, SummitValue = 0, IsNewRound = true })
                        end
                        PlayerRoundState[uid] = true
                        PlayerVisited[uid]    = { BC = true }
                        updateCheckpoint(player, "BC", true)
                        CP_PartColorUpdate:FireClient(player, nil, "reset")
                        CP_PartColorUpdate:FireClient(player, "BC", "visited")
                        return
                    end
                    
                    if checkpointId == "Summit" or checkpointId == "ApexSummit" then
    if not PlayerRoundState[uid] then return end
    if not PlayerVisited[uid].BC then return end
    
    local missingCP = not JekyConfig:GetSkipCheckpointMode() and getMissingCheckpoint(uid) or nil
    if missingCP then 
        -- TAMBAHKAN WARNING AGAR TIDAK SILENT FAILURE
        dWarn(player.Name .. " mencoba Summit tetapi belum menginjak semua CP! Missing: CP" .. missingCP)
        
        -- Beritahu UI Client bahwa mereka melewatkan CP
        CP_SkippedWarning:FireClient(player, missingCP) 
        
        -- Opsional: Teleport mereka ke CP tertinggi yang sudah mereka injak
        return 
    end
    
    awardSummit(player, checkpointId)
    -- ...
                        awardSummit(player, checkpointId)
                        PlayerRoundState[uid] = false
                        PlayerBCNotified[uid] = nil
                        updateCheckpoint(player, checkpointId, true)
                        -- Respawn tetap di summit, tidak reset ke BC
                        return
                    end
                    
                    if string.match(checkpointId, "^CP%d+$") then
                        local cpNum = tonumber(string.match(checkpointId, "%d+"))
                        if not cpNum then return end
                        if not PlayerRoundState[uid] then return end
                        if not PlayerVisited[uid].BC then return end
                        
                        local skipMode = JekyConfig:GetSkipCheckpointMode()
                        
                        -- FIX SPAM: Jika player menginjak CP yang sama berulang kali
                        if currentCP == checkpointId then return end
                        -- Jika player sudah mengunjungi CP ini sebelumnya
                        if PlayerVisited[uid] and PlayerVisited[uid][checkpointId] then return end
                        
                        if skipMode then
                            PlayerVisited[uid][checkpointId] = true
                            updateCheckpoint(player, checkpointId, true)
                            CP_PlayerTouched:FireClient(player, { CheckpointId = checkpointId, IsSummit = false, SummitValue = 0, IsNewRound = false })
                            CP_PartColorUpdate:FireClient(player, checkpointId, "visited")
                        else
                            local expectedCP = 1
                            if string.match(currentCP, "^CP%d+$") then
                                expectedCP = tonumber(string.match(currentCP, "%d+")) + 1
                            elseif currentCP == "BC" then
                                expectedCP = 1
                            end
                            
                            if cpNum == expectedCP then
                                PlayerVisited[uid][checkpointId] = true
                                updateCheckpoint(player, checkpointId, true)
                                CP_PlayerTouched:FireClient(player, { CheckpointId = checkpointId, IsSummit = false, SummitValue = 0, IsNewRound = false })
                                CP_PartColorUpdate:FireClient(player, checkpointId, "visited")
                            elseif cpNum > expectedCP then
                                CP_SkippedWarning:FireClient(player, expectedCP)
                            end
                        end
                    end
                end
                
                for _, model in ipairs(checkpointFolder:GetChildren()) do
                    if not model:IsA("Model") then continue end
                    local modelName = model.Name
                    
                    local spawnLoc = model:FindFirstChildOfClass("SpawnLocation")
                    if spawnLoc then
                        spawnLoc.CanTouch = true
                        spawnLoc.Touched:Connect(function(hit)
                            onCheckpointTouch(modelName, hit)
                        end)
                    end
                    
                    -- SUMMIT / BIGSUMMIT: no Destinasi teleport, SpawnLocation touch handles award + reset
                    -- No separate Destinasi touch needed for SUMMIT/BIGSUMMIT
                end
            end
            
            -- setupTeleportSystem dihapus dari Server, sekarang dipindah ke Client (CheckpointClient)
            -- untuk mencegah bug teleport karena lag / server delay.
                            
                            
                            -- Handler: client minta reset ke BC via GUI
                            CP_RequestResetToBC.OnServerEvent:Connect(function(player)
                                resetAndTeleportToBC(player)
                            end)

                            -- Handler: client menyentuh part Teleport (killbrick) di layarnya
                            CP_RequestTeleportToLastCP.OnServerEvent:Connect(function(player)
                                local cpLS = ensureLeaderstats(player)
                                local currentCP = cpLS.Value
                                if player.Character then
                                    teleportToCheckpoint(player.Character, currentCP)
                                end
                            end)
                            
                            Players.PlayerAdded:Connect(function(player)
                                
                                player.Chatted:Connect(function(message)
                                    local roleTitle = JekyTitle.GetRoleTitle(player)
                                    if not roleTitle then return end
                                    local parts   = string.split(message, " ")
                                    local command = parts[1]
                                    
                                    if command == "_Add" and #parts >= 3 then
                                        if not JekyConfig:HasCommandAccess(roleTitle, "_Add") then return end
                                        local targetName = parts[2]
                                        local amount     = tonumber(parts[3])
                                        if not amount then return end
                                        local tp = nil
                                        for _, p in ipairs(Players:GetPlayers()) do
                                            if string.lower(p.Name) == string.lower(targetName) or string.lower(p.DisplayName) == string.lower(targetName) then
                                                tp = p; break
                                            end
                                        end
                                        if tp then
                                            local _, sLS = ensureLeaderstats(tp)
                                            sLS.Value = sLS.Value + amount
                                            task.spawn(function()
                                                JekyDataStore:ForceUpdateSummit(tp.UserId, sLS.Value)
                                                task.wait(0.5); updateServerLeaderboard()
                                                task.wait(0.5); updateGlobalLeaderboard()
                                            end)
                                        else
                                            task.spawn(function()
                                                local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(targetName) end)
                                                    if ok and uid then
                                                        local lok, profile = pcall(function() return JekyDataStore:LoadProfile(uid, true) end)
                                                            if lok and profile then
                                                                local newTotal = profile.SummitData.TotalSummit + amount
                                                                pcall(function() JekyDataStore:ForceUpdateSummit(uid, newTotal) end)
                                                                    task.wait(0.5); pcall(function() JekyDataStore:SaveProfile(uid, true) end)
                                                                        task.wait(0.5); pcall(function() JekyDataStore:UpdateGlobalLeaderboardEntry(uid, targetName, newTotal) end)
                                                                            task.wait(1); updateGlobalLeaderboard()
                                                                        end
                                                                    end
                                                                end)
                                                            end
                                                            
                                                        elseif command == "_R" and #parts >= 2 then
                                                            if not JekyConfig:HasCommandAccess(roleTitle, "_R") then return end
                                                            local targetName = parts[2]
                                                            local tp = nil
                                                            for _, p in ipairs(Players:GetPlayers()) do
                                                                if string.lower(p.Name) == string.lower(targetName) or string.lower(p.DisplayName) == string.lower(targetName) then
                                                                    tp = p; break
                                                                end
                                                            end
                                                            if tp then
                                                                local _, sLS = ensureLeaderstats(tp)
                                                                sLS.Value = 0
                                                                task.spawn(function()
                                                                    JekyDataStore:ForceUpdateSummit(tp.UserId, 0)
                                                                    task.wait(0.5); updateServerLeaderboard()
                                                                    task.wait(0.5); updateGlobalLeaderboard()
                                                                end)
                                                            else
                                                                task.spawn(function()
                                                                    local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(targetName) end)
                                                                        if ok and uid then
                                                                            local lok, profile = pcall(function() return JekyDataStore:LoadProfile(uid, true) end)
                                                                                if lok and profile then
                                                                                    pcall(function() JekyDataStore:ForceUpdateSummit(uid, 0) end)
                                                                                        task.wait(0.5); pcall(function() JekyDataStore:SaveProfile(uid, true) end)
                                                                                            task.wait(0.5); pcall(function() JekyDataStore:UpdateGlobalLeaderboardEntry(uid, targetName, 0) end)
                                                                                                task.wait(1); updateGlobalLeaderboard()
                                                                                            end
                                                                                        end
                                                                                    end)
                                                                                end
                                                                                
                                                                            elseif command == "_Value" and #parts >= 3 then
                                                                                if not JekyConfig:HasCommandAccess(roleTitle, "_Value") then return end
                                                                                local vt = parts[2]; local nv = tonumber(parts[3])
                                                                                if not nv or nv < 0 then return end
                                                                                if vt == "Big" then
                                                                                    JekyConfig:SetApexValue(nv); task.wait(0.5); JekyConfig:LoadValues()
                                                                                elseif vt == "Summit" then
                                                                                    JekyConfig:SetSummitValue(nv); task.wait(0.5); JekyConfig:LoadValues()
                                                                                end
                                                                                
                                                                            elseif command == "_AddRole" and #parts >= 3 then
                                                                                if not JekyConfig:HasCommandAccess(roleTitle, "_AddRole") then return end
                                                                                JekyTitle:AddDynamicRole(parts[2], parts[3])
                                                                                
                                                                            elseif command == "_RemoveRole" and #parts >= 2 then
                                                                                if not JekyConfig:HasCommandAccess(roleTitle, "_RemoveRole") then return end
                                                                                JekyTitle:RemoveDynamicRole(parts[2])
                                                                            end
                                                                        end)
                                                                        
                                                                        local uid = player.UserId
                                                                        PlayerRoundState[uid]      = false
                                                                        PlayerVisited[uid]         = { BC = true }
                                                                        PlayerLastTouch[uid]       = 0
                                                                        PlayerRespawnLocation[uid] = "BC"
                                                                        PlayerCharacterState[uid]  = "loading"
                                                                        PlayerBCNotified[uid]      = nil
                                                                        PlayerLoadLock[uid]        = nil
                                                                        PlayerSetupActive[uid]     = nil
                                                                        
                                                                        local cpLS, summitLS = ensureLeaderstats(player)
                                                                        
                                                                        local profile = JekyDataStore:LoadProfile(uid, false)
                                                                        if profile then
                                                                            local savedCP     = profile.CheckpointData.CurrentCheckpoint or "BC"
                                                                            local savedSummit = profile.SummitData.TotalSummit           or 0
                                                                            summitLS.Value    = savedSummit
                                                                            
                                                                            task.spawn(function() task.wait(0.5); player:SetAttribute("_SummitLoaded", true) end)
                                                                                
                                                                                local visitedData = profile.CheckpointData and (
                                                                                profile.CheckpointData.VisitedCheckpoints or
                                                                                profile.CheckpointData.Visited or
                                                                                profile.CheckpointData.visited
                                                                                ) or { BC = true }
                                                                                
                                                                                if savedCP == "Summit" or savedCP == "ApexSummit" or savedCP == "BC" then
                                                                                    cpLS.Value                 = savedCP
                                                                                    PlayerRoundState[uid]      = false
                                                                                    PlayerVisited[uid]         = { BC = true }
                                                                                    PlayerRespawnLocation[uid] = savedCP
                                                                                else
                                                                                    -- Backfill missing CPs from saved data
                                                                                    local savedNum = tonumber(string.match(savedCP, "^CP(%d+)$"))
                                                                                    if savedNum then
                                                                                        for i = 1, savedNum do
                                                                                            visitedData["CP" .. i] = true
                                                                                        end
                                                                                    end
                                                                                    visitedData["BC"] = true
                                                                                    
                                                                                    cpLS.Value                 = savedCP
                                                                                    PlayerRoundState[uid]      = true
                                                                                    PlayerVisited[uid]         = visitedData
                                                                                    PlayerRespawnLocation[uid] = savedCP
                                                                                end
                                                                                
                                                                                local respawnLoc = getSpawnLocation(PlayerRespawnLocation[uid])
                                                                                player.RespawnLocation = respawnLoc or getSpawnLocation("BC")
                                                                            else
                                                                                cpLS.Value     = "BC"
                                                                                summitLS.Value = 0
                                                                                PlayerRespawnLocation[uid] = "BC"
                                                                                task.spawn(function() task.wait(0.5); player:SetAttribute("_SummitLoaded", true) end)
                                                                                    local respawnLoc = getSpawnLocation("BC")
                                                                                    if respawnLoc then player.RespawnLocation = respawnLoc end
                                                                                end
                                                                                
                                                                                summitLS.Changed:Connect(function() task.spawn(updateServerLeaderboard) end)
                                                                                    
                                                                                    player.CharacterAdded:Connect(function(character)
                                                                                        local uid = player.UserId
                                                                                        
                                                                                        if PlayerSetupActive[uid] then return end
                                                                                        PlayerSetupActive[uid]    = true
                                                                                        PlayerCharacterState[uid] = "spawning"
                                                                                        
                                                                                        PlayerLoadLock[uid] = nil
                                                                                        
                                                                                        local humanoid = character:WaitForChild("Humanoid", 5)
                                                                                        if not humanoid then
                                                                                            PlayerSetupActive[uid]    = nil
                                                                                            PlayerCharacterState[uid] = "dead"
                                                                                            task.wait(1); safeLoadCharacter(player)
                                                                                            return
                                                                                        end
                                                                                        
                                                                                        local hrp = character:WaitForChild("HumanoidRootPart", 3)
                                                                                        if not hrp then
                                                                                            PlayerSetupActive[uid]    = nil
                                                                                            PlayerCharacterState[uid] = "dead"
                                                                                            task.wait(1); safeLoadCharacter(player)
                                                                                            return
                                                                                        end
                                                                                        
                                                                                        task.wait(0.2)
                                                                                        
                                                                                        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                                                                                        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                                                                                        humanoid:ChangeState(Enum.HumanoidStateType.Running)
                                                                                        humanoid.Health = humanoid.MaxHealth
                                                                                        
                                                                                        local respawnCP = PlayerRespawnLocation[uid] or cpLS.Value
                                                                                        local spawnLoc  = getSpawnLocation(respawnCP)
                                                                                        if spawnLoc then player.RespawnLocation = spawnLoc end
                                                                                        
                                                                                        local tpOk = false
                                                                                        for attempt = 1, 3 do
                                                                                            tpOk = teleportToCheckpoint(character, respawnCP)
                                                                                            if tpOk then break end
                                                                                            task.wait(0.5)
                                                                                        end
                                                                                        if not tpOk then
                                                                                            teleportToCheckpoint(character, "BC")
                                                                                        end
                                                                                        
                                                                                        PlayerSpawnImmunity[uid]  = os.clock() + SPAWN_IMMUNITY_TIME
                                                                                        PlayerCharacterState[uid] = "alive"
                                                                                        
                                                                                        local ff = Instance.new("ForceField")
                                                                                        ff.Visible = false
                                                                                        ff.Parent  = character
                                                                                        
                                                                                        local godCon
                                                                                        godCon = humanoid.HealthChanged:Connect(function(health)
                                                                                            if PlayerSpawnImmunity[uid] and os.clock() < PlayerSpawnImmunity[uid] then
                                                                                                if health < humanoid.MaxHealth then
                                                                                                    humanoid.Health = humanoid.MaxHealth
                                                                                                end
                                                                                            else
                                                                                                if godCon then godCon:Disconnect(); godCon = nil end
                                                                                            end
                                                                                        end)
                                                                                        
                                                                                        task.delay(SPAWN_IMMUNITY_TIME, function()
                                                                                            if ff and ff.Parent then ff:Destroy() end
                                                                                            if godCon then godCon:Disconnect(); godCon = nil end
                                                                                            PlayerSpawnImmunity[uid] = nil
                                                                                        end)
                                                                                        
                                                                                        local deathCon
                                                                                        deathCon = humanoid.Died:Connect(function()
                                                                                            if deathCon then deathCon:Disconnect(); deathCon = nil end
                                                                                            
                                                                                            PlayerCharacterState[uid] = "dead"
                                                                                            PlayerSetupActive[uid]    = nil
                                                                                            PlayerLoadLock[uid]       = nil
                                                                                            
                                                                                            task.spawn(function()
                                                                                                local p = JekyDataStore:GetProfile(uid)
                                                                                                if p then JekyDataStore:IncrementDeaths(uid) end
                                                                                            end)
                                                                                            
                                                                                            local newRespawnCP = PlayerRespawnLocation[uid] or cpLS.Value
                                                                                            local newSpawnLoc  = getSpawnLocation(newRespawnCP)
                                                                                            if newSpawnLoc then player.RespawnLocation = newSpawnLoc end
                                                                                            
                                                                                            task.wait(Players.RespawnTime + 0.5)
                                                                                            if player and player.Parent then
                                                                                                safeLoadCharacter(player)
                                                                                            end
                                                                                        end)
                                                                                        
                                                                                        PlayerSetupActive[uid] = nil
                                                                                    end)
                                                                                    
                                                                                    task.spawn(function()
                                                                                        task.wait(0.5)
                                                                                        if player and player.Parent then
                                                                                            safeLoadCharacter(player)
                                                                                        end
                                                                                    end)
                                                                                end)
                                                                                
                                                                                Players.PlayerRemoving:Connect(function(player)
                                                                                    local uid = player.UserId
                                                                                    task.spawn(function()
                                                                                        local profile = JekyDataStore:GetProfile(uid)
                                                                                        if profile then
                                                                                            JekyDataStore:SaveProfile(uid, true)
                                                                                        end
                                                                                    end)
                                                                                    PlayerRoundState[uid]       = nil
                                                                                    PlayerVisited[uid]          = nil
                                                                                    PlayerLastTouch[uid]        = nil
                                                                                    PlayerSpawnImmunity[uid]    = nil
                                                                                    PlayerLastSummitReward[uid] = nil
                                                                                    PlayerSummitLock[uid]       = nil
                                                                                    PlayerRespawnLocation[uid]  = nil
                                                                                    PlayerCharacterState[uid]   = nil
                                                                                    PlayerBCNotified[uid]       = nil
                                                                                    PlayerLoadLock[uid]         = nil
                                                                                    PlayerSetupActive[uid]      = nil
                                                                                    task.spawn(updateServerLeaderboard)
                                                                                end)
                                                                                
                                                                                -- Duplicate teleport connection removed
                                                                                
                                                                                task.spawn(function()
                                                                                    workspace:WaitForChild("AllPartSummitkitJeky", 30)
                                                                                    task.wait(1)
                                                                                    setupCheckpointSystem()
                                                                                    task.wait(2)
                                                                                    updateServerLeaderboard()
                                                                                    updateGlobalLeaderboard()
                                                                                end)
                                                                                
                                                                                task.spawn(function()
                                                                                    while true do
                                                                                        task.wait(300)
                                                                                        updateGlobalLeaderboard()
                                                                                    end
                                                                                end)

