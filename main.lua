--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Nord / Deep Sea Edition)
    👑 Authors: Abror & Antigravity
    🔬 Architecture: 100% Legit Ground Movement & Loot Filter (v2.3)
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
    LastStageTeleport = 0,
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
        LootInterval = 0.8,
        MinLootTier = 7, -- 6 = Mythic+, 7 = Выше мификов (Divine/Secret/Celestial+)
        AutoStage = true,
        StageInterval = 5.0,
        AntiAFK = true,
        AutoReturn = false, -- Отключен агрессивный возврат чтобы избежать проверок античита
        FPSBoost = false,
        WebhookEnabled = false,
        WebhookURL = "",
        WebhookInterval = 300
    }
}
getgenv().SwordMonarchInstance = Context

-- Таблица редкостей для фильтрации лута
local RarityTiers = {
    ["common"] = 1,
    ["uncommon"] = 2,
    ["rare"] = 3,
    ["epic"] = 4,
    ["legendary"] = 5,
    ["mythic"] = 6,
    ["divine"] = 7,
    ["celestial"] = 8,
    ["secret"] = 9,
    ["monarch"] = 10,
    ["godly"] = 11,
    ["ancient"] = 12
}

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
            Stage = data.CareerMaxStage or 1
        }
    end
    return { Power = 0, Coins = 0, Rebirth = 0, Level = 1, Stage = 1 }
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

-- Проверка редкости выпавшего предмета перед подбором
function Farm.IsLootAllowed(dropPart)
    local minTier = Context.Settings.MinLootTier
    if minTier <= 1 then return true end

    -- 1. Проверка через атрибуты
    local tierAttr = dropPart:GetAttribute("Rarity") or dropPart:GetAttribute("Tier")
    if type(tierAttr) == "number" then
        return tierAttr >= minTier
    end

    -- 2. Проверка через текст в ProximityPrompt
    local prompt = dropPart:FindFirstChildOfClass("ProximityPrompt") or dropPart:FindFirstChild("PickupPrompt")
    local text = prompt and (prompt.ObjectText .. " " .. prompt.ActionText) or dropPart.Name
    local lowerText = string.lower(text)

    for name, tier in pairs(RarityTiers) do
        if string.find(lowerText, name) then
            return tier >= minTier
        end
    end

    -- 3. Проверка через цвет светового луча дропа (LootBeam)
    local beam = dropPart:FindFirstChildOfClass("Beam") or dropPart:FindFirstChild("LootBeam")
    if beam and beam.Color and #beam.Color.Keypoints > 0 then
        local col = beam.Color.Keypoints[1].Value
        local isMythic = (col.R > 0.75 and col.G < 0.35 and col.B < 0.35)
        local isAboveMythic = (col.R > 0.65 and col.B > 0.65) or (col.G > 0.75 and col.B > 0.75) or (col.R > 0.85 and col.G > 0.85 and col.B > 0.85)

        if minTier > 6 then
            return isAboveMythic
        elseif minTier == 6 then
            return isMythic or isAboveMythic
        end
    end

    -- Сундуки боссов и реликвии всегда ценны
    if string.find(lowerText, "boss") or string.find(lowerText, "chest") or string.find(lowerText, "curse") then
        return true
    end

    return false
end

-- Умный сбор лута (Фильтрация: выше мификов)
function Farm.CollectLoot()
    local drops = Workspace:FindFirstChild("DropsClient")
    if not drops then return end

    local root = GetRootPart()
    if not root then return end

    for _, desc in ipairs(drops:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local part = desc.Parent
            if part and part:IsA("BasePart") then
                local dist = (part.Position - root.Position).Magnitude
                if dist < 50 then
                    if Farm.IsLootAllowed(part) then
                        pcall(fireproximityprompt, desc)
                    end
                end
            end
        end
    end
end

-- Авто-переход на следующий этап
function Farm.TeleportMaxStage()
    local stats = GetStats()
    if stats.Stage and stats.Stage > 0 then
        pcall(function()
            Net.InvokeServer(Msg.StageTeleport, stats.Stage)
        end)
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

-- 100% ЛЕГИТИМНЫЙ БОЙ НА ЗЕМЛЕ (Без полёта, без телепортов, без приклеивания)
function Farm.AttackTargetLegit(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum or not target or not target.Root or target.Hum.Health <= 0 then return end

    local myPos = root.Position
    local targetPos = target.Root.Position
    local toTarget = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = toTarget.Magnitude

    -- 1. Безопасный откат при низком здоровье (<35% HP)
    if Context.Settings.SmartHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.35 then
        if dist > 0.1 then
            local runAwayPos = myPos - toTarget.Unit * 25
            hum:MoveTo(runAwayPos)
        end
        task.wait(0.3)
        return
    end

    local desiredDist = Context.Settings.CombatDistance or 8.5

    -- 2. Естественное перемещение по земле ногами
    if dist > desiredDist + 3 then
        -- Подбегаем к мобу ногами
        hum:MoveTo(targetPos)
    elseif dist < desiredDist - 2 then
        -- Слегка отходим назад если моб наступает
        local backPos = myPos - toTarget.Unit * 3
        hum:MoveTo(backPos)
    else
        -- На боевой дистанции: стрейф влево-вправо по земле
        local perp = Vector3.new(-toTarget.Z, 0, toTarget.X).Unit
        local strafeDir = math.sin(os.clock() * 2.8)
        local strafePos = targetPos + (toTarget.Unit * desiredDist) + (perp * strafeDir * 5)
        hum:MoveTo(strafePos)
    end

    -- 3. Плавный поворот лицом к врагу (Строго по горизонтали, Y не меняется!)
    local lookTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
    root.CFrame = CFrame.lookAt(myPos, lookTarget)

    -- 4. Нативный Dash на земле для сброса агро и уклонения
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

-- Естественный бег вперёд по этапу
function Farm.AdvanceStageForward()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    -- Поиск интерактивных ворот/портала
    local portalPos = nil
    local portalNames = { "StageGate", "Portal", "StageTeleporter", "Gate", "Finish", "NextStage" }
    for _, name in ipairs(portalNames) do
        local obj = Workspace:FindFirstChild(name, true)
        if obj and (obj:IsA("BasePart") or obj:IsA("Model")) then
            local pos = obj:IsA("Model") and (obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position) or obj.Position
            if (pos - root.Position).Magnitude < 180 then
                portalPos = pos
                break
            end
        end
    end

    if portalPos then
        hum:MoveTo(portalPos)
    else
        -- Бег вперёд по направлению коридора
        local lookDir = root.CFrame.LookVector * Vector3.new(1, 0, 1)
        if lookDir.Magnitude > 0.05 then
            hum:MoveTo(root.Position + lookDir.Unit * 30)
        end
    end
end

-- 6. СЛУЖЕБНЫЕ ХУКИ
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

-- Перехват StageCleared
local function SetupGameEvents()
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local MainEvent = Remotes and Remotes:FindFirstChild("MainEvent")
    if MainEvent then
        TrackConnection(MainEvent.OnClientEvent:Connect(function(msgId, ...)
            if msgId == Msg.StageCleared then
                task.delay(1.0, function()
                    Farm.CollectLoot()
                    if Context.Settings.AutoStage or Context.Settings.AutoStageRun then
                        task.wait(0.5)
                        Farm.TeleportMaxStage()
                    end
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
            color = 2337742,
            fields = {
                { name = "👑 Разработчик", value = "`Abror`", inline = true },
                { name = "👤 Игрок", value = "`" .. LocalPlayer.Name .. " (" .. LocalPlayer.DisplayName .. ")`", inline = true },
                { name = "⏱️ Время сессии", value = "`" .. uptime .. "`", inline = true },
                { name = "⚡ Сила / Power", value = "`" .. tostring(math.floor(stats.Power)) .. "`", inline = false },
                { name = "🔄 Перерождения", value = "`" .. tostring(stats.Rebirth) .. "`", inline = true },
                { name = "💰 Монеты", value = "`" .. tostring(stats.Coins) .. "`", inline = true },
                { name = "🗺️ Макс. Этап", value = "`Stage " .. tostring(stats.Stage) .. "`", inline = true },
                { name = "🛡️ Режим боя", value = "🟢 100% Legit Ground (Anti-Kick)", inline = true }
            },
            footer = { text = "Sword Loot Monarch • by Abror" },
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

-- Поток легитимного боя и этапов
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoStageRun or Context.Settings.AutoMobs then
            local target = Farm.GetTargetEnemy()
            if target then
                Farm.AttackTargetLegit(target)
                task.wait(Context.Settings.SwingDelay)
            else
                if Context.Settings.AutoStageRun then
                    Farm.AdvanceStageForward()
                    Farm.CollectLoot()

                    local now = os.clock()
                    if Context.Settings.AutoStage and (now - Context.LastStageTeleport) > Context.Settings.StageInterval then
                        Context.LastStageTeleport = now
                        Farm.TeleportMaxStage()
                    end
                end
                task.wait(0.25)
            end
        else
            task.wait(0.3)
        end
    end
end)

-- Поток сбора лута с фильтрацией выше мификов
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

-- 9. FLUENT UI
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Sword Loot Monarch",
    SubTitle = "by Abror • v2.3 Legit Ground",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Aqua",
    MinimizeKey = Enum.KeyCode.LeftControl
})

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
    Title = "🚀 Автопрохождение этапов (Легитимный бег по земле)",
    Default = false
})
ToggleStageRun:OnChanged(function(val)
    Context.Settings.AutoStageRun = val
    if val then
        Fluent:Notify({
            Title = "Этапы",
            Content = "Запущен легитимный наземный фарм без полётов и телепортов!",
            Duration = 3.5
        })
    end
end)

local ToggleMobs = Tabs.Stages:AddToggle("AutoMobs", {
    Title = "Авто-фарм мобов (Наземный бой на дистанции)",
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
        "Выше мификов (Divine / Secret / Celestial+)",
        "Мифик и выше (Mythic+)",
        "Легендарный и выше (Legendary+)",
        "Собирать всё подряд (All Drops)"
    },
    Default = "Выше мификов (Divine / Secret / Celestial+)"
})
DropdownLoot:OnChanged(function(val)
    if val == "Выше мификов (Divine / Secret / Celestial+)" then
        Context.Settings.MinLootTier = 7
    elseif val == "Мифик и выше (Mythic+)" then
        Context.Settings.MinLootTier = 6
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

local ToggleStage = Tabs.Progress:AddToggle("AutoStage", { Title = "Авто-переход на максимальный этап", Default = true })
ToggleStage:OnChanged(function(val) Context.Settings.AutoStage = val end)

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
    Content = "v2.3 Legit Ground загружен! Автор: Abror. Меню: LeftControl.",
    Duration = 4
})
