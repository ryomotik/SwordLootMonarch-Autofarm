--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ UI Style: Fluent Interface Suite (Amethyst Edition)
    👑 Author: Ryomotik
    ✨ Features:
       • Дефолтные плавные анимации (TweenService Quart / Spring-like)
       • Гладкие скруглённые края (Smooth Rounded Corners & Acrylic Glass)
       • Классический сайдбар с вкладками и скользящим индикатором
       • Непрерывный авто-кликер силы (20 кликов/сек)
       • Авто-перерождение (Auto Rebirth)
       • Умный фарм этапов (Stages 1..38, No-Clip барьеров)
       • Авто-каст способностей и моментальный сбор лута
       • Горячая клавиша: Left Control
    ═══════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net.Net)
local Protocol = require(Shared.Net.Protocol)
local Msg = Protocol.Msg

-- Configuration
local Config = {
    AutoClicker = true,       -- Непрерывный кликер силы
    ClickSpeed = 20,          -- Частота кликов в секунду (макс ~25)
    AutoRebirth = true,       -- Авто-перерождение
    AutoFarmStages = false,   -- Авто-прохождение этапов
    StageWaitTime = 1.0,      -- Задержка на зачистку мобов
    AutoCast = true,          -- Авто-каст навыков и атака мечом
    AutoPickup = true,        -- Авто-подбор лута
    GuiVisible = true,
}

-- Cleanup old GUI instances
local GUI_NAME = "Ryomotik_Fluent_Hub"
local parentGui = (gethui and gethui()) or game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
for _, name in ipairs({"Ryomotik_Fluent_Hub", "Ryomotik_Monarch_Hub", "Ryomotik_VisionGlass_Hub", "Ryomotik_LiquidGlass_Hub", "SwordMonarchGui"}) do
    local old = parentGui:FindFirstChild(name)
    if old then pcall(function() old:Destroy() end) end
    if LocalPlayer:FindFirstChild("PlayerGui") then
        local pOld = LocalPlayer.PlayerGui:FindFirstChild(name)
        if pOld then pcall(function() pOld:Destroy() end) end
    end
end

-- =============================================================================
-- BARRIER BYPASS (Снятие коллизий всех барьеров карты)
-- =============================================================================
local function disableAllBarriers()
    pcall(function()
        local stages = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Stages")
        if stages then
            for _, obj in ipairs(stages:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local lname = string.lower(obj.Name)
                    if string.find(lname, "barrier") or string.find(lname, "wall") or string.find(lname, "gate") then
                        obj.CanCollide = false
                    end
                end
            end
        end
    end)
end
disableAllBarriers()

-- =============================================================================
-- FLUENT UI AMETHYST THEME CONSTANTS
-- =============================================================================
local Theme = {
    Background = Color3.fromRGB(18, 14, 28),
    BackgroundGradTop = Color3.fromRGB(28, 20, 44),
    BackgroundGradBot = Color3.fromRGB(14, 10, 22),
    Accent = Color3.fromRGB(168, 85, 247),       -- Amethyst Purple
    AccentHover = Color3.fromRGB(192, 132, 252),
    Element = Color3.fromRGB(26, 20, 40),
    ElementBorder = Color3.fromRGB(60, 42, 90),
    Text = Color3.fromRGB(245, 243, 255),
    SubText = Color3.fromRGB(167, 155, 185),
    Sidebar = Color3.fromRGB(14, 10, 22),
    TabHover = Color3.fromRGB(38, 28, 58),
    TabSelected = Color3.fromRGB(48, 34, 74),
    Stroke = Color3.fromRGB(120, 75, 180),
}

local function tween(instance, duration, properties, style, direction)
    local info = TweenInfo.new(duration or 0.22, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out)
    local t = TweenService:Create(instance, info, properties)
    t:Play()
    return t
end

-- =============================================================================
-- SCREEN GUI & ROOT WINDOW
-- =============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
ScreenGui.Parent = parentGui

local RootWindow = Instance.new("Frame")
RootWindow.Name = "FluentWindow"
RootWindow.Size = UDim2.fromOffset(590, 455)
local vp = workspace.CurrentCamera.ViewportSize
RootWindow.Position = UDim2.fromOffset(math.floor(vp.X/2 - 295), math.floor(vp.Y/2 - 227))
RootWindow.BackgroundColor3 = Theme.Background
RootWindow.BorderSizePixel = 0
RootWindow.ClipsDescendants = true
RootWindow.Parent = ScreenGui

local RootCorner = Instance.new("UICorner")
RootCorner.CornerRadius = UDim.new(0, 12)
RootCorner.Parent = RootWindow

local RootGradient = Instance.new("UIGradient")
RootGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0.0, Theme.BackgroundGradTop),
    ColorSequenceKeypoint.new(1.0, Theme.BackgroundGradBot),
})
RootGradient.Rotation = 90
RootGradient.Parent = RootWindow

local RootStroke = Instance.new("UIStroke")
RootStroke.Color = Theme.Stroke
RootStroke.Transparency = 0.55
RootStroke.Thickness = 1.2
RootStroke.Parent = RootWindow

-- Top Specular Acrylic Line
local TopSpec = Instance.new("Frame")
TopSpec.Size = UDim2.new(1, 0, 0, 1.2)
TopSpec.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TopSpec.BackgroundTransparency = 0.65
TopSpec.BorderSizePixel = 0
TopSpec.Parent = RootWindow

-- =============================================================================
-- TITLE BAR (Draggable)
-- =============================================================================
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundTransparency = 1
TitleBar.Parent = RootWindow

-- Dragging Logic
local dragging, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = RootWindow.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
TitleBar.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        RootWindow.Position = UDim2.fromOffset(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y)
    end
end)

local TitleIcon = Instance.new("TextLabel")
TitleIcon.Text = "💎"
TitleIcon.TextSize = 14
TitleIcon.Size = UDim2.new(0, 24, 0, 24)
TitleIcon.Position = UDim2.new(0, 12, 0.5, -12)
TitleIcon.BackgroundTransparency = 1
TitleIcon.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Text = "Sword Loot Monarch"
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13.5
TitleLabel.TextColor3 = Theme.Text
TitleLabel.Size = UDim2.new(0, 140, 1, 0)
TitleLabel.Position = UDim2.new(0, 38, 0, 0)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.BackgroundTransparency = 1
TitleLabel.Parent = TitleBar

local SubTitleLabel = Instance.new("TextLabel")
SubTitleLabel.Text = "by Ryomotik  •  Amethyst Edition"
SubTitleLabel.Font = Enum.Font.GothamMedium
SubTitleLabel.TextSize = 11.5
SubTitleLabel.TextColor3 = Theme.SubText
SubTitleLabel.Size = UDim2.new(0, 200, 1, 0)
SubTitleLabel.Position = UDim2.new(0, 185, 0, 0)
SubTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubTitleLabel.BackgroundTransparency = 1
SubTitleLabel.Parent = TitleBar

-- Minimize Button
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -36, 0.5, -14)
MinBtn.BackgroundColor3 = Theme.Element
MinBtn.BackgroundTransparency = 0.4
MinBtn.Text = "—"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.TextColor3 = Theme.SubText
MinBtn.AutoButtonColor = false
MinBtn.Parent = TitleBar
local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

MinBtn.MouseEnter:Connect(function()
    tween(MinBtn, 0.18, { BackgroundColor3 = Theme.Accent, TextColor3 = Color3.fromRGB(255, 255, 255) })
end)
MinBtn.MouseLeave:Connect(function()
    tween(MinBtn, 0.18, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.SubText })
end)
MinBtn.MouseButton1Click:Connect(function()
    Config.GuiVisible = false
    ScreenGui.Enabled = false
end)

local TitleDivider = Instance.new("Frame")
TitleDivider.Size = UDim2.new(1, 0, 0, 1)
TitleDivider.Position = UDim2.new(0, 0, 0, 42)
TitleDivider.BackgroundColor3 = Theme.ElementBorder
TitleDivider.BackgroundTransparency = 0.5
TitleDivider.BorderSizePixel = 0
TitleDivider.Parent = RootWindow

-- =============================================================================
-- SIDEBAR & SMOOTH TAB SELECTOR
-- =============================================================================
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 155, 1, -43)
Sidebar.Position = UDim2.new(0, 0, 0, 43)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BackgroundTransparency = 0.35
Sidebar.BorderSizePixel = 0
Sidebar.Parent = RootWindow

local SidebarRightBorder = Instance.new("Frame")
SidebarRightBorder.Size = UDim2.new(0, 1, 1, 0)
SidebarRightBorder.Position = UDim2.new(1, -1, 0, 0)
SidebarRightBorder.BackgroundColor3 = Theme.ElementBorder
SidebarRightBorder.BackgroundTransparency = 0.5
SidebarRightBorder.BorderSizePixel = 0
SidebarRightBorder.Parent = Sidebar

local TabListHolder = Instance.new("ScrollingFrame")
TabListHolder.Size = UDim2.new(1, -14, 1, -50)
TabListHolder.Position = UDim2.new(0, 7, 0, 10)
TabListHolder.BackgroundTransparency = 1
TabListHolder.BorderSizePixel = 0
TabListHolder.ScrollBarThickness = 0
TabListHolder.CanvasSize = UDim2.fromScale(0, 0)
TabListHolder.Parent = Sidebar

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.Padding = UDim.new(0, 4)
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabListLayout.Parent = TabListHolder

-- Gliding Active Tab Selector Pill (Smooth spring-like vertical movement)
local SelectorPill = Instance.new("Frame")
SelectorPill.Name = "SelectorPill"
SelectorPill.Size = UDim2.new(0, 3.5, 0, 20)
SelectorPill.Position = UDim2.new(0, 2, 0, 8)
SelectorPill.BackgroundColor3 = Theme.Accent
SelectorPill.BorderSizePixel = 0
SelectorPill.Parent = Sidebar
local SelCorner = Instance.new("UICorner")
SelCorner.CornerRadius = UDim.new(1, 0)
SelCorner.Parent = SelectorPill

-- Sidebar Footer User Chip
local UserChip = Instance.new("Frame")
UserChip.Size = UDim2.new(1, -16, 0, 32)
UserChip.Position = UDim2.new(0, 8, 1, -38)
UserChip.BackgroundColor3 = Theme.Element
UserChip.BackgroundTransparency = 0.4
UserChip.Parent = Sidebar
local UCCorner = Instance.new("UICorner")
UCCorner.CornerRadius = UDim.new(0, 6)
UCCorner.Parent = UserChip
local UCStroke = Instance.new("UIStroke")
UCStroke.Color = Theme.ElementBorder
UCStroke.Transparency = 0.6
UCStroke.Thickness = 1
UCStroke.Parent = UserChip

local UCAvatar = Instance.new("TextLabel")
UCAvatar.Text = "👑"
UCAvatar.TextSize = 13
UCAvatar.Size = UDim2.new(0, 24, 1, 0)
UCAvatar.BackgroundTransparency = 1
UCAvatar.Parent = UserChip

local UCNick = Instance.new("TextLabel")
UCNick.Text = "Ryomotik"
UCNick.Font = Enum.Font.GothamBold
UCNick.TextSize = 11.5
UCNick.TextColor3 = Theme.Text
UCNick.Position = UDim2.new(0, 26, 0, 0)
UCNick.Size = UDim2.new(1, -26, 1, 0)
UCNick.TextXAlignment = Enum.TextXAlignment.Left
UCNick.BackgroundTransparency = 1
UCNick.Parent = UserChip

-- =============================================================================
-- CONTENT AREA
-- =============================================================================
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -165, 1, -51)
ContentArea.Position = UDim2.new(0, 160, 0, 47)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = RootWindow

-- Tab Navigation System
local Tabs = {}
local TabButtons = {}
local CurrentTabIndex = 1

local function selectTab(index)
    if not Tabs[index] then return end
    CurrentTabIndex = index

    for i, tabData in ipairs(Tabs) do
        local btn = TabButtons[i]
        local container = tabData.Container

        if i == index then
            -- Active button style
            tween(btn, 0.2, { BackgroundColor3 = Theme.TabSelected, BackgroundTransparency = 0.2 })
            btn.Title.TextColor3 = Theme.Text
            btn.Title.Font = Enum.Font.GothamBold
            btn.Icon.TextColor3 = Theme.Accent

            -- Smooth selector movement
            local targetY = btn.Position.Y.Offset + (btn.Size.Y.Offset / 2) - (SelectorPill.Size.Y.Offset / 2) + 10
            tween(SelectorPill, 0.25, { Position = UDim2.new(0, 2, 0, targetY) }, Enum.EasingStyle.Quart)

            -- Show container with fade & slide
            container.Visible = true
            container.Position = UDim2.new(0, 10, 0, 0)
            container.GroupTransparency = 1
            tween(container, 0.22, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 })
        else
            -- Inactive button style
            tween(btn, 0.2, { BackgroundColor3 = Theme.TabHover, BackgroundTransparency = 1 })
            btn.Title.TextColor3 = Theme.SubText
            btn.Title.Font = Enum.Font.GothamMedium
            btn.Icon.TextColor3 = Theme.SubText
            container.Visible = false
        end
    end
end

local function createTab(title, iconText)
    local tabIndex = #Tabs + 1

    -- Sidebar Tab Button
    local btn = Instance.new("TextButton")
    btn.Name = "TabBtn_" .. title
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.Position = UDim2.new(0, 0, 0, (tabIndex - 1) * 38)
    btn.BackgroundColor3 = Theme.TabHover
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = TabListHolder
    local bCorn = Instance.new("UICorner")
    bCorn.CornerRadius = UDim.new(0, 6)
    bCorn.Parent = btn

    local icLbl = Instance.new("TextLabel")
    icLbl.Name = "Icon"
    icLbl.Text = iconText
    icLbl.TextSize = 14
    icLbl.Size = UDim2.new(0, 28, 1, 0)
    icLbl.BackgroundTransparency = 1
    icLbl.Parent = btn

    local tLbl = Instance.new("TextLabel")
    tLbl.Name = "Title"
    tLbl.Text = title
    tLbl.Font = Enum.Font.GothamMedium
    tLbl.TextSize = 12
    tLbl.TextColor3 = Theme.SubText
    tLbl.Position = UDim2.new(0, 30, 0, 0)
    tLbl.Size = UDim2.new(1, -30, 1, 0)
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.BackgroundTransparency = 1
    tLbl.Parent = btn

    btn.MouseEnter:Connect(function()
        if CurrentTabIndex ~= tabIndex then
            tween(btn, 0.18, { BackgroundTransparency = 0.6 })
        end
    end)
    btn.MouseLeave:Connect(function()
        if CurrentTabIndex ~= tabIndex then
            tween(btn, 0.18, { BackgroundTransparency = 1 })
        end
    end)
    btn.MouseButton1Click:Connect(function()
        selectTab(tabIndex)
    end)

    -- Tab Content Container (CanvasGroup for smooth fade-in)
    local container = Instance.new("CanvasGroup")
    container.Name = "TabContent_" .. title
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = ContentArea

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.ScrollBarImageTransparency = 0.7
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = container

    local scrollLayout = Instance.new("UIListLayout")
    scrollLayout.Padding = UDim.new(0, 8)
    scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    scrollLayout.Parent = scroll

    local scrollPad = Instance.new("UIPadding")
    scrollPad.PaddingRight = UDim.new(0, 10)
    scrollPad.PaddingTop = UDim.new(0, 6)
    scrollPad.PaddingBottom = UDim.new(0, 14)
    scrollPad.Parent = scroll

    local tabObj = {
        Index = tabIndex,
        Button = btn,
        Container = container,
        Scroll = scroll,
    }

    table.insert(Tabs, tabObj)
    table.insert(TabButtons, btn)

    return tabObj
end

-- =============================================================================
-- FLUENT ELEMENT BUILDERS (Smooth animations & rounded edges)
-- =============================================================================

local function addSection(tab, title)
    local sec = Instance.new("Frame")
    sec.Size = UDim2.new(1, 0, 0, 24)
    sec.BackgroundTransparency = 1
    sec.Parent = tab.Scroll

    local lbl = Instance.new("TextLabel")
    lbl.Text = string.upper(title)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = Theme.Accent
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Parent = sec

    return sec
end

local function addToggle(tab, title, desc, defaultVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, desc and 48 or 38)
    frame.BackgroundColor3 = Theme.Element
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = tab.Scroll

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 8)
    fCorner.Parent = frame

    local fStroke = Instance.new("UIStroke")
    fStroke.Color = Theme.ElementBorder
    fStroke.Transparency = 0.6
    fStroke.Thickness = 1
    fStroke.Parent = frame

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Text = title
    titleLbl.Font = Enum.Font.GothamMedium
    titleLbl.TextSize = 12.5
    titleLbl.TextColor3 = Theme.Text
    titleLbl.Position = UDim2.new(0, 12, 0, desc and 8 or 10)
    titleLbl.Size = UDim2.new(1, -70, 0, 16)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.BackgroundTransparency = 1
    titleLbl.Parent = frame

    if desc and desc ~= "" then
        local descLbl = Instance.new("TextLabel")
        descLbl.Text = desc
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 10.5
        descLbl.TextColor3 = Theme.SubText
        descLbl.Position = UDim2.new(0, 12, 0, 26)
        descLbl.Size = UDim2.new(1, -70, 0, 14)
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.BackgroundTransparency = 1
        descLbl.Parent = frame
    end

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 42, 0, 22)
    toggleBtn.Position = UDim2.new(1, -54, 0.5, -11)
    toggleBtn.BackgroundColor3 = defaultVal and Theme.Accent or Color3.fromRGB(36, 26, 52)
    toggleBtn.Text = ""
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = frame
    local tgCorner = Instance.new("UICorner")
    tgCorner.CornerRadius = UDim.new(1, 0)
    tgCorner.Parent = toggleBtn

    local tgStroke = Instance.new("UIStroke")
    tgStroke.Color = defaultVal and Theme.AccentHover or Theme.ElementBorder
    tgStroke.Transparency = 0.4
    tgStroke.Thickness = 1
    tgStroke.Parent = toggleBtn

    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 16, 0, 16)
    thumb.Position = defaultVal and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    thumb.Parent = toggleBtn
    local thCorner = Instance.new("UICorner")
    thCorner.CornerRadius = UDim.new(1, 0)
    thCorner.Parent = thumb

    local state = defaultVal
    toggleBtn.MouseButton1Click:Connect(function()
        state = not state
        local targetColor = state and Theme.Accent or Color3.fromRGB(36, 26, 52)
        local strokeCol = state and Theme.AccentHover or Theme.ElementBorder
        local targetPos = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)

        tween(toggleBtn, 0.2, { BackgroundColor3 = targetColor })
        tween(tgStroke, 0.2, { Color = strokeCol })
        tween(thumb, 0.22, { Position = targetPos }, Enum.EasingStyle.Quart)

        callback(state)
    end)

    return frame
end

local function addSlider(tab, title, minVal, maxVal, defaultVal, suffix, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 52)
    frame.BackgroundColor3 = Theme.Element
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = tab.Scroll

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 8)
    fCorner.Parent = frame

    local fStroke = Instance.new("UIStroke")
    fStroke.Color = Theme.ElementBorder
    fStroke.Transparency = 0.6
    fStroke.Thickness = 1
    fStroke.Parent = frame

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Text = title
    titleLbl.Font = Enum.Font.GothamMedium
    titleLbl.TextSize = 12
    titleLbl.TextColor3 = Theme.Text
    titleLbl.Position = UDim2.new(0, 12, 0, 8)
    titleLbl.Size = UDim2.new(1, -80, 0, 16)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.BackgroundTransparency = 1
    titleLbl.Parent = frame

    local valLbl = Instance.new("TextLabel")
    valLbl.Text = tostring(defaultVal) .. suffix
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 11.5
    valLbl.TextColor3 = Theme.Accent
    valLbl.Position = UDim2.new(1, -70, 0, 8)
    valLbl.Size = UDim2.new(0, 58, 0, 16)
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.BackgroundTransparency = 1
    valLbl.Parent = frame

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 6)
    track.Position = UDim2.new(0, 12, 0, 32)
    track.BackgroundColor3 = Color3.fromRGB(36, 26, 52)
    track.BorderSizePixel = 0
    track.Parent = frame
    local trCorner = Instance.new("UICorner")
    trCorner.CornerRadius = UDim.new(1, 0)
    trCorner.Parent = track

    local pct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    local fCornerFill = Instance.new("UICorner")
    fCornerFill.CornerRadius = UDim.new(1, 0)
    fCornerFill.Parent = fill

    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 14, 0, 14)
    thumb.Position = UDim2.new(1, -7, 0.5, -7)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    thumb.Parent = fill
    local thCorner = Instance.new("UICorner")
    thCorner.CornerRadius = UDim.new(1, 0)
    thCorner.Parent = thumb

    local draggingSlider = false
    local function updateFromInput(input)
        local posX = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local rawVal = minVal + posX * (maxVal - minVal)
        local val = math.floor(rawVal * 10) / 10
        fill.Size = UDim2.new(posX, 0, 1, 0)
        valLbl.Text = tostring(val) .. suffix
        callback(val)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            updateFromInput(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    return frame
end

local function addButton(tab, title, desc, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, desc and 44 or 36)
    btn.BackgroundColor3 = Theme.Element
    btn.BackgroundTransparency = 0.25
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = tab.Scroll
    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 8)
    bCorner.Parent = btn
    local bStroke = Instance.new("UIStroke")
    bStroke.Color = Theme.ElementBorder
    bStroke.Transparency = 0.6
    bStroke.Thickness = 1
    bStroke.Parent = btn

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Text = title
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 12.5
    titleLbl.TextColor3 = Theme.Text
    titleLbl.Position = UDim2.new(0, 12, 0, desc and 7 or 10)
    titleLbl.Size = UDim2.new(1, -40, 0, 16)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.BackgroundTransparency = 1
    titleLbl.Parent = btn

    if desc and desc ~= "" then
        local descLbl = Instance.new("TextLabel")
        descLbl.Text = desc
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 10.5
        descLbl.TextColor3 = Theme.SubText
        descLbl.Position = UDim2.new(0, 12, 0, 24)
        descLbl.Size = UDim2.new(1, -40, 0, 14)
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.BackgroundTransparency = 1
        descLbl.Parent = btn
    end

    local arr = Instance.new("TextLabel")
    arr.Text = "▶"
    arr.Font = Enum.Font.GothamBold
    arr.TextSize = 11
    arr.TextColor3 = Theme.Accent
    arr.Size = UDim2.new(0, 20, 1, 0)
    arr.Position = UDim2.new(1, -26, 0, 0)
    arr.BackgroundTransparency = 1
    arr.Parent = btn

    btn.MouseEnter:Connect(function()
        tween(btn, 0.18, { BackgroundColor3 = Theme.TabSelected, BackgroundTransparency = 0.1 })
        tween(bStroke, 0.18, { Color = Theme.Accent })
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, 0.18, { BackgroundColor3 = Theme.Element, BackgroundTransparency = 0.25 })
        tween(bStroke, 0.18, { Color = Theme.ElementBorder })
    end)
    btn.MouseButton1Click:Connect(function()
        tween(btn, 0.1, { BackgroundColor3 = Theme.Accent })
        task.wait(0.1)
        tween(btn, 0.18, { BackgroundColor3 = Theme.TabSelected })
        callback()
    end)

    return btn
end

local function addParagraph(tab, title, content)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 72)
    frame.BackgroundColor3 = Theme.Element
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = tab.Scroll
    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 8)
    fCorner.Parent = frame
    local fStroke = Instance.new("UIStroke")
    fStroke.Color = Theme.ElementBorder
    fStroke.Transparency = 0.6
    fStroke.Thickness = 1
    fStroke.Parent = frame

    local tLbl = Instance.new("TextLabel")
    tLbl.Text = title
    tLbl.Font = Enum.Font.GothamBold
    tLbl.TextSize = 12.5
    tLbl.TextColor3 = Theme.Accent
    tLbl.Position = UDim2.new(0, 12, 0, 8)
    tLbl.Size = UDim2.new(1, -24, 0, 16)
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.BackgroundTransparency = 1
    tLbl.Parent = frame

    local cLbl = Instance.new("TextLabel")
    cLbl.Text = content
    cLbl.Font = Enum.Font.GothamMedium
    cLbl.TextSize = 11
    cLbl.TextColor3 = Theme.Text
    cLbl.Position = UDim2.new(0, 12, 0, 26)
    cLbl.Size = UDim2.new(1, -24, 0, 40)
    cLbl.TextXAlignment = Enum.TextXAlignment.Left
    cLbl.TextYAlignment = Enum.TextYAlignment.Top
    cLbl.BackgroundTransparency = 1
    cLbl.Parent = frame

    return frame, cLbl
end

-- =============================================================================
-- POPULATING TABS (Identical structure to user's GitHub repo)
-- =============================================================================

-- TAB 1: ФАРМ (SWORDS)
local TabFarm = createTab("Фарм", "⚔️")
addSection(TabFarm, "Автоматизация тренировок")
addToggle(TabFarm, "Авто-клик силы (Native Clicker)", "Непрерывный софт-кап ~20 кликов/сек во время любых действий", Config.AutoClicker, function(v)
    Config.AutoClicker = v
end)
addToggle(TabFarm, "Авто-перерождение (Auto Rebirth)", "Мгновенное перерождение при готовности (Rebirth 12 -> 13)", Config.AutoRebirth, function(v)
    Config.AutoRebirth = v
end)
addToggle(TabFarm, "Авто-каст способностей и атака", "Автоматические удары мечом и кулдауны слотов", Config.AutoCast, function(v)
    Config.AutoCast = v
    pcall(Net.InvokeServer, Msg.SetAutoCast, v)
end)
addSlider(TabFarm, "Частота кликов в секунду", 5, 25, Config.ClickSpeed, " /сек", function(v)
    Config.ClickSpeed = v
end)

-- TAB 2: ЭТАПЫ & БОЙ (CROSSHAIR)
local TabStages = createTab("Этапы & Бой", "🎯")
addSection(TabStages, "Прохождение локаций (Stages 1..38)")
addToggle(TabStages, "Авто-прохождение этапов", "Умный No-Clip + взятие спавна + проход в WinArea", Config.AutoFarmStages, function(v)
    Config.AutoFarmStages = v
    if v then disableAllBarriers() end
end)
addSlider(TabStages, "Задержка зачистки этапа", 0.3, 2.5, Config.StageWaitTime, " сек", function(v)
    Config.StageWaitTime = v
end)
addSection(TabStages, "Быстрые действия")

-- Helper logic declarations
local advanceOneStage

addButton(TabStages, "Следующий этап ▶", "Телепортироваться и зачистить текущий этап", function()
    if advanceOneStage then task.spawn(advanceOneStage) end
end)
addButton(TabStages, "В лобби (Сброс этапа) 🏠", "Вернуться в город и перезапустить заход", function()
    pcall(function() Net.FireServer(Msg.StageReturnTown) end)
end)

-- TAB 3: ЛУТ & ТРОФЕИ (SHIELD)
local TabLoot = createTab("Фильтр Лута", "🛡️")
addSection(TabLoot, "Сбор выпавших предметов")
addToggle(TabLoot, "Мгновенный авто-сбор лута (DropPickup)", "Перехват сетевого события DropSpawn и мгновенный сбор", Config.AutoPickup, function(v)
    Config.AutoPickup = v
end)

-- TAB 4: ПРОКАЧКА & СТАТУС (TRENDING UP)
local TabStats = createTab("Прокачка", "📈")
addSection(TabStats, "Телеметрия охотника")

local _, StatLabel = addParagraph(TabStats, "Показатели персонажа", "Мощность: Загрузка...\nУровень: 0 | Перерождений: 0\nЭтап: 0 / 38")

-- EXP Progress Bar inside TabStats
local ExpBarFrame = Instance.new("Frame")
ExpBarFrame.Size = UDim2.new(1, 0, 0, 48)
ExpBarFrame.BackgroundColor3 = Theme.Element
ExpBarFrame.BackgroundTransparency = 0.3
ExpBarFrame.BorderSizePixel = 0
ExpBarFrame.Parent = TabStats.Scroll
local ebCorner = Instance.new("UICorner")
ebCorner.CornerRadius = UDim.new(0, 8)
ebCorner.Parent = ExpBarFrame
local ebStroke = Instance.new("UIStroke")
ebStroke.Color = Theme.ElementBorder
ebStroke.Transparency = 0.6
ebStroke.Thickness = 1
ebStroke.Parent = ExpBarFrame

local ExpTitle = Instance.new("TextLabel")
ExpTitle.Text = "Прогресс до следующего Rebirth"
ExpTitle.Font = Enum.Font.GothamMedium
ExpTitle.TextSize = 11.5
ExpTitle.TextColor3 = Theme.SubText
ExpTitle.Position = UDim2.new(0, 12, 0, 6)
ExpTitle.Size = UDim2.new(1, -24, 0, 16)
ExpTitle.TextXAlignment = Enum.TextXAlignment.Left
ExpTitle.BackgroundTransparency = 1
ExpTitle.Parent = ExpBarFrame

local ExpTrack = Instance.new("Frame")
ExpTrack.Size = UDim2.new(1, -24, 0, 6)
ExpTrack.Position = UDim2.new(0, 12, 0, 28)
ExpTrack.BackgroundColor3 = Color3.fromRGB(36, 26, 52)
ExpTrack.BorderSizePixel = 0
ExpTrack.Parent = ExpBarFrame
local etCorner = Instance.new("UICorner")
etCorner.CornerRadius = UDim.new(1, 0)
etCorner.Parent = ExpTrack

local ExpFill = Instance.new("Frame")
ExpFill.Size = UDim2.new(0.5, 0, 1, 0)
ExpFill.BackgroundColor3 = Theme.Accent
ExpFill.BorderSizePixel = 0
ExpFill.Parent = ExpTrack
local efCorner = Instance.new("UICorner")
efCorner.CornerRadius = UDim.new(1, 0)
efCorner.Parent = ExpFill

-- TAB 5: НАСТРОЙКИ (SETTINGS)
local TabSettings = createTab("Настройки", "⚙️")
addSection(TabSettings, "Интерфейс и управление")
addParagraph(TabSettings, "Горячие клавиши", "• Нажмите [Left Control] чтобы свернуть или развернуть GUI.\n• Окно можно свободно перетаскивать мышью за заголовок.")

-- Select first tab initially
selectTab(1)

-- Hotkey toggle
UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        Config.GuiVisible = not Config.GuiVisible
        ScreenGui.Enabled = Config.GuiVisible
    end
end)

-- =============================================================================
-- LOGIC WORKERS (Exact same high-performance backend)
-- =============================================================================

-- 1. Continuous Training Clicker (~20 Hz)
task.spawn(function()
    while true do
        if Config.AutoClicker then
            pcall(function()
                Net.FireServer(Msg.TrainManualClick)
            end)
            local waitTime = 1 / math.clamp(Config.ClickSpeed, 5, 25)
            task.wait(waitTime)
        else
            task.wait(0.25)
        end
    end
end)

-- 2. Auto Rebirth Worker
task.spawn(function()
    while true do
        if Config.AutoRebirth then
            pcall(function()
                Net.InvokeServer(Msg.PlayerRebirth)
            end)
            task.wait(1.5)
        else
            task.wait(1)
        end
    end
end)

-- 3. Drop Pickup
pcall(function()
    Net.OnClientEvent(Msg.DropSpawn, function(dropId)
        if Config.AutoPickup and dropId then
            task.spawn(function()
                pcall(function()
                    Net.FireServer(Msg.DropPickup, dropId)
                end)
            end)
        end
    end)
end)

-- Safe Move Helper
local function safeMove(targetCF)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = targetCF
    end
end

-- Smart Stage Progression
advanceOneStage = function()
    local stagesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Stages")
    if not stagesFolder then return end

    disableAllBarriers()
    local currentClear = LocalPlayer:GetAttribute("RunMaxClear") or 0
    local nextStageNum = math.clamp(currentClear + 1, 1, 38)
    local st = stagesFolder:FindFirstChild(tostring(nextStageNum))

    if st then
        local levelArea = st:FindFirstChild("LevelArea") or st:FindFirstChild("Spawn")
        if levelArea then
            safeMove(levelArea.CFrame + Vector3.new(0, 3, 0))
            pcall(function() Net.FireServer(Msg.StageSpawnRequest, nextStageNum) end)
            pcall(function() Net.InvokeServer(Msg.SetAutoCast, true) end)
            task.wait(Config.StageWaitTime)
        end

        local winArea = st:FindFirstChild("WinArea")
        local winFloor = winArea and winArea:FindFirstChild("Floor")
        if winFloor then
            safeMove(winFloor.CFrame + Vector3.new(0, 3, 0))
            task.wait(0.4)
        end

        pcall(function() Net.FireServer(Msg.TrainManualClick) end)
    end
end

-- 4. Auto Stage Farm Loop
task.spawn(function()
    while true do
        if Config.AutoFarmStages then
            advanceOneStage()
            task.wait(0.5)
        else
            task.wait(0.5)
        end
    end
end)

-- 5. Real-time Status Display
task.spawn(function()
    while true do
        pcall(function()
            local p = LocalPlayer:GetAttribute("Power") or LocalPlayer:GetAttribute("PowerCurrent") or 0
            local maxClear = LocalPlayer:GetAttribute("RunMaxClear") or 0
            
            local reb = 0
            local lvl = 0
            local cd = require(LocalPlayer.PlayerScripts.Client.ClientData)
            if cd and cd.Get then
                local d = cd.Get()
                reb = d.Rebirth or 0
                lvl = d.Level or 0
            end

            local function formatNum(n)
                if n >= 1e12 then
                    return string.format("%.2fT", n / 1e12)
                elseif n >= 1e9 then
                    return string.format("%.2fB", n / 1e9)
                elseif n >= 1e6 then
                    return string.format("%.2fM", n / 1e6)
                elseif n >= 1e3 then
                    return string.format("%.1fK", n / 1e3)
                else
                    return tostring(math.floor(n))
                end
            end

            local pStr = formatNum(tonumber(p) or 0)
            local nextReq = (reb + 1) * 25
            local pct = math.clamp(lvl / math.max(nextReq, 1), 0, 1)

            StatLabel.Text = "⚡ Мощность: " .. pStr .. "\n👑 Перерождений: " .. tostring(reb) .. "  •  Уровень: " .. tostring(lvl) .. " / " .. tostring(nextReq) .. "\n🏰 Очищено этапов: " .. tostring(maxClear) .. " / 38"
            tween(ExpFill, 0.3, { Size = UDim2.new(pct, 0, 1, 0) })
            ExpTitle.Text = "Прогресс до Rebirth " .. tostring(reb + 1) .. ": " .. tostring(lvl) .. "/" .. tostring(nextReq) .. " (" .. string.format("%.1f%%", pct * 100) .. ")"
        end)
        task.wait(0.4)
    end
end)

print("[ryomotik] Fluent UI (Amethyst Edition) loaded successfully!")
