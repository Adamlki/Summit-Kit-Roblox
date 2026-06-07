local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

-- ServerScriptService > DonationServer
local Players           = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
 
-- ============================================
-- DONATION PACKAGES
-- ============================================
local DONATION_PACKAGES = {
    {id = 3534865193, price = 5},    -- Donation 1
    {id = 3534866153, price = 10},   -- Donation 2
    {id = 3534866169, price = 20},   -- Donation 3
    {id = 3534866168, price = 50},   -- Donation 4
    {id = 3534866165, price = 100},  -- Donation 5
    {id = 3534866167, price = 250},  -- Donation 6
    {id = 3534866176, price = 500},  -- Donation 7
    {id = 3534866177, price = 1000}, -- Donation 8
    {id = 3534866166, price = 2000}, -- Donation 9
    {id = 3534866149, price = 4000}, -- Donation 10
}
 
-- ============================================
-- CREATE REMOTES
-- ============================================
local GetDonationPackagesRF = Instance.new("RemoteFunction")
GetDonationPackagesRF.Name   = "Donation_GetPackages"
GetDonationPackagesRF.Parent = ReplicatedStorage
 
local PurchaseDonationRE = Instance.new("RemoteEvent")
PurchaseDonationRE.Name   = "Donation_Purchase"
PurchaseDonationRE.Parent = ReplicatedStorage
 
local DonationNotifyRE = Instance.new("RemoteEvent")
DonationNotifyRE.Name   = "Donation_Notify"
DonationNotifyRE.Parent = ReplicatedStorage
 
-- ============================================
-- GET PACKAGES (client request)
-- ============================================
GetDonationPackagesRF.OnServerInvoke = function(_player)
    return DONATION_PACKAGES
end
 
-- ============================================
-- VALIDATE PACKAGE
-- ============================================
local function isValidPackage(productId)
    for _, package in ipairs(DONATION_PACKAGES) do
        if package.id == productId then
            return true, package.price
        end
    end
    return false, 0
end
 
-- ============================================
-- BROADCAST NOTIFIKASI KE SEMUA PLAYER
-- ============================================
local function broadcastDonation(donorPlayer, amount)
    for _, target in ipairs(Players:GetPlayers()) do
        DonationNotifyRE:FireClient(target, donorPlayer.DisplayName, amount)
    end
end
 
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local JekyDSKeys = require(ServerStorage:WaitForChild("JekyModules"):WaitForChild("JekyDSKeys"))

local DonationDataStore = DataStoreService:GetOrderedDataStore(JekyDSKeys.Keys.DonationGlobalLB)

-- ============================================
-- PROCESS RECEIPT (MarketplaceService)
-- ============================================
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local donorPlayer = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	if not donorPlayer then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local isValid, price = isValidPackage(receiptInfo.ProductId)
	if not isValid then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 🛑 TAMBAHKAN PENGECEKAN STUDIO DI SINI 🛑
	if RunService:IsStudio() then
		dPrint("[DonationServer] Pembelian TEST di Studio berhasil. (TIDAK DISIMPAN KE LEADERBOARD)")
		broadcastDonation(donorPlayer, price) -- Tetap broadcast agar kamu bisa ngetes UI notifikasinya
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Proses penyimpanan ke OrderedDataStore (Ini hanya akan jalan di Live Game)
	local key = "Player_" .. donorPlayer.UserId
	local success, err = pcall(function()
		DonationDataStore:IncrementAsync(key, price)
	end)

	if success then
		broadcastDonation(donorPlayer, price)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		dWarn("[DonationServer] Gagal menyimpan donasi untuk " .. donorPlayer.Name .. ": " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end
-- ============================================
-- HANDLE PURCHASE REQUEST FROM CLIENT
-- ============================================
PurchaseDonationRE.OnServerEvent:Connect(function(requestPlayer, productId)
    local isValid, _ = isValidPackage(productId)
    if not isValid then return end
    
    pcall(function()
        MarketplaceService:PromptProductPurchase(requestPlayer, productId)
    end)
end)

