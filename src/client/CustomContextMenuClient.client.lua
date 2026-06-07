local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local mouse = localPlayer:GetMouse()

-- Matikan menu klik bawaan Roblox agar tidak nabrak
pcall(function() StarterGui:SetCore("AvatarContextMenuEnabled", false) end)

local carryRemote = ReplicatedStorage:WaitForChild("CarryRemote")

-- Mengambil Folder Syncing dengan aman menghindari konflik nama dengan Event
local function getSyncFolder()
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child.Name == "Syncing" and child:IsA("Folder") then
			return child
		end
	end
end

local syncFolder = getSyncFolder()
local syncEvent = syncFolder and syncFolder:FindFirstChild("Sync")
local unsyncEvent = syncFolder and syncFolder:FindFirstChild("UnSync")

local targetPlayer = nil

-- UI Reference
local PlayerGui = localPlayer:WaitForChild("PlayerGui")

-- Menggunakan WaitForChild dengan waktu yang sangat lama (999 detik) 
-- agar script SABAR menunggu meskipun player lag parah saat loading.
local isiGui = PlayerGui:WaitForChild("IsiGui", 999)
if not isiGui then dWarn("Custom Context Menu: 'IsiGui' gagal dimuat karena lag ekstrim!") return end

local contextMenu = isiGui:WaitForChild("AvatarContextMenu", 999)
if not contextMenu then dWarn("Custom Context Menu: 'AvatarContextMenu' gagal dimuat!") return end

contextMenu.Visible = false

-- Tunggu semua tombol sampai benar-benar ada (Anti-Lag / Anti-Bug)
local carryBtn = contextMenu:WaitForChild("CarryBtn", 60)
local stopCarryBtn = contextMenu:WaitForChild("StopCarryBtn", 60)
local syncBtn = contextMenu:WaitForChild("SyncBtn", 60)
local unsyncBtn = contextMenu:WaitForChild("UnsyncBtn", 60)
local closeBtn = contextMenu:WaitForChild("CloseBtn", 60)

if closeBtn then
	closeBtn.MouseButton1Click:Connect(function()
		contextMenu.Visible = false
	end)
end

-- Custom click distance
local MAX_DISTANCE = 50 -- Bebas nge-klik orang sampai jarak 50 stud (sangat jauh)

-- Logika mendeteksi klik pemain dari kejauhan
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local target = mouse.Target
		if not target then
			contextMenu.Visible = false
			return
		end
		
		-- Cari apakah yang diklik itu bagian dari karakter pemain lain
		local model = target:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChild("Humanoid") then
			local clickedPlayer = Players:GetPlayerFromCharacter(model)
			if clickedPlayer and clickedPlayer ~= localPlayer then
				-- Cek jarak antara karakter kita dan dia
				local myChar = localPlayer.Character
				if myChar and myChar.PrimaryPart and model.PrimaryPart then
					local dist = (myChar.PrimaryPart.Position - model.PrimaryPart.Position).Magnitude
					if dist <= MAX_DISTANCE then
						targetPlayer = clickedPlayer
						
						-- Tampilkan GUI Custom di posisi aslinya (tengah layar / tempat awal)
						contextMenu.Visible = true
						return
					end
				end
			end
		end
		
		-- Kalau mengklik tempat yang kosong atau map, tutup GUI nya
		contextMenu.Visible = false
	end
end)

-- Hubungkan tombol-tombolnya
if carryBtn then
	carryBtn.MouseButton1Click:Connect(function()
		contextMenu.Visible = false
		if targetPlayer then
			carryRemote:FireServer("Request", { targetId = targetPlayer.UserId })
			StarterGui:SetCore("SendNotification", {
				Title = "Carry",
				Text = "Permintaan carry dikirim ke " .. targetPlayer.DisplayName,
				Duration = 3
			})
		end
	end)
end

if stopCarryBtn then
	stopCarryBtn.MouseButton1Click:Connect(function()
		contextMenu.Visible = false
		carryRemote:FireServer("Stop", {})
	end)
end

if syncBtn and syncEvent then
	syncBtn.MouseButton1Click:Connect(function()
		contextMenu.Visible = false
		if targetPlayer then
			syncEvent:FireServer(targetPlayer)
			StarterGui:SetCore("SendNotification", {
				Title = "Sync",
				Text = "Mencoba Sync Dance dengan " .. targetPlayer.DisplayName,
				Duration = 3
			})
		end
	end)
end

if unsyncBtn and unsyncEvent then
	unsyncBtn.MouseButton1Click:Connect(function()
		contextMenu.Visible = false
		unsyncEvent:FireServer()
	end)
end
