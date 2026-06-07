-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

-- Setup Collision Group untuk pemain yang digendong agar tembus (tidak nyangkut)
pcall(function()
    PhysicsService:RegisterCollisionGroup("CarriedGroup")
    PhysicsService:CollisionGroupSetCollidable("CarriedGroup", "Default", false)
    PhysicsService:CollisionGroupSetCollidable("CarriedGroup", "CarriedGroup", false)
end)

-- Remotes
local REMOTE_NAME = "CarryRemote"
local CarryRemote = ReplicatedStorage:FindFirstChild(REMOTE_NAME) or Instance.new("RemoteEvent")
CarryRemote.Name = REMOTE_NAME
CarryRemote.Parent = ReplicatedStorage

-- Config
local PENDING_TIMEOUT = 8
local MAX_DISTANCE = 20
local MAX_CARRY = 20 -- Max players per carry

-- Formation
local BASE_Z = 1.6
local SPACING_Z = 1.1
local Y_OFFSET = 0.9
local SLOT1_ADJ_Z = -0.2
local SLOT2_ADJ_Z =  0.2
local STEP_Y_FIRST = 0.55
local STEP_Y_NEXT  = 0.30
local MAX_EXTRA_Y  = 6.0
local function slotOffset(i: number): CFrame
    -- Semua player akan numplek di posisi yang sama, dengan sedikit offset acak agar tidak glitch
    local randomOffset = Vector3.new(
    math.random(-5,5) * 0.02, -- geser kecil X
    0,                         -- Y tetap
    math.random(-5,5) * 0.02  -- geser kecil Z
    )
    return CFrame.new(randomOffset.X, Y_OFFSET, BASE_Z + randomOffset.Z)
end


-- State
local pending: {[number]: {requester: Player, time: number}} = {}
local carryingByCarrier: {[number]: {[number]: Player}} = {}
local carriedByTarget: {[number]: Player} = {}
local slotByCarrier: {[number]: {[number]: number}} = {}
local lockMap: {[number]: boolean} = {}
local detachGuard: {[number]: boolean} = {}

-- Save/Restore
local savedProps: {[number]: {[BasePart]: {cc:boolean, ml:boolean, cg:string}}} = {}
local savedHum: {[number]: {ws:number, useJP:boolean, jp:number, jh:number, autoRotate:boolean, jumpEnabled:boolean}} = {}

local function getCharHRP(p: Player)
    local char = p.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    return char, hrp, hum
end

local function acquireLock(uid: number)
    local waited = 0
    while lockMap[uid] and waited < 5 do
        waited += task.wait()
    end
    lockMap[uid] = true
end
local function releaseLock(uid: number) lockMap[uid] = false end
local function acquireLocks(a: number, b: number)
    if a == b then acquireLock(a) return end
    if a < b then acquireLock(a); acquireLock(b) else acquireLock(b); acquireLock(a) end
end
local function releaseLocks(a: number, b: number)
    releaseLock(a); if b ~= a then releaseLock(b) end
end

local function getCarryMap(carrier: Player)
    local m = carryingByCarrier[carrier.UserId]
    if not m then m = {}; carryingByCarrier[carrier.UserId] = m end
    return m
end
local function getSlotMap(carrier: Player)
    local m = slotByCarrier[carrier.UserId]
    if not m then m = {}; slotByCarrier[carrier.UserId] = m end
    return m
end
local function countCarried(carrier: Player)
    local m = carryingByCarrier[carrier.UserId]; if not m then return 0 end
    local n = 0; for _ in pairs(m) do n += 1 end
    return n
end
local function isBeingCarried(p: Player) return carriedByTarget[p.UserId] ~= nil end
local function canCarrierRequest(p: Player) return not isBeingCarried(p) end
local function targetAvailable(p: Player) return not isBeingCarried(p) end

local function saveHumState(uid: number, hum: Humanoid)
    savedHum[uid] = {
        -- HAPUS ATAU COMMENT BAGIAN INI:
        -- ws = hum.WalkSpeed,
        -- useJP = hum.UseJumpPower,
        -- jp = hum.JumpPower,
        -- jh = hum.JumpHeight,
        
        autoRotate = hum.AutoRotate,
        jumpEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping),
    }
end

local function restoreHumState(uid: number, hum: Humanoid)
    local st = savedHum[uid]
    if st then
        hum.AutoRotate = st.autoRotate
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, st.jumpEnabled)
        savedHum[uid] = nil
    else
        hum.AutoRotate = true
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    end
end

local function makeCarriedLight(char: Model, userId: number)
    local map: {[BasePart]: {cc:boolean, ml:boolean, cg:string}} = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            map[d] = { cc = d.CanCollide, ml = d.Massless, cg = d.CollisionGroup }
            d.CanCollide = false
            d.Massless = true
            pcall(function()
                d.CollisionGroup = "CarriedGroup"
            end)
        end
    end
    savedProps[userId] = map
end
local function restoreCarriedLight(userId: number)
    local map = savedProps[userId]; if not map then return end
    for part, st in pairs(map) do
        if part and part.Parent then
            part.CanCollide = st.cc
            part.Massless  = st.ml
            pcall(function()
                part.CollisionGroup = st.cg or "Default"
            end)
        end
    end
    savedProps[userId] = nil
end

-- Weld
local function clearCarryWeldsForChar(char: Model)
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        for _, w in ipairs(hrp:GetChildren()) do
            if w:IsA("WeldConstraint") and w.Name == "CarryWeld" then
                w:Destroy()
            end
        end
    end
end
local function findCarryWeldBetween(targetHRP: BasePart, carrierHRP: BasePart): WeldConstraint?
    for _, w in ipairs(targetHRP:GetChildren()) do
        if w:IsA("WeldConstraint") and w.Name == "CarryWeld" and w.Part0 == carrierHRP and w.Part1 == targetHRP then
            return w
        end
    end
    return nil
end
local function ensureCarryWeldBetween(carrierHRP: BasePart, targetHRP: BasePart): WeldConstraint
    local w = findCarryWeldBetween(targetHRP, carrierHRP)
    if not w then
        w = Instance.new("WeldConstraint")
        w.Name = "CarryWeld"
        w.Part0 = carrierHRP
        w.Part1 = targetHRP
        w.Parent = targetHRP
    end
    return w
end
local function removeCarryWeldBetween(carrierHRP: BasePart, targetHRP: BasePart)
    local w = findCarryWeldBetween(targetHRP, carrierHRP)
    if w then w:Destroy() end
end

-- UI Snapshot
local function buildCarriedList(carrier: Player)
    local list = {}
    local cmap = carryingByCarrier[carrier.UserId]
    if cmap then
        for tid, t in pairs(cmap) do table.insert(list, {id=tid, name=t.DisplayName}) end
        table.sort(list, function(a,b) return a.name < b.name end)
        end
            return list
        end
        local function sendCarrierList(carrier: Player)
            CarryRemote:FireClient(carrier, "CarrierList", {list = buildCarriedList(carrier)})
        end
        
        -- Reindex
        local function reindexSlots(carrier: Player)
            acquireLock(carrier.UserId)
            local ok = pcall(function()
                local _, cHRP = getCharHRP(carrier); if not cHRP then return end
                local smap = slotByCarrier[carrier.UserId]; if not smap then return end
                local temp = {}
                for tid, s in pairs(smap) do
                    local t = Players:GetPlayerByUserId(tid)
                    if t then table.insert(temp, {p=t, s=s}) end
                end
                table.sort(temp, function(a,b) return a.s < b.s end)
                    for i, e in ipairs(temp) do
                        local tChar, tHRP = getCharHRP(e.p)
                        if tHRP then
                            if e.s ~= i then
                                removeCarryWeldBetween(cHRP, tHRP)
                                tHRP.CFrame = cHRP.CFrame * slotOffset(i)
                                ensureCarryWeldBetween(cHRP, tHRP)
                                slotByCarrier[carrier.UserId][e.p.UserId] = i
                            else
                                ensureCarryWeldBetween(cHRP, tHRP)
                            end
                        end
                    end
                end)
                releaseLock(carrier.UserId)
                if not ok then end
            end
            
            -- Notify
            local function sendStart(carrier: Player, target: Player)
                local total = countCarried(carrier)
                CarryRemote:FireClient(carrier, "Start", {
                carrierId=carrier.UserId, carrierName=carrier.DisplayName,
                targetId=target.UserId,   targetName=target.DisplayName,
                youAreCarrier=true, carrierActiveCount=total
                })
                CarryRemote:FireClient(target, "Start", {
                carrierId=carrier.UserId, carrierName=carrier.DisplayName,
                targetId=target.UserId,   targetName=target.DisplayName,
                youAreCarrier=false
                })
            end
            local function sendEndForCarrierOnly(carrier: Player, removedTarget: Player, reason: string?)
                local total = countCarried(carrier)
                CarryRemote:FireClient(carrier, "End", {
                reason = reason or "end",
                youAreCarrier = true,
                carrierActiveCount = total,
                removedId = removedTarget.UserId,
                removedName = removedTarget.DisplayName,
                })
            end
            local function sendEndPair(carrier: Player, target: Player, reason: string?)
                local total = countCarried(carrier)
                CarryRemote:FireClient(carrier, "End", {
                reason = reason or "end",
                youAreCarrier = true,
                carrierActiveCount = total,
                removedId = target.UserId,
                removedName = target.DisplayName,
                })
                local still = countCarried(target)
                CarryRemote:FireClient(target , "End", {reason = reason or "end", youAreCarrier = false, yourCarryCount = still})
            end
            
            -- Detach
            local function detachPair(carrier: Player, target: Player, reason: string?)
                local cUID = carrier.UserId
                local tUID = target.UserId
                
                acquireLock(cUID)
                local cChar, cHRP = getCharHRP(carrier)
                local tChar, tHRP, tHum = getCharHRP(target)
                
if cHRP and tHRP then
    removeCarryWeldBetween(cHRP, tHRP)
    -- TAMBAHKAN INI: Beri jarak aman ke belakang/samping agar hitbox tidak tabrakan
    tHRP.CFrame = cHRP.CFrame * CFrame.new(0, 0, 3) 
end
                
                if tHum then
                    restoreHumState(tUID, tHum)
                    tHum.Sit = false
                    tHum.Jump = false
                end
                restoreCarriedLight(tUID)
                
                local cmap = carryingByCarrier[cUID]
                if cmap then
                    cmap[tUID] = nil
                    if not next(cmap) then carryingByCarrier[cUID] = nil end
                end
                if slotByCarrier[cUID] then slotByCarrier[cUID][tUID] = nil end
                carriedByTarget[tUID] = nil
                
                releaseLock(cUID)
                
                sendEndPair(carrier, target, reason)
                
                task.defer(function()
                    if carryingByCarrier[cUID] then reindexSlots(carrier) end
                    sendCarrierList(carrier)
                end)
            end
            
            local function detachAllForCarrier(carrier: Player, reason: string?)
                local cmap = carryingByCarrier[carrier.UserId]; if not cmap then return end
                local list = {}
                for _, t in pairs(cmap) do table.insert(list, t) end
                for _, t in ipairs(list) do detachPair(carrier, t, reason) end
            end
            local function detachIfAny(p: Player, reason: string?)
                if carriedByTarget[p.UserId] then
                    detachPair(carriedByTarget[p.UserId], p, reason)
                elseif carryingByCarrier[p.UserId] then
                    detachAllForCarrier(p, reason)
                end
            end
            local function safeDetachIfAny(p: Player, reason: string?)
                if detachGuard[p.UserId] then return end
                detachGuard[p.UserId] = true
                task.defer(function()
                    detachIfAny(p, reason)
                    detachGuard[p.UserId] = nil
                end)
            end
            
            -- Transfer
            local function transferPassengersToAtomic(newCarrier: Player, oldCarrier: Player)
                local oldMap = carryingByCarrier[oldCarrier.UserId]; if not oldMap then return end
                local smapOld = slotByCarrier[oldCarrier.UserId] or {}
                local arr = {}
                for tid, t in pairs(oldMap) do table.insert(arr, {t=t, s=smapOld[tid] or 999}) end
                table.sort(arr, function(a,b) return a.s < b.s end)
                    
                    local _, newHRP = getCharHRP(newCarrier)
                    local _, oldHRP = getCharHRP(oldCarrier)
                    if not newHRP or not oldHRP then return end
                    
                    acquireLocks(newCarrier.UserId, oldCarrier.UserId)
                    
                    for _, entry in ipairs(arr) do
                        local t: Player = entry.t
                        local tChar, tHRP, tHum = getCharHRP(t)
                        if tChar and tHRP and tHum then
                            local used, smNew = {}, getSlotMap(newCarrier)
                            for _, idx in pairs(smNew) do used[idx] = true end
                            local slotIdx
                            for i = 1, MAX_CARRY do if not used[i] then slotIdx = i break end end
                            if not slotIdx then continue end
                            
                            removeCarryWeldBetween(oldHRP, tHRP)
                            tHRP.CFrame = newHRP.CFrame * slotOffset(slotIdx)
                            ensureCarryWeldBetween(newHRP, tHRP)
                            
                            tHum.AutoRotate = false
                            
                            local oldMap2 = carryingByCarrier[oldCarrier.UserId]
                            if oldMap2 then
                                oldMap2[t.UserId] = nil
                                if not next(oldMap2) then carryingByCarrier[oldCarrier.UserId] = nil end
                            end
                            if slotByCarrier[oldCarrier.UserId] then slotByCarrier[oldCarrier.UserId][t.UserId] = nil end
                            getCarryMap(newCarrier)[t.UserId] = t
                            getSlotMap(newCarrier)[t.UserId] = slotIdx
                            carriedByTarget[t.UserId] = newCarrier
                            
                            sendEndForCarrierOnly(oldCarrier, t, "transfer")
                            sendStart(newCarrier, t)
                        end
                    end
                    
                    releaseLocks(newCarrier.UserId, oldCarrier.UserId)
                    
                    if carryingByCarrier[oldCarrier.UserId] then reindexSlots(oldCarrier) end
                    sendCarrierList(newCarrier)
                    sendCarrierList(oldCarrier)
                end
                
                -- Pending
                task.spawn(function()
                    while true do
                        task.wait(2)
                        local now = os.clock()
                        for targetId, info in pairs(pending) do
                            if now - info.time > PENDING_TIMEOUT then
                                local target = Players:GetPlayerByUserId(targetId)
                                if info.requester and info.requester.Parent == Players then
                                    CarryRemote:FireClient(info.requester, "RequestExpired", {targetId = targetId})
                                    if target then CarryRemote:FireClient(target, "PromptExpire", {}) end
                                end
                                pending[targetId] = nil
                            end
                        end
                    end
                end)
                
                local function hasPendingIncoming(p: Player)
                    return pending[p.UserId] ~= nil
                end
                local function hasPendingOutgoing(p: Player)
                    for _, info in pairs(pending) do
                        if info.requester == p then
                            return true
                        end
                    end
                    return false
                end
                
                -- Start Carry
                local function startCarry(carrier: Player, target: Player)
                    local cChar, cHRP = getCharHRP(carrier)
                    local tChar, tHRP, tHum = getCharHRP(target)
                    if not (cChar and cHRP and tChar and tHRP and tHum) then return false, "character missing" end
                    
                    acquireLock(carrier.UserId)
                    local ok, err = pcall(function()
                        if (cHRP.Position - tHRP.Position).Magnitude > MAX_DISTANCE then error("too far") end
                        if not canCarrierRequest(carrier) then error("busy") end
                        if not targetAvailable(target) then error("busy") end
                        
                        local extra = countCarried(target)
                        if (countCarried(carrier) + 1 + extra) > MAX_CARRY then error("limit_transfer") end
                        
                        local used, sm = {}, getSlotMap(carrier)
                        for _, idx in pairs(sm) do used[idx] = true end
                        local slotIdx
                        for i = 1, MAX_CARRY do if not used[i] then slotIdx = i break end end
                        if not slotIdx then error("limit") end
                        
                        tHRP.CFrame = cHRP.CFrame * slotOffset(slotIdx)
                        ensureCarryWeldBetween(cHRP, tHRP)
                        
                        saveHumState(target.UserId, tHum)
                        tHum.AutoRotate = false
                        
                        makeCarriedLight(tChar, target.UserId)
                        
                        getCarryMap(carrier)[target.UserId] = target
                        getSlotMap(carrier)[target.UserId] = slotIdx
                        carriedByTarget[target.UserId] = carrier
                        
                        local function bindCleanupForCharacter(char: Instance, p: Player)
                            local hum = char:FindFirstChildOfClass("Humanoid")
                            if hum then hum.Died:Connect(function() safeDetachIfAny(p, "death") end) end
                            char.AncestryChanged:Connect(function(_, parent) if not parent then safeDetachIfAny(p, "character removed") end end)
                            end
                                bindCleanupForCharacter(cChar, carrier)
                                bindCleanupForCharacter(tChar, target)
                                
                                sendStart(carrier, target)
                            end)
                            releaseLock(carrier.UserId)
                            if not ok then return false, tostring(err) end
                            
                            if countCarried(target) > 0 then transferPassengersToAtomic(carrier, target) end
                            sendCarrierList(carrier)
                            return true
                        end
                        
                        -- Remote Handlers
                        CarryRemote.OnServerEvent:Connect(function(player: Player, action: string, data)
                            if action == "Request" then
                                local targetId = data and data.targetId
                                if type(targetId) ~= "number" then return end
                                local target = Players:GetPlayerByUserId(targetId); if not target or target == player then return end
                                local _, cHRP = getCharHRP(player); local _, tHRP = getCharHRP(target)
                                if not (cHRP and tHRP) then return end
                                if (cHRP.Position - tHRP.Position).Magnitude > MAX_DISTANCE then
                                    CarryRemote:FireClient(player, "TooFar", {targetId=targetId}); return
                                end
                                local extra = countCarried(target)
                                if (countCarried(player) + 1 + extra) > MAX_CARRY then
                                    CarryRemote:FireClient(player, "Limit", {max = MAX_CARRY, reason = "transfer"}); return
                                end
                                if not canCarrierRequest(player) or not targetAvailable(target) then
                                    CarryRemote:FireClient(player, "Busy", {}); return
                                end
                                if hasPendingIncoming(player) or hasPendingOutgoing(player) or pending[target.UserId] then
                                    CarryRemote:FireClient(player, "Busy", {}); return
                                end
                                
                                pending[target.UserId] = {requester = player, time = os.clock()}
                                CarryRemote:FireClient(target, "Prompt", {fromId = player.UserId, fromName = player.DisplayName})
                                
                            elseif action == "Response" then
                                local accept = data and data.accept == true
                                local requesterId = data and data.requesterId
                                if type(requesterId) ~= "number" then return end
                                local requester = Players:GetPlayerByUserId(requesterId); if not requester then return end
                                local pend = pending[player.UserId]; if not pend or pend.requester ~= requester then return end
                                pending[player.UserId] = nil
                                if not accept then
                                    CarryRemote:FireClient(requester, "Declined", {targetId = player.UserId})
                                    CarryRemote:FireClient(player, "PromptClose", {})
                                    return
                                end
                                local ok2, err2 = startCarry(requester, player)
                                if not ok2 then
                                    if tostring(err2) == "limit_transfer" then
                                        CarryRemote:FireClient(requester, "Limit", {max = MAX_CARRY, reason = "transfer"})
                                        CarryRemote:FireClient(player, "Failed", {reason="limit_transfer"})
                                    else
                                        CarryRemote:FireClient(requester, "Failed", {reason=err2})
                                        CarryRemote:FireClient(player, "Failed", {reason=err2})
                                    end
                                end
                                
                            elseif action == "Stop" then
                                local targetId = data and data.targetId
                                if type(targetId) == "number" then
                                    local t = Players:GetPlayerByUserId(targetId)
                                    if t and carryingByCarrier[player.UserId] and carryingByCarrier[player.UserId][targetId] then
                                        detachPair(player, t, "stop"); return
                                    end
                                end
                                detachIfAny(player, "stop")
                            end
                        end)
                        
                        -- Respawn
                        local function onCharacterAdded(p: Player, char: Model)
                            task.defer(function()
                                clearCarryWeldsForChar(char)
                                local hum = char:FindFirstChildOfClass("Humanoid")
                                if hum then
                                    hum.Sit = false
                                    hum.AutoRotate = true
                                    hum.WalkSpeed = 16
                                    if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
                                    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
                                    hum.Jump = false
                                end
                                savedProps[p.UserId] = nil
                                savedHum[p.UserId]   = nil
                                safeDetachIfAny(p, "respawn")
                            end)
                        end
                        
                        Players.PlayerAdded:Connect(function(p)
                            p.CharacterAdded:Connect(function(char) onCharacterAdded(p, char) end)
                            end)
                                Players.PlayerRemoving:Connect(function(p: Player)
                                    pending[p.UserId] = nil
                                    detachIfAny(p, "left")
                                end)

