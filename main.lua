--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Amethyst Purple Edition)
    👑 Author: Ryomotik
    🛠️ Co-Developer: Antigravity Automation
    🔬 Version: v2.6 Straight Corridor Walk & Strict Combat Proximity
    ═══════════════════════════════════════════════════════════════
]]

-- 0. ПРЕДОТВРАЩЕНИЕ ДУБЛИРОВАНИЯ
if getgenv().SwordMonarchInstance then
    pcall(function()
        getgenv().SwordMonarchInstance:Unload()
    end)
end

-- 1. СЕРВИСЫ
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- 2. ПОДКЛЮЧЕНИЕ К ВНУТРЕННИМ МОДУЛЯМ ИГРЫ
local Shared = ReplicatedStorage:WaitForChild("Shared", 15)
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Enums = require(Shared:WaitForChild("Enums"))
local Msg = Protocol.Msg

local ClientScripts = LocalPlayer:WaitForChild("PlayerScripts", 15):WaitForChild("Client", 15)
local ClientData = require(ClientScripts:WaitForChild("ClientData", 15))
local SkillInput = require(ClientScripts:WaitForChild("SkillInput", 15))

local HttpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

-- 3. СОСТОЯНИЕ СКРИПТА
local Context = {
    Running = true,
    Connections = {},
    Threads = {},
    LastFarmPosition = nil,
    LastDashTime = 0,
    StartTime = os.clock(),
    Settings = {
        AutoSwing = false,
        SwingDelay = 0.08,
        AutoStageRun = false,
        AutoMobs = false,
        CombatDistance = 8.0,
        MaxTargetRange = 45.0, -- Только мобы в радиусе 45 studs! Никакого таргета за 300+ studs!
        AutoDash = true,
        SmartHeal = true,
        AutoRebirth = false,
        RebirthDelay = 2.0,
        AutoEquipBest = false,
        EquipInterval = 8.0,
        AutoLoot = true,
        LootInterval = 0.5,
        MinLootTier = 6, -- 6 = Мифик и выше (Mythic, Celestial, Secret, Divine, Zenith)
        AntiAFK = true,
        FPSBoost = false,
        WebhookEnabled = false,
        WebhookURL = "",
        WebhookInterval = 300
    }
}
getgenv().SwordMonarchInstance = Context

-- 4. СЛУЖЕБНЫЕ ФУНКЦИИ
local function TrackConnection(conn)
    table.insert(Context.Connections, conn)
    return conn
end

local function SpawnThread(fn)
    local co = task.spawn(function()
        while Context.Running do
            local success, err = pcall(fn)
            if not success and Context.Running then
                task.wait(1)
            end
        end
    end)
    table.insert(Context.Threads, co)
    return co
end

local function GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function GetRootPart()
    local char = GetCharacter()
    return char:WaitForChild("HumanoidRootPart", 5)
end

local function GetHumanoid()
    local char = GetCharacter()
    return char:WaitForChild("Humanoid", 5)
end

local function GetStats()
    local data = ClientData and ClientData.Get and ClientData.Get()
    if data then
        return {
            Power = data.Power or 0,
            Coins = data.Coins or 0,
            Rebirth = data.Rebirth or 0,
            Level = data.Level or 1,
            CareerMaxStage = data.CareerMaxStage or 1
        }
    end
    return { Power = 0, Coins = 0, Rebirth = 0, Level = 1, CareerMaxStage = 1 }
end

-- Плавное перетаскивание окна (Smooth Dragging)
local function EnableSmoothDrag(frame, dragHandle)
    dragHandle = dragHandle or frame
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    local function update(input)
        local delta = input.Position - dragStart
        local newPos = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
        TweenService:Create(frame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = newPos }):Play()
    end

    TrackConnection(dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end))

    TrackConnection(dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end))
end

-- 5. МОДУЛИ ФАРМА
local Farm = {}

function Farm.ClickTrain()
    pcall(function()
        Net.FireServer(Msg.TrainManualClick)
    end)
end

function Farm.EquipBest()
    pcall(function()
        Net.InvokeServer(Msg.InvEquipBest)
    end)
end

function Farm.Rebirth()
    pcall(function()
        Net.InvokeServer(Msg.PlayerRebirth)
    end)
end

function Farm.ApplyNativeLootFilter(tier)
    pcall(function()
        Net.InvokeServer(Msg.SetLootFilter, tier)
    end)
end

-- Определение редкости по источнику света PointLight
function Farm.GetDropRarity(dropPart)
    if not dropPart then return 1 end

    local light = dropPart:FindFirstChildOfClass("PointLight")
    if not light then
        for _, child in ipairs(dropPart:GetChildren()) do
            if child:IsA("BasePart") then
                light = child:FindFirstChildOfClass("PointLight")
                if light then break end
            end
        end
    end

    if light and light.Color and Enums and Enums.RarityColor then
        local c = light.Color
        local bestTier = 1
        local minDiff = 999
        for tier = 1, 10 do
            local col = Enums.RarityColor[tier]
            if col then
                local diff = math.abs(c.R - col.R) + math.abs(c.G - col.G) + math.abs(c.B - col.B)
                if diff < minDiff then
                    minDiff = diff
                    bestTier = tier
                end
            end
        end
        if minDiff < 0.28 then
            return bestTier
        end
    end

    local prompt = dropPart:FindFirstChildOfClass("ProximityPrompt", true)
    if prompt then
        local text = string.lower(prompt.ObjectText .. " " .. prompt.ActionText)
        if string.find(text, "zenith") then return 10
        elseif string.find(text, "divine") then return 9
        elseif string.find(text, "secret") then return 8
        elseif string.find(text, "celestial") then return 7
        elseif string.find(text, "mythic") then return 6
        elseif string.find(text, "legendary") then return 5
        elseif string.find(text, "epic") then return 4
        elseif string.find(text, "rare") then return 3
        elseif string.find(text, "uncommon") then return 2
        elseif string.find(text, "common") then return 1
        end
    end

    return 1
end

-- Сбор лута: подбор через Net.FireServer по UID и ProximityPrompt
function Farm.CollectLoot()
    local drops = Workspace:FindFirstChild("DropsClient")
    if not drops then return end

    local root = GetRootPart()
    if not root then return end

    local minTier = Context.Settings.MinLootTier or 6

    for _, obj in ipairs(drops:GetChildren()) do
        local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
        if part then
            local dist = (part.Position - root.Position).Magnitude
            if dist < 65 then
                local rarity = Farm.GetDropRarity(part)
                local name = string.lower(obj.Name)
                local isBossChest = string.find(name, "boss") or string.find(name, "chest")

                if rarity >= minTier or isBossChest then
                    local uid = tonumber(string.match(obj.Name, "%d+"))
                    if uid then
                        pcall(function()
                            Net.FireServer(Msg.DropPickup, uid)
                        end)
                    end
                    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)
                    if prompt then
                        pcall(fireproximityprompt, prompt)
                    end
                end
            end
        end
    end
end

-- Поиск цели ТОЛЬКО в радиусе maxDistance (по умолчанию 45 studs)
-- Если моб дальше 45 studs — функция вернет nil, и бот не будет бить воздух!
function Farm.GetTargetEnemy(maxDistance)
    maxDistance = maxDistance or Context.Settings.MaxTargetRange or 45.0

    local enemiesFolder = Workspace:FindFirstChild("EnemiesClient")
    if not enemiesFolder then return nil end

    local root = GetRootPart()
    if not root then return nil end

    local bestTarget = nil
    local minDistance = maxDistance

    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        if enemy:IsA("Model") then
            local eHum = enemy:FindFirstChildOfClass("Humanoid")
            local eHrp = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
            if eHum and eHrp and eHum.Health > 0 then
                local dist = (eHrp.Position - root.Position).Magnitude
                if dist <= minDistance then
                    minDistance = dist
                    bestTarget = { Model = enemy, Root = eHrp, Hum = eHum, Distance = dist }
                end
            end
        end
    end
    return bestTarget
end

-- Наземный бой: только с мобами рядом
function Farm.AttackTargetLegit(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum or not target or not target.Root or target.Hum.Health <= 0 then return end

    local myPos = root.Position
    local targetPos = target.Root.Position
    local toTarget = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = toTarget.Magnitude

    -- 1. Откат при критическом здоровье
    if Context.Settings.SmartHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.35 then
        if dist > 0.1 then
            local runAwayPos = myPos - toTarget.Unit * 25
            hum:MoveTo(runAwayPos)
        end
        task.wait(0.3)
        return
    end

    local desiredDist = Context.Settings.CombatDistance or 8.0

    -- 2. Подход к мобу ногами
    if dist > desiredDist + 2.5 then
        hum:MoveTo(targetPos)
    elseif dist < desiredDist - 2.0 then
        local backPos = myPos - toTarget.Unit * 3
        hum:MoveTo(backPos)
    else
        -- На боевой дистанции: стрейф
        local perp = Vector3.new(-toTarget.Z, 0, toTarget.X).Unit
        local strafeDir = math.sin(os.clock() * 2.8)
        local strafePos = targetPos + (toTarget.Unit * desiredDist) + (perp * strafeDir * 4.5)
        hum:MoveTo(strafePos)
    end

    -- 3. Поворот лицом к врагу
    local lookTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
    root.CFrame = CFrame.lookAt(myPos, lookTarget)

    -- 4. Нативный Dash
    local now = os.clock()
    if Context.Settings.AutoDash and (now - Context.LastDashTime) > 3.0 then
        Context.LastDashTime = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Dash)
        end)
    end

    -- 5. Атака мечом и всеми навыками
    pcall(function()
        SkillInput.Press(Enums.SkillSlot.NormalAttack)
        SkillInput.Press(Enums.SkillSlot.Skill1)
        SkillInput.Press(Enums.SkillSlot.Skill2)
        SkillInput.Press(Enums.SkillSlot.Skill3)
    end)
end

-- ПРЯМОЙ БЕГ ВПЕРЁД ПО ДОРОГЕ (через ворота Подземелья в локации)
function Farm.WalkForward()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    -- Осевая линия коридора подземелья: X = -1.2, направление Z строго уменьшается (-Z)
    -- Персонаж бежит прямо по дороге вперёд
    local currentPos = root.Position
    local nextPoint = Vector3.new(-1.2, currentPos.Y, currentPos.Z - 30)

    hum:MoveTo(nextPoint)

    -- Если упёрся в бордюр или ступеньку ворот — авто-прыжок
    if root.Velocity.Magnitude < 1.0 and hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
    end
end

-- 6. СЛУЖЕБНЫЕ ХУКИ
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

Farm.ApplyNativeLootFilter(Context.Settings.MinLootTier)

-- 7. DISCORD WEBHOOK
local function SendWebhook()
    if not Context.Settings.WebhookEnabled or Context.Settings.WebhookURL == "" or not HttpRequest then return end

    local stats = GetStats()
    local uptimeSec = math.floor(os.clock() - Context.StartTime)
    local uptime = string.format("%02dч %02dм %02dс", math.floor(uptimeSec / 3600), math.floor((uptimeSec % 3600) / 60), uptimeSec % 60)

    local payload = {
        embeds = {{
            title = "⚔️ [+1 Sword Loot Monarch] • Отчёт автофарма",
            color = 9127187,
            fields = {
                { name = "👑 Разработчик", value = "`Ryomotik`", inline = true },
                { name = "👤 Игрок", value = "`" .. LocalPlayer.Name .. " (" .. LocalPlayer.DisplayName .. ")`", inline = true },
                { name = "⏱️ Время сессии", value = "`" .. uptime .. "`", inline = true },
                { name = "⚡ Сила / Power", value = "`" .. tostring(math.floor(stats.Power)) .. "`", inline = false },
                { name = "🔄 Перерождения", value = "`" .. tostring(stats.Rebirth) .. "`", inline = true },
                { name = "💰 Монеты", value = "`" .. tostring(stats.Coins) .. "`", inline = true },
                { name = "🗺️ Макс. Этап", value = "`Stage " .. tostring(stats.CareerMaxStage) .. "`", inline = true },
                { name = "🛡️ Режим боя", value = "🟢 Ground Corridor Runner", inline = true }
            },
            footer = { text = "Sword Loot Monarch • by Ryomotik" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        HttpRequest({
            Url = Context.Settings.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)
end

-- 8. ГЛАВНЫЙ ИНТЕЛЛЕКТУАЛЬНЫЙ ЦИКЛ
-- Поток тренировки силы (если включен ручной режим свинга)
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoSwing and not Context.Settings.AutoStageRun and not Context.Settings.AutoMobs then
            Farm.ClickTrain()
            task.wait(Context.Settings.SwingDelay)
        else
            task.wait(0.2)
        end
    end
end)

-- ГЛАВНЫЙ ПОТОК: Идти вперед -> Увидел моба рядом (<45 studs) -> Убил -> Пошел дальше
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoStageRun or Context.Settings.AutoMobs then
            -- Проверяем мобов ТОЛЬКО рядом (в радиусе 45 studs)!
            local target = Farm.GetTargetEnemy(Context.Settings.MaxTargetRange or 45.0)

            if target then
                -- Рядом есть враг: дерёмся
                Farm.AttackTargetLegit(target)
                task.wait(Context.Settings.SwingDelay)
            else
                -- Врагов рядом НЕТ: НЕ используем скилы в пустоту, а ПРОСТО ИДЁМ ВПЕРЁД!
                if Context.Settings.AutoStageRun then
                    Farm.WalkForward()
                    Farm.CollectLoot()
                end
                task.wait(0.12)
            end
        else
            task.wait(0.3)
        end
    end
end)

-- Поток подбора лута
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoLoot then
            Farm.CollectLoot()
            task.wait(Context.Settings.LootInterval)
        else
            task.wait(1.5)
        end
    end
end)

-- Поток авто-ребёрфа
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoRebirth then
            Farm.Rebirth()
            task.wait(Context.Settings.RebirthDelay)
        else
            task.wait(1)
        end
    end
end)

-- Поток авто-экипировки
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoEquipBest then
            Farm.EquipBest()
            task.wait(Context.Settings.EquipInterval)
        else
            task.wait(1)
        end
    end
end)

-- Поток Webhook
SpawnThread(function()
    while Context.Running do
        if Context.Settings.WebhookEnabled and Context.Settings.WebhookURL ~= "" then
            task.wait(Context.Settings.WebhookInterval)
            SendWebhook()
        else
            task.wait(5)
        end
    end
end)

-- 9. FLUENT UI (Amethyst Purple Edition)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Sword Loot Monarch",
    SubTitle = "by Ryomotik • v2.6 Runner",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Amethyst",
    MinimizeKey = Enum.KeyCode.LeftControl
})
Fluent:SetTheme("Amethyst")

task.defer(function()
    pcall(function()
        if Window and Window.Frame then
            Window.Frame.Active = true
            EnableSmoothDrag(Window.Frame, Window.TopBar or Window.Frame)
        end
        local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
        for _, gui in ipairs(guiParent:GetChildren()) do
            if gui:IsA("ScreenGui") and (string.find(gui.Name:lower(), "fluent") or gui:FindFirstChild("Main") or gui:FindFirstChild("Window")) then
                local mainF = gui:FindFirstChild("Main") or gui:FindFirstChild("Window") or gui:FindFirstChildWhichIsA("Frame")
                if mainF then
                    mainF.Active = true
                    EnableSmoothDrag(mainF, mainF:FindFirstChild("TopBar") or mainF:FindFirstChild("Header") or mainF)
                end
            end
        end
    end)
end)

local Tabs = {
    Main = Window:AddTab({ Title = "Фарм", Icon = "swords" }),
    Stages = Window:AddTab({ Title = "Этапы & Бой", Icon = "crosshair" }),
    Loot = Window:AddTab({ Title = "Фильтр Лута", Icon = "shield" }),
    Progress = Window:AddTab({ Title = "Прокачка", Icon = "trending-up" }),
    Utility = Window:AddTab({ Title = "Сервис & AFK", Icon = "cpu" }),
    Webhook = Window:AddTab({ Title = "Discord", Icon = "bell" }),
    Settings = Window:AddTab({ Title = "Конфиг", Icon = "settings" })
}

local ToggleSwing = Tabs.Main:AddToggle("AutoSwing", { Title = "Авто-клик / Тренировка силы (Native)", Default = false })
ToggleSwing:OnChanged(function(val) Context.Settings.AutoSwing = val end)

Tabs.Main:AddSlider("SwingSpeed", {
    Title = "Задержка клика / атаки (сек)",
    Default = 0.08,
    Min = 0.04,
    Max = 0.5,
    Rounding = 2,
    Callback = function(val) Context.Settings.SwingDelay = val end
})

-- Вкладка 2: Прохождение Этапов
local ToggleStageRun = Tabs.Stages:AddToggle("AutoStageRun", {
    Title = "🚀 Автопрохождение этапов (Идти вперёд -> Убить мобов -> Дальше)",
    Default = false
})
ToggleStageRun:OnChanged(function(val)
    Context.Settings.AutoStageRun = val
    if val then
        Fluent:Notify({
            Title = "Этапы",
            Content = "Запущен режим коридорного бега: идёт вперёд, зачищает мобов и идёт дальше!",
            Duration = 3.5
        })
    end
end)

local ToggleMobs = Tabs.Stages:AddToggle("AutoMobs", {
    Title = "Только бой с мобами рядом (без бега вперёд)",
    Default = false
})
ToggleMobs:OnChanged(function(val) Context.Settings.AutoMobs = val end)

Tabs.Stages:AddSlider("CombatDist", {
    Title = "Дистанция удара мечом от моба (Studs)",
    Default = 8.0,
    Min = 5.0,
    Max = 12.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.CombatDistance = val end
})

Tabs.Stages:AddSlider("TargetRange", {
    Title = "Радиус обнаружения врагов рядом (Studs)",
    Default = 45.0,
    Min = 20.0,
    Max = 80.0,
    Rounding = 0,
    Callback = function(val) Context.Settings.MaxTargetRange = val end
})

local ToggleDash = Tabs.Stages:AddToggle("AutoDash", {
    Title = "Использовать рывок (Dash) в бою",
    Default = true
})
ToggleDash:OnChanged(function(val) Context.Settings.AutoDash = val end)

local ToggleHeal = Tabs.Stages:AddToggle("SmartHeal", {
    Title = "Отбегать назад при низком HP (<35%)",
    Default = true
})
ToggleHeal:OnChanged(function(val) Context.Settings.SmartHeal = val end)

-- Вкладка 3: Фильтр Лута
local DropdownLoot = Tabs.Loot:AddDropdown("LootFilterDropdown", {
    Title = "Минимальная редкость сбора дропа",
    Values = {
        "Мифик и выше (Mythic, Celestial, Secret, Divine)",
        "Строго выше мификов (Celestial, Secret, Divine, Zenith)",
        "Легендарный и выше (Legendary+)",
        "Собирать всё подряд (All Drops)"
    },
    Default = "Мифик и выше (Mythic, Celestial, Secret, Divine)"
})
DropdownLoot:OnChanged(function(val)
    if val == "Мифик и выше (Mythic, Celestial, Secret, Divine)" then
        Context.Settings.MinLootTier = 6
    elseif val == "Строго выше мификов (Celestial, Secret, Divine, Zenith)" then
        Context.Settings.MinLootTier = 7
    elseif val == "Легендарный и выше (Legendary+)" then
        Context.Settings.MinLootTier = 5
    else
        Context.Settings.MinLootTier = 1
    end
    Farm.ApplyNativeLootFilter(Context.Settings.MinLootTier)
    Fluent:Notify({
        Title = "Фильтр дропа",
        Content = "Установлен фильтр: " .. val,
        Duration = 3
    })
end)

local ToggleLoot = Tabs.Loot:AddToggle("AutoLoot", {
    Title = "Включить авто-сбор отфильтрованного лута",
    Default = true
})
ToggleLoot:OnChanged(function(val) Context.Settings.AutoLoot = val end)

-- Вкладка 4: Прокачка
local ToggleRebirth = Tabs.Progress:AddToggle("AutoRebirth", { Title = "Авто-перерождение (PlayerRebirth)", Default = false })
ToggleRebirth:OnChanged(function(val) Context.Settings.AutoRebirth = val end)

local ToggleEquip = Tabs.Progress:AddToggle("AutoEquip", { Title = "Авто-экипировка лучшего меча (InvEquipBest)", Default = false })
ToggleEquip:OnChanged(function(val) Context.Settings.AutoEquipBest = val end)

Tabs.Progress:AddButton({
    Title = "⚔️ Экипировать лучший меч сейчас",
    Callback = function()
        Farm.EquipBest()
        Fluent:Notify({ Title = "Инвентарь", Content = "InvEquipBest выполнен!", Duration = 2.5 })
    end
})

Tabs.Progress:AddButton({
    Title = "🔄 Сделать Rebirth сейчас",
    Callback = function()
        Farm.Rebirth()
        Fluent:Notify({ Title = "Прокачка", Content = "PlayerRebirth выполнен!", Duration = 2.5 })
    end
})

-- Вкладка 5: Сервис и AFK
local ToggleAntiAFK = Tabs.Utility:AddToggle("AntiAFK", { Title = "Встроенный Anti-AFK (VirtualUser)", Default = true })
ToggleAntiAFK:OnChanged(function(val) Context.Settings.AntiAFK = val end)

local ToggleFPS = Tabs.Utility:AddToggle("FPSBoost", { Title = "FPS Boost (Отключение 3D-рендеринга)", Default = false })
ToggleFPS:OnChanged(function(val)
    Context.Settings.FPSBoost = val
    RunService:Set3dRenderingEnabled(not val)
    if val and setfpscap then setfpscap(15) elseif setfpscap then setfpscap(60) end
end)

-- Вкладка 6: Discord Webhook
local ToggleWebhook = Tabs.Webhook:AddToggle("WebhookActive", { Title = "Включить отправку в Discord", Default = false })
ToggleWebhook:OnChanged(function(val) Context.Settings.WebhookEnabled = val end)

Tabs.Webhook:AddInput("WebhookURL", {
    Title = "Webhook URL",
    Default = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Finished = true,
    Callback = function(val) Context.Settings.WebhookURL = val end
})

Tabs.Webhook:AddButton({
    Title = "📡 Отправить тестовый отчет",
    Callback = function()
        if Context.Settings.WebhookURL ~= "" then
            SendWebhook()
            Fluent:Notify({ Title = "Webhook", Content = "Тестовый пакет отправлен в Discord!", Duration = 3 })
        else
            Fluent:Notify({ Title = "Ошибка", Content = "Сначала вставьте URL вебхука!", Duration = 3 })
        end
    end
})

-- Вкладка 7: Настройки
Tabs.Settings:AddKeybind("MenuBind", {
    Title = "Клавиша скрытия меню",
    Mode = "Toggle",
    Default = "LeftControl",
    Callback = function() end
})

Tabs.Settings:AddButton({
    Title = "🗑️ Полная выгрузка скрипта (Unload)",
    Callback = function()
        Context:Unload()
    end
})

function Context:Unload()
    Context.Running = false
    for _, conn in ipairs(Context.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(Context.Connections)
    table.clear(Context.Threads)
    RunService:Set3dRenderingEnabled(true)
    if setfpscap then setfpscap(60) end
    pcall(function() Window:Destroy() end)
    getgenv().SwordMonarchInstance = nil
    print("[Sword Monarch]: Выгружен из памяти.")
end

Window:SelectTab(2)
Fluent:Notify({
    Title = "Sword Loot Monarch",
    Content = "v2.6 Runner загружен! Автор: Ryomotik. Меню: LeftControl.",
    Duration = 4
})
