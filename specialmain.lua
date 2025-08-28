-- mobilescript.lua
-- Reimplementation of Ability / ESP utilities using Venyx UI (mobile friendly)
-- Leaves original script.lua (Tokyo Lib UI) untouched.

-- Safety: prevent double load
if _G.__MobileAbilitiesUILoaded then return end
_G.__MobileAbilitiesUILoaded = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer

-- Knit safe require
local Knit
pcall(function()
    Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
end)
if not Knit then
    warn("[MobileAbilities] Knit not found; aborting UI load")
    return
end

-- =====================================================================
-- State
-- =====================================================================
local state = {
    abilityController = nil,
    ballController = nil,
    ballService = nil, -- Knit service reference

    -- Shot modification toggles (assist + flat aerial removed per user request)
    forceCurveShots = false,
    powerShotOn = false,
    powerShotMultiplier = 1.25,
    -- accuratePassOn removed
    -- flatAerialShotsOn removed

    originalCooldown = nil,
    heartbeatConn = nil,
    forceLoopConn = nil,

    infiniteOn = false,
    forceFlow = false,
    infiniteStaminaOn = false,

    -- Anti ragdoll
    antiRagdollOn = false,
    antiRagdollConn = nil,
    characterAddedConn = nil,

    -- Auto Dribble
    autoDribbleOn = false,
    autoDribbleConn = nil,
    lastAutoDribbleTime = 0,
    autoDribbleCooldown = 0.45,

    -- ESP (Ball)
    ballESPOn = false,
    ballESPRadius = 14,
    ballESPColor = Color3.fromRGB(255,200,0),
    ballESPShowDistance = true,
    ballESPCircle = nil,
    ballESPText = nil,
    ballESPUpdateConn = nil,
    ballESPSearchConn = nil,

    -- ESP (Player)
    playerESPOn = false,
    playerESPShowDistance = true,
    playerESPRadius = 16, -- half size of square
    playerESPUseTeamColors = true,
    playerESPColor = Color3.fromRGB(255,255,255),
    playerESPShowTeammates = true,
    playerESPShowEnemies = true,
    playerESPUpdateConn = nil,
    playerESPSearchConn = nil,
    playerESPDrawings = {}, -- [player] = {box=, text=}

    -- Aiming Line State
    showOwnAimLine = false,
    showOtherAimLine = false,
    playerIndicators = {}, -- Manages Beam objects for all players
    aimLineUpdateConn = nil,
    aimLineLength = 75,
    aimLineWidth = 0.2,

    -- UI refs
    ui = nil,
    menuOpen = true,
    mobileToggleGui = nil,
    mobileToggleButton = nil,
}

-- =====================================================================
-- Helpers
-- =====================================================================
local function getStat(name)
    local ps = localPlayer:FindFirstChild("PlayerStats")
    return ps and ps:FindFirstChild(name)
end

-- Ability cooldown override
local function instantReady(slot)
    if not state.abilityController then return end
    local key = slot == "1" and "AbilityOne" or slot == "2" and "AbilityTwo" or slot == "3" and "AbilityThree"
    if key then state.abilityController[key] = tick() end
    state.abilityController.AbilityUsed = tick() - 999
    state.abilityController.JustOne = tick() - 999
end

local function applyInfinite()
    if state.infiniteOn or not state.abilityController then return end
    if not state.originalCooldown then state.originalCooldown = state.abilityController.AbilityCooldown end
    state.abilityController.AbilityCooldown = function(self, slot, baseCd, originalCd, bypass)
        instantReady("1"); instantReady("2"); instantReady("3")
    end
    state.heartbeatConn = RunService.Heartbeat:Connect(function()
        instantReady("1"); instantReady("2"); instantReady("3")
    end)
    state.infiniteOn = true
    print("[MobileAbilities] Infinite abilities ON")
end

local function removeInfinite()
    if not state.infiniteOn then return end
    if state.originalCooldown and state.abilityController then
        state.abilityController.AbilityCooldown = state.originalCooldown
    end
    if state.heartbeatConn then state.heartbeatConn:Disconnect(); state.heartbeatConn=nil end
    state.infiniteOn = false
    print("[MobileAbilities] Infinite abilities OFF")
end

local function toggleFlow(on)
    state.forceFlow = on
    if state.forceLoopConn then state.forceLoopConn:Disconnect(); state.forceLoopConn=nil end
    if on then
        state.forceLoopConn = RunService.Heartbeat:Connect(function()
            local inflow = getStat("InFlow")
            if inflow and inflow.Value ~= true then inflow.Value = true end
        end)
    end
    print("[MobileAbilities] Force Flow =", on)
end

-- Infinite stamina
local function enforceInfiniteStamina()
    local stamina = getStat("Stamina")
    if stamina and stamina.Value < 100 then stamina.Value = 100 end
end
local function toggleInfiniteStamina(on)
    state.infiniteStaminaOn = on
    if state.staminaConn then state.staminaConn:Disconnect(); state.staminaConn=nil end
    if on then
        state.staminaConn = RunService.Heartbeat:Connect(enforceInfiniteStamina)
    end
    print("[MobileAbilities] Infinite Stamina =", on)
end

-- Anti ragdoll
local function enforceAntiRagdollOnce(char)
    if not char then return end
    local isRagdoll = char:FindFirstChild("IsRagdoll")
    if isRagdoll and isRagdoll.Value ~= false then isRagdoll.Value = false end
    local values = char:FindFirstChild("Values")
    if values then
        local stunned = values:FindFirstChild("Stunned")
        if stunned and stunned.Value ~= false then stunned.Value = false end
    end
end
local function toggleAntiRagdoll(on)
    state.antiRagdollOn = on
    if not on then
        if state.antiRagdollConn then state.antiRagdollConn:Disconnect(); state.antiRagdollConn=nil end
        if state.characterAddedConn then state.characterAddedConn:Disconnect(); state.characterAddedConn=nil end
        print('[MobileAbilities] Anti Ragdoll OFF')
        return
    end
    enforceAntiRagdollOnce(localPlayer.Character)
    if state.antiRagdollConn then state.antiRagdollConn:Disconnect() end
    state.antiRagdollConn = RunService.Heartbeat:Connect(function()
        local char = localPlayer.Character
        if char then enforceAntiRagdollOnce(char) end
    end)
    if state.characterAddedConn then state.characterAddedConn:Disconnect() end
    state.characterAddedConn = localPlayer.CharacterAdded:Connect(function(c)
        task.delay(0.25, function()
            if state.antiRagdollOn then enforceAntiRagdollOnce(c) end
        end)
    end)
    print('[MobileAbilities] Anti Ragdoll ON')
end

-- Auto Dribble (simplified threat check)
local function autoDribbleCheck()
    if not state.autoDribbleOn then return end
    local char = localPlayer.Character; if not char then return end
    local values = char:FindFirstChild("Values"); if not values then return end
    local hasBall = values:FindFirstChild("HasBall")
    if not (hasBall and hasBall.Value) then return end
    local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local now = tick()
    if now - state.lastAutoDribbleTime < state.autoDribbleCooldown then return end
    -- Basic: if any other player within 16 studs & moving toward us, trigger
    local trigger = false
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer then
            local echar = plr.Character
            local ehrp = echar and (echar:FindFirstChild("HumanoidRootPart") or echar:FindFirstChild("Head"))
            if ehrp then
                local dist = (ehrp.Position - hrp.Position).Magnitude
                if dist < 16 then
                    trigger = true; break
                end
            end
        end
    end
    if trigger and state.ballController and state.ballController.Dribble then
        pcall(function() state.ballController:Dribble() end)
        state.lastAutoDribbleTime = now
    end
end
local function toggleAutoDribble(on)
    state.autoDribbleOn = on
    if state.autoDribbleConn then state.autoDribbleConn:Disconnect(); state.autoDribbleConn=nil end
    if on then
        state.autoDribbleConn = RunService.Heartbeat:Connect(autoDribbleCheck)
    end
    print('[MobileAbilities] Auto Dribble =', on)
end

-- Goal / net finder using workspace.Goals with parts Home and Away
local goalCache = { lastScan = 0, homeParts = {}, awayParts = {} }
local function scanGoals()
    goalCache.homeParts = {}
    goalCache.awayParts = {}
    local goalsFolder = workspace:FindFirstChild("Goals")
    if not goalsFolder then return end
    local home = goalsFolder:FindFirstChild("Home")
    local away = goalsFolder:FindFirstChild("Away")
    local function collectParts(container, store)
        if not container then return end
        if container:IsA("BasePart") then table.insert(store, container) return end
        for _,desc in ipairs(container:GetDescendants()) do
            if desc:IsA("BasePart") then table.insert(store, desc) end
        end
    end
    collectParts(home, goalCache.homeParts)
    collectParts(away, goalCache.awayParts)
    goalCache.lastScan = tick()
end

local function averagePosition(parts)
    if #parts == 0 then return nil end
    local sum = Vector3.zero
    for _,p in ipairs(parts) do sum += p.Position end
    return sum / #parts
end

-- (Removed aim-at-goal feature entirely)

-- =====================================================================
-- Ball ESP
-- =====================================================================
local cachedBall
local function ensureBallDrawings()
    if not state.ballESPCircle then
        local c = Drawing.new("Circle")
        c.Thickness = 2; c.Filled=false; c.Transparency=1; c.Visible=false
        c.Color = state.ballESPColor; c.Radius = state.ballESPRadius
        state.ballESPCircle = c
    end
    if not state.ballESPText then
        local t = Drawing.new("Text")
        t.Size=14; t.Center=true; t.Outline=true; t.Transparency=1
        t.Color = state.ballESPColor; t.Text="BALL"; t.Visible=false
        state.ballESPText = t
    end
end
local function destroyBallDrawings()
    if state.ballESPCircle then pcall(function() state.ballESPCircle:Remove() end); state.ballESPCircle=nil end
    if state.ballESPText then pcall(function() state.ballESPText:Remove() end); state.ballESPText=nil end
end
local function findBall()
    local top = workspace:FindFirstChild("Football")
    if top then
        if top:IsA("BasePart") then return top end
        if top:IsA("Model") then
            local primary = top.PrimaryPart or top:FindFirstChildWhichIsA("BasePart")
            if primary then return primary end
        end
    end
    for _,plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and char:FindFirstChild("Football") then
            local b = char:FindFirstChild("Football")
            if b:IsA("BasePart") then return b end
            if b:IsA("Model") then
                local pp = b.PrimaryPart or b:FindFirstChildWhichIsA("BasePart")
                if pp then return pp end
            end
        end
    end
    return nil
end
local function updateBallDrawingProps()
    if state.ballESPCircle then
        state.ballESPCircle.Radius = state.ballESPRadius
        state.ballESPCircle.Color = state.ballESPColor
    end
    if state.ballESPText then state.ballESPText.Color = state.ballESPColor end
end
local function updateBallESP()
    if not state.ballESPOn then return end
    if not cachedBall or not cachedBall.Parent then cachedBall = findBall(); if not cachedBall then return end end
    local cam = workspace.CurrentCamera; if not cam then return end
    local pos, onScreen = cam:WorldToViewportPoint(cachedBall.Position)
    ensureBallDrawings()
    if onScreen then
        state.ballESPCircle.Position = Vector2.new(pos.X, pos.Y)
        state.ballESPCircle.Visible = true
        local dist = 0
        local myhrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if myhrp then dist = (myhrp.Position - cachedBall.Position).Magnitude end
        state.ballESPText.Position = Vector2.new(pos.X, pos.Y - (state.ballESPRadius + 14))
        state.ballESPText.Text = state.ballESPShowDistance and ("BALL ("..math.floor(dist)..")") or "BALL"
        state.ballESPText.Visible = true
    else
        state.ballESPCircle.Visible = false
        state.ballESPText.Visible = false
    end
end
local function toggleBallESP(on)
    state.ballESPOn = on
    if not on then
        if state.ballESPUpdateConn then state.ballESPUpdateConn:Disconnect(); state.ballESPUpdateConn=nil end
        if state.ballESPSearchConn then state.ballESPSearchConn:Disconnect(); state.ballESPSearchConn=nil end
        destroyBallDrawings(); print('[MobileAbilities] Ball ESP OFF'); return
    end
    ensureBallDrawings(); updateBallDrawingProps(); cachedBall = findBall()
    state.ballESPUpdateConn = RunService.RenderStepped:Connect(updateBallESP)
    state.ballESPSearchConn = RunService.Heartbeat:Connect(function()
        if not cachedBall or not cachedBall.Parent then cachedBall = findBall() end
    end)
    print('[MobileAbilities] Ball ESP ON')
end

-- =====================================================================
-- Player ESP
-- =====================================================================
local function destroyPlayerDrawings(plr)
    local d = state.playerESPDrawings[plr]
    if not d then return end
    if d.box then pcall(function() d.box:Remove() end) end
    if d.text then pcall(function() d.text:Remove() end) end
    state.playerESPDrawings[plr] = nil
end
local function destroyAllPlayerDrawings()
    for plr,_ in pairs(state.playerESPDrawings) do destroyPlayerDrawings(plr) end
end
local function ensurePlayerDrawings(plr)
    local entry = state.playerESPDrawings[plr]
    if entry and entry.box and entry.text then return entry end
    entry = entry or {}
    if not entry.box then
        local b = Drawing.new("Square")
        b.Thickness=2; b.Filled=false; b.Transparency=1; b.Visible=false
        b.Color = state.playerESPColor
        entry.box = b
    end
    if not entry.text then
        local t = Drawing.new("Text")
        t.Size=14; t.Center=true; t.Outline=true; t.Transparency=1; t.Visible=false
        entry.text = t
    end
    state.playerESPDrawings[plr] = entry
    return entry
end
local function getPlayerTeamColor(plr)
    -- Priority: Roblox Team object -> TeamColor -> custom TeamColor StringValue -> fallback
    local team = plr.Team
    if team then
        if team.TeamColor then
            local ok,color = pcall(function() return team.TeamColor.Color end)
            if ok and color then return color end
        end
        if team.Color then
            local ok2,color2 = pcall(function() return team.Color end)
            if ok2 and typeof(color2)=="Color3" then return color2 end
        end
    end
    local stats = plr:FindFirstChild("PlayerStats")
    if stats then
        local tc = stats:FindFirstChild("TeamColor") or stats:FindFirstChild("TeamColour")
        if tc and tc:IsA("StringValue") then
            local raw = tc.Value
            if raw and raw ~= "" then
                local first = raw:split("-")[1]
                first = first and first:match("^%s*(.-)%s*$") or raw
                local okB,brick = pcall(function() return BrickColor.new(first) end)
                if okB and brick then return brick.Color end
            end
        end
    end
    return Color3.fromRGB(200,200,200)
end
local function updateOnePlayerESP(plr, cam, myTeamColor)
    if plr == localPlayer then return end
    local char = plr.Character; if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"); if not hrp then return end
    local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
    local entry = ensurePlayerDrawings(plr)
    if not onScreen then entry.box.Visible=false; entry.text.Visible=false; return end
    local show = true
    local sameTeam = (plr.Team ~= nil and localPlayer.Team ~= nil and plr.Team == localPlayer.Team)
    if sameTeam and not state.playerESPShowTeammates then show=false end
    if (not sameTeam) and not state.playerESPShowEnemies then show=false end
    if not show then entry.box.Visible=false; entry.text.Visible=false; return end
    local color = state.playerESPUseTeamColors and getPlayerTeamColor(plr) or state.playerESPColor
    local half = state.playerESPRadius
    entry.box.Size = Vector2.new(half*2, half*2)
    entry.box.Position = Vector2.new(pos.X - half, pos.Y - half)
    entry.box.Color = color
    entry.box.Visible = true
    local dist = 0
    local myhrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if myhrp then dist = (myhrp.Position - hrp.Position).Magnitude end
    entry.text.Position = Vector2.new(pos.X, pos.Y - (half + 14))
    entry.text.Color = color
    entry.text.Text = state.playerESPShowDistance and (plr.Name.. " (".. math.floor(dist).. ")") or plr.Name
    entry.text.Visible = true
end
local function updatePlayerESP()
    if not state.playerESPOn then return end
    local cam = workspace.CurrentCamera; if not cam then return end
    for _,plr in ipairs(Players:GetPlayers()) do
        updateOnePlayerESP(plr, cam)
    end
end
local function togglePlayerESP(on)
    state.playerESPOn = on
    if not on then
        if state.playerESPUpdateConn then state.playerESPUpdateConn:Disconnect(); state.playerESPUpdateConn=nil end
        if state.playerESPSearchConn then state.playerESPSearchConn:Disconnect(); state.playerESPSearchConn=nil end
        destroyAllPlayerDrawings(); print('[MobileAbilities] Player ESP OFF'); return
    end
    if state.playerESPUpdateConn then state.playerESPUpdateConn:Disconnect() end
    state.playerESPUpdateConn = RunService.RenderStepped:Connect(updatePlayerESP)
    if state.playerESPSearchConn then state.playerESPSearchConn:Disconnect() end
    state.playerESPSearchConn = Players.PlayerRemoving:Connect(function(plr)
        destroyPlayerDrawings(plr)
    end)
    print('[MobileAbilities] Player ESP ON')
end

-- Settings setters for sliders / pickers
local function setBallESPRadius(v) state.ballESPRadius = v; updateBallDrawingProps() end
local function setBallESPColor(c) state.ballESPColor = c; updateBallDrawingProps() end
local function setBallESPShowDistance(on) state.ballESPShowDistance = on end

local function setPlayerESPRadius(v) state.playerESPRadius = v end
local function setPlayerESPColor(c) state.playerESPColor = c end
local function setPlayerESPShowDistance(on) state.playerESPShowDistance = on end
local function setPlayerESPUseTeamColors(on) state.playerESPUseTeamColors = on end
local function setPlayerESPShowTeammates(on) state.playerESPShowTeammates = on end
local function setPlayerESPShowEnemies(on) state.playerESPShowEnemies = on end

-- =====================================================================
-- Aiming Line
-- =====================================================================
local LINE_COLOR_SELF = Color3.fromRGB(75, 255, 150)
local LINE_COLOR_OTHER = Color3.fromRGB(255, 180, 75)
local LINE_TEXTURE = "rbxassetid://284989634"
local VERTICAL_CLAMP = -0.05

local aimLineSystemActive = false
local aimLinePlayerAddedConn, aimLinePlayerRemovingConn

local function updateAllAimingLines()
    for player, indicator in pairs(state.playerIndicators) do
        local shouldShowForPlayer = (player == localPlayer and state.showOwnAimLine) or (player ~= localPlayer and state.showOtherAimLine)
        if indicator.beam.Enabled and indicator.character and indicator.hrp and indicator.hrp.Parent and shouldShowForPlayer then
            local originPos = indicator.attachment0.WorldPosition
            local aimDirection
            if player == localPlayer then
                aimDirection = workspace.CurrentCamera.CFrame.LookVector
            else
                aimDirection = indicator.hrp.CFrame.LookVector
            end
            if aimDirection.Y < VERTICAL_CLAMP then
                aimDirection = Vector3.new(aimDirection.X, VERTICAL_CLAMP, aimDirection.Z).Unit
            end
            local endPos = originPos + (aimDirection * state.aimLineLength)
            indicator.attachment1.WorldPosition = endPos
        end
    end
end

local function onHasBallChanged(indicator, hasBall, player)
    local shouldShow = (player == localPlayer and state.showOwnAimLine) or (player ~= localPlayer and state.showOtherAimLine)
    indicator.beam.Enabled = hasBall and shouldShow
end

local function setupCharacterForPlayer(player, character)
    local indicator = state.playerIndicators[player]
    if not indicator then return end
    indicator.character = character
    indicator.hrp = character:WaitForChild("HumanoidRootPart")
    indicator.attachment0.Parent = indicator.hrp
    local valuesFolder = character:WaitForChild("Values")
    local hasBallValue = valuesFolder:WaitForChild("HasBall")
    local conn = hasBallValue:GetPropertyChangedSignal("Value"):Connect(function()
        onHasBallChanged(indicator, hasBallValue.Value, player)
    end)
    table.insert(indicator.connections, conn)
    onHasBallChanged(indicator, hasBallValue.Value, player)
end

local function cleanupCharacterForPlayer(player)
    local indicator = state.playerIndicators[player]
    if not indicator then return end
    for _, conn in ipairs(indicator.connections) do
        conn:Disconnect()
    end
    table.clear(indicator.connections)
    indicator.beam.Enabled = false
    indicator.character = nil
    indicator.hrp = nil
end

local function cleanupPlayer(player)
    local indicator = state.playerIndicators[player]
    if not indicator then return end
    cleanupCharacterForPlayer(player)
    indicator.beam:Destroy()
    indicator.attachment0:Destroy()
    indicator.attachment1:Destroy()
    state.playerIndicators[player] = nil
end

local function setupPlayer(player)
    if state.playerIndicators[player] then return end
    local attachment0 = Instance.new("Attachment")
    attachment0.Name = "AimOriginAttachment"
    local attachment1 = Instance.new("Attachment")
    attachment1.Name = "AimEndAttachment"
    attachment1.Parent = workspace.Terrain
    local aimBeam = Instance.new("Beam")
    aimBeam.Name = "AimingBeam"
    aimBeam.Attachment0 = attachment0
    aimBeam.Attachment1 = attachment1
    aimBeam.LightEmission = 1
    aimBeam.LightInfluence = 0
    aimBeam.Texture = LINE_TEXTURE
    aimBeam.TextureMode = Enum.TextureMode.Stretch
    aimBeam.TextureLength = 1
    aimBeam.Width0 = state.aimLineWidth
    aimBeam.Width1 = state.aimLineWidth
    aimBeam.FaceCamera = true
    aimBeam.Enabled = false
    aimBeam.Parent = workspace.Terrain
    if player == localPlayer then
        aimBeam.Color = ColorSequence.new(LINE_COLOR_SELF)
    else
        aimBeam.Color = ColorSequence.new(LINE_COLOR_OTHER)
    end
    local indicator = {
        beam = aimBeam,
        attachment0 = attachment0,
        attachment1 = attachment1,
        character = nil,
        hrp = nil,
        connections = {}
    }
    state.playerIndicators[player] = indicator
    if player.Character then
        setupCharacterForPlayer(player, player.Character)
    end
    player.CharacterAdded:Connect(function(char)
        cleanupCharacterForPlayer(player)
        setupCharacterForPlayer(player, char)
    end)
    player.CharacterRemoving:Connect(function()
        cleanupCharacterForPlayer(player)
    end)
end

local function toggleAimLineSystem()
    local shouldBeActive = state.showOwnAimLine or state.showOtherAimLine
    if shouldBeActive and not aimLineSystemActive then
        aimLineSystemActive = true
        state.aimLineUpdateConn = RunService.RenderStepped:Connect(updateAllAimingLines)
        aimLinePlayerAddedConn = Players.PlayerAdded:Connect(setupPlayer)
        aimLinePlayerRemovingConn = Players.PlayerRemoving:Connect(cleanupPlayer)
        for _, player in ipairs(Players:GetPlayers()) do
            setupPlayer(player)
        end
        print("[MobileAbilities] Aim Line System ON")
    elseif not shouldBeActive and aimLineSystemActive then
        aimLineSystemActive = false
        if state.aimLineUpdateConn then state.aimLineUpdateConn:Disconnect(); state.aimLineUpdateConn = nil end
        if aimLinePlayerAddedConn then aimLinePlayerAddedConn:Disconnect(); aimLinePlayerAddedConn = nil end
        if aimLinePlayerRemovingConn then aimLinePlayerRemovingConn:Disconnect(); aimLinePlayerRemovingConn = nil end
        for player, _ in pairs(state.playerIndicators) do
            cleanupPlayer(player)
        end
        print("[MobileAbilities] Aim Line System OFF")
    end
    -- Update visibility for all existing indicators after a toggle change
    for player, indicator in pairs(state.playerIndicators) do
        if indicator.character and indicator.character:FindFirstChild("Values") then
            local hasBall = indicator.character.Values.HasBall.Value
            onHasBallChanged(indicator, hasBall, player)
        end
    end
end

-- =====================================================================
-- UI (Rayfield)
-- =====================================================================
local function buildUI()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    local Window = Rayfield:CreateWindow({
        Name = "Blue Lock Utilities (Mobile)",
        LoadingTitle = "Blue Lock Utilities",
        LoadingSubtitle = "by Script Team",
        ConfigurationSaving = {
            Enabled = false,
        },
        Discord = {
            Enabled = false,
        },
        KeySystem = false,
    })
    state.ui = Window

    -- Tabs
    local MainTab = Window:CreateTab("Main", 4483362458)
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    local ESPTab = Window:CreateTab("ESP", 4483362458)
    local ShotsTab = Window:CreateTab("Shots", 4483362458)
    local AimTab = Window:CreateTab("Aim", 4483362458)
    local FlowsTab = Window:CreateTab("Flows", 4483362458)

    -- Core Section
    local CoreSection = MainTab:CreateSection("Core Features")
    
    MainTab:CreateToggle({
        Name = "Infinite Abilities",
        CurrentValue = false,
        Flag = "InfiniteAbilities",
        Callback = function(Value)
            if Value then applyInfinite() else removeInfinite() end
        end,
    })

    MainTab:CreateToggle({
        Name = "Force Flow",
        CurrentValue = false,
        Flag = "ForceFlow",
        Callback = function(Value)
            toggleFlow(Value)
        end,
    })

    MainTab:CreateToggle({
        Name = "Infinite Stamina",
        CurrentValue = false,
        Flag = "InfiniteStamina",
        Callback = function(Value)
            toggleInfiniteStamina(Value)
        end,
    })

    -- Combat Section
    local CombatSection = CombatTab:CreateSection("Combat Aids")

    CombatTab:CreateToggle({
        Name = "Auto Dribble",
        CurrentValue = false,
        Flag = "AutoDribble",
        Callback = function(Value)
            toggleAutoDribble(Value)
        end,
    })

    CombatTab:CreateToggle({
        Name = "Anti Ragdoll",
        CurrentValue = false,
        Flag = "AntiRagdoll",
        Callback = function(Value)
            toggleAntiRagdoll(Value)
        end,
    })

    -- ESP Section
    local BallESPSection = ESPTab:CreateSection("Ball ESP")

    ESPTab:CreateToggle({
        Name = "Ball ESP",
        CurrentValue = false,
        Flag = "BallESP",
        Callback = function(Value)
            toggleBallESP(Value)
        end,
    })

    ESPTab:CreateSlider({
        Name = "Ball ESP Radius",
        Range = {4, 80},
        Increment = 1,
        Suffix = "px",
        CurrentValue = state.ballESPRadius,
        Flag = "BallESPRadius",
        Callback = function(Value)
            setBallESPRadius(Value)
        end,
    })

    ESPTab:CreateToggle({
        Name = "Show Ball Distance",
        CurrentValue = state.ballESPShowDistance,
        Flag = "BallESPDistance",
        Callback = function(Value)
            setBallESPShowDistance(Value)
        end,
    })

    ESPTab:CreateColorPicker({
        Name = "Ball ESP Color",
        Color = state.ballESPColor,
        Flag = "BallESPColor",
        Callback = function(Value)
            setBallESPColor(Value)
        end
    })

    local PlayerESPSection = ESPTab:CreateSection("Player ESP")

    ESPTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "PlayerESP",
        Callback = function(Value)
            togglePlayerESP(Value)
        end,
    })

    ESPTab:CreateSlider({
        Name = "Player ESP Box Size",
        Range = {4, 80},
        Increment = 1,
        Suffix = "px",
        CurrentValue = state.playerESPRadius,
        Flag = "PlayerESPRadius",
        Callback = function(Value)
            setPlayerESPRadius(Value)
        end,
    })

    ESPTab:CreateToggle({
        Name = "Show Player Distance",
        CurrentValue = state.playerESPShowDistance,
        Flag = "PlayerESPDistance",
        Callback = function(Value)
            setPlayerESPShowDistance(Value)
        end,
    })

    ESPTab:CreateToggle({
        Name = "Use Team Colors",
        CurrentValue = state.playerESPUseTeamColors,
        Flag = "PlayerESPTeamColors",
        Callback = function(Value)
            setPlayerESPUseTeamColors(Value)
        end,
    })

    ESPTab:CreateToggle({
        Name = "Show Teammates",
        CurrentValue = state.playerESPShowTeammates,
        Flag = "PlayerESPTeammates",
        Callback = function(Value)
            setPlayerESPShowTeammates(Value)
        end,
    })

    ESPTab:CreateToggle({
        Name = "Show Enemies",
        CurrentValue = state.playerESPShowEnemies,
        Flag = "PlayerESPEnemies",
        Callback = function(Value)
            setPlayerESPShowEnemies(Value)
        end,
    })

    ESPTab:CreateColorPicker({
        Name = "Player ESP Fallback Color",
        Color = state.playerESPColor,
        Flag = "PlayerESPColor",
        Callback = function(Value)
            setPlayerESPColor(Value)
        end
    })

    -- Shots Section
    local ShotsSection = ShotsTab:CreateSection("Shot Modifications")

    ShotsTab:CreateToggle({
        Name = "Force Curve Shots",
        CurrentValue = false,
        Flag = "ForceCurveShots",
        Callback = function(Value)
            state.forceCurveShots = Value
        end,
    })

    ShotsTab:CreateToggle({
        Name = "Power Shot",
        CurrentValue = false,
        Flag = "PowerShot",
        Callback = function(Value)
            state.powerShotOn = Value
            -- If an earlier version overrode Shoot, restore it to keep charge bar functional
            if state._originalShoot and state.ballController then
                state.ballController.Shoot = state._originalShoot
                state._originalShoot = nil
            end
        end,
    })

    ShotsTab:CreateSlider({
        Name = "Power Multiplier",
        Range = {1.0, 15.0},
        Increment = 0.01,
        Suffix = "x",
        CurrentValue = state.powerShotMultiplier,
        Flag = "PowerMultiplier",
        Callback = function(Value)
            state.powerShotMultiplier = Value
        end,
    })

    -- Aim Section
    local AimSection = AimTab:CreateSection("Aiming Assistance")

    AimTab:CreateToggle({
        Name = "Draw Your Aiming Line",
        CurrentValue = false,
        Flag = "ShowOwnAimLine",
        Callback = function(Value)
            state.showOwnAimLine = Value
            toggleAimLineSystem()
        end,
    })

    AimTab:CreateToggle({
        Name = "Draw Ball Holder Aiming Line",
        CurrentValue = false,
        Flag = "ShowOtherAimLine",
        Callback = function(Value)
            state.showOtherAimLine = Value
            toggleAimLineSystem()
        end,
    })

    AimTab:CreateSlider({
        Name = "Line Length",
        Range = {10, 400},
        Increment = 1,
        Suffix = "studs",
        CurrentValue = state.aimLineLength,
        Flag = "AimLineLength",
        Callback = function(Value)
            state.aimLineLength = Value
        end,
    })

    AimTab:CreateSlider({
        Name = "Line Width",
        Range = {0.05, 2.0},
        Increment = 0.01,
        Suffix = "studs",
        CurrentValue = state.aimLineWidth,
        Flag = "AimLineWidth",
        Callback = function(Value)
            state.aimLineWidth = Value
            -- Iterate and update existing beams
            for _, indicator in pairs(state.playerIndicators) do
                if indicator.beam then
                    indicator.beam.Width0 = Value
                    indicator.beam.Width1 = Value
                end
            end
        end,
    })

    -- Flows Section
    local FlowsSection = FlowsTab:CreateSection("Flow Management")
    
    local availableFlows = {
        "Genius","Monster","Wild Card","Puzzle","Lightning","Demon Wings","Stealth","King's Authority","Snake","Destructive Impulses","Trap","Dribbler","Ice","Buddha's Blessing","Crow","Soul Harvester","Awakened Genius","Emperor","Bee Freestyle","Godspeed","Master Of All Trades","Singularity","Contrarian","Homeless Man"
    }

    local function setFlowValue(flowName)
        local ps = localPlayer:FindFirstChild("PlayerStats")
        if not ps then return end
        local flow = ps:FindFirstChild("Flow")
        if flow and flow:IsA("StringValue") then
            flow.Value = flowName
            Rayfield:Notify({
                Title = "Flow Changed",
                Content = "Flow set to: ".. flowName,
                Duration = 3,
                Image = 4483362458,
            })
        end
    end

    FlowsTab:CreateDropdown({
        Name = "Select Flow",
        Options = availableFlows,
        CurrentOption = "Genius",
        Flag = "FlowSelection",
        Callback = function(Option)
            setFlowValue(Option)
        end,
    })

    FlowsTab:CreateButton({
        Name = "Cycle Next Flow",
        Callback = function()
            local ps = localPlayer:FindFirstChild("PlayerStats")
            if not ps then return end
            local flow = ps:FindFirstChild("Flow")
            if not (flow and flow:IsA("StringValue")) then return end
            local current = flow.Value
            local idx = 0
            for i,name in ipairs(availableFlows) do 
                if name == current then 
                    idx = i 
                    break 
                end 
            end
            local nextName = availableFlows[(idx % #availableFlows) + 1]
            setFlowValue(nextName)
        end,
    })

    state.menuOpen = true
    print('[MobileAbilities] Rayfield UI initialized (mobile optimized)')
end

-- =====================================================================
-- Knit start & init
-- =====================================================================
Knit.OnStart():andThen(function()
    pcall(function() state.abilityController = Knit.GetController("AbilityController") end)
    pcall(function() state.ballController = Knit.GetController("BallController") end)
    pcall(function() state.ballService = Knit.GetService("BallService") end)

    -- Hook BallService remotes (client-side velocity adjustments)
    if state.ballService then
        -- Attempt to require AbilityUtils for curve direction (mirrors main logic naming)
        local AbilityUtils
        pcall(function()
            AbilityUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityUtils"))
        end)

        local function applyForcedCurve(ball, power)
            if not state.forceCurveShots then return end
            if not ball or not ball.Parent then return end
            -- Skip if ball already attached / on player
            local onPlayerTag = ball:FindFirstChild("OnPlayer")
            if onPlayerTag and onPlayerTag.Value then return end
            local lateral
            if AbilityUtils then
                pcall(function() lateral = AbilityUtils.FindCurveDirection(Players.LocalPlayer) end)
            end
            if not lateral then
                -- Fallback lateral perpendicular to camera look
                local cam = workspace.CurrentCamera
                if cam then
                    local look = cam.CFrame.LookVector
                    lateral = Vector3.new(-look.Z, 0, look.X).Unit
                end
            end
            if not lateral then return end
            -- Destructive Impulses mimic:
            -- 1. Inject initial lateral component (half-strength) into current velocity.
            -- 2. Start curve scalar at -power/2.75 (stronger initial bend) and ease toward -power/8.
            -- 3. Each frame increase scalar by power/6 * dt and lerp velocity toward adding lateral * scalar.
            local baseVel = ball.AssemblyLinearVelocity
            local speed = baseVel.Magnitude
            if speed < 5 then speed = power end
            -- Initial lateral injection (half of current speed) similar to (forward+vertical+lateral/2)*power pattern
            ball.AssemblyLinearVelocity = baseVel + (lateral * (speed * 0.5))
            local scalar = -(power / 2.75)
            local finalLimit = -(power / 8)
            local conn
            conn = RunService.Heartbeat:Connect(function(dt)
                if not ball or not ball.Parent then if conn then conn:Disconnect() end return end
                local onPlayer = ball:FindFirstChild("OnPlayer")
                if onPlayer and onPlayer.Value then if conn then conn:Disconnect() end return end
                scalar = scalar + (power/6) * dt
                if scalar > finalLimit then scalar = finalLimit end
                ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity:Lerp(ball.AssemblyLinearVelocity + lateral * scalar, 6.5 * dt)
                if scalar >= finalLimit - 0.01 then if conn then conn:Disconnect() end end
            end)
        end

        -- Assuming BallService exposes signals RemoteEvents; use :Connect if RBXScriptSignal
        if state.ballService.Shoot and typeof(state.ballService.Shoot.Connect) == "function" then
            state.ballService.Shoot:Connect(function(ball, a1, a2,...)
                if not (ball and ball.Parent) then return end
                local extra = {...}
                -- Parse arguments: first number = power, second number = arc (if any), first string = style token.
                local power, arc, style
                local candidates = {a1, a2}
                for _,v in ipairs(extra) do table.insert(candidates, v) end
                for _,v in ipairs(candidates) do
                    if not power and type(v)=="number" then power = v elseif power and not arc and type(v)=="number" then arc = v end
                    if not style and type(v)=="string" then style = v end
                end
                power = power or 100
                -- Classification sets
                local aerialStyles = {
                    Volley = true,
                    Bicycle = true,
                    BicycleState = true,
                    Flick = true,
                    FlickKick = true,
                    Header = true,
                }
                -- Animation based fallback (if style not provided yet)
                if not style and state.ballController and state.ballController.Animations then
                    local anims = state.ballController.Animations
                    pcall(function()
                        if anims.Shots and anims.Shots.Volley and anims.Shots.Volley.IsPlaying then style = "Volley" end
                        if anims.Bicycles and anims.Bicycles.Bicycle and anims.Bicycles.Bicycle.IsPlaying then style = "Bicycle" end
                        if anims.Movement and anims.Movement.Header and anims.Movement.Header.IsPlaying then style = "Header" end
                    end)
                end
                -- State controller fallback
                if not style and state.ballController and state.ballController.StatesController and state.ballController.StatesController.States then
                    local st = state.ballController.StatesController.States
                    if st.Bicycle then style = "Bicycle" end
                end
                -- Heuristic aerial if none yet but arc large or vertical velocity big
                local vel = ball.AssemblyLinearVelocity
                local aerial = false
                if style and aerialStyles[style] then aerial = true end
                if not aerial then
                    if type(arc) == "number" and arc > 0.05 then aerial = true end
                    if math.abs(vel.Y) > 28 then aerial = true end
                end
                -- Apply multiplier only for ground kick (non-aerial)
                if not aerial and state.powerShotOn and state.powerShotMultiplier and state.powerShotMultiplier > 1 then
                    task.defer(function()
                        if not (ball and ball.Parent) then return end
                        ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity * state.powerShotMultiplier
                    end)
                end
                -- Flatten only ground kick shots if enabled
                if not aerial and state.flatAerialShotsOn then
                    local v = ball.AssemblyLinearVelocity
                    local horiz = Vector3.new(v.X, 0, v.Z)
                    local hmag = horiz.Magnitude
                    if hmag > 5 then
                        local total = v.Magnitude
                        ball.AssemblyLinearVelocity = horiz.Unit * total
                    end
                end
                -- Force curve last
                local effectivePower = power * (state.powerShotOn and not aerial and state.powerShotMultiplier or 1)
                applyForcedCurve(ball, effectivePower)
            end)
        end

        -- Pass assist removed per user request
    end
    buildUI()
end)
