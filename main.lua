--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Nord / Deep Sea Edition)
    👑 Authors: Abror & Antigravity
    🔬 Architecture: Native Net & Protocol Integration (v2.2 Stages & Evasion)
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

-- 3. СОСТОЯНИЕ
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
        MobDistance = 5.5,
        DodgeRadius = 7.0,
        AutoDash = true,
        SmartHeal = true,
        AutoRebirth = false,
        RebirthDelay = 2.0,
        AutoEquipBest = false,
        EquipInterval = 8.0,
        AutoLoot = true,
        LootInterval = 1.0,
        AutoStage = true,
        StageInterval = 5.0,
        AntiAFK = true,
        AutoReturn = true,
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

-- Авто-сбор выпавшего лута и сундуков
function Farm.CollectLoot()
    local drops = Workspace:FindFirstChild("DropsClient")
    if not drops then return end
    for _, desc in ipairs(drops:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            pcall(fireproximityprompt, desc)
        end
    end
end

-- Авто-переход в максимальную открытую зону
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

-- Атака моба с круговым уворотом (Orbital Evasion) и дэшем
function Farm.AttackTargetWithEvasion(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not target or not target.Root or target.Hum.Health <= 0 then return end

    -- 1. Безопасный откат при критическом здоровье (<35% HP)
    if Context.Settings.SmartHeal and hum and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.35 then
        local safeSpot = target.Root.CFrame * CFrame.new(0, 14, 22)
        root.CFrame = safeSpot
        root.Velocity = Vector3.zero
        task.wait(0.4)
        return
    end

    -- 2. Динамический круговой стрейф вокруг моба
    local angle = (os.clock() * 3.2)
    local radius = Context.Settings.DodgeRadius or 7.0
    local height = Context.Settings.MobDistance or 5.5

    local offsetX = math.cos(angle) * radius
    local offsetZ = math.sin(angle) * radius

    local targetPos = target.Root.Position + Vector3.new(offsetX, height, offsetZ)
    root.CFrame = CFrame.lookAt(targetPos, target.Root.Position)
    root.Velocity = Vector3.zero

    -- 3. Нативный дэш для уклонения от сильных атак
    local now = os.clock()
    if Context.Settings.AutoDash and (now - Context.LastDashTime) > 2.8 then
        Context.LastDashTime = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Dash)
        end)
    end

    -- 4. Ротация всех скиллов и ударов
    pcall(function()
        SkillInput.Press(Enums.SkillSlot.NormalAttack)
        SkillInput.Press(Enums.SkillSlot.Skill1)
        SkillInput.Press(Enums.SkillSlot.Skill2)
        SkillInput.Press(Enums.SkillSlot.Skill3)
    end)
end

-- Продвижение вперёд по этапу к воротам или следующей пачке мобов
function Farm.AdvanceStageForward()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    -- Поиск интерактивных ворот/портала этапа
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
        -- Движение вперёд по направлению коридора
        local lookDir = root.CFrame.LookVector * Vector3.new(1, 0, 1)
        if lookDir.Magnitude > 0.05 then
            hum:MoveTo(root.Position + lookDir.Unit * 30)
        end
    end
end

-- 6. FAILSAFE И СИСТЕМА ВОЗВРАТА
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

TrackConnection(LocalPlayer.CharacterAdded:Connect(function(newChar)
    if not Context.Settings.AutoReturn then return end
    local root = newChar:WaitForChild("HumanoidRootPart", 10)
    if root and Context.LastFarmPosition then
        task.wait(0.7)
        root.CFrame = Context.LastFarmPosition
        root.Velocity = Vector3.zero
        if Context.Settings.AutoEquipBest then
            task.wait(0.3)
            Farm.EquipBest()
        end
    end
end))

TrackConnection(RunService.Heartbeat:Connect(function()
    if Context.Settings.AutoReturn and Context.LastFarmPosition then
        local root = GetRootPart()
        if root and root.Position.Y < (Workspace.FallenPartsDestroyHeight + 40) then
            root.Velocity = Vector3.zero
            root.CFrame = Context.LastFarmPosition
        end
    end
end))

-- Перехват события StageCleared для автоматического перехода на следующий этап
local function SetupGameEvents()
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local MainEvent = Remotes and Remotes:FindFirstChild("MainEvent")
    if MainEvent then
        TrackConnection(MainEvent.OnClientEvent:Connect(function(msgId, ...)
            if msgId == Msg.StageCleared then
                task.delay(0.8, function()
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
                { name = "🛡️ Режим боя", value = Context.Settings.AutoStageRun and "⚡ Stage Progression" or "🗡️ Normal Farm", inline = true }
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
            local root = GetRootPart()
            if root and not Context.LastFarmPosition then
                Context.LastFarmPosition = root.CFrame
            end
            Farm.ClickTrain()
            task.wait(Context.Settings.SwingDelay)
        else
            task.wait(0.2)
        end
    end
end)

-- Поток автопрохождения этапов, мобов и уворотов
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoStageRun or Context.Settings.AutoMobs then
            local target = Farm.GetTargetEnemy()
            if target then
                Farm.AttackTargetWithEvasion(target)
                task.wait(Context.Settings.SwingDelay)
            else
                -- Если все мобы в зоне зачищены
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

-- Поток сбора лута (Drops Magnet)
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
    SubTitle = "by Abror • v2.2 Stages",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Aqua",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Фарм", Icon = "swords" }),
    Stages = Window:AddTab({ Title = "Этапы & Бой", Icon = "crosshair" }),
    Progress = Window:AddTab({ Title = "Прокачка", Icon = "trending-up" }),
    Utility = Window:AddTab({ Title = "Сервис & AFK", Icon = "cpu" }),
    Webhook = Window:AddTab({ Title = "Discord", Icon = "bell" }),
    Settings = Window:AddTab({ Title = "Конфиг", Icon = "settings" })
}

-- Вкладка 1: Основной фарм
local ToggleSwing = Tabs.Main:AddToggle("AutoSwing", { Title = "Авто-клик / Тренировка силы (Native)", Default = false })
ToggleSwing:OnChanged(function(val)
    Context.Settings.AutoSwing = val
    if val then
        local root = GetRootPart()
        if root then Context.LastFarmPosition = root.CFrame end
        Fluent:Notify({ Title = "Фарм", Content = "Тренировка силы запущена через прямой Net-канал!", Duration = 3 })
    end
end)

Tabs.Main:AddSlider("SwingSpeed", {
    Title = "Задержка клика / атаки (сек)",
    Default = 0.08,
    Min = 0.03,
    Max = 0.5,
    Rounding = 2,
    Callback = function(val) Context.Settings.SwingDelay = val end
})

local ToggleLoot = Tabs.Main:AddToggle("AutoLoot", { Title = "Авто-сбор сундуков и дропа (Loot Magnet)", Default = true })
ToggleLoot:OnChanged(function(val) Context.Settings.AutoLoot = val end)

Tabs.Main:AddButton({
    Title = "📍 Зафиксировать текущую позицию",
    Description = "Обновляет точку для Failsafe возврата",
    Callback = function()
        local root = GetRootPart()
        if root then
            Context.LastFarmPosition = root.CFrame
            Fluent:Notify({ Title = "Failsafe", Content = "Точка возврата успешно сохранена!", Duration = 3 })
        end
    end
})

-- Вкладка 2: Прохождение Этапов и Уклонение
local ToggleStageRun = Tabs.Stages:AddToggle("AutoStageRun", {
    Title = "🚀 Автопрохождение этапов (Run, Dodge & Clear)",
    Default = false
})
ToggleStageRun:OnChanged(function(val)
    Context.Settings.AutoStageRun = val
    if val then
        local root = GetRootPart()
        if root then Context.LastFarmPosition = root.CFrame end
        Fluent:Notify({
            Title = "Прохождение этапов",
            Content = "Запущен цикл продвижения вперёд, зачистки волн и уклонения!",
            Duration = 3.5
        })
    end
end)

local ToggleMobs = Tabs.Stages:AddToggle("AutoMobs", {
    Title = "Авто-фарм только ближайших мобов (без бега вперёд)",
    Default = false
})
ToggleMobs:OnChanged(function(val) Context.Settings.AutoMobs = val end)

local ToggleDash = Tabs.Stages:AddToggle("AutoDash", {
    Title = "Использовать рывок (Dash) для уклонения",
    Default = true
})
ToggleDash:OnChanged(function(val) Context.Settings.AutoDash = val end)

local ToggleHeal = Tabs.Stages:AddToggle("SmartHeal", {
    Title = "Безопасный откат при низком здоровье (<35% HP)",
    Default = true
})
ToggleHeal:OnChanged(function(val) Context.Settings.SmartHeal = val end)

Tabs.Stages:AddSlider("MobElevation", {
    Title = "Высота зависания над мобом (Studs)",
    Default = 5.5,
    Min = 3.5,
    Max = 12.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.MobDistance = val end
})

Tabs.Stages:AddSlider("DodgeRadius", {
    Title = "Радиус кругового стрейфа (Studs)",
    Default = 7.0,
    Min = 4.0,
    Max = 14.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.DodgeRadius = val end
})

-- Вкладка 3: Прокачка
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
        Fluent:Notify({ Title = "Инвентарь", Content = "Команда InvEquipBest отправлена!", Duration = 2.5 })
    end
})

Tabs.Progress:AddButton({
    Title = "🔄 Сделать Rebirth сейчас",
    Callback = function()
        Farm.Rebirth()
        Fluent:Notify({ Title = "Прокачка", Content = "Команда PlayerRebirth отправлена!", Duration = 2.5 })
    end
})

-- Вкладка 4: Сервис и AFK
local ToggleAntiAFK = Tabs.Utility:AddToggle("AntiAFK", { Title = "Встроенный Anti-AFK (VirtualUser)", Default = true })
ToggleAntiAFK:OnChanged(function(val) Context.Settings.AntiAFK = val end)

local ToggleReturn = Tabs.Utility:AddToggle("AutoReturn", { Title = "Failsafe авто-возврат на точку", Default = true })
ToggleReturn:OnChanged(function(val) Context.Settings.AutoReturn = val end)

local ToggleFPS = Tabs.Utility:AddToggle("FPSBoost", { Title = "FPS Boost (Отключение 3D-рендеринга)", Default = false })
ToggleFPS:OnChanged(function(val)
    Context.Settings.FPSBoost = val
    RunService:Set3dRenderingEnabled(not val)
    if val and setfpscap then setfpscap(15) elseif setfpscap then setfpscap(60) end
    Fluent:Notify({
        Title = "Оптимизация",
        Content = val and "3D-рендеринг выключен для тихой работы в фоне." or "3D-рендеринг включен.",
        Duration = 3
    })
end)

-- Вкладка 5: Discord Webhook
local ToggleWebhook = Tabs.Webhook:AddToggle("WebhookActive", { Title = "Включить отправку в Discord", Default = false })
ToggleWebhook:OnChanged(function(val) Context.Settings.WebhookEnabled = val end)

Tabs.Webhook:AddInput("WebhookURL", {
    Title = "Webhook URL",
    Default = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Numeric = false,
    Finished = true,
    Callback = function(val) Context.Settings.WebhookURL = val end
})

Tabs.Webhook:AddSlider("WebhookDelay", {
    Title = "Интервал отчетов (секунды)",
    Default = 300,
    Min = 60,
    Max = 1800,
    Rounding = 0,
    Callback = function(val) Context.Settings.WebhookInterval = val end
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

-- Вкладка 6: Настройки
Tabs.Settings:AddKeybind("MenuBind", {
    Title = "Клавиша скрытия меню",
    Mode = "Toggle",
    Default = "LeftControl",
    Callback = function() end
})

Tabs.Settings:AddButton({
    Title = "🗑️ Полная выгрузка скрипта (Unload)",
    Description = "Останавливает потоки и удаляет интерфейс",
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

Window:SelectTab(2) -- Сразу открываем вкладку «Этапы & Бой»
Fluent:Notify({
    Title = "Sword Loot Monarch",
    Content = "v2.2 Stages & Evasion загружен! Автор: Abror. Меню: LeftControl.",
    Duration = 4
})
