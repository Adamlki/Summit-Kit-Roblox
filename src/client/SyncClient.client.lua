local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local function getSyncFolder()
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if child.Name == "Syncing" and child:IsA("Folder") then
			return child
		end
	end
	return nil
end

local SyncFolder = getSyncFolder()
if not SyncFolder then return end
local SyncEvent = SyncFolder:WaitForChild("Sync", 999)
if not SyncEvent then return end

local ignoredAnimations = { Enum.AnimationPriority.Core }
local ignoredEmoteNames = { "running", "swimming", "platformstanding", "seated", "fallingdown", "gettingup", "jumping", "climbing", "walking", "carrysystemanim" }

local animPlayedConn = nil
local deathConn = nil
local leaveConn = nil
local stopConns = {}
local cachedTracks = {}

local function stopLocalSync()
	if animPlayedConn then animPlayedConn:Disconnect() animPlayedConn = nil end
	if deathConn then deathConn:Disconnect() deathConn = nil end
	if leaveConn then leaveConn:Disconnect() leaveConn = nil end

	for _, conn in ipairs(stopConns) do
		if conn then conn:Disconnect() end
	end
	table.clear(stopConns)

	for _, track in pairs(cachedTracks) do
		if track then
			if track.IsPlaying then 
				track:Stop() 
			end
			track:Destroy()
		end
	end
	table.clear(cachedTracks)
end

local function startLocalSync(targetPlayer)
	if not targetPlayer or not targetPlayer.Character then return end
	local myChar = localPlayer.Character
	local targetChar = targetPlayer.Character
	if not myChar then return end

	local myAnim = myChar:FindFirstChild("Humanoid") and myChar.Humanoid:FindFirstChild("Animator")
	local targetAnim = targetChar:FindFirstChild("Humanoid") and targetChar.Humanoid:FindFirstChild("Animator")
	if not myAnim or not targetAnim then return end

	stopLocalSync()

	local function cloneTrack(hostTrack)
		if not hostTrack or not hostTrack.Animation then return end
		local animName = hostTrack.Animation.Name:lower()

		if table.find(ignoredAnimations, hostTrack.Priority) or table.find(ignoredEmoteNames, animName) then 
			return 
		end

		local animId = hostTrack.Animation.AnimationId
		local followerTrack = cachedTracks[animId]
		
		if not followerTrack then
			followerTrack = myAnim:LoadAnimation(hostTrack.Animation)
			cachedTracks[animId] = followerTrack
		end

		followerTrack.Priority = Enum.AnimationPriority.Action
		followerTrack.TimePosition = hostTrack.TimePosition
		followerTrack:AdjustSpeed(hostTrack.Speed)
		followerTrack:Play()

		local stopConn
		stopConn = hostTrack.Stopped:Connect(function()
			if followerTrack.IsPlaying then
				followerTrack:Stop()
			end
			-- Clear from cache and destroy to prevent exceeding the 64 tracks limit
			if cachedTracks[animId] == followerTrack then
				cachedTracks[animId] = nil
			end
			pcall(function() followerTrack:Destroy() end)

			if stopConn then 
				stopConn:Disconnect() 
				local index = table.find(stopConns, stopConn)
				if index then table.remove(stopConns, index) end
			end
		end)
		table.insert(stopConns, stopConn)
	end

	for _, track in ipairs(targetAnim:GetPlayingAnimationTracks()) do
		cloneTrack(track)
	end

	animPlayedConn = targetAnim.AnimationPlayed:Connect(function(hostTrack)
		cloneTrack(hostTrack)
	end)

	deathConn = targetChar.Humanoid.Died:Connect(function()
		stopLocalSync()
	end)
	
	leaveConn = targetChar.AncestryChanged:Connect(function(_, parent)
		if not parent then
			stopLocalSync()
		end
	end)
end

SyncEvent.OnClientEvent:Connect(function(syncingPlayer, targetPlayer, action)
	if syncingPlayer ~= localPlayer then return end
	if action == "START" then
		startLocalSync(targetPlayer)
	elseif action == "STOP" then
		stopLocalSync()
	end
end)

localPlayer.CharacterAdded:Connect(function()
	stopLocalSync()
end)
