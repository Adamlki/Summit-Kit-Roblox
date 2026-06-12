local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

-- ReplicatedStorage/JekyProfile/ProfileServiceJeky
-- v8 — fix GlobalLB stale data + reset support
 
local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local ServerStorage    = game:GetService("ServerStorage")
local JekyDSKeys       = require(ServerStorage:WaitForChild("JekyModules"):WaitForChild("JekyDSKeys"))
local DSKeys           = JekyDSKeys.Keys
 
local PS = {}
 
local PlaceId = game.PlaceId
local JobId   = game.JobId
 
local AUTO_SAVE_INTERVAL      = 60
local SESSION_TIMEOUT         = 1800
local MIN_READ_BUDGET         = 10
local MIN_WRITE_BUDGET        = 5
local ROLES_COOLDOWN          = 6
local MAX_RETRIES             = 5
local RETRY_WAIT              = 2
local USERNAME_CACHE_EXPIRY   = 1800
local USERNAME_WRITE_COOLDOWN = 300
 
-- ============================================================
-- BUDGET
-- ============================================================
local function getReadBudget()
    local ok, v = pcall(function()
        return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
    end)
    return ok and v or 0
end
 
local function getWriteBudget()
    local ok, v = pcall(function()
        return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
    end)
    return ok and v or 0
end
 
local function waitForWriteBudget(maxWait)
    maxWait = maxWait or 10
    local w = 0
    while getWriteBudget() < MIN_WRITE_BUDGET and w < maxWait do
        task.wait(1); w = w + 1
    end
    return getWriteBudget() >= MIN_WRITE_BUDGET
end
 
local function waitForReadBudget(maxWait)
    maxWait = maxWait or 10
    local w = 0
    while getReadBudget() < MIN_READ_BUDGET and w < maxWait do
        task.wait(1); w = w + 1
    end
    return getReadBudget() >= MIN_READ_BUDGET
end
 
-- ============================================================
-- DEEP COPY & RECONCILE
-- ============================================================
local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end
 
local function reconcile(data, template)
    for k, v in pairs(template) do
        if data[k] == nil then
            data[k] = deepCopy(v)
        elseif type(v) == "table" and type(data[k]) == "table" then
            reconcile(data[k], v)
        end
    end
end
 
-- ============================================================
-- STORE HELPERS
-- ============================================================
local storeRefs = {}
local function getStore(name, ordered)
    local key = name .. (ordered and "_ord" or "")
    if storeRefs[key] then return storeRefs[key] end
    local s = ordered
    and DataStoreService:GetOrderedDataStore(name)
    or  DataStoreService:GetDataStore(name)
    storeRefs[key] = s
    return s
end
 
local function safeSet(store, key, value)
    if not waitForWriteBudget(10) then return false end
    local ok, err = pcall(function() store:SetAsync(key, value) end)
        if not ok then dWarn("[PS] safeSet:", err) end
        return ok
    end
    
    local function safeGet(store, key)
        if not waitForReadBudget(10) then return false, nil end
        local ok, r = pcall(function() return store:GetAsync(key) end)
            if not ok then dWarn("[PS] safeGet:", r) end
            return ok, ok and r or nil
        end
        
        local function safeUpdate(store, key, fn)
            if not waitForWriteBudget(15) then return false, nil end
            local ok, r = pcall(function() return store:UpdateAsync(key, fn) end)
                if not ok then dWarn("[PS] safeUpdate:", r) end
                return ok, ok and r or nil
            end
            
            -- ============================================================
            -- 0. USERNAME SYSTEM
            -- ============================================================
            local usernameCache      = {}
            local usernameTimestamps = {}
            local usernameWriteLast  = {}
            local usernameResolving  = {}
            
            -- Antrean penyimpanan agar tidak spam DataStore Queue
            local usernameSaveQueue = {}
            local isUsernameSaverRunning = false

            local function startUsernameSaver()
                if isUsernameSaverRunning then return end
                isUsernameSaverRunning = true
                task.spawn(function()
                    while true do
                        local nextUserId, nextName = next(usernameSaveQueue)
                        if nextUserId then
                            usernameSaveQueue[nextUserId] = nil
                            local store = getStore(DSKeys.Profile.."_UserCache")
                            if store and waitForWriteBudget(15) then
                                pcall(function() store:SetAsync("U_"..nextUserId, nextName) end)
                                usernameWriteLast[nextUserId] = os.time()
                            end
                            task.wait(2) -- Beri jeda 2 detik antar request agar tidak memicu peringatan kuning
                        else
                            task.wait(1)
                        end
                    end
                end)
            end

            local function _persistUsername(userId, name)
                if not userId or not name or name == "" then return end
                local now = os.time()
                if usernameWriteLast[userId] and (now - usernameWriteLast[userId]) < USERNAME_WRITE_COOLDOWN then
                    return
                end
                
                -- Masukkan ke antrean dan jalankan prosesor antrean
                usernameSaveQueue[userId] = name
                startUsernameSaver()
            end
                
                function PS.CacheUsername(userId, name)
                    if not userId or not name or name == "" then return end
                    userId = tonumber(userId)
                    if not userId then return end
                    local old = usernameCache[userId]
                    usernameCache[userId]      = name
                    usernameTimestamps[userId] = os.time()
                    if old ~= name then _persistUsername(userId, name) end
                end
                PS.RegisterUsername = PS.CacheUsername
                
                function PS.GetUsernameFromUserId(userId)
                    userId = tonumber(userId)
                    if not userId then return nil end
                    
                    local p = Players:GetPlayerByUserId(userId)
                    if p then
                        usernameCache[userId]      = p.Name
                        usernameTimestamps[userId] = os.time()
                        return p.Name
                    end
                    
                    local cached = usernameCache[userId]
                    if cached and cached ~= "" then
                        local ts = usernameTimestamps[userId] or 0
                        if (os.time() - ts) < USERNAME_CACHE_EXPIRY then
                            return cached
                        end
                    end
                    
                    return nil
                end
                PS.GetUsernameCached = PS.GetUsernameFromUserId
                
                function PS.ResolveUsernameBackfill(userId)
                    userId = tonumber(userId)
                    if not userId then return end
                    if usernameResolving[userId] then return end
                    
                    local cached = usernameCache[userId]
                    if cached and cached ~= "" then
                        local ts = usernameTimestamps[userId] or 0
                        if (os.time() - ts) < USERNAME_CACHE_EXPIRY then return end
                    end
                    
                    usernameResolving[userId] = true
                    task.spawn(function()
                        local store = getStore(DSKeys.Profile.."_UserCache")
                        if store then
                            local ok, name = pcall(function() return store:GetAsync("U_"..userId) end)
                                if ok and name and name ~= "" then
                                    usernameCache[userId]      = name
                                    usernameTimestamps[userId] = os.time()
                                    usernameResolving[userId]  = nil
                                    return
                                end
                            end
                            local ok, name = pcall(function()
                                return Players:GetNameFromUserIdAsync(userId)
                            end)
                            if ok and name and name ~= "" then
                                usernameCache[userId]      = name
                                usernameTimestamps[userId] = os.time()
                                _persistUsername(userId, name)
                            end
                            usernameResolving[userId] = nil
                        end)
                    end
                    
                    function PS.PreloadOnlineUsernames()
                        for _, p in ipairs(Players:GetPlayers()) do
                            usernameCache[p.UserId]      = p.Name
                            usernameTimestamps[p.UserId] = os.time()
                        end
                    end
                    
                    function PS.PreloadUsernames(userIds, callback)
                        if not userIds or #userIds == 0 then
                            if callback then callback({}) end
                            return
                        end
                        task.spawn(function()
                            local resolved = {}
                            local needAPI  = {}
                            
                            for _, uid in ipairs(userIds) do
                                uid = tonumber(uid)
                                if not uid then continue end
                                local p = Players:GetPlayerByUserId(uid)
                                if p then
                                    usernameCache[uid]      = p.Name
                                    usernameTimestamps[uid] = os.time()
                                    resolved[uid]           = p.Name
                                    continue
                                end
                                local cached = usernameCache[uid]
                                if cached and cached ~= "" then
                                    local ts = usernameTimestamps[uid] or 0
                                    if (os.time() - ts) < USERNAME_CACHE_EXPIRY then
                                        resolved[uid] = cached
                                        continue
                                    end
                                end
                                table.insert(needAPI, uid)
                            end
                            
                            for _, uid in ipairs(needAPI) do
                                if usernameResolving[uid] then continue end
                                usernameResolving[uid] = true
                                local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
                                    if ok and name and name ~= "" then
                                        usernameCache[uid]      = name
                                        usernameTimestamps[uid] = os.time()
                                        resolved[uid]           = name
                                        _persistUsername(uid, name)
                                    end
                                    usernameResolving[uid] = nil
                                    task.wait(0.15)
                                end
                                
                                if callback then callback(resolved) end
                            end)
                        end
                        
                        Players.PlayerAdded:Connect(function(p)
                            usernameCache[p.UserId]      = p.Name
                            usernameTimestamps[p.UserId] = os.time()
                            _persistUsername(p.UserId, p.Name)
                        end)
                        
                        Players.PlayerRemoving:Connect(function(p)
                            usernameCache[p.UserId]      = p.Name
                            usernameTimestamps[p.UserId] = os.time()
                            _persistUsername(p.UserId, p.Name)
                        end)
                        
                        for _, p in ipairs(Players:GetPlayers()) do
                            usernameCache[p.UserId]      = p.Name
                            usernameTimestamps[p.UserId] = os.time()
                        end
                        
                        PS.Username = {}
                        function PS.Username.Save(u, n) PS.CacheUsername(u, n) end
                        function PS.Username.Get(u) return PS.GetUsernameFromUserId(u) end
                        
                        -- ============================================================
                        -- 1. PLAYER PROFILE
                        -- ============================================================
                        local PROFILE_STORE = DSKeys.Profile
                        local PROFILE_TMPL  = {
                        CurrentCheckpoint  = "BC",
                        VisitedCheckpoints = { BC = true },
                        TotalDeaths        = 0,
                        FirstJoinTime      = 0,
                        TotalSummit        = 0,
                        _session           = nil,
                        _lastUpdate        = 0,
                        _username          = "",
                        }
                        
                        local profiles = {}
                        PS.Profile = {}
                        
                        function PS.Profile.Load(userId, forceLoad)
                            userId = tonumber(userId)
                            if not userId then return nil end
                            if profiles[userId] then return profiles[userId] end
                            
                            local store  = getStore(PROFILE_STORE)
                            local key    = "Player_"..userId
                            local result = nil
                            
                            for attempt = 1, MAX_RETRIES do
                                if not waitForWriteBudget(15) then task.wait(RETRY_WAIT); continue end
                                local ok, data = safeUpdate(store, key, function(old)
                                    local d = old or deepCopy(PROFILE_TMPL)
                                    reconcile(d, PROFILE_TMPL)
                                    local sess = d._session
                                    local age  = os.time() - (d._lastUpdate or 0)
                                    local dead = sess and age > SESSION_TIMEOUT
                                    local mine = sess and sess[1] == PlaceId and sess[2] == JobId
                                    if sess and not dead and not mine and not forceLoad then return nil end
                                    if d.FirstJoinTime == 0 then d.FirstJoinTime = os.time() end
                                    d._session    = { PlaceId, JobId, os.time() }
                                    d._lastUpdate = os.time()
                                    return d
                                end)
                                if ok and data then result = data; break end
                                if ok and not data then
                                    dWarn("[PS] Session conflict userId:", userId, "attempt", attempt)
                                    task.wait(RETRY_WAIT * attempt)
                                else
                                    task.wait(RETRY_WAIT)
                                end
                            end
                            
                            if not result then
                                dWarn("[PS] GAGAL load profile userId:", userId)
                                return nil
                            end
                            
                            if result._username and result._username ~= "" then
                                if not usernameCache[userId] or usernameCache[userId] == "" then
                                    usernameCache[userId]      = result._username
                                    usernameTimestamps[userId] = os.time()
                                end
                            end
                            
                            local prof = {
                            data   = result,
                            snap   = deepCopy(result),
                            saving = false,
                            store  = store,
                            key    = key,
                            active = true,
                            userId = userId,
                            }
                            profiles[userId] = prof
                            
                            task.spawn(function()
                                while prof.active do
                                    task.wait(AUTO_SAVE_INTERVAL)
                                    if prof.active then PS.Profile.Save(userId, false) end
                                end
                            end)
                            
                            return prof
                        end
                        
                        local function isDirty(prof)
                            local d, s = prof.data, prof.snap
                            return d.CurrentCheckpoint ~= s.CurrentCheckpoint
                            or d.TotalSummit        ~= s.TotalSummit
                            or d.TotalDeaths        ~= s.TotalDeaths
                            or d._username          ~= s._username
                        end
                        
                        function PS.Profile.Save(userId, release)
                            userId = tonumber(userId)
                            local prof = profiles[userId]
                            if not prof or prof.saving then return false end
                            if not isDirty(prof) and not release then return true end
                            if not waitForWriteBudget(10) then return false end
                            
                            prof.saving           = true
                            prof.data._lastUpdate = os.time()
                            
                            local player = Players:GetPlayerByUserId(userId)
                            if player then
                                prof.data._username   = player.Name
                                usernameCache[userId] = player.Name
                            elseif usernameCache[userId] and usernameCache[userId] ~= "" then
                                prof.data._username = usernameCache[userId]
                            end
                            
                            if release then
                                prof.data._session = nil
                            else
                                prof.data._session = { PlaceId, JobId, os.time() }
                            end
                            
                            local ok, err = pcall(function()
                                prof.store:UpdateAsync(prof.key, function() return prof.data end)
                                end)
                                    prof.saving = false
                                    
                                    if ok then
                                        prof.snap = deepCopy(prof.data)
                                        if release then
                                            prof.active      = false
                                            profiles[userId] = nil
                                        end
                                    else
                                        dWarn("[PS] Save error userId:", userId, err)
                                    end
                                    return ok
                                end
                                
                                function PS.Profile.Release(userId) return PS.Profile.Save(tonumber(userId), true) end
                                function PS.Profile.Get(userId)
                                    local prof = profiles[tonumber(userId)]
                                    return prof and prof.data or nil
                                end
                                
                                -- ============================================================
                                -- 2. VIP
                                -- ============================================================
                                local VIP_STORE = DSKeys.VIP
                                local vipCache  = {}
                                local vipSnap   = {}
                                local vipSaving = {}
                                PS.Vip = {}
                                
                                function PS.Vip.Load(userId)
                                    userId = tonumber(userId)
                                    if vipCache[userId] ~= nil then return vipCache[userId] end
                                    local ok, r = safeGet(getStore(VIP_STORE), "VIP_"..userId)
                                    local v = ok and r == true or false
                                    vipCache[userId] = v
                                    vipSnap[userId]  = v
                                    return v
                                end
                                
                                function PS.Vip.Save(userId, isVip)
                                    userId = tonumber(userId)
                                    vipCache[userId] = isVip
                                    if vipSnap[userId] == isVip or vipSaving[userId] then return end
                                    vipSaving[userId] = true
                                    task.spawn(function()
                                        safeSet(getStore(VIP_STORE), "VIP_"..userId, isVip)
                                        vipSnap[userId]   = isVip
                                        vipSaving[userId] = nil
                                    end)
                                end
                                
                                function PS.Vip.SaveOnLeave(userId, isVip)
                                    userId = tonumber(userId)
                                    local changed = vipSnap[userId] ~= isVip
                                    vipCache[userId]  = nil
                                    vipSnap[userId]   = nil
                                    vipSaving[userId] = nil
                                    if not changed then return end
                                    task.spawn(function() safeSet(getStore(VIP_STORE), "VIP_"..userId, isVip) end)
                                    end
                                        
                                        -- ============================================================
                                        -- 3. GLOBAL CONFIG
                                        -- ============================================================
                                        local CFG_STORE = DSKeys.GlobalConfig
                                        local cfgCache  = { SummitValue = 1, ApexValue = 2000, SkipCheckpoint = false }
                                        local cfgSnap   = { SummitValue = 1, ApexValue = 2000, SkipCheckpoint = false }
                                        local cfgSaving = false
                                        local cfgDirty  = false
                                        PS.Config = {}
                                        
                                        function PS.Config.Load()
                                            local ok, r = safeGet(getStore(CFG_STORE), "ConfigValues")
                                            if ok and r then
                                                cfgCache.SummitValue    = r.SummitValue    or 1
                                                cfgCache.ApexValue      = r.ApexValue      or 2000
                                                cfgCache.SkipCheckpoint = r.SkipCheckpoint or false
                                                cfgSnap.SummitValue     = cfgCache.SummitValue
                                                cfgSnap.ApexValue       = cfgCache.ApexValue
                                                cfgSnap.SkipCheckpoint  = cfgCache.SkipCheckpoint
                                            end
                                            return cfgCache
                                        end
                                        
                                        function PS.Config.Save()
                                            if cfgSaving then cfgDirty = true; return end
                                            local noChange = cfgCache.SummitValue    == cfgSnap.SummitValue
                                            and cfgCache.ApexValue      == cfgSnap.ApexValue
                                            and cfgCache.SkipCheckpoint == cfgSnap.SkipCheckpoint
                                            if noChange then return end
                                            cfgSaving = true
                                            task.spawn(function()
                                                safeSet(getStore(CFG_STORE), "ConfigValues", {
                                                SummitValue    = cfgCache.SummitValue,
                                                ApexValue      = cfgCache.ApexValue,
                                                SkipCheckpoint = cfgCache.SkipCheckpoint,
                                                LastUpdate     = os.time(),
                                                })
                                                cfgSnap.SummitValue    = cfgCache.SummitValue
                                                cfgSnap.ApexValue      = cfgCache.ApexValue
                                                cfgSnap.SkipCheckpoint = cfgCache.SkipCheckpoint
                                                cfgSaving = false
                                                if cfgDirty then cfgDirty = false; PS.Config.Save() end
                                            end)
                                        end
                                        
                                        function PS.Config.Set(k, v) cfgCache[k] = v; PS.Config.Save() end
                                        function PS.Config.Get(k) return cfgCache[k] end
                                        
                                        -- ============================================================
                                        -- 4. DYNAMIC ROLES
                                        -- ============================================================
                                        local ROLES_STORE    = DSKeys.DynamicRoles
                                        local rolesCache     = {}
                                        local rolesPending   = {}
                                        local rolesDebounce  = {}
                                        local rolesLastWrite = {}
                                        PS.Roles = {}
                                        
                                        function PS.Roles.Load(userId)
                                            userId = tonumber(userId)
                                            if rolesCache[userId] ~= nil then
                                                return rolesCache[userId] ~= false and rolesCache[userId] or nil
                                            end
                                            local ok, d = safeGet(getStore(ROLES_STORE), "ROLE_"..userId)
                                            rolesCache[userId]     = (ok and d) or false
                                            rolesLastWrite[userId] = tick()
                                            return (ok and d) or nil
                                        end
                                        
                                        function PS.Roles.Save(userId, roleData)
                                            userId = tonumber(userId)
                                            rolesCache[userId]   = roleData or false
                                            rolesPending[userId] = roleData
                                            if rolesDebounce[userId] then return end
                                            rolesDebounce[userId] = true
                                            task.spawn(function()
                                                local elapsed = rolesLastWrite[userId] and (tick() - rolesLastWrite[userId]) or ROLES_COOLDOWN
                                                local w = math.max(0, ROLES_COOLDOWN - elapsed)
                                                if w > 0 then task.wait(w) end
                                                local toSave = rolesPending[userId]
                                                rolesPending[userId]  = nil
                                                rolesDebounce[userId] = nil
                                                local store = getStore(ROLES_STORE)
                                                if toSave then
                                                    safeSet(store, "ROLE_"..userId, toSave)
                                                else
                                                    pcall(function() store:RemoveAsync("ROLE_"..userId) end)
                                                    end
                                                        rolesLastWrite[userId] = tick()
                                                    end)
                                                end
                                                
                                                function PS.Roles.ForceFlush(userId)
                                                    userId = tonumber(userId)
                                                    local toSave = rolesPending[userId]
                                                    rolesDebounce[userId] = nil
                                                    rolesPending[userId]  = nil
                                                    local data = toSave
                                                    if data == nil then
                                                        local c = rolesCache[userId]
                                                        data = (c and c ~= false) and c or nil
                                                    end
                                                    task.spawn(function()
                                                        local store = getStore(ROLES_STORE)
                                                        if data then
                                                            safeSet(store, "ROLE_"..userId, data)
                                                        else
                                                            pcall(function() store:RemoveAsync("ROLE_"..userId) end)
                                                            end
                                                                rolesLastWrite[userId] = tick()
                                                            end)
                                                        end
                                                        
                                                        function PS.Roles.FlushOnLeave(userId)
                                                            userId = tonumber(userId)
                                                            local toSave = rolesPending[userId]
                                                            rolesCache[userId]    = nil
                                                            rolesPending[userId]  = nil
                                                            rolesDebounce[userId] = nil
                                                            if toSave == nil then return end
                                                            task.spawn(function()
                                                                local store = getStore(ROLES_STORE)
                                                                if toSave then
                                                                    safeSet(store, "ROLE_"..userId, toSave)
                                                                else
                                                                    pcall(function() store:RemoveAsync("ROLE_"..userId) end)
                                                                    end
                                                                    end)
                                                                    end
                                                                        
                                                                        -- ============================================================
                                                                        -- 5. VERIFIED
                                                                        -- ============================================================
                                                                        local VERIFIED_STORE = DSKeys.VerifiedDynamic
                                                                        local verifiedCache  = nil
                                                                        local verifiedSaving = false
                                                                        local verifiedDirty  = false
                                                                        PS.Verified = {}
                                                                        
                                                                        function PS.Verified.Load()
                                                                            if verifiedCache then return verifiedCache end
                                                                            local ok, d = safeGet(getStore(VERIFIED_STORE), "dynamic_list")
                                                                            verifiedCache = (ok and d) or {}
                                                                            return verifiedCache
                                                                        end
                                                                        
                                                                        function PS.Verified.Save()
                                                                            if verifiedSaving then verifiedDirty = true; return end
                                                                            verifiedSaving = true
                                                                            task.spawn(function()
                                                                                safeSet(getStore(VERIFIED_STORE), "dynamic_list", verifiedCache or {})
                                                                                verifiedSaving = false
                                                                                if verifiedDirty then verifiedDirty = false; PS.Verified.Save() end
                                                                            end)
                                                                        end
                                                                        
                                                                        function PS.Verified.Add(username, addedBy, reason)
                                                                            if not username or username == "" then return false end
                                                                            local list = PS.Verified.Load()
                                                                            local low  = string.lower(username)
                                                                            for _, e in ipairs(list) do
                                                                                if string.lower(e.username) == low then return false end
                                                                            end
                                                                            table.insert(list, {
                                                                            username = low,
                                                                            addedBy  = tostring(addedBy or "System"),
                                                                            reason   = tostring(reason or ""),
                                                                            addedAt  = os.time(),
                                                                            })
                                                                            PS.Verified.Save()
                                                                            return true
                                                                        end
                                                                        
                                                                        function PS.Verified.Remove(username)
                                                                            if not username or username == "" then return false end
                                                                            local list  = PS.Verified.Load()
                                                                            local low   = string.lower(username)
                                                                            local new   = {}
                                                                            local found = false
                                                                            for _, e in ipairs(list) do
                                                                                if string.lower(e.username) == low then
                                                                                    found = true
                                                                                else
                                                                                    table.insert(new, e)
                                                                                end
                                                                            end
                                                                            if found then verifiedCache = new; PS.Verified.Save() end
                                                                            return found
                                                                        end
                                                                        
                                                                        function PS.Verified.Check(username)
                                                                            if not username or username == "" then return false end
                                                                            local list = PS.Verified.Load()
                                                                            local low  = string.lower(username)
                                                                            for _, e in ipairs(list) do
                                                                                if string.lower(e.username) == low then return true end
                                                                            end
                                                                            return false
                                                                        end
                                                                        
                                                                        -- ============================================================
                                                                        -- 6. SPEEDRUN
                                                                        -- ============================================================
                                                                        local SR_STORE    = DSKeys.SpeedRun
                                                                        local SR_LB_STORE = DSKeys.SpeedRunGlobalLB
                                                                        local srCache     = {}
                                                                        local srSaving    = {}
                                                                        PS.SpeedRun = {}
                                                                        
                                                                        function PS.SpeedRun.Load(userId)
                                                                            userId = tonumber(userId)
                                                                            if srCache[userId] then return srCache[userId] end
                                                                            local ok, d = safeGet(getStore(SR_STORE), "Player_"..userId)
                                                                            local data = (ok and d) or { BestTime = 0, Username = "" }
                                                                            srCache[userId] = data
                                                                            if data.Username and data.Username ~= "" then
                                                                                if not usernameCache[userId] or usernameCache[userId] == "" then
                                                                                    usernameCache[userId]      = data.Username
                                                                                    usernameTimestamps[userId] = os.time()
                                                                                end
                                                                            end
                                                                            return data
                                                                        end
                                                                        
                                                                        function PS.SpeedRun.Save(userId, username, timeSeconds, forceUpdate)
                                                                            userId = tonumber(userId)
                                                                            local cur = PS.SpeedRun.Load(userId)
                                                                            if not forceUpdate and cur.BestTime > 0 and timeSeconds >= cur.BestTime then return false end
                                                                            if srSaving[userId] then return false end
                                                                            srSaving[userId] = true
                                                                            PS.CacheUsername(userId, username)
                                                                            local newData = {
                                                                            BestTime    = timeSeconds,
                                                                            Username    = tostring(username or ""),
                                                                            LastUpdated = os.time(),
                                                                            }
                                                                            srCache[userId] = newData
                                                                            task.spawn(function()
                                                                                safeSet(getStore(SR_STORE), "Player_"..userId, newData)
                                                                                safeSet(getStore(SR_LB_STORE, true), tostring(userId), math.floor(timeSeconds * 1000))
                                                                                srSaving[userId] = nil
                                                                            end)
                                                                            return true
                                                                        end
                                                                        
                                                                        function PS.SpeedRun.Reset(userId)
                                                                            userId = tonumber(userId)
                                                                            srCache[userId] = { BestTime = 0, Username = "" }
                                                                            task.spawn(function()
                                                                                pcall(function() getStore(SR_STORE):RemoveAsync("Player_"..userId) end)
                                                                                    pcall(function() getStore(SR_LB_STORE, true):RemoveAsync(tostring(userId)) end)
                                                                                    end)
                                                                                        return true
                                                                                    end
                                                                                    
                                                                                    function PS.SpeedRun.GetLeaderboard(max)
                                                                                        max = max or 100
                                                                                        local store = getStore(SR_LB_STORE, true)
                                                                                        local ok, pages = pcall(function() return store:GetSortedAsync(true, max) end)
                                                                                            if not ok or not pages then return {} end
                                                                                            local ok2, cur = pcall(function() return pages:GetCurrentPage() end)
                                                                                                if not ok2 then return {} end
                                                                                                local list = {}
                                                                                                for rank, entry in ipairs(cur) do
                                                                                                    local uid  = tonumber(entry.key)
                                                                                                    local secs = entry.value / 1000
                                                                                                    if not uid or secs <= 0 then continue end
                                                                                                    local name = PS.GetUsernameFromUserId(uid)
                                                                                                    if not name or name == "" then
                                                                                                        local c = srCache[uid]
                                                                                                        if c and c.Username and c.Username ~= "" then
                                                                                                            name                    = c.Username
                                                                                                            usernameCache[uid]      = name
                                                                                                            usernameTimestamps[uid] = os.time()
                                                                                                        end
                                                                                                    end
                                                                                                    if not name or name == "" then
                                                                                                        name = "Player_"..uid
                                                                                                        PS.ResolveUsernameBackfill(uid)
                                                                                                    end
                                                                                                    table.insert(list, { Rank = rank, UserId = uid, Username = name, BestTime = secs })
                                                                                                end
                                                                                                return list
                                                                                            end
                                                                                            
                                                                                            function PS.SpeedRun.GetCached(userId)
                                                                                                local c = srCache[tonumber(userId)]
                                                                                                return c and c.BestTime or 0
                                                                                            end
                                                                                            
                                                                                            -- ============================================================
                                                                                            -- 7. GLOBAL SUMMIT LEADERBOARD
                                                                                            -- ============================================================
                                                                                            local GLBL_STORE     = "TopSummit"
                                                                                            local glbCache       = {}
                                                                                            local glbLastRefresh = 0
                                                                                            local glbLastUpdate  = {}
                                                                                            local GLB_COOLDOWN   = 10
                                                                                            local GLB_CACHE_TIME = 30
                                                                                            
                                                                                            PS.GlobalLB = {}
                                                                                            
                                                                                            -- Update: hanya naik (math.max) — untuk summit normal
                                                                                            function PS.GlobalLB.Update(userId, username, total)
                                                                                                userId = tonumber(userId)
                                                                                                local now = os.time()
                                                                                                if (now - (glbLastUpdate[userId] or 0)) < GLB_COOLDOWN then return false end
                                                                                                glbLastUpdate[userId] = now
                                                                                                if username and username ~= "" then PS.CacheUsername(userId, username) end
                                                                                                
                                                                                                task.spawn(function()
                                                                                                    if not waitForWriteBudget(10) then return end
                                                                                                    local store = getStore(GLBL_STORE, true)
                                                                                                    local key   = "Summit"..userId
                                                                                                    pcall(function()
                                                                                                        store:UpdateAsync(key, function(current)
                                                                                                            local cur    = current or 0
                                                                                                            local newVal = math.max(cur, math.floor(total))
                                                                                                            return (newVal ~= cur) and newVal or nil
                                                                                                        end)
                                                                                                    end)
                                                                                                    for _, e in ipairs(glbCache) do
                                                                                                        if e.UserId == userId then
                                                                                                            e.Summit   = total
                                                                                                            e.Username = tostring(username or e.Username)
                                                                                                            break
                                                                                                        end
                                                                                                    end
                                                                                                end)
                                                                                                return true
                                                                                            end
                                                                                            
                                                                                            -- Set: tulis nilai PERSIS ke DS — untuk reset/koreksi admin
                                                                                            -- Nilai 0 atau negatif = hapus entry dari OrderedDataStore
                                                                                            function PS.GlobalLB.Set(userId, total)
                                                                                                userId = tonumber(userId)
                                                                                                if not userId then return false end
                                                                                                total  = math.floor(tonumber(total) or 0)
                                                                                                
                                                                                                -- Update cache in-memory dulu (instant)
                                                                                                if total <= 0 then
                                                                                                    for i, e in ipairs(glbCache) do
                                                                                                        if e.UserId == userId then
                                                                                                            table.remove(glbCache, i)
                                                                                                            break
                                                                                                        end
                                                                                                    end
                                                                                                else
                                                                                                    local found = false
                                                                                                    for _, e in ipairs(glbCache) do
                                                                                                        if e.UserId == userId then
                                                                                                            e.Summit = total; found = true; break
                                                                                                        end
                                                                                                    end
                                                                                                    if not found then
                                                                                                        local name = PS.GetUsernameFromUserId(userId) or ("Player_"..userId)
                                                                                                        table.insert(glbCache, { UserId = userId, Username = name, Summit = total })
                                                                                                    end
                                                                                                end
                                                                                                
                                                                                                -- Tulis ke DS
                                                                                                task.spawn(function()
                                                                                                    if not waitForWriteBudget(10) then return end
                                                                                                    local store = getStore(GLBL_STORE, true)
                                                                                                    local key   = "Summit"..userId
                                                                                                    if total <= 0 then
                                                                                                        -- Hapus entry dari OrderedDataStore
                                                                                                        pcall(function() store:RemoveAsync(key) end)
                                                                                                        else
                                                                                                            pcall(function() store:SetAsync(key, total) end)
                                                                                                            end
                                                                                                            end)
                                                                                                                return true
                                                                                                            end
                                                                                                            
                                                                                                            -- Reset: hapus entry player dari GlobalLB sepenuhnya
                                                                                                            function PS.GlobalLB.Reset(userId)
                                                                                                                return PS.GlobalLB.Set(userId, 0)
                                                                                                            end
                                                                                                            
                                                                                                            -- ForceSyncOnlinePlayers — pakai nilai EXACT dari leaderstats (bukan math.max)
                                                                                                            -- Dipanggil saat server init dan auto-sync
                                                                                                            -- Kalau summit=0 → hapus entry (Remove) bukan tulis 0
                                                                                                            function PS.GlobalLB.ForceSyncOnline()
                                                                                                                local writeBudget = getWriteBudget()
                                                                                                                if writeBudget < MIN_WRITE_BUDGET then return 0 end
                                                                                                                
                                                                                                                local syncCount = 0
                                                                                                                local maxSync   = math.max(1, math.min(5, math.floor(writeBudget / 2)))
                                                                                                                local store     = getStore(GLBL_STORE, true)
                                                                                                                
                                                                                                                for _, player in ipairs(Players:GetPlayers()) do
                                                                                                                    if syncCount >= maxSync then break end
                                                                                                                    local ls    = player:FindFirstChild("leaderstats")
                                                                                                                    local sv    = ls and ls:FindFirstChild("Summit")
                                                                                                                    local total = sv and (tonumber(sv.Value) or 0) or 0
                                                                                                                    local key   = "Summit"..player.UserId
                                                                                                                    
                                                                                                                    if total > 0 then
                                                                                                                        local ok = pcall(function()
                                                                                                                            store:UpdateAsync(key, function(current)
                                                                                                                                local cur    = current or 0
                                                                                                                                local newVal = math.max(cur, total)
                                                                                                                                return (newVal ~= cur) and newVal or nil
                                                                                                                            end)
                                                                                                                        end)
                                                                                                                        if ok then syncCount = syncCount + 1 end
                                                                                                                    else
                                                                                                                        -- Summit 0 → hapus entry lama supaya tidak muncul di LB
                                                                                                                        pcall(function() store:RemoveAsync(key) end)
                                                                                                                            syncCount = syncCount + 1
                                                                                                                        end
                                                                                                                        task.wait(0.2)
                                                                                                                    end
                                                                                                                    return syncCount
                                                                                                                end
                                                                                                                
                                                                                                                function PS.GlobalLB.Get(max)
                                                                                                                    max = max or 100
                                                                                                                    local now = os.clock()
                                                                                                                    if (now - glbLastRefresh) < GLB_CACHE_TIME and #glbCache > 0 then
                                                                                                                        return true, glbCache
                                                                                                                    end
                                                                                                                    if getReadBudget() < MIN_READ_BUDGET then return false, glbCache end
                                                                                                                    
                                                                                                                    local store = getStore(GLBL_STORE, true)
                                                                                                                    local ok, pages = pcall(function() return store:GetSortedAsync(false, max) end)
                                                                                                                        if not ok then return false, glbCache end
                                                                                                                        local ok2, cur = pcall(function() return pages:GetCurrentPage() end)
                                                                                                                            if not ok2 then return false, glbCache end
                                                                                                                            
                                                                                                                            local data = {}
                                                                                                                            for rank, entry in ipairs(cur) do
                                                                                                                                local uid = tonumber(string.match(tostring(entry.key), "^Summit(%d+)$"))
                                                                                                                                if uid then
                                                                                                                                    local name = PS.GetUsernameFromUserId(uid)
                                                                                                                                    if not name or name == "" then
                                                                                                                                        name = "Player_"..uid
                                                                                                                                        PS.ResolveUsernameBackfill(uid)
                                                                                                                                    end
                                                                                                                                    table.insert(data, { Rank = rank, UserId = uid, Username = name, Summit = entry.value })
                                                                                                                                end
                                                                                                                            end
                                                                                                                            glbCache       = data
                                                                                                                            glbLastRefresh = now
                                                                                                                            return true, data
                                                                                                                        end
                                                                                                                        
                                                                                                                        -- ============================================================
                                                                                                                        -- BIND TO CLOSE
                                                                                                                        -- ============================================================
                                                                                                                        game:BindToClose(function()
                                                                                                                            for userId in pairs(profiles) do
                                                                                                                                PS.Profile.Save(userId, true)
                                                                                                                            end
                                                                                                                            
                                                                                                                            for userId, isVip in pairs(vipCache) do
                                                                                                                                if vipSnap[userId] ~= isVip then
                                                                                                                                    pcall(function() getStore(VIP_STORE):SetAsync("VIP_"..userId, isVip) end)
                                                                                                                                    end
                                                                                                                                    end
                                                                                                                                        
                                                                                                                                        for userId, toSave in pairs(rolesPending) do
                                                                                                                                            local store = getStore(ROLES_STORE)
                                                                                                                                            if toSave then
                                                                                                                                                pcall(function() store:SetAsync("ROLE_"..userId, toSave) end)
                                                                                                                                                else
                                                                                                                                                    pcall(function() store:RemoveAsync("ROLE_"..userId) end)
                                                                                                                                                    end
                                                                                                                                                    end
                                                                                                                                                        
                                                                                                                                                        if cfgCache.SummitValue    ~= cfgSnap.SummitValue
                                                                                                                                                            or cfgCache.ApexValue      ~= cfgSnap.ApexValue
                                                                                                                                                            or cfgCache.SkipCheckpoint ~= cfgSnap.SkipCheckpoint then
                                                                                                                                                            pcall(function()
                                                                                                                                                                getStore(CFG_STORE):SetAsync("ConfigValues", {
                                                                                                                                                                SummitValue    = cfgCache.SummitValue,
                                                                                                                                                                ApexValue      = cfgCache.ApexValue,
                                                                                                                                                                SkipCheckpoint = cfgCache.SkipCheckpoint,
                                                                                                                                                                LastUpdate     = os.time(),
                                                                                                                                                                })
                                                                                                                                                            end)
                                                                                                                                                        end
                                                                                                                                                        
                                                                                                                                                        task.wait(2)
                                                                                                                                                    end)
                                                                                                                                                    
                                                                                                                                                    return PS

