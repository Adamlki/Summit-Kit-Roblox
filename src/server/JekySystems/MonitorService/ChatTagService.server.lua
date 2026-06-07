-- Script: ServerScriptService/ChatTag_Server
-- FIXED VERSION: timing DynamicRole load, normalisasi role name, debug print

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JekyTitle = require(ServerStorage:WaitForChild("JekyModules"):WaitForChild("JekyTitle"))

-- Buat RemoteFunction & RemoteEvent
local GetPlayerRolesRF = Instance.new("RemoteFunction")
GetPlayerRolesRF.Name = "ChatTag_GetRoles"
GetPlayerRolesRF.Parent = ReplicatedStorage

local RoleUpdatedRE = Instance.new("RemoteEvent")
RoleUpdatedRE.Name = "ChatTag_RoleUpdated"
RoleUpdatedRE.Parent = ReplicatedStorage

local ROLE_PRIORITY = {
	Owner     = 1,
	Developer = 2,
	HeadAdmin = 3,
	Admin     = 4,
	Moderator = 5,
	Streamer  = 6,
	VIP       = 7,
	Community = 8,
}

-- ✅ FIX: Normalisasi kapitalisasi role name agar cocok dengan ROLE_COLORS di client
local function normalizeRoleName(rawName)
	if not rawName or rawName == "" then return nil end
	-- Exact match dulu
	if ROLE_PRIORITY[rawName] then return rawName end
	-- Coba kapitalisasi huruf pertama saja
	local capitalized = rawName:sub(1, 1):upper() .. rawName:sub(2):lower()
	if ROLE_PRIORITY[capitalized] then return capitalized end
	-- Return as-is jika tidak cocok
	return rawName
end

local function getPlayerRoles(player)
	local roles = {}

	-- Ambil role dari JekyTitle
	local rawRoleTitle = JekyTitle.GetRoleTitle(player)
	local roleTitle = normalizeRoleName(rawRoleTitle)

	if roleTitle then
		table.insert(roles, {
			name     = roleTitle,
			priority = ROLE_PRIORITY[roleTitle] or 50,
		})
	end

	-- Cek VIP Aura attribute
	local hasVIP = player:GetAttribute("HasVipAura") == true
	-- Hindari duplikasi jika role utama sudah VIP
	if hasVIP and roleTitle ~= "VIP" then
		table.insert(roles, {
			name     = "VIP",
			priority = ROLE_PRIORITY.VIP,
		})
	end

	-- Urutkan berdasarkan prioritas
	table.sort(roles, function(a, b)
		return a.priority < b.priority
	end)

	-- Debug: cetak roles di Output Studio
	local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end
	if DEBUG_MODE then
		dPrint(string.format("[ChatTag] Roles for %s (UserId: %d):", player.Name, player.UserId))
		if #roles == 0 then
			dPrint("  -> (tidak ada role)")
		else
			for _, r in ipairs(roles) do
				dPrint(string.format("  -> %s (priority: %d)", r.name, r.priority))
			end
		end
	end

	return roles
end

-- ✅ FIX UTAMA: Tunggu DynamicRole selesai di-load dari DataStore sebelum return roles
-- JekyTitle:InitializePlayer() pakai task.wait(1), jadi kita tunggu max 5 detik
GetPlayerRolesRF.OnServerInvoke = function(player, targetUserId)
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then return {} end

	-- Tunggu attribute DynamicRole tersedia (di-load dari DataStore oleh JekyTitle)
	local waited = 0
	local maxWait = 5 -- detik
	local interval = 0.3

	while waited < maxWait do
		-- Cek apakah attribute sudah di-set (nil = belum, string/false = sudah)
		-- GetAttribute return nil kalau belum ada, jadi kita tunggu sampai bukan nil
		-- ATAU sampai timeout
		local dynRole = targetPlayer:GetAttribute("DynamicRole")
		if dynRole ~= nil then
			break -- Attribute sudah siap
		end
		-- Cek juga apakah player ini punya role statis dari RoleRules
		local staticRole = JekyTitle.GetRoleTitle(targetPlayer)
		if staticRole then
			break -- Punya role statis, tidak perlu tunggu DataStore
		end
		task.wait(interval)
		waited += interval
	end

	return getPlayerRoles(targetPlayer)
end

-- Helper: notify semua client bahwa role player berubah
local function notifyAllClients(userId)
	for _, p in ipairs(Players:GetPlayers()) do
		RoleUpdatedRE:FireClient(p, userId)
	end
end

Players.PlayerAdded:Connect(function(player)
	-- Listen perubahan attribute HasVipAura
	player:GetAttributeChangedSignal("HasVipAura"):Connect(function()
		notifyAllClients(player.UserId)
	end)

	-- Listen perubahan DynamicRole (di-set oleh JekyTitle:InitializePlayer)
	player:GetAttributeChangedSignal("DynamicRole"):Connect(function()
		notifyAllClients(player.UserId)
	end)

	-- Notify setelah JekyTitle selesai InitializePlayer (butuh ~1 detik + buffer)
	task.delay(3, function()
		if player and player.Parent then
			notifyAllClients(player.UserId)
		end
	end)
end)