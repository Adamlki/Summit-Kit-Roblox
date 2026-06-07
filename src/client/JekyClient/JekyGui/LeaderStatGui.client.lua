-- StarterPlayerScripts / JekyListBoard  (LocalScript)
 
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")   -- FIX: untuk block leaderboard Roblox
local LocalPlayer       = Players.LocalPlayer

local DEBUG_MODE = false
local function debugWarn(msg)
    if DEBUG_MODE then warn(msg) end
end

-- ============================================================
-- GUI REFERENCES (Dengan Timeout Anti-Error)
-- ============================================================
local PlayerGui       = LocalPlayer:WaitForChild("PlayerGui")

-- Tambahkan angka 10 (artinya script bersedia menunggu maksimal 10 detik)
local ListGui         = PlayerGui:WaitForChild("ListGui", 999)
local IsiGui          = PlayerGui:WaitForChild("IsiGui", 999)

-- Cegah error lanjutan jika UI ternyata benar-benar hilang/terhapus
if not ListGui or not IsiGui then
	debugWarn("[LeaderStatGui] ListGui atau IsiGui tidak ditemukan di PlayerGui!")
	return -- Hentikan script agar tidak error beruntun
end

local ListTopBarKanan = ListGui:WaitForChild("ListTopBarKanan", 999)
local ListButton      = ListTopBarKanan:WaitForChild("ListButton", 999)
local ListPlayer      = IsiGui:WaitForChild("ListPlayer", 999)
local ScrollingFrame  = ListPlayer:WaitForChild("ScrollingFrame", 999)
local Template        = ScrollingFrame:WaitForChild("Frame", 999)

Template.Visible = false
 
-- ============================================================
-- DISABLE LEADERBOARD ROBLOX & USER INPUT SERVICE
-- ============================================================
local UserInputService = game:GetService("UserInputService")

local function disableRobloxLeaderboard()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
    end)
end
 
-- Matikan leaderboard bawaan Roblox secara permanen
disableRobloxLeaderboard()

-- Pastikan selalu mati (antisipasi jika Roblox otomatis menyalakannya kembali)
task.spawn(function()
    while task.wait(2) do
        disableRobloxLeaderboard()
    end
end)
 
-- ============================================================
-- REMOTE EVENTS
-- ============================================================
local JekyEvents    = ReplicatedStorage:WaitForChild("JekyEvents", 15)
local SR_UpdateMemory = JekyEvents and JekyEvents:WaitForChild("SR_UpdateMemory", 999) or nil
local SR_Finish       = JekyEvents and JekyEvents:WaitForChild("SR_Finish", 999) or nil
 
-- ============================================================
-- BESTTIME CACHE
-- ============================================================
local bestTimeCache = {}
 
local function formatBestTime(seconds)
    if not seconds or seconds <= 0 then return "N/A" end
    local m  = math.floor(seconds / 60)
    local s  = math.floor(seconds % 60)
    local ms = math.floor((seconds % 1) * 1000)
    return string.format("%02d:%02d.%03d", m, s, ms)
end
 
if SR_UpdateMemory then
    SR_UpdateMemory.OnClientEvent:Connect(function(bestTimeSeconds)
        local uid = LocalPlayer.UserId
        if bestTimeSeconds and bestTimeSeconds > 0 then
            bestTimeCache[uid] = formatBestTime(bestTimeSeconds)
        else
            local ls  = LocalPlayer:FindFirstChild("leaderstats")
            local btv = ls and ls:FindFirstChild("BestTime")
            if btv and btv.Value ~= "" and btv.Value ~= "N/A" and btv.Value ~= "nil" then
                bestTimeCache[uid] = btv.Value
            else
                bestTimeCache[uid] = "N/A"
            end
        end
        local frame = playerFrames and playerFrames[uid]
        if frame then
            local btLabel = frame:FindFirstChild("BestTimeLabel")
            if btLabel then btLabel.Text = bestTimeCache[uid] end
        end
    end)
end
 
if SR_Finish then
    SR_Finish.OnClientEvent:Connect(function(elapsedTime, isNewRecord)
        if not isNewRecord then return end
        local uid = LocalPlayer.UserId
        if elapsedTime and elapsedTime > 0 then
            bestTimeCache[uid] = formatBestTime(elapsedTime)
        end
        task.delay(0.2, function()
            local ls  = LocalPlayer:FindFirstChild("leaderstats")
            local btv = ls and ls:FindFirstChild("BestTime")
            if btv and btv.Value ~= "" and btv.Value ~= "N/A" and btv.Value ~= "nil" then
                bestTimeCache[uid] = btv.Value
            end
            local frame = playerFrames and playerFrames[uid]
            if frame then
                local btLabel = frame:FindFirstChild("BestTimeLabel")
                if btLabel then btLabel.Text = bestTimeCache[uid] end
            end
        end)
    end)
end
 
-- ============================================================
-- ROLE CONFIG
-- ============================================================
local JekyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("JekyConfig"))
local ROLE_PRIORITY = {}
for i, name in ipairs(JekyConfig.RoleOrder) do ROLE_PRIORITY[name] = i end
 
-- ============================================================
-- PALETTE
-- ============================================================
local PALETTE = {
Color3.fromRGB(100, 210, 255), Color3.fromRGB( 80, 255, 180),
Color3.fromRGB(255, 220,  90), Color3.fromRGB(190, 110, 255),
Color3.fromRGB(110, 255, 110), Color3.fromRGB(255, 185,  90),
Color3.fromRGB(110, 185, 255), Color3.fromRGB(255, 110, 210),
Color3.fromRGB(200, 255, 110), Color3.fromRGB(255, 200, 160),
Color3.fromRGB(160, 255, 230), Color3.fromRGB(230, 230, 110),
Color3.fromRGB(110, 230, 230), Color3.fromRGB(230, 110, 255),
Color3.fromRGB(255, 230, 200),
}
local playerColors = {}
local nextColorIdx = 0
 
local function getPlayerColor(player)
    if not playerColors[player.UserId] then
        nextColorIdx = (nextColorIdx % #PALETTE) + 1
        playerColors[player.UserId] = PALETTE[nextColorIdx]
    end
    return playerColors[player.UserId]
end
 
-- ============================================================
-- STAT READERS
-- ============================================================
local function tContains(t, v)
    for _, x in ipairs(t or {}) do if x == v then return true end end
    return false
end
 
local function getPlayerRole(player)
    local dyn = player:GetAttribute("DynamicRole")
    if dyn and dyn ~= "" then return dyn end
    for _, name in ipairs(JekyConfig.RoleOrder) do
        local rule = JekyConfig.RoleRules[name]
        if rule then
            if tContains(rule.UserIds,   player.UserId) then return name end
            if tContains(rule.Usernames, player.Name)   then return name end
        end
    end
    return nil
end
 
local function getSummit(player)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return 0 end
    local v = ls:FindFirstChild("Summit")
    return v and (tonumber(v.Value) or 0) or 0
end
 
local function getCheckpoint(player)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return "BC" end
    local v = ls:FindFirstChild("Checkpoint")
    return v and tostring(v.Value) or "BC"
end
 
local function getBestTime(player)
    local uid = player.UserId
    if bestTimeCache[uid] and bestTimeCache[uid] ~= "" then
        return bestTimeCache[uid]
    end
    local ls  = player:FindFirstChild("leaderstats")
    local btv = ls and ls:FindFirstChild("BestTime")
    if btv then
        local v = tostring(btv.Value)
        if v ~= "" and v ~= "nil" and v ~= "N/A" then
            bestTimeCache[uid] = v
            return v
        end
    end
    return "N/A"
end
 
-- ============================================================
-- SORT
-- ============================================================
local function sortedPlayers()
    local list = Players:GetPlayers()
    table.sort(list, function(a, b)
        local ra = getPlayerRole(a)
        local rb = getPlayerRole(b)
        local pa = ra and (ROLE_PRIORITY[ra] or #JekyConfig.RoleOrder + 1) or (#JekyConfig.RoleOrder + 1)
        local pb = rb and (ROLE_PRIORITY[rb] or #JekyConfig.RoleOrder + 1) or (#JekyConfig.RoleOrder + 1)
        if pa ~= pb then return pa < pb end
        return getSummit(a) > getSummit(b)
    end)
    return list
end
 
-- ============================================================
-- CANVAS AUTO-RESIZE
-- ============================================================
if ScrollingFrame then
    ScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
end
 
-- ============================================================
-- FRAME POOL
-- ============================================================
playerFrames = {}
 
local function destroyFrame(userId)
    if playerFrames[userId] then
        playerFrames[userId]:Destroy()
        playerFrames[userId] = nil
    end
end
 
local function destroyAllFrames()
    for uid in pairs(playerFrames) do
        if playerFrames[uid] then
            playerFrames[uid]:Destroy()
        end
    end
    playerFrames = {}
end
 
-- ============================================================
-- ANIMASI
-- ============================================================
local function animateIn(frame, originalPos)
    frame.Position = UDim2.new(
    originalPos.X.Scale + 1.2,
    originalPos.X.Offset,
    originalPos.Y.Scale,
    originalPos.Y.Offset
    )
    TweenService:Create(
    frame,
    TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
    { Position = originalPos }
    ):Play()
end
 
-- ============================================================
-- BUILD ENTRY
-- ============================================================
local function buildEntry(player, order, doAnimate)
    destroyFrame(player.UserId)
 
    local frame = Template:Clone()
    frame.Name        = "Entry_" .. player.UserId
    frame.Visible     = true
    frame.LayoutOrder = order
 
    local originalPos = frame.Position
    local color       = getPlayerColor(player)
 
    local cpLabel = frame:FindFirstChild("CpLabel")
    if cpLabel then
        cpLabel.Text       = getCheckpoint(player)
        cpLabel.TextColor3 = color
    end
 
    local nameLabel = frame:FindFirstChild("NameLabel")
    if nameLabel then
        nameLabel.Text       = player.DisplayName
        nameLabel.TextColor3 = color
    end
 
    local summitLabel = frame:FindFirstChild("SummitLabel")
    if summitLabel then
        summitLabel.Text       = tostring(getSummit(player))
        summitLabel.TextColor3 = color
    end
 
    local btLabel = frame:FindFirstChild("BestTimeLabel")
    if btLabel then
        btLabel.Text       = getBestTime(player)
        btLabel.TextColor3 = color
    end
 
    frame.Parent = ScrollingFrame
    playerFrames[player.UserId] = frame
 
    if doAnimate then
        animateIn(frame, originalPos)
    end
end
 
-- ============================================================
-- REBUILD / UPDATE
-- ============================================================
local function rebuildAll(doAnimate)
    destroyAllFrames()
    local sorted = sortedPlayers()
    for i, player in ipairs(sorted) do
        buildEntry(player, i, doAnimate)
    end
end
 
local function updateEntry(player)
    local frame = playerFrames[player.UserId]
    if not frame then return end
 
    local cpLabel = frame:FindFirstChild("CpLabel")
    if cpLabel then cpLabel.Text = getCheckpoint(player) end
 
    local nameLabel = frame:FindFirstChild("NameLabel")
    if nameLabel then nameLabel.Text = player.DisplayName end
 
    local summitLabel = frame:FindFirstChild("SummitLabel")
    if summitLabel then summitLabel.Text = tostring(getSummit(player)) end
 
    local btLabel = frame:FindFirstChild("BestTimeLabel")
    if btLabel then btLabel.Text = getBestTime(player) end
end
 
-- ============================================================
-- LEADERSTAT WATCHERS
-- ============================================================
local statConns  = {}
local needResort = false
 
local function scheduleResort()
    if needResort then return end
    needResort = true
    task.defer(function()
        needResort = false
        if ListPlayer.Visible then rebuildAll(false) end
    end)
end
 
local function hookLeaderstats(player, ls)
    local uid = player.UserId
    for _, stat in ipairs(ls:GetChildren()) do
        local conn = stat:GetPropertyChangedSignal("Value"):Connect(function()
            if not ListPlayer.Visible then return end
            if stat.Name == "BestTime" then
                local v = tostring(stat.Value)
                if v ~= "" and v ~= "nil" and v ~= "N/A" then
                    bestTimeCache[player.UserId] = v
                end
            end
            updateEntry(player)
            if stat.Name == "Summit" then scheduleResort() end
        end)
        table.insert(statConns[uid], conn)
    end
 
    local addConn = ls.ChildAdded:Connect(function(stat)
        if stat.Name == "BestTime" then
            task.defer(function()
                local v = tostring(stat.Value)
                if v ~= "" and v ~= "nil" and v ~= "N/A" then
                    bestTimeCache[player.UserId] = v
                end
                if ListPlayer.Visible then updateEntry(player) end
            end)
        elseif ListPlayer.Visible then
            updateEntry(player)
            if stat.Name == "Summit" then scheduleResort() end
        end
 
        local conn = stat:GetPropertyChangedSignal("Value"):Connect(function()
            if not ListPlayer.Visible then return end
            if stat.Name == "BestTime" then
                local v = tostring(stat.Value)
                if v ~= "" and v ~= "nil" and v ~= "N/A" then
                    bestTimeCache[player.UserId] = v
                end
            end
            updateEntry(player)
            if stat.Name == "Summit" then scheduleResort() end
        end)
        table.insert(statConns[uid], conn)
    end)
    table.insert(statConns[uid], addConn)
end
 
local function watchPlayer(player)
    local uid = player.UserId
    statConns[uid] = {}
 
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        hookLeaderstats(player, ls)
    end
 
    local childConn = player.ChildAdded:Connect(function(child)
        if child.Name == "leaderstats" then
            hookLeaderstats(player, child)
        end
    end)
    table.insert(statConns[uid], childConn)
 
    local roleConn = player:GetAttributeChangedSignal("DynamicRole"):Connect(function()
        if ListPlayer.Visible then scheduleResort() end
    end)
    table.insert(statConns[uid], roleConn)
end
 
local function unwatchPlayer(player)
    local uid = player.UserId
    if statConns[uid] then
        for _, conn in ipairs(statConns[uid]) do conn:Disconnect() end
        statConns[uid] = nil
    end
    playerColors[uid] = nil
    destroyFrame(uid)
end
 
for _, player in ipairs(Players:GetPlayers()) do
    watchPlayer(player)
end
 
Players.PlayerAdded:Connect(function(player)
    watchPlayer(player)
    if ListPlayer.Visible then scheduleResort() end
end)
 
Players.PlayerRemoving:Connect(function(player)
    unwatchPlayer(player)
    if ListPlayer.Visible then
        task.defer(function()
            if ListPlayer.Visible then rebuildAll(false) end
        end)
    end
end)
 
-- ============================================================
-- TOGGLE
-- ============================================================
local isOpen = false
 
local function openList()
    isOpen = true
    ListPlayer.Visible = true
    rebuildAll(true)
end
 
local function closeList()
    isOpen = false
    ListPlayer.Visible = false
end
 
ListButton.MouseButton1Click:Connect(function()
    if isOpen then closeList() else openList() end
end)

-- Buka/Tutup menggunakan tombol Tab
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- Jika player sedang mengetik di chat, abaikan input
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.Tab then
        if isOpen then 
            closeList() 
        else 
            openList() 
        end
    end
end)
 
-- ============================================================
-- SEMUA TextButton LAIN → TUTUP LIST
-- ============================================================
local function bindClose(btn)
    if btn ~= ListButton then
        btn.MouseButton1Click:Connect(closeList)
    end
end
 
for _, desc in ipairs(ListGui:GetDescendants()) do
    if desc:IsA("TextButton") then bindClose(desc) end
end
 
ListGui.DescendantAdded:Connect(function(desc)
    if desc:IsA("TextButton") then
        task.defer(bindClose, desc)
    end
end)

