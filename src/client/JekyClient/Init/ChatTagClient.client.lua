local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

-- LocalScript: StarterPlayerScripts/ChatTag_Client
-- FIXED VERSION: colorize, timing, rich text + VIP gradient Cyan→Biru→Ungu→Pink→Putih

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerRolesCache = {}
local GetPlayerRolesRF = nil
local RoleUpdatedRE    = nil
local isReady          = false

local ROLE_TAGS = {
	Owner     = "👑OWNER👑",
	Developer = "🛠️DEVELOPER🛠️",
	HeadAdmin = "HEAD ADMIN",
	Admin     = "ADMIN",
	Moderator = "MODERATOR",
	Streamer  = "STREAMER",
	VIP       = "VIP",
	Community = "COMMUNITY",
}

local ROLE_COLORS = {
	Owner     = "#FFD700",
	Developer = "#FF69B4",
	HeadAdmin = "#FF4500",
	Admin     = "#FF6347",
	Moderator = "#1E90FF",
	Streamer  = "#9400D3",
	VIP       = "#00FFFF", -- fallback, tidak dipakai karena VIP pakai gradient
	Community = "#FFA500",
}

-- ✅ 5 warna gradien VIP: Cyan → Biru → Ungu → Pink → Putih
local VIP_GRADIENT_COLORS = {
	"#00FFFF", -- Cyan
	"#4169E1", -- Biru Royal
	"#8A2BE2", -- Ungu
	"#FF69B4", -- Pink
	"#FFFFFF", -- Putih
}

local NAME_COLORS = {
	"#F5A2A2", "#F5A2E8", "#A2C4F5", "#A2F5B9",
	"#F5D9A2", "#D9A2F5", "#A2F5F5", "#F5F5A2",
	"#F5B8A2", "#A2F5D9",
}

-- ✅ FIX UTAMA: colorize menggunakan string.format agar tag tidak kosong
local function colorize(text, hexColor)
	return string.format('<font color="%s">%s</font>', hexColor, text)
end

local function getUsernameColor(userId)
	return NAME_COLORS[(userId % #NAME_COLORS) + 1]
end

-- ✅ Gradien per karakter, warna terdistribusi merata kiri ke kanan
local function gradientText(text, colors)
	local result     = ""
	local len        = #text
	local colorCount = #colors

	for i = 1, len do
		local char = text:sub(i, i)
		local colorIndex
		if len == 1 then
			colorIndex = 1
		else
			colorIndex = math.floor((i - 1) / (len - 1) * (colorCount - 1)) + 1
		end
		colorIndex = math.clamp(colorIndex, 1, colorCount)
		result = result .. colorize(char, colors[colorIndex])
	end

	return result
end

-- ✅ Buat tag VIP dengan gradien per karakter
local function createVIPTag()
	local openBracket  = colorize("[", VIP_GRADIENT_COLORS[1])
	local vipText      = gradientText("VIP", VIP_GRADIENT_COLORS)
	local closeBracket = colorize("]", VIP_GRADIENT_COLORS[#VIP_GRADIENT_COLORS])
	return openBracket .. vipText .. closeBracket
end

local function createAllRoleTags(roles)
	if not roles or #roles == 0 then return "" end
	local parts  = {}
	local colors = {}

	for _, role in ipairs(roles) do
		local tag

		if role.name == "VIP" then
			-- ✅ VIP pakai gradien khusus
			tag = createVIPTag()
			table.insert(colors, VIP_GRADIENT_COLORS[3]) -- warna tengah untuk separator ×
		else
			local color   = ROLE_COLORS[role.name] or "#FFFFFF"
			local tagText = ROLE_TAGS[role.name] or role.name
			tag = colorize("[" .. tagText .. "]", color)
			table.insert(colors, color)
		end

		table.insert(parts, tag)
	end

	local result = ""
	for i, tag in ipairs(parts) do
		result = result .. tag
		if i < #parts then
			result = result .. colorize(" × ", colors[i])
		end
	end
	return result .. " "
end

local function fetchRolesFromServer(userId)
	if not GetPlayerRolesRF then return {} end
	local success, roles = pcall(function()
		return GetPlayerRolesRF:InvokeServer(userId)
	end)
	if success and roles then
		playerRolesCache[userId] = roles
		return roles
	end
	return {}
end

local function getRolesForPlayer(userId)
	if playerRolesCache[userId] then
		return playerRolesCache[userId]
	end
	if not isReady then return {} end
	return fetchRolesFromServer(userId)
end

-- ✅ FIX: OnIncomingMessage dengan rich text yang benar
TextChatService.OnIncomingMessage = function(message)
	local properties = Instance.new("TextChatMessageProperties")
	local textSource = message.TextSource
	if not textSource then return properties end

	local userId      = textSource.UserId
	local roles       = getRolesForPlayer(userId)
	local roleTags    = createAllRoleTags(roles)

	local senderPlayer = Players:GetPlayerByUserId(userId)
	local displayName  = senderPlayer and senderPlayer.DisplayName or textSource.Name
	local coloredName  = colorize(displayName, getUsernameColor(userId))

	if roleTags ~= "" then
		properties.PrefixText = roleTags .. coloredName .. ":"
	else
		properties.PrefixText = coloredName .. ":"
	end

	return properties
end

-- ✅ FIX: Gunakan WaitForChild agar tidak gagal saat server belum siap
task.spawn(function()
	GetPlayerRolesRF = ReplicatedStorage:WaitForChild("ChatTag_GetRoles",   15)
	RoleUpdatedRE    = ReplicatedStorage:WaitForChild("ChatTag_RoleUpdated", 15)

	if not GetPlayerRolesRF then
		dWarn("[ChatTag] ChatTag_GetRoles tidak ditemukan! Pastikan Server Script berjalan.")
		return
	end

	isReady = true

	-- Sync semua player yang sudah ada
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			fetchRolesFromServer(p.UserId)
		end)
	end

	-- Listen update role dari server dan refresh cache
	if RoleUpdatedRE then
		RoleUpdatedRE.OnClientEvent:Connect(function(userId)
			if userId then
				playerRolesCache[userId] = nil -- hapus cache lama
				fetchRolesFromServer(userId)   -- fetch ulang dari server
			end
		end)
	end
end)

Players.PlayerAdded:Connect(function(joinedPlayer)
	-- Tunggu JekyTitle:InitializePlayer() selesai (butuh ~1 detik + buffer)
	task.delay(2, function()
		if isReady then
			pcall(function() fetchRolesFromServer(joinedPlayer.UserId) end)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	playerRolesCache[leavingPlayer.UserId] = nil
end)