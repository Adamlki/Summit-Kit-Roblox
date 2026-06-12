-- ServerScriptService > JekySystems > MonitorService > DonationBoardManager
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local ServerStorage = game:GetService("ServerStorage")

local JekyDSKeys = require(ServerStorage:WaitForChild("JekyModules"):WaitForChild("JekyDSKeys"))
local DonationDataStore = DataStoreService:GetOrderedDataStore(JekyDSKeys.Keys.DonationGlobalLB)

-- ============================================
-- KONFIGURASI & DEBUGGER
-- ============================================
local REFRESH_TIME = 120
local MAX_ITEMS = 10
local EMOTE_ID = "rbxassetid://140349022227594"

local DEBUG_MODE = false -- SET KE 'false' JIKA GAME SUDAH RILIS AGAR OUTPUT TIDAK SPAM
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

local function debugLog(tag, message, isError)
	if not DEBUG_MODE then return end
	local prefix = "[DonationLB | " .. tag .. "] "
	if isError then
		dWarn(prefix .. tostring(message))
	else
		dPrint(prefix .. tostring(message))
	end
end

debugLog("INIT", "Memulai inisialisasi script DonationBoardManager...")

-- ============================================
-- REMOTE EVENT SETUP
-- ============================================
local UpdateDonationBoardEvent = ReplicatedStorage:FindFirstChild("UpdateDonationBoard")
if not UpdateDonationBoardEvent then
	UpdateDonationBoardEvent = Instance.new("RemoteEvent")
	UpdateDonationBoardEvent.Name = "UpdateDonationBoard"
	UpdateDonationBoardEvent.Parent = ReplicatedStorage
end

-- ============================================
-- REFERENSI OBJEK & CACHE DUMMY
-- ============================================
local allPartsFolder = workspace:WaitForChild("AllPartSummitkitJeky")
local leaderboardFolder = allPartsFolder:WaitForChild("LeaderBoard")
local boardModel = leaderboardFolder:WaitForChild("DonationLeaderBoard")

local statuesFolder = boardModel:FindFirstChild("Statues")
local billboardTemplate = ReplicatedStorage:WaitForChild("DonationBillboardGui")

local cachedDummies = {}
if statuesFolder and billboardTemplate then
	debugLog("INIT", "Semua referensi objek berhasil ditemukan!")
	
	-- Cache semua patung Top 1-3 dan simpan posisi aslinya, lalu sembunyikan di awal
	for i = 1, 3 do
		local dummy = statuesFolder:FindFirstChild("Top" .. tostring(i))
		if dummy then
			cachedDummies[i] = {
				Model = dummy,
				OriginalCFrame = dummy:GetPivot()
			}
			dummy.Parent = nil -- Sembunyikan di awal
		end
	end
else
	debugLog("INIT", "Peringatan: Ada objek yang hilang di Workspace atau ReplicatedStorage!", true)
end

-- ============================================
-- FUNGSI GET NICKNAME (DISPLAY NAME)
-- ============================================
local function getOfflineDisplayName(userId)
	local success, userInfo = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync({userId})
	end)

	if success and userInfo and userInfo[1] then
		debugLog("USERINFO", "Berhasil menarik DisplayName untuk UserID: " .. userId)
		return userInfo[1].DisplayName
	end

	debugLog("USERINFO", "Gagal tarik DisplayName, mencoba fallback Username untuk UserID: " .. userId, true)
	local successName, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return successName and name or ("Player_" .. tostring(userId))
end

-- ============================================
-- FUNGSI UPDATE PATUNG (EMOTE & BILLBOARD)
-- ============================================
local function updateStatue(rank, userId, displayName, totalDonated)
	if not statuesFolder then return end

	local dummyCache = cachedDummies[rank]
	if not dummyCache then return end
	
	local dummy = dummyCache.Model
	dummy.Parent = statuesFolder -- Munculkan patung

	if dummy and dummy:FindFirstChild("Humanoid") then
		local humanoid = dummy.Humanoid
		local rootPart = dummy:FindFirstChild("HumanoidRootPart")

		if not rootPart then
			debugLog("STATUE", "HumanoidRootPart tidak ditemukan pada Top " .. rank .. "! Pastikan Dummy memiliki HumanoidRootPart.", true)
			return
		end

		local originalCFrame = dummyCache.OriginalCFrame 

		task.spawn(function()
			debugLog("STATUE", "Mulai proses update patung Top " .. rank .. " (User: " .. displayName .. ")")

			local descSuccess, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(userId)
			end)

			if not descSuccess or not desc then return end

			-- 1. Update Penampilan Baju/Aksesoris
			local success, err = pcall(function()
				humanoid:ApplyDescription(desc)
			end)

			-- PENTING: Tunggu sedikit lebih lama (0.5 detik) agar Roblox selesai menghitung proporsi tubuh / panjang kaki baru
			task.wait(0.5)

			local currentRoot = dummy:FindFirstChild("HumanoidRootPart")
			if currentRoot then
				-- 2. Gunakan MoveTo agar telapak kaki otomatis mencari pijakan / napak di atas podium
				dummy:MoveTo(originalCFrame.Position)

				-- 3. Karena MoveTo kadang mereset arah hadap (rotasi), kita kembalikan arah hadapnya seperti semula
				local newPos = dummy:GetPivot().Position
				dummy:PivotTo(CFrame.new(newPos) * originalCFrame.Rotation)

				-- 4. Kunci HANYA HumanoidRootPart agar tidak jatuh/melorot
				-- Sisa tubuhnya (tangan, kaki) harus Unanchored agar bisa digerakkan Emote
				currentRoot.Anchored = true

				for _, part in ipairs(dummy:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						part.Anchored = false
					end
				end

				debugLog("STATUE", "Sukses membuat patung napak di podium untuk Top " .. rank)
			end

			local head = dummy:FindFirstChild("Head")

			-- 3. Pasang & Update BillboardGui dengan aman
			if head then
				local existingGui = dummy:FindFirstChild("DonationBillboardGui")
				if not existingGui then
					debugLog("STATUE", "Membuat BillboardGui baru untuk Top " .. rank)
					existingGui = billboardTemplate:Clone()
					existingGui.Parent = dummy
				end

				existingGui.Adornee = head

				local mainFrame = existingGui:FindFirstChild("MainFrame")
				if mainFrame then
					local nameLabel = mainFrame:FindFirstChild("Name")
					local valueLabel = mainFrame:FindFirstChild("Value")

					if nameLabel then nameLabel.Text = displayName end
					if valueLabel then valueLabel.Text = tostring(totalDonated) .. " Robux" end
				end
			else
				debugLog("STATUE", "Part 'Head' tidak ditemukan pada patung Top " .. rank, true)
			end

			-- 4. Mainkan Emote/Animasi
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end

			-- Gunakan track yang sudah di-cache agar tidak perlu LoadAnimation berkali-kali (mencegah memory leak)
			if not dummyCache.AnimationTrack then
				local anim = Instance.new("Animation")
				anim.AnimationId = EMOTE_ID
				dummyCache.AnimationTrack = animator:LoadAnimation(anim)
				dummyCache.AnimationTrack.Looped = true
			end

			-- Stop animasi lain yang sedang berjalan (jika ada)
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track ~= dummyCache.AnimationTrack then
					track:Stop()
				end
			end

			-- Mainkan track jika belum berjalan
			if not dummyCache.AnimationTrack.IsPlaying then
				debugLog("STATUE", "Memutar animasi emote untuk Top " .. rank)
				dummyCache.AnimationTrack:Play()
			end
		end)
	else
		debugLog("STATUE", "Dummy atau Humanoid tidak ditemukan untuk Top " .. rank, true)
	end
end

-- ============================================
-- FUNGSI PULL DATA & UPDATE PATUNG & BROADCAST
-- ============================================
local function updateBoard()
	debugLog("DATASTORE", "Memulai penarikan data dari OrderedDataStore...")

	local success, pages = pcall(function()
		return DonationDataStore:GetSortedAsync(false, MAX_ITEMS)
	end)

	if not success or not pages then
		debugLog("DATASTORE", "Gagal mengambil data dari Roblox DataStore!", true)
		return
	end

	local currentPage = pages:GetCurrentPage()
	debugLog("DATASTORE", "Sukses menarik " .. #currentPage .. " data player.")

	local top10Data = {}

	for rank = 1, MAX_ITEMS do
		local data = currentPage[rank]

		if data then
			local userId = tonumber(string.match(data.key, "%d+"))
			local totalDonated = data.value
			local displayName = getOfflineDisplayName(userId)

			table.insert(top10Data, {
				Rank = rank,
				UserId = userId,
				DisplayName = displayName,
				TotalDonated = totalDonated
			})

			if rank <= 3 then
				updateStatue(rank, userId, displayName, totalDonated)
			end
		else
			-- Sembunyikan patung dan hapus Billboard jika sudah tidak masuk Top 3
			if rank <= 3 and statuesFolder then
				local dummyCache = cachedDummies[rank]
				if dummyCache then
					local dummy = dummyCache.Model
					local gui = dummy:FindFirstChild("DonationBillboardGui")
					if gui then 
						gui:Destroy() 
						debugLog("STATUE", "Menghapus BillboardGui dari patung kosong Top " .. rank)
					end
					-- Sembunyikan patung
					dummy.Parent = nil
				end
			end
		end
	end

	-- Broadcast data ke semua client untuk update UI
	UpdateDonationBoardEvent:FireAllClients(top10Data)

	debugLog("DATASTORE", "Proses update UI dan Patung selesai.")
end

-- ============================================
-- LOOP UTAMA (TIMER & REFRESH)
-- ============================================
task.spawn(function()
	task.wait(5)
	debugLog("LOOP", "Loop utama berjalan.")

	while true do
		updateBoard()
		task.wait(REFRESH_TIME)
	end
end)