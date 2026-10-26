--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Amethyst Purple Edition)
    👑 Author: Ryomotik
    🛠️ Co-Developer: Antigravity Automation
    🔬 Version: v2.5 Smart Stages & Precise Loot Filter
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
local TeleportConfig = require(Shared:WaitForChild("Config"):WaitForChild("Teleport"))
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
    LastLootTime = 0,
    LastStageAction = 0,
    StartTime = os.clock(),
    Settings = {
        AutoSwing = false,
        SwingDelay = 0.08,
        AutoStageRun = false,
        AutoMobs = false,
        CombatDistance = 8.5,
        AutoDash = true,
        SmartHeal = true,
        AutoRebirth = false,
        RebirthDelay = 2.0,
        AutoEquipBest = false,
        EquipInterval = 8.0,
        AutoLoot = true,
        LootInterval = 0.6,
        MinLootTier = 6, -- 6 = Мифик и выше (Mythic, Celestial, Secret, Divine, Zenith)
        AutoStage = true,
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
            Stage = data.Stage,
            CareerMaxStage = data.CareerMaxStage or 1
        }
    end
    return { Power = 0, Coins = 0, Rebirth = 0, Level = 1, Stage = nil, CareerMaxStage = 1 }
end

-- Плавное и стабильное перетаскивание окна (Smooth Dragging)
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

-- Фарм силы через прямой сетевой протокол
function Farm.ClickTrain()
    pcall(function()
        Net.FireServer(Msg.TrainManualClick)
    end)
end

-- Авто-экипировка лучшего оружия
function Farm.EquipBest()
    pcall(function()
        Net.InvokeServer(Msg.InvEquipBest)
    end)
end

-- Авто-ребёрф
function Farm.Rebirth()
    pcall(function()
        Net.InvokeServer(Msg.PlayerRebirth)
    end)
end

-- Установка серверного фильтра лута игры
function Farm.ApplyNativeLootFilter(tier)
    pcall(function()
        Net.InvokeServer(Msg.SetLootFilter, tier)
    end)
end

-- Точное определение редкости выпавшего предмета (по PointLight и цвету Enums)
function Farm.GetDropRarity(dropPart)
    if not dropPart then return 1 end

    -- 1. Поиск PointLight (создаётся нативным DropRenderer с цветом Enums.RarityColor)
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

    -- 2. Проверка текста на ProximityPrompt
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

-- Умный сбор лута (Фильтрация: мифики и выше)
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
                    -- 1. Вызов нативного сетевого события подбора по UID
                    local uid = tonumber(string.match(obj.Name, "%d+"))
                    if uid then
                        pcall(function()
                            Net.FireServer(Msg.DropPickup, uid)
                        end)
                    end
                    -- 2. Активация ProximityPrompt
                    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)
                    if prompt then
                        pcall(fireproximityprompt, prompt)
                    end
                end
            end
        end
    end
end

-- Поиск цели в EnemiesClient
function Farm.GetTargetEnemy()
    local enemiesFolder = Workspace:FindFirstChild("EnemiesClient")
    if not enemiesFolder then return nil end

    local root = GetRootPart()
    if not root then return nil end

    local bestTarget = nil
    local minDistance = math.huge

    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        if enemy:IsA("Model") then
            local eHum = enemy:FindFirstChildOfClass("Humanoid")
            local eHrp = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso")
            if eHum and eHrp and eHum.Health > 0 then
                local dist = (eHrp.Position - root.Position).Magnitude
                if dist < minDistance then
                    minDistance = dist
                    bestTarget = { Model = enemy, Root = eHrp, Hum = eHum, Distance = dist }
                end
            end
        end
    end
    return bestTarget
end

-- 100% Легитимный бой на земле (Без полёта, без кика Error 267)
function Farm.AttackTargetLegit(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum or not target or not target.Root or target.Hum.Health <= 0 then return end

    local myPos = root.Position
    local targetPos = target.Root.Position
    local toTarget = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = toTarget.Magnitude

    -- 1. Откат при низком здоровье (<35% HP)
    if Context.Settings.SmartHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.35 then
        if dist > 0.1 then
            local runAwayPos = myPos - toTarget.Unit * 25
            hum:MoveTo(runAwayPos)
        end
        task.wait(0.3)
        return
    end

    local desiredDist = Context.Settings.CombatDistance or 8.5

    -- 2. Наземное перемещение
    if dist > desiredDist + 3 then
        hum:MoveTo(targetPos)
    elseif dist < desiredDist - 2 then
        local backPos = myPos - toTarget.Unit * 3
        hum:MoveTo(backPos)
    else
        local perp = Vector3.new(-toTarget.Z, 0, toTarget.X).Unit
        local strafeDir = math.sin(os.clock() * 2.8)
        local strafePos = targetPos + (toTarget.Unit * desiredDist) + (perp * strafeDir * 5)
        hum:MoveTo(strafePos)
    end

    -- 3. Плавный поворот к врагу
    local lookTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
    root.CFrame = CFrame.lookAt(myPos, lookTarget)

    -- 4. Нативный Dash на земле
    local now = os.clock()
    if Context.Settings.AutoDash and (now - Context.LastDashTime) > 3.0 then
        Context.LastDashTime = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Dash)
        end)
    end

    -- 5. Атака оружием и скиллами
    pcall(function()
        SkillInput.Press(Enums.SkillSlot.NormalAttack)
        SkillInput.Press(Enums.SkillSlot.Skill1)
        SkillInput.Press(Enums.SkillSlot.Skill2)
        SkillInput.Press(Enums.SkillSlot.Skill3)
    end)
end

-- Автопрохождение и продвижение по этапам (Stages Progression)
function Farm.AdvanceStage()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    local map = Workspace:FindFirstChild("Map")
    local stagesFolder = map and map:FindFirstChild("Stages")
    local lobby = map and map:FindFirstChild("Lobby")

    local runMaxClear = LocalPlayer:GetAttribute("RunMaxClear") or 0
    local currentStageNum = runMaxClear + 1

    -- Определяем, находится ли игрок в Лобби или уже на этапах
    local isAtStages = root.Position.Z < 250

    if not isAtStages then
        -- ИГРОК В ЛОББИ: Направляемся к StageTeleporter
        local stats = GetStats()
        local bestCheckpoint = 1
        if TeleportConfig and TeleportConfig.Best and stats.CareerMaxStage then
            local bestTable = TeleportConfig.Best(stats.CareerMaxStage)
            if bestTable and (bestTable.Stage or bestTable.Id) then
                bestCheckpoint = bestTable.Stage or bestTable.Id
            end
        end

        local stageTeleporter = lobby and lobby:FindFirstChild("StageTeleporter")
        if stageTeleporter then
            local padPos = stageTeleporter:IsA("Model") and stageTeleporter:GetPivot().Position or stageTeleporter.Position
            local distToPad = (Vector3.new(padPos.X, root.Position.Y, padPos.Z) - root.Position).Magnitude

            if distToPad > 12 then
                hum:MoveTo(padPos)
            else
                -- Стоим на телепортере: вызываем телепорт на валидный чекпоинт
                local now = os.clock()
                if (now - Context.LastStageAction) > 2.5 then
                    Context.LastStageAction = now
                    pcall(function()
                        Net.InvokeServer(Msg.StageTeleport, bestCheckpoint)
                    end)
                end
            end
        else
            -- Если телепортер не найден, бежим к первому этапу
            local s1 = stagesFolder and stagesFolder:FindFirstChild("1")
            if s1 and s1:FindFirstChild("Spawn") then
                hum:MoveTo(s1.Spawn.Position)
            end
        end
        return
    end

    -- ИГРОК НА ЭТАПАХ: Продвижение по цепочке Stage 1 -> 2 -> 3 ...
    local currentStageFolder = stagesFolder and stagesFolder:FindFirstChild(tostring(currentStageNum))
    if currentStageFolder then
        local levelArea = currentStageFolder:FindFirstChild("LevelArea") or currentStageFolder:FindFirstChild("BattleArea")
        local spawnPart = currentStageFolder:FindFirstChild("Spawn")
        local winArea = currentStageFolder:FindFirstChild("WinArea")

        local areaPos = (levelArea and levelArea.Position) or (spawnPart and spawnPart.Position)
        if areaPos then
            local distToArea = (Vector3.new(areaPos.X, root.Position.Y, areaPos.Z) - root.Position).Magnitude
            if distToArea > 16 then
                -- Бежим в зону боя текущего этапа
                hum:MoveTo(areaPos)
            else
                -- Если стоим в зоне боя, но мобов нет — бежим в сторону WinArea / следующего этапа
                local nextStageFolder = stagesFolder:FindFirstChild(tostring(currentStageNum + 1))
                if nextStageFolder and nextStageFolder:FindFirstChild("Spawn") then
                    hum:MoveTo(nextStageFolder.Spawn.Position)
                elseif winArea then
                    local wPos = winArea:IsA("Model") and winArea:GetPivot().Position or winArea.Position
                    hum:MoveTo(wPos)
                else
                    -- Бег по коридору этапов в сторону убывания Z
                    hum:MoveTo(root.Position + Vector3.new(0, 0, -28))
                end
            end
        end
    else
        -- За пределами последнего известного этапа: бег вперед
        hum:MoveTo(root.Position + Vector3.new(0, 0, -30))
    end
end

-- 6. СЛУЖЕБНЫЕ ХУКИ
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

-- Перехват StageCleared для моментального сбора лута
local function SetupGameEvents()
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local MainEvent = Remotes and Remotes:FindFirstChild("MainEvent")
    if MainEvent then
        TrackConnection(MainEvent.OnClientEvent:Connect(function(msgId, ...)
            if msgId == Msg.StageCleared then
                task.delay(0.5, function()
                    Farm.CollectLoot()
                end)
            end
        end))
    end
end
SetupGameEvents()

-- Применение фильтра при запуске
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
                { name = "🛡️ Режим боя", value = "🟢 100% Legit Ground (Anti-Kick)", inline = true }
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

-- 8. ИСПОЛНИТЕЛЬНЫЕ ФОНОВЫЕ ПОТОКИ
-- Поток тренировки силы
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

-- Поток прохождения этапов и наземного боя
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoStageRun or Context.Settings.AutoMobs then
            local target = Farm.GetTargetEnemy()
            if target then
                Farm.AttackTargetLegit(target)
                task.wait(Context.Settings.SwingDelay)
            else
                if Context.Settings.AutoStageRun then
                    Farm.AdvanceStage()
                    Farm.CollectLoot()
                end
                task.wait(0.2)
            end
        else
            task.wait(0.3)
        end
    end
end)

-- Поток сбора лута с точной фильтрацией
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
    SubTitle = "by Ryomotik • v2.5 Amethyst",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Amethyst",
    MinimizeKey = Enum.KeyCode.LeftControl
})
Fluent:SetTheme("Amethyst")

-- Подключение плавного перемещения окна (Smooth Dragging)
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

-- Вкладка 1: Основной фарм
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

-- Вкладка 2: Прохождение Этапов и Легитимный Бой
local ToggleStageRun = Tabs.Stages:AddToggle("AutoStageRun", {
    Title = "🚀 Автопрохождение этапов (Lobby -> Run -> Next)",
    Default = false
})
ToggleStageRun:OnChanged(function(val)
    Context.Settings.AutoStageRun = val
    if val then
        Fluent:Notify({
            Title = "Этапы",
            Content = "Запущен цикл умного прохождения этапов и наземного боя!",
            Duration = 3.5
        })
    end
end)

local ToggleMobs = Tabs.Stages:AddToggle("AutoMobs", {
    Title = "Авто-фарм только мобов рядом (без перехода на этапы)",
    Default = false
})
ToggleMobs:OnChanged(function(val) Context.Settings.AutoMobs = val end)

Tabs.Stages:AddSlider("CombatDist", {
    Title = "Дистанция удара мечом от моба (Studs)",
    Default = 8.5,
    Min = 6.0,
    Max = 14.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.CombatDistance = val end
})

local ToggleDash = Tabs.Stages:AddToggle("AutoDash", {
    Title = "Использовать рывок (Dash) на земле",
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
    Content = "v2.5 загружен! Автор: Ryomotik. Меню: LeftControl.",
    Duration = 4
})
