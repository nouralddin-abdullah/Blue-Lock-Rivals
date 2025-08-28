-- ################################# --
-- ##      CONFIGURATION      ## --
-- ################################# --

local KEY_CHECK_ENABLED = false -- Set this to false to bypass the key check

-- CONFIGURE YOUR LINKS HERE
local MAIN_SCRIPT_URL = "https://raw.githubusercontent.com/nouralddin-abdullah/Blue-Lock-Rivals/refs/heads/main/specialmain.lua" -- Paste your Main Script URL from Step 1 here
local KEY_URL = "https://pastebin.com/raw/a1Uz1nL1" -- Paste your Key URL from Step 2 here
local SHORTCUT_LINK = "https://exe.io/hUhBl" -- Paste the link you want users to complete

-- ################################# --
-- ##     SCRIPT LOADER         ## --
-- ################################# --

-- This function loads and runs the main script.
local function loadMainScript()
    local mainScriptSuccess, mainScriptContent = pcall(function()
        return game:HttpGet(MAIN_SCRIPT_URL)
    end)

    if mainScriptSuccess then
        loadstring(mainScriptContent)()
    else
        warn("Failed to load main script: " .. tostring(mainScriptContent))
    end
end

-- ################################# --
-- ##    UI AND LOGIC           ## --
-- ################################# --

if KEY_CHECK_ENABLED then
    -- If key check is enabled, create the UI and wait for user input.
    local CoreGui = game:GetService("CoreGui")

    -- Create the UI
    local KeyAuthScreen = Instance.new("ScreenGui")
    KeyAuthScreen.Name = "KeyAuthScreen"
    KeyAuthScreen.Parent = CoreGui
    KeyAuthScreen.ResetOnSpawn = false

    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.fromOffset(300, 180)
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    MainFrame.Parent = KeyAuthScreen
    local UICorner = Instance.new("UICorner", MainFrame)
    UICorner.CornerRadius = UDim.new(0, 5)

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 30)
    Title.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    Title.Text = "Verification Required"
    Title.Font = Enum.Font.GothamBold
    Title.TextColor3 = Color3.new(1, 1, 1)
    Title.Parent = MainFrame
    local UICorner2 = Instance.new("UICorner", Title)
    UICorner2.CornerRadius = UDim.new(0, 5)

    local KeyInput = Instance.new("TextBox")
    KeyInput.Size = UDim2.new(1, -20, 0, 35)
    KeyInput.Position = UDim2.new(0.5, 0, 0, 50)
    KeyInput.AnchorPoint = Vector2.new(0.5, 0)
    KeyInput.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    KeyInput.PlaceholderText = "Enter Key..."
    KeyInput.Text = ""
    KeyInput.Font = Enum.Font.Gotham
    KeyInput.TextColor3 = Color3.new(1, 1, 1)
    KeyInput.Parent = MainFrame
    local UICorner3 = Instance.new("UICorner", KeyInput)

    local GetKeyButton = Instance.new("TextButton")
    GetKeyButton.Size = UDim2.new(0.5, -15, 0, 30)
    GetKeyButton.Position = UDim2.new(0.25, 0, 0, 100)
    GetKeyButton.AnchorPoint = Vector2.new(0.5, 0)
    GetKeyButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    GetKeyButton.Text = "Get Key"
    GetKeyButton.Font = Enum.Font.GothamBold
    GetKeyButton.TextColor3 = Color3.new(1, 1, 1)
    GetKeyButton.Parent = MainFrame
    local UICorner4 = Instance.new("UICorner", GetKeyButton)

    local CheckKeyButton = Instance.new("TextButton")
    CheckKeyButton.Size = UDim2.new(0.5, -15, 0, 30)
    CheckKeyButton.Position = UDim2.new(0.75, 0, 0, 100)
    CheckKeyButton.AnchorPoint = Vector2.new(0.5, 0)
    CheckKeyButton.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    CheckKeyButton.Text = "Check Key"
    CheckKeyButton.Font = Enum.Font.GothamBold
    CheckKeyButton.TextColor3 = Color3.new(1, 1, 1)
    CheckKeyButton.Parent = MainFrame
    local UICorner5 = Instance.new("UICorner", CheckKeyButton)

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -20, 0, 20)
    StatusLabel.Position = UDim2.new(0.5, 0, 1, -15)
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = ""
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.TextColor3 = Color3.new(1, 1, 1)
    StatusLabel.Parent = MainFrame

    -- Button Functions
    GetKeyButton.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(SHORTCUT_LINK)
            StatusLabel.Text = "Shortcut link copied to clipboard!"
            StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
        else
            StatusLabel.Text = "Could not copy link."
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
    end)

    CheckKeyButton.MouseButton1Click:Connect(function()
        StatusLabel.Text = "Checking..."
        StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)

        -- Fetch the correct key from your Key URL
        local success, correctKey = pcall(function()
            return game:HttpGet(KEY_URL)
        end)

        if not success then
            StatusLabel.Text = "Error: Could not fetch key."
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
            return
        end

        -- Trim whitespace from both keys for a clean comparison
        local enteredKey = KeyInput.Text:match("^%s*(.-)%s*$")
        correctKey = correctKey:match("^%s*(.-)%s*$")

        if enteredKey == correctKey then
            StatusLabel.Text = "Success! Loading script..."
            StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
            task.wait(1)
            KeyAuthScreen:Destroy() -- Clean up the key UI
            loadMainScript() -- Load the main script
        else
            StatusLabel.Text = "Invalid Key."
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
    end)
else
    -- If key check is disabled, just load the script immediately.
    loadMainScript()
end
