local DEBUG_MODE = false
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EventTitleClaim = ReplicatedStorage:WaitForChild("EventTitleClaim")
local EventTitlePreview = ReplicatedStorage:WaitForChild("EventTitlePreview")

local ProximityPromptService = game:GetService("ProximityPromptService")

local eventTitleGui = playerGui:WaitForChild("EventTitle", 999)
if not eventTitleGui then 
	dWarn("EventTitle GUI gagal dimuat karena lag ekstrim!")
	return 
end

local mainFrame = eventTitleGui:WaitForChild("MainFrame")
local editor = mainFrame:WaitForChild("Editor")
local infoBox = editor:WaitForChild("InfoBox")
local textBox = editor:WaitForChild("TextBox")
local previewLabel = editor:WaitForChild("Preview")
local modeSwitch = editor:WaitForChild("ModeSwitch")
local colorBtn = editor:WaitForChild("ColorBtn")
local animBtn = editor:WaitForChild("AnimBtn")

local footer = mainFrame:WaitForChild("Footer")
local previewBtn = footer:WaitForChild("PreviewBtn")
local applyBtn = footer:WaitForChild("ApplyBtn")

local header = mainFrame:WaitForChild("Header")
local closeBtn = header:WaitForChild("CloseBtn")

local claimLines = {}
for i = 1, 4 do
	claimLines[i] = mainFrame:WaitForChild("ClaimLine" .. i)
end

-- UI State
local PRESETS = {
	{Colors = {Color3.fromRGB(0, 255, 255), Color3.fromRGB(180, 0, 255), Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 105, 180)}},
	{Colors = {Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 255, 0)}},
	{Colors = {Color3.fromRGB(135, 206, 250), Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 192, 203)}},
	{Colors = {Color3.fromRGB(138, 43, 226), Color3.fromRGB(255, 20, 147), Color3.fromRGB(0, 255, 255)}},
	{Colors = {Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 140, 0), Color3.fromRGB(255, 69, 0)}}
}

local SOLIDS = {
	Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 215, 0), Color3.fromRGB(0, 100, 255), Color3.fromRGB(0, 255, 255), Color3.fromRGB(255, 105, 180)
}

local ANIMS = {"Gradient360", "LeftRight", "Diagonal", "Wave", "Pulse"}

local currentMode = "PRESET"
local currentPreset = 1
local currentAnim = 1
local currentSolid = 1

local function buildSeq(colors)
	local kp = {}
	local n = #colors
	for i, c in ipairs(colors) do
		table.insert(kp, ColorSequenceKeypoint.new((i - 1) / math.max(1, n - 1), c))
	end
	return ColorSequence.new(kp)
end

local function clearAnim(lbl)
	for _, g in pairs(lbl:GetChildren()) do
		if g:IsA("UIGradient") then g:Destroy() end
	end
end

local function updatePreviewUI()
	previewLabel.Text = textBox.Text
	clearAnim(previewLabel)
	previewLabel:SetAttribute("TitleAnimType", nil)
	CollectionService:RemoveTag(previewLabel, "AnimatedTitleLabel")
	
	if currentMode == "PRESET" then
		previewLabel.TextColor3 = Color3.new(1, 1, 1)
		local grad = Instance.new("UIGradient")
		grad.Color = buildSeq(PRESETS[currentPreset].Colors)
		grad.Parent = previewLabel
		
		previewLabel:SetAttribute("TitleAnimType", ANIMS[currentAnim])
		CollectionService:AddTag(previewLabel, "AnimatedTitleLabel")
		
		colorBtn.Text = "Color Preset: " .. currentPreset
		animBtn.Text = "Anim: " .. ANIMS[currentAnim]
		animBtn.Visible = true
		modeSwitch.Text = "Mode: PRESET"
	else
		previewLabel.TextColor3 = SOLIDS[currentSolid]
		colorBtn.Text = "Color Solid: " .. currentSolid
		animBtn.Visible = false
		modeSwitch.Text = "Mode: SOLID"
	end
end

textBox:GetPropertyChangedSignal("Text"):Connect(updatePreviewUI)

modeSwitch.MouseButton1Click:Connect(function()
	currentMode = currentMode == "PRESET" and "SOLID" or "PRESET"
	updatePreviewUI()
end)

colorBtn.MouseButton1Click:Connect(function()
	if currentMode == "PRESET" then
		currentPreset = currentPreset % #PRESETS + 1
	else
		currentSolid = currentSolid % #SOLIDS + 1
	end
	updatePreviewUI()
end)

animBtn.MouseButton1Click:Connect(function()
	if currentMode == "PRESET" then
		currentAnim = currentAnim % #ANIMS + 1
		updatePreviewUI()
	end
end)

local LINE_REQS = { [1] = 50, [2] = 200, [3] = 600, [4] = 2000 }

local function showNotification(title, text)
	StarterGui:SetCore("SendNotification", {
		Title = title,
		Text = text,
		Duration = 5
	})
end

local function fetchStatus()
	EventTitleClaim:FireServer("GetStatus")
end

local selectedLine = nil

local function updateButtonStyles()
	for i = 1, 4 do
		local btn = claimLines[i]
		if btn:GetAttribute("Claimed") then
			btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		else
			if selectedLine == i then
				btn.BackgroundColor3 = Color3.fromRGB(0, 170, 255) -- Warna biru saat dipilih
			else
				btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
			end
		end
	end
end

EventTitleClaim.OnClientEvent:Connect(function(action, status, msg, lineIdx)
	if action == "Status" then
		for i = 1, 4 do
			local btn = claimLines[i]
			if status[i] then
				btn.Text = "Line " .. i .. " (Claimed)"
				btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
				btn.Active = false
				btn:SetAttribute("Claimed", true)
			else
				btn.Text = "Pilih Line " .. i .. " (" .. LINE_REQS[i] .. " Summit)"
				btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
				btn.Active = true
				btn:SetAttribute("Claimed", false)
			end
			if selectedLine == i and status[i] then
				selectedLine = nil
			end
		end
		updateButtonStyles()
	elseif action == "ClaimResult" then
		if status == true then
			showNotification("Success", msg)
			if lineIdx then
				local btn = claimLines[lineIdx]
				btn.Text = "Line " .. lineIdx .. " (Claimed)"
				btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
				btn.Active = false
				btn:SetAttribute("Claimed", true)
				if selectedLine == lineIdx then
					selectedLine = nil
				end
				updateButtonStyles()
			end
		else
			showNotification("Error", msg)
		end
	end
end)

for i = 1, 4 do
	claimLines[i].MouseButton1Click:Connect(function()
		if not claimLines[i].Active or claimLines[i]:GetAttribute("Claimed") then return end
		
		selectedLine = i
		updateButtonStyles()
	end)
end

applyBtn.MouseButton1Click:Connect(function()
	if not selectedLine then
		showNotification("Error", "Silahkan pilih Line yang ingin di-claim terlebih dahulu!")
		return
	end
	
	local ls = player:FindFirstChild("leaderstats")
	local summit = ls and ls:FindFirstChild("Summit")
	local mySummit = summit and summit.Value or 0
	
	if mySummit < LINE_REQS[selectedLine] then
		showNotification("Error", "Belum memenuhi syarat " .. LINE_REQS[selectedLine] .. " Summit untuk Line " .. selectedLine .. "!")
		return
	end
	
	if textBox.Text == "" then
		showNotification("Error", "Teks title tidak boleh kosong!")
		return
	end
	
	local data = {
		Text = textBox.Text,
		Mode = currentMode,
		Preset = currentPreset,
		Anim = currentAnim,
		Solid = currentSolid
	}
	
	EventTitleClaim:FireServer("Claim", selectedLine, data)
end)

previewBtn.MouseButton1Click:Connect(function()
	if not selectedLine then
		showNotification("Error", "Silahkan pilih Line yang ingin di-preview terlebih dahulu!")
		return
	end
	
	mainFrame.Visible = false
	local data = {
		Text = textBox.Text,
		Mode = currentMode,
		Preset = currentPreset,
		Anim = currentAnim,
		Solid = currentSolid
	}
	EventTitlePreview:FireServer(selectedLine, data)
end)

EventTitlePreview.OnClientEvent:Connect(function(action)
	if action == "PreviewDone" then
		mainFrame.Visible = true
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = false
end)

ProximityPromptService.PromptTriggered:Connect(function(promptTriggered, playerTriggered)
	if playerTriggered == player and promptTriggered.Parent and promptTriggered.Parent.Name == "PartClaimTitle" then
		fetchStatus()
		mainFrame.Visible = true
		updatePreviewUI()
	end
end)

mainFrame.Visible = false
updatePreviewUI()
