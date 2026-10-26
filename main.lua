--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Nord / Deep Sea Edition)
    👑 Authors: Abror & Antigravity
    🌐 Repository: https://github.com/YOUR_USERNAME/SwordLootMonarch-Autofarm
    ═══════════════════════════════════════════════════════════════
]]

-- 0. ПРЕДОТВРАЩЕНИЕ ДУБЛИРОВАНИЯ ЭКЗЕМПЛЯРОВ
if getgenv().SwordMonarchInstance then
    pcall(function()
        getgenv().SwordMonarchInstance:Unload()
    end)
end

local Context = {
    Running = true,
    Connections = {},
    Threads = {},
    LastFarmPosition = nil,
    StartTime = os.clock(),
    Remotes = {},
    Settings = {
        AutoSwing = false,
        SwingDelay = 0.08,
        AutoRebirth = false,
        RebirthDelay = 2.0,
        AutoEquipBest = false,
        EquipInterval = 10,
        AutoMobs = false,
        MobDistance = 6.5,
        TargetMob = "Nearest",
        AutoBuyZones = false,
        ZoneInterval = 5,
        AntiAFK = true,
        AutoReturn = true,
        FPSBoost = false,
        WebhookEnabled = false,
        WebhookURL = "",
        WebhookInterval = 300
    }
}
getgenv().SwordMonarchInstance = Context

-- 1. СЕРВИСЫ И ОКРУЖЕНИЕ
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Универсальный HTTP-клиент для Webhook
local HttpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

-- 2. СИСТЕМА УПРАВЛЕНИЯ РЕСУРСАМИ (Clean Registry)
local function TrackConnection(conn)
    table.insert(Context.Connections, conn)
    return conn
end

local function SpawnThread(fn)
    local co = task.spawn(function()
        while Context.Running do
            local success, err = pcall(fn)
            if not success and Context.Running then
                warn("[Thread Error]:", err)
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

-- Поиск характеристик (leaderstats / Attributes)
local function GetPlayerStat(statName)
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    if stats then
        for _, item in ipairs(stats:GetChildren()) do
            if string.lower(item.Name) == string.lower(statName) then
                return item.Value
            end
        end
    end
    local attr = LocalPlayer:GetAttribute(statName)
    if attr ~= nil then return attr end
    local char = LocalPlayer.Character
    if char then
        local charAttr = char:GetAttribute(statName)
        if charAttr ~= nil then return charAttr end
    end
    return 0
end

-- 3. NETBRIDGE: АДАПТИВНЫЙ СКАНЕР И ЗАЩИЩЕННЫЙ КЛИЕНТ РЕМОУТОВ
local NetBridge = {
    Cooldowns = {},
    RateLimit = 0.05
}

function NetBridge.ScanRemotes()
    local keywords = {
        Swing = { "swing", "click", "train", "slash", "attack", "hit", "damage", "punch" },
        Rebirth = { "rebirth", "prestige", "ascend", "restart" },
        Equip = { "equipbest", "equip_best", "autoequip", "bestsword", "weaponequip" },
        Zone = { "unlockzone", "buyzone", "teleportzone", "area", "unlockarea", "world" },
        Upgrade = { "upgrade", "buyupgrade", "purchasestat", "upgradestat" }
    }

    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local lowerName = string.lower(obj.Name)
            for category, list in pairs(keywords) do
                if not Context.Remotes[category] then
                    for _, kw in ipairs(list) do
                        if string.find(lowerName, kw) then
                            Context.Remotes[category] = obj
                            break
                        end
                    end
                end
            end
        end
    end
end

NetBridge.ScanRemotes()

function NetBridge.Fire(remote, ...)
    if not remote then return false end
    local now = os.clock()
    local lastFire = NetBridge.Cooldowns[remote] or 0
    if (now - lastFire) < NetBridge.RateLimit then return false end
    NetBridge.Cooldowns[remote] = now

    local success, res = pcall(function(...)
        if remote:IsA("RemoteEvent") then
            remote:FireServer(...)
        elseif remote:IsA("RemoteFunction") then
            return remote:InvokeServer(...)
        end
    end, ...)
    return success, res
end

-- 4. МЕХАНИКА ФАРМА (1000+ IQ Loop Engine)
local FarmEngine = {}

-- Авто-клик / Тренировка силы
function FarmEngine.PerformSwing()
    if Context.Remotes.Swing then
        NetBridge.Fire(Context.Remotes.Swing)
    else
        local char = GetCharacter()
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            tool:Activate()
        else
            local bpTool = LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
            if bpTool then
                local hum = GetHumanoid()
                if hum then hum:EquipTool(bpTool) end
            else
                VirtualUser:CaptureController()
                VirtualUser:Button1Down(Vector2.new(100, 100))
                task.wait(0.02)
                VirtualUser:Button1Up(Vector2.new(100, 100))
            end
        end
    end
end

-- Авто-экипировка лучшего оружия
function FarmEngine.EquipBest()
    if Context.Remotes.Equip then
        NetBridge.Fire(Context.Remotes.Equip)
    else
        local bestSword = nil
        local maxPower = -1
        local allSwords = {}

        for _, item in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if item:IsA("Tool") then table.insert(allSwords, item) end
        end
        local char = LocalPlayer.Character
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") then table.insert(allSwords, item) end
            end
        end

        for _, tool in ipairs(allSwords) do
            local power = tool:GetAttribute("Power") or tool:GetAttribute("Damage") or tool:GetAttribute("Multiplier") or 0
            if power > maxPower then
                maxPower = power
                bestSword = tool
            end
        end

        if bestSword and char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and bestSword.Parent == LocalPlayer.Backpack then
                hum:EquipTool(bestSword)
            end
        end
    end
end

-- Поиск мобов и боссов для безопасного фарма
function FarmEngine.GetTargetMob()
    local root = GetRootPart()
    if not root then return nil end

    local targets = {}
    local mobFolders = {
        Workspace:FindFirstChild("Enemies"),
        Workspace:FindFirstChild("Mobs"),
        Workspace:FindFirstChild("Monsters"),
        Workspace:FindFirstChild("Bosses"),
        Workspace
    }

    for _, folder in ipairs(mobFolders) do
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and model ~= LocalPlayer.Character then
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    local mRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                    local isPlayer = Players:GetPlayerFromCharacter(model)

                    if hum and mRoot and not isPlayer and hum.Health > 0 then
                        local dist = (mRoot.Position - root.Position).Magnitude
                        table.insert(targets, { Model = model, Root = mRoot, Hum = hum, Distance = dist })
                    end
                end
            end
        end
    end

    if #targets == 0 then return nil end
    table.sort(targets, function(a, b) return a.Distance < b.Distance end)
    return targets[1]
end

-- 5. FAILSAFE & ANTI-AFK СИСТЕМЫ
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

local function SetupFailsafe()
    TrackConnection(LocalPlayer.CharacterAdded:Connect(function(newChar)
        if not Context.Settings.AutoReturn then return end
        local root = newChar:WaitForChild("HumanoidRootPart", 10)
        local hum = newChar:WaitForChild("Humanoid", 10)

        if root and Context.LastFarmPosition then
            task.wait(0.7)
            root.CFrame = Context.LastFarmPosition
            root.Velocity = Vector3.zero
            root.RotVelocity = Vector3.zero
            if Context.Settings.AutoEquipBest then
                task.wait(0.3)
                FarmEngine.EquipBest()
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
end
SetupFailsafe()

-- 6. DISCORD WEBHOOK
local function SendDiscordWebhook()
    if not Context.Settings.WebhookEnabled or Context.Settings.WebhookURL == "" then return end
    if not HttpRequest then return end

    local power = GetPlayerStat("Power") or GetPlayerStat("Strength") or "N/A"
    local rebirths = GetPlayerStat("Rebirth") or GetPlayerStat("Rebirths") or "N/A"
    local coins = GetPlayerStat("Coins") or GetPlayerStat("Gold") or GetPlayerStat("Wins") or "N/A"
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
                { name = "⚡ Сила / Power", value = "`" .. tostring(power) .. "`", inline = false },
                { name = "🔄 Перерождения", value = "`" .. tostring(rebirths) .. "`", inline = true },
                { name = "💰 Монеты / Победы", value = "`" .. tostring(coins) .. "`", inline = true },
                { name = "🛡️ Статус защиты", value = Context.Settings.AutoReturn and "🟢 Failsafe Active" or "🟡 Failsafe Disabled", inline = false }
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

-- 7. ЗАПУСК ФОНОВЫХ ПОТОКОВ ФАРМА
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoSwing and not Context.Settings.AutoMobs then
            local root = GetRootPart()
            if root and not Context.LastFarmPosition then
                Context.LastFarmPosition = root.CFrame
            end
            FarmEngine.PerformSwing()
            task.wait(Context.Settings.SwingDelay)
        else
            task.wait(0.2)
        end
    end
end)

SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoMobs then
            local target = FarmEngine.GetTargetMob()
            local root = GetRootPart()

            if target and root and target.Root and target.Hum.Health > 0 then
                local safeCF = target.Root.CFrame * CFrame.new(0, Context.Settings.MobDistance, 0) * CFrame.Angles(math.rad(-90), 0, 0)
                root.CFrame = safeCF
                root.Velocity = Vector3.zero

                FarmEngine.PerformSwing()
                task.wait(Context.Settings.SwingDelay)
            else
                task.wait(0.4)
            end
        else
            task.wait(0.3)
        end
    end
end)

SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoRebirth then
            if Context.Remotes.Rebirth then
                NetBridge.Fire(Context.Remotes.Rebirth)
            end
            task.wait(Context.Settings.RebirthDelay)
        else
            task.wait(1)
        end
    end
end)

SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoEquipBest then
            FarmEngine.EquipBest()
            task.wait(Context.Settings.EquipInterval)
        else
            task.wait(1)
        end
    end
end)

SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoBuyZones then
            if Context.Remotes.Zone then
                NetBridge.Fire(Context.Remotes.Zone)
            end
            task.wait(Context.Settings.ZoneInterval)
        else
            task.wait(2)
        end
    end
end)

SpawnThread(function()
    while Context.Running do
        if Context.Settings.WebhookEnabled and Context.Settings.WebhookURL ~= "" then
            task.wait(Context.Settings.WebhookInterval)
            SendDiscordWebhook()
        else
            task.wait(5)
        end
    end
end)

-- 8. ИНТЕРФЕЙС FLUENT UI (Nord / Deep Sea)
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Sword Loot Monarch",
    SubTitle = "by Abror • v2.0 Nord",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Aqua",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Фарм", Icon = "swords" }),
    Combat = Window:AddTab({ Title = "Мобы и Боссы", Icon = "crosshair" }),
    Progress = Window:AddTab({ Title = "Прокачка", Icon = "trending-up" }),
    Utility = Window:AddTab({ Title = "Сервис & AFK", Icon = "cpu" }),
    Webhook = Window:AddTab({ Title = "Discord", Icon = "bell" }),
    Settings = Window:AddTab({ Title = "Конфиг", Icon = "settings" })
}

local ToggleSwing = Tabs.Main:AddToggle("AutoSwing", { Title = "Авто-клик / Тренировка силы", Default = false })
ToggleSwing:OnChanged(function(val)
    Context.Settings.AutoSwing = val
    if val then
        local root = GetRootPart()
        if root then Context.LastFarmPosition = root.CFrame end
        Fluent:Notify({ Title = "Фарм", Content = "Цикл тренировки запущен. Точка зафиксирована.", Duration = 3 })
    end
end)

Tabs.Main:AddSlider("SwingSpeed", {
    Title = "Задержка клика (сек)",
    Default = 0.08,
    Min = 0.02,
    Max = 0.5,
    Rounding = 2,
    Callback = function(val) Context.Settings.SwingDelay = val end
})

Tabs.Main:AddButton({
    Title = "📍 Зафиксировать текущую позицию",
    Description = "Обновляет точку возврата для Failsafe",
    Callback = function()
        local root = GetRootPart()
        if root then
            Context.LastFarmPosition = root.CFrame
            Fluent:Notify({ Title = "Failsafe", Content = "Новая позиция для респавна успешно сохранена!", Duration = 3 })
        end
    end
})

local ToggleMobs = Tabs.Combat:AddToggle("AutoMobs", { Title = "Авто-фарм мобов и боссов", Default = false })
ToggleMobs:OnChanged(function(val)
    Context.Settings.AutoMobs = val
    if val then
        local root = GetRootPart()
        if root then Context.LastFarmPosition = root.CFrame end
        Fluent:Notify({ Title = "Бой", Content = "Режим охоты на мобов включён (Safe Elevation).", Duration = 3 })
    end
end)

Tabs.Combat:AddSlider("MobElevation", {
    Title = "Безопасная высота над мобом (Studs)",
    Default = 6.5,
    Min = 4.0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.MobDistance = val end
})

local ToggleRebirth = Tabs.Progress:AddToggle("AutoRebirth", { Title = "Авто-перерождение (Auto Rebirth)", Default = false })
ToggleRebirth:OnChanged(function(val) Context.Settings.AutoRebirth = val end)

local ToggleEquip = Tabs.Progress:AddToggle("AutoEquip", { Title = "Авто-экипировка лучшего меча (Equip Best)", Default = false })
ToggleEquip:OnChanged(function(val) Context.Settings.AutoEquipBest = val end)

local ToggleZones = Tabs.Progress:AddToggle("AutoZones", { Title = "Авто-покупка следующих зон/миров", Default = false })
ToggleZones:OnChanged(function(val) Context.Settings.AutoBuyZones = val end)

Tabs.Progress:AddButton({
    Title = "⚔️ Экипировать лучшее оружие сейчас",
    Description = "Ручной триггер экипировки максимального меча",
    Callback = function()
        FarmEngine.EquipBest()
        Fluent:Notify({ Title = "Инвентарь", Content = "Лучший меч экипирован!", Duration = 2.5 })
    end
})

local ToggleAntiAFK = Tabs.Utility:AddToggle("AntiAFK", { Title = "Встроенный Anti-AFK (VirtualUser)", Default = true })
ToggleAntiAFK:OnChanged(function(val) Context.Settings.AntiAFK = val end)

local ToggleReturn = Tabs.Utility:AddToggle("AutoReturn", { Title = "Failsafe возврат на точку при респавне", Default = true })
ToggleReturn:OnChanged(function(val) Context.Settings.AutoReturn = val end)

local ToggleFPS = Tabs.Utility:AddToggle("FPSBoost", { Title = "FPS Boost (Отключение 3D-рендеринга)", Default = false })
ToggleFPS:OnChanged(function(val)
    Context.Settings.FPSBoost = val
    RunService:Set3dRenderingEnabled(not val)
    if val and setfpscap then setfpscap(15) elseif setfpscap then setfpscap(60) end
    Fluent:Notify({
        Title = "Оптимизация",
        Content = val and "3D-рендеринг отключен для экономии GPU/CPU." or "3D-рендеринг восстановлен.",
        Duration = 3
    })
end)

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
    Title = "📡 Отправить тестовый отчет сейчас",
    Callback = function()
        if Context.Settings.WebhookURL ~= "" then
            SendDiscordWebhook()
            Fluent:Notify({ Title = "Webhook", Content = "Тестовый пакет отправлен!", Duration = 3 })
        else
            Fluent:Notify({ Title = "Ошибка", Content = "Сначала вставьте URL вебхука!", Duration = 3 })
        end
    end
})

Tabs.Settings:AddKeybind("MenuBind", {
    Title = "Клавиша скрытия меню",
    Mode = "Toggle",
    Default = "LeftControl",
    Callback = function() end
})

Tabs.Settings:AddButton({
    Title = "🗑️ Полная выгрузка скрипта (Unload)",
    Description = "Останавливает все потоки, удаляет хуки и закрывает GUI",
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
    print("[Sword Monarch]: Скрипт полностью выгружен из памяти.")
end

Window:SelectTab(1)
Fluent:Notify({
    Title = "Sword Loot Monarch",
    Content = "Скрипт успешно запущен! Автор: Abror. Скрытие: LeftControl.",
    Duration = 4
})
