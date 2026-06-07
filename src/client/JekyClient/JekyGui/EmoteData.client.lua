-- EmoteSystemClient.lua
-- StarterPlayer/StarterPlayerScripts
 
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
 
-- ============================================
-- DEBUG SETTINGS
-- ============================================
local DEBUG_MODE = false  -- Set ke true untuk debug
local function dPrint(...) if DEBUG_MODE then dPrint(...) end end
local function dWarn(...) if DEBUG_MODE then dWarn(...) end end
 
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
 
-- ============================================
-- VARIABLES
-- ============================================
local ListGui
local ListTopBar
local EmoteButton
 
local IsiGui
local EmotePanel
local ScrollingFrame
local TemplateButton
local EmoteListButton
local DanceListButton
local SearchBox
local SearchButton
local CloseButton
local SpeedBar
local SpeedSlider
 
local currentTrack = nil
local currentSpeed = 1.0
local MIN_SPEED = 0.1
local MAX_SPEED = 3.0
local isFrameOpen = false
local currentMode = "dance"  -- "dance" atau "emote"
local currentPlayingButton = nil
 
local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
 
-- ============================================
-- COLORS
-- ============================================
local COLORS = {
Cyan = Color3.fromRGB(255, 255, 255),      -- Dance color
Magenta = Color3.fromRGB(255, 255, 255),   -- Emote color
White = Color3.fromRGB(255, 255, 255),
Yellow = Color3.fromRGB(255, 255, 255),    -- Playing color
FeedbackActive = Color3.fromRGB(255, 105, 180)
}
 
-- ============================================
-- ANIMATION DATA
-- ============================================
local dances = {
{name="Funky Groove", animId=78416657618448},
{name="Hip Hop Slide", animId=129373064455405},
{name="Wave Motion", animId=103948800984170},
{name="Spin Master", animId=97086109091396},
{name="Body Roll", animId=136095999219650},
{name="Bounce Step", animId=122254727316758},
{name="Pop Lock", animId=80933111363555},
{name="Shuffle Beat", animId=108759656834820},
{name="Moon Walk", animId=73314582348097},
{name="Robot Dance", animId=90518809140968},
{name="Twist Move", animId=111257123835413},
{name="Glide Flow", animId=110494040742516},
{name="Jump Kick", animId=129764254213842},
{name="Break Spin", animId=116835198609765},
{name="Freeze Pose", animId=94480432559942},
{name="Sway Dance", animId=122719596509695},
{name="Electric Slide", animId=123471454475978},
{name="Pump It Up", animId=79689692681563},
{name="Disco Fever", animId=96147994216119},
{name="Jazz Hands", animId=125724450808506},
{name="Salsa Step", animId=104149584253673},
{name="Floss Move", animId=111754856931573},
{name="Dab Motion", animId=118468821959324},
{name="Whip Nae Nae", animId=96100759913198},
{name="Fortnite Flow", animId=109364514498221},
{name="TikTok Trend", animId=93062298566806},
{name="Viral Move", animId=102864411236212},
{name="Swag Walk", animId=112534296956901},
{name="Cool Guy", animId=89558401923098},
{name="Party Time", animId=126771729094882},
{name="Hype Dance", animId=103710256055561},
{name="Victory Lap", animId=80621140833482},
{name="Smooth Criminal", animId=95127716920692},
{name="Thriller Vibe", animId=126597745883758},
{name="Savage Mode", animId=121966805049108},
{name="Renegade", animId=89794141549021},
{name="Say So", animId=75117155576035},
{name="Blinding Lights", animId=83650099589962},
{name="Levitating", animId=118552217459650},
{name="Toosie Slide", animId=94593166146998},
{name="Savage Love", animId=92354174724298},
{name="Tap In", animId=88050523705839},
{name="Buss It", animId=89794141549021},
{name="Up Move", animId=96100759913198},
}
 
local emotes = {
{name="Wave", animId=507770239},
{name="Point", animId=507776043},
{name="Cheer", animId=507770677},
{name="Shrug", animId=99622371046192},
{name="Thinking", animId=126899447275562},
{name="Salute", animId=112082806790047},
{name="Facepalm", animId=105824857171709},
{name="Clap", animId=132760747409859},
{name="Cry", animId=77139456213922},
{name="Laugh", animId=80222624644964},
{name="Angry", animId=100698821205549},
{name="Shocked", animId=115257437995638},
{name="Sleep", animId=109030594660124},
{name="Sit", animId=98352002677627},
{name="Jump Joy", animId=85945097006032},
{name="Heart Hands", animId=123975418223144},
{name="Yawn", animId=106808430180168},
{name="Sneeze", animId=124522818196151},
{name="Stretch", animId=96308221977337},
{name="Peace Sign", animId=128941887300629},
{name="Thumbs Up", animId=100678061110922},
{name="High Five", animId=104595291484684},
{name="Flex", animId=88042477607072},
{name="Cool Pose", animId=117597565445349},
{name="Victory", animId=132798681855515},
{name="Sad Walk", animId=74231110404376},
{name="Confident Walk", animId=138859415166285},
{name="Shy", animId=138591721528570},
{name="Angry Stomp", animId=138706623195970},
{name="Excited Jump", animId=111251252458517},
{name="Stadium", animId=10214319518},
{name="Head Bang", animId=127626736897320},
{name="Air Guitar", animId=80879471830819},
{name="Drum Solo", animId=107990372400562}
}
 
-- ============================================
-- PLAY ANIMATION
-- ============================================
local function playAnimation(animId, buttonClicked)
    -- Check if clicking the same button that's currently playing
    if currentPlayingButton == buttonClicked and currentTrack and currentTrack.IsPlaying then
        -- Stop the animation
        currentTrack:Stop()
        currentTrack:Destroy()
        currentTrack = nil
        
        -- Return button color to mode color
        local modeColor = currentMode == "dance" and COLORS.Cyan or COLORS.Magenta
        buttonClicked.TextColor3 = modeColor
        currentPlayingButton = nil
        
        if DEBUG_MODE then dPrint("[EmoteSystem] Stopped animation") end
        return
    end
    
    local char = player.Character or player.CharacterAdded:Wait()
    local humanoid = char:WaitForChild("Humanoid")
    
    -- Stop current track
    if currentTrack then
        currentTrack:Stop()
        currentTrack:Destroy()
        currentTrack = nil
    end
    
    -- Reset previous button color
    if currentPlayingButton then
        -- Return to mode color (cyan for dance, magenta for emote)
        local modeColor = currentMode == "dance" and COLORS.Cyan or COLORS.Magenta
        currentPlayingButton.TextColor3 = modeColor
    end
    
    -- Create new animation
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://"..animId
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        currentTrack = animator:LoadAnimation(anim)
    else
        currentTrack = humanoid:LoadAnimation(anim)
    end
    
    currentTrack.Priority = Enum.AnimationPriority.Action4
    currentTrack:Play()
    currentTrack:AdjustSpeed(currentSpeed)
    
    -- Set button to yellow (playing)
    if buttonClicked then
        buttonClicked.TextColor3 = COLORS.Yellow
        currentPlayingButton = buttonClicked
    end
    
    if DEBUG_MODE then dPrint("[EmoteSystem] Playing animation: " .. animId) end
end
 
-- ============================================
-- SPEED CONTROL
-- ============================================
local function updateSpeed()
    if currentTrack and currentTrack.IsPlaying then
        currentTrack:AdjustSpeed(currentSpeed)
    end
    
    -- Update slider position
    if SpeedSlider and SpeedBar then
        local percentage = (currentSpeed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED)
        local barWidth = SpeedBar.AbsoluteSize.X - SpeedSlider.AbsoluteSize.X
        local newX = barWidth * percentage
        
        SpeedSlider.Position = UDim2.new(0, newX, SpeedSlider.Position.Y.Scale, SpeedSlider.Position.Y.Offset)
    end
end
 
local function setSpeedFromSlider(positionX)
    if not SpeedBar then return end
    
    local minX = SpeedBar.AbsolutePosition.X
    local maxX = minX + SpeedBar.AbsoluteSize.X - (SpeedSlider and SpeedSlider.AbsoluteSize.X or 0)
    
    local relativeX = math.clamp(positionX, minX, maxX) - minX
    local barWidth = maxX - minX
    
    currentSpeed = MIN_SPEED + ((relativeX / barWidth) * (MAX_SPEED - MIN_SPEED))
    
    updateSpeed()
end
 
local function initializeSpeedSlider()
    if not SpeedBar or not SpeedSlider then 
        if DEBUG_MODE then dWarn("[EmoteSystem] SpeedBar or SpeedSlider not found!") end
        return 
    end
    
    local isDragging = false
    
    SpeedSlider.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
            input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
            input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or 
            input.UserInputType == Enum.UserInputType.Touch) then
            setSpeedFromSlider(input.Position.X)
        end
    end)
    
    SpeedBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
            input.UserInputType == Enum.UserInputType.Touch then
            setSpeedFromSlider(input.Position.X)
        end
    end)
    
    -- Initialize to normal speed (1.0)
    currentSpeed = 1.0
    updateSpeed()
end
 
-- ============================================
-- UPDATE LIST
-- ============================================
local function updateList(searchTerm)
    if not ScrollingFrame or not TemplateButton then 
        if DEBUG_MODE then dWarn("[EmoteSystem] ScrollingFrame or TemplateButton not found!") end
        return 
    end
    
    -- Clear existing buttons
    for _, child in ipairs(ScrollingFrame:GetChildren()) do
        if child:IsA("TextButton") and child.Name == "AnimButton" then
            child:Destroy()
        end
    end
    
    local list = currentMode == "dance" and dances or emotes
    local displayList = {}
    
    -- Filter by search term
    if searchTerm and searchTerm ~= "" then
        for _, item in ipairs(list) do
            if string.find(string.lower(item.name), string.lower(searchTerm)) then
                table.insert(displayList, item)
            end
        end
    else
        displayList = list
    end
    
    -- Get color based on mode
    local modeColor = currentMode == "dance" and COLORS.Cyan or COLORS.Magenta
    
    -- Create buttons
    for i, item in ipairs(displayList) do
        local newButton = TemplateButton:Clone()
        newButton.Name = "AnimButton"
        newButton.LayoutOrder = i
        newButton.Visible = true
        newButton.Text = item.name
        
        -- Set color based on mode (cyan for dance, magenta for emote)
        newButton.TextColor3 = modeColor
        
        newButton.MouseButton1Click:Connect(function()
            playAnimation(item.animId, newButton)
        end)
        
        newButton.Parent = ScrollingFrame
    end
    
    -- Update canvas size secara otomatis menyesuaikan jumlah emote
    ScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    
    if DEBUG_MODE then dPrint("[EmoteSystem] Updated list with " .. #displayList .. " items") end
end
 
-- ============================================
-- SWITCH MODE (DANCE/EMOTE)
-- ============================================
local function switchMode(mode)
    currentMode = mode
    
    -- Get original colors
    local danceOriginalColor = DanceListButton and DanceListButton.BackgroundColor3 or COLORS.White
    local emoteOriginalColor = EmoteListButton and EmoteListButton.BackgroundColor3 or COLORS.White
    
    -- Update button with feedback animation
    if DanceListButton then
        if mode == "dance" then
            -- Feedback animation then return to white
            TweenService:Create(DanceListButton, TweenInfo.new(0.1), {
            BackgroundColor3 = COLORS.FeedbackActive
            }):Play()
            task.wait(0.1)
            TweenService:Create(DanceListButton, TweenInfo.new(0.2), {
            BackgroundColor3 = COLORS.White
            }):Play()
        else
            -- Keep original color when not active
            DanceListButton.BackgroundColor3 = COLORS.White
        end
    end
    
    if EmoteListButton then
        if mode == "emote" then
            -- Feedback animation then return to white
            TweenService:Create(EmoteListButton, TweenInfo.new(0.1), {
            BackgroundColor3 = COLORS.FeedbackActive
            }):Play()
            task.wait(0.1)
            TweenService:Create(EmoteListButton, TweenInfo.new(0.2), {
            BackgroundColor3 = COLORS.White
            }):Play()
        else
            -- Keep original color when not active
            EmoteListButton.BackgroundColor3 = COLORS.White
        end
    end
    
    -- Update list
    updateList()
end
 
-- ============================================
-- OPEN/CLOSE FRAME
-- ============================================
local function openFrame()
    if not EmotePanel then return end
    
    isFrameOpen = true
    EmotePanel.Visible = true
    
    if DEBUG_MODE then dPrint("[EmoteSystem] Frame opened") end
end
 
local function closeFrame()
    if not EmotePanel then return end
    
    isFrameOpen = false
    EmotePanel.Visible = false
    
    if DEBUG_MODE then dPrint("[EmoteSystem] Frame closed") end
end
 
-- ============================================
-- AUTO CLOSE WHEN OTHER GUI CLICKED
-- ============================================
local function setupAutoClose()
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextButton") then
            -- Skip buttons that should NOT close the panel
            local skipButtons = {
            "EmoteButton", "EmoteListButton", "DanceListButton", 
            "CloseButton", "SearchButton", "SpeedSlider"
            }
            
            local shouldSkip = false
            for _, skipName in ipairs(skipButtons) do
                if gui.Name == skipName then
                    shouldSkip = true
                    break
                end
            end
            
            -- Skip buttons inside EmotePanel
            if not shouldSkip then
                local parent = gui.Parent
                local isInPanel = false
                while parent do
                    if parent == EmotePanel then
                        isInPanel = true
                        break
                    end
                    parent = parent.Parent
                end
                
                if isInPanel then
                    shouldSkip = true
                end
            end
            
            if not shouldSkip then
                gui.MouseButton1Click:Connect(function()
                    if isFrameOpen then
                        closeFrame()
                    end
                end)
            end
        end
    end
end
 
-- ============================================
-- WAIT FOR GUI ELEMENTS
-- ============================================
local function waitForElements()
    if DEBUG_MODE then dPrint("[EmoteSystem] Looking for GUI elements...") end
    
    ListGui = playerGui:WaitForChild("ListGui", 999)
    if not ListGui then return false end
    
    ListTopBar = ListGui:WaitForChild("ListTopBar", 999)
    EmoteButton = ListTopBar:WaitForChild("EmoteButton", 999)
    
    IsiGui = playerGui:WaitForChild("IsiGui", 999)
    EmotePanel = IsiGui:WaitForChild("EmotePanel", 999)
    
    ScrollingFrame = EmotePanel:WaitForChild("ScrollingFrame", 999)
    EmoteListButton = EmotePanel:WaitForChild("EmoteButton", 999)
    DanceListButton = EmotePanel:WaitForChild("DanceButton", 999)
    SearchBox = EmotePanel:WaitForChild("TextBox", 999)
    CloseButton = EmotePanel:WaitForChild("CloseButton", 999)
    SpeedBar = EmotePanel:WaitForChild("SpeedBar", 999)
    
    TemplateButton = ScrollingFrame:WaitForChild("Button", 999)
    TemplateButton.Visible = false
    
    SpeedSlider = SpeedBar:WaitForChild("SpeedSlider", 999)
    SearchButton = SearchBox:WaitForChild("Button", 999)
    
    return true
end
 
-- ============================================
-- INITIALIZE SYSTEM
-- ============================================
local function initializeSystem()
    if DEBUG_MODE then dPrint("[EmoteSystem] Initializing...") end
    
    if not waitForElements() then 
        if DEBUG_MODE then dWarn("[EmoteSystem] Failed to find GUI elements!") end
        return 
    end
    
    -- Set initial state
    if EmotePanel then
        EmotePanel.Visible = false
    end
    
    -- Initialize speed slider
    if SpeedBar and SpeedSlider then
        initializeSpeedSlider()
    end
    
    -- Update initial list
    switchMode("dance")
    
    -- Connect toggle button
    if EmoteButton then
        EmoteButton.MouseButton1Click:Connect(function()
            if isFrameOpen then
                closeFrame()
            else
                openFrame()
            end
        end)
    end
    
    -- Connect close button
    if CloseButton then
        CloseButton.MouseButton1Click:Connect(closeFrame)
    end
    
    -- Connect mode switch buttons
    if DanceListButton then
        DanceListButton.MouseButton1Click:Connect(function()
            switchMode("dance")
        end)
    end
    
    if EmoteListButton then
        EmoteListButton.MouseButton1Click:Connect(function()
            switchMode("emote")
        end)
    end
    
    -- Connect search
    if SearchButton and SearchBox then
        SearchButton.MouseButton1Click:Connect(function()
            local searchTerm = SearchBox.Text
            updateList(searchTerm)
        end)
        
        SearchBox.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                local searchTerm = SearchBox.Text
                updateList(searchTerm)
            end
        end)
    end
    
    -- Setup auto close
    setupAutoClose()
    
    if DEBUG_MODE then dPrint("[EmoteSystem] Initialization complete!") end
end
 
-- ============================================
-- MAIN EXECUTION
-- ============================================
task.spawn(function()
    task.wait(1)
    
    local success, err = pcall(initializeSystem)
    if not success then
        dWarn("[EmoteSystem ERROR]: " .. err)
    end
end)

