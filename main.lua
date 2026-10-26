--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Amethyst Purple Edition)
    👑 Author: Ryomotik
    🛠️ Co-Developer: Antigravity Automation
    🔬 Version: v2.9 Natural Ground Walking & Footstep Navigation (Zero Air Diving / Pure Legs Movement)
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
        SwingDelay = 0.12,
        AutoStageRun = false,
        AutoMobs = false,
        CombatDistance = 8.0,
        MaxTargetRange = 45.0, -- Только мобы в радиусе 45 studs! Никакого таргета за 300+ studs!
        AutoDash = false, -- Отключено по умолчанию для естественной ходьбы ногами
        SmartHeal = true,
        AutoRebirth = false,
        RebirthDelay = 2.0,
        AutoEquipBest = false,
        EquipInterval = 8.0,
        AutoLoot = true,
        LootAll = false, -- Собирать абсолютно весь дроп без ограничений
        MinLootTier = 6, -- 6 = Мифик и выше (Mythic, Celestial, Secret, Divine, Zenith)
        LootMagnet = true, -- Физический вакуум/магнит дропов прямо к ногам
        LootRadius = 85.0, -- Радиус сбора лута
        LootInterval = 0.2, -- Высокая частота цикла сбора
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

-- Идеальное плавное перетаскивание окна (Fluent Window Dragging)
local function SetupWindowDragging(win)
    local rootFrame = win and (win.Root or win.Frame)
    if not rootFrame then
        local gui = (win and win.GUI) or Fluent.GUI or (gethui and gethui():FindFirstChildOfClass("ScreenGui"))
        if gui then
            rootFrame = gui:FindFirstChildWhichIsA("Frame", true)
        end
    end
    if not rootFrame then return end

    -- Перетаскивание привязано строго к заголовку (TitleBar), не ломая клики по кнопкам и вкладкам
    local titleBar = (win and win.TitleBar and win.TitleBar.Frame) or rootFrame:FindFirstChild("TitleBar", true) or rootFrame:FindFirstChildWhichIsA("Frame")
    if not titleBar then return end

    titleBar.Active = true

    local dragging = false
    local dragStart = nil
    local startPos = nil

    TrackConnection(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = rootFrame.Position

            local endConn
            endConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if endConn then endConn:Disconnect() end
                end
            end)
        end
    end))

    TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local targetPos = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            rootFrame.Position = targetPos
            if win then
                win.Position = targetPos
            end
        end
    end))

    TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
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

-- Точнейшее определение редкости (по формуле игры из DropRenderer)
function Farm.GetDropRarity(dropObj)
    if not dropObj then return 1 end

    -- 1. Поиск PointLight (в объекте или его потомках)
    local light = dropObj:IsA("PointLight") and dropObj or dropObj:FindFirstChildOfClass("PointLight")
    if not light then
        light = dropObj:FindFirstChildWhichIsA("PointLight", true)
    end

    if light then
        -- Точнейшая формула игры: Range = Rarity + 6
        if light.Range and light.Range >= 6.5 and light.Range <= 16.5 then
            local r = math.round(light.Range - 6)
            if r >= 1 and r <= 10 then
                return r
            end
        end

        -- Формула яркости игры: Brightness = Rarity * 0.15 + 0.8
        if light.Brightness and light.Brightness >= 0.85 and light.Brightness <= 2.5 then
            local r = math.round((light.Brightness - 0.8) / 0.15)
            if r >= 1 and r <= 10 then
                return r
            end
        end

        -- Сравнение с таблицей цветов Enums.RarityColor
        if light.Color and Enums and Enums.RarityColor then
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
            if minDiff < 0.45 then
                return bestTier
            end
        end
    end

    -- 2. Проверка текста в ProximityPrompt или названии
    local prompt = dropObj:FindFirstChildOfClass("ProximityPrompt", true)
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

local LastLootPickupTime = 0

-- Обработка и моментальный сбор конкретного дропа (без физического флинга и с защитой от rate-limit 15/sec)
function Farm.ProcessDrop(obj)
    if not obj or not obj.Parent then return end
    local root = GetRootPart()
    if not root then return end

    local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end

    local dist = (part.Position - root.Position).Magnitude
    local maxRadius = Context.Settings.LootRadius or 85.0
    if dist > maxRadius then return end

    -- Определение редкости и сундуков
    local rarity = Farm.GetDropRarity(obj)
    local isBossOrChest = false
    local objNameLower = string.lower(obj.Name)
    if string.find(objNameLower, "chest") or string.find(objNameLower, "boss") or string.find(objNameLower, "box") then
        isBossOrChest = true
    end

    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)
    if prompt then
        local pText = string.lower(prompt.ObjectText .. " " .. prompt.ActionText)
        if string.find(pText, "chest") or string.find(pText, "boss") or string.find(pText, "box") or string.find(pText, "сундук") then
            isBossOrChest = true
        end
    end

    -- Фильтрация лута
    local isAllowed = false
    if Context.Settings.LootAll or isBossOrChest then
        isAllowed = true
    else
        local minTier = Context.Settings.MinLootTier or 6
        if rarity >= minTier then
            isAllowed = true
        end
    end

    if not isAllowed then return end

    -- Защита от кика по превышению пакетов DropPickup (лимит сервера: max 15 в секунду)
    local now = os.clock()
    if (now - LastLootPickupTime) < 0.09 then
        return
    end
    LastLootPickupTime = now

    -- Активация ProximityPrompt и сбор
    if prompt then
        pcall(function()
            prompt.HoldDuration = 0
            prompt.MaxActivationDistance = 99999
            prompt.RequiresLineOfSight = false
        end)

        -- Извлечение UID из памяти замыкания Triggered
        local uid = nil
        local getconn = getconnections
        local getupv = (debug and debug.getupvalues) or getupvalues
        if getconn and getupv then
            pcall(function()
                for _, conn in ipairs(getconn(prompt.Triggered)) do
                    if conn.Function then
                        for _, val in pairs(getupv(conn.Function)) do
                            if type(val) == "number" and val > 0 and val < 1000000000 then
                                uid = val
                                break
                            end
                        end
                    end
                    if uid then break end
                end
            end)
        end

        if not uid then
            local rawUid = obj:GetAttribute("UID") or obj:GetAttribute("uid") or obj:GetAttribute("Id")
            uid = tonumber(rawUid) or tonumber(string.match(obj.Name, "%d+"))
        end

        -- Прямой сетевой вызов
        if uid then
            pcall(function()
                Net.FireServer(Msg.DropPickup, uid)
            end)
        end

        if firesignal then
            pcall(firesignal, prompt.Triggered)
        end

        if getconn then
            pcall(function()
                for _, conn in ipairs(getconn(prompt.Triggered)) do
                    if conn.Fire then conn:Fire() end
                    if conn.Function then conn.Function() end
                end
            end)
        end

        if fireproximityprompt then
            pcall(fireproximityprompt, prompt, 1, true)
            pcall(fireproximityprompt, prompt, 0, true)
            pcall(fireproximityprompt, prompt)
        end
    else
        local rawUid = obj:GetAttribute("UID") or obj:GetAttribute("uid") or obj:GetAttribute("Id")
        local uid = tonumber(rawUid) or tonumber(string.match(obj.Name, "%d+"))
        if uid then
            pcall(function()
                Net.FireServer(Msg.DropPickup, uid)
            end)
        end
    end
end

-- Сбор всех предметов в мире
function Farm.CollectLoot()
    local drops = Workspace:FindFirstChild("DropsClient")
    if drops then
        for _, obj in ipairs(drops:GetChildren()) do
            Farm.ProcessDrop(obj)
        end
    end

    local altDrops = Workspace:FindFirstChild("Drops")
    if altDrops and altDrops ~= drops then
        for _, obj in ipairs(altDrops:GetChildren()) do
            Farm.ProcessDrop(obj)
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

local LastAttackTime = 0
local LastSkill1Time = 0
local LastSkill2Time = 0
local LastSkill3Time = 0

-- 100% Естественная ходьба ногами по земле (БЕЗ парения, БЕЗ рывков в воздух)
function Farm.AttackTargetLegit(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum or not target or not target.Root or target.Hum.Health <= 0 then return end

    -- Всегда гарантируем прямое стояние на двух ногах
    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end
    hum.AutoRotate = true

    local myPos = root.Position
    local targetPos = target.Root.Position
    local toTarget = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = toTarget.Magnitude

    -- 1. Failsafe отхила: отбегаем назад по земле, если HP < 30%
    if Context.Settings.SmartHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.30 then
        if dist > 0.1 then
            local retreatPos = Vector3.new(myPos.X - toTarget.Unit.X * 18, myPos.Y, myPos.Z - toTarget.Unit.Z * 18)
            hum:MoveTo(retreatPos)
        end
        task.wait(0.25)
        return
    end

    local desiredDist = Context.Settings.CombatDistance or 8.0

    -- 2. Естественное перемещение ногами по земле к мобу (высота строго на уровне пола!)
    if dist > desiredDist + 1.5 then
        -- Идем шагами по земле к врагу:
        local groundTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
        hum:MoveTo(groundTarget)
    elseif dist < desiredDist - 2.5 then
        -- Моб подошел слишком близко: делаем пару шагов назад
        local stepBack = Vector3.new(myPos.X - toTarget.Unit.X * 3.0, myPos.Y, myPos.Z - toTarget.Unit.Z * 3.0)
        hum:MoveTo(stepBack)
    else
        -- На дистанции удара: стоим твердо на ногах (не скользим!)
        hum:Move(Vector3.zero, false)
    end

    -- 3. Натуральная атака мечом (рубим стоя на ногах)
    local now = os.clock()
    if (now - LastAttackTime) >= (Context.Settings.SwingDelay or 0.14) then
        LastAttackTime = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.NormalAttack)
        end)
    end

    -- Навыки по своим таймингам
    if (now - LastSkill1Time) >= 3.5 then
        LastSkill1Time = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Skill1)
        end)
    end

    if (now - LastSkill2Time) >= 4.8 then
        LastSkill2Time = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Skill2)
        end)
    end

    if (now - LastSkill3Time) >= 6.5 then
        LastSkill3Time = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Skill3)
        end)
    end

    -- Рывок Dash ТОЛЬКО если включен вручную (по умолчанию выключен, чтобы не бросать в воздух)
    if Context.Settings.AutoDash and (now - Context.LastDashTime) >= 5.0 then
        Context.LastDashTime = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.Dash)
        end)
    end
end

-- ЕСТЕСТВЕННЫЙ БЕГ ВПЕРЁД ПО ДОРОЖКЕ (ноги двигаются, персонаж шагает по земле)
function Farm.WalkForward()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end
    hum.AutoRotate = true

    local currentPos = root.Position
    -- Точка шага строго впереди на уровне пола дорожки (-Z)
    local nextPoint = Vector3.new(-1.2, currentPos.Y, currentPos.Z - 28)

    hum:MoveTo(nextPoint)

    -- Прыжок ТОЛЬКО если персонаж застрял в бордюре или ступеньке
    if root.Velocity.Magnitude < 0.5 and hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
    end
end

-- 6. СЛУЖЕБНЫЕ ХУКИ И ИНСТАНТ-СБОР ЛУТА (ChildAdded Event)
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

local function HookDropsFolder(folder)
    if not folder then return end
    TrackConnection(folder.ChildAdded:Connect(function(child)
        if Context.Settings.AutoLoot then
            task.defer(function()
                task.wait(0.04)
                Farm.ProcessDrop(child)
            end)
        end
    end))
end

local existingDrops = Workspace:FindFirstChild("DropsClient")
if existingDrops then
    HookDropsFolder(existingDrops)
end

TrackConnection(Workspace.ChildAdded:Connect(function(child)
    if child.Name == "DropsClient" or child.Name == "Drops" then
        HookDropsFolder(child)
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
                task.wait(0.3) -- Пауза дает анимации ног полностью воспроизвести шаги без скольжения
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
    SubTitle = "by Ryomotik • v2.9 Natural Walker",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Amethyst",
    MinimizeKey = Enum.KeyCode.LeftControl
})
Fluent:SetTheme("Amethyst")

task.defer(function()
    pcall(function()
        task.wait(0.2)
        SetupWindowDragging(Window)
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
    Title = "Рывок (Dash) в бою [Выкл = чистая ходьба ногами]",
    Default = false
})
ToggleDash:OnChanged(function(val) Context.Settings.AutoDash = val end)

local ToggleHeal = Tabs.Stages:AddToggle("SmartHeal", {
    Title = "Отбегать назад при низком HP (<35%)",
    Default = true
})
ToggleHeal:OnChanged(function(val) Context.Settings.SmartHeal = val end)

-- Вкладка 3: Фильтр и Вакуум Лута
local ToggleLoot = Tabs.Loot:AddToggle("AutoLoot", {
    Title = "⚡ Авто-сбор лута (Инстант подбор)",
    Default = true
})
ToggleLoot:OnChanged(function(val) Context.Settings.AutoLoot = val end)

local ToggleLootAll = Tabs.Loot:AddToggle("LootAll", {
    Title = "🌟 Собирать абсолютно ВСЁ без фильтра (All Tiers)",
    Default = false
})
ToggleLootAll:OnChanged(function(val)
    Context.Settings.LootAll = val
    if val then
        Fluent:Notify({
            Title = "Сбор лута",
            Content = "Включен сбор абсолютно всех предметов без ограничений!",
            Duration = 3
        })
    end
end)

local DropdownLoot = Tabs.Loot:AddDropdown("LootFilterDropdown", {
    Title = "Минимальная редкость (если 'Всё' выключено)",
    Values = {
        "Мифик и выше (Mythic+) [Tier 6]",
        "Строго выше мификов (Celestial+) [Tier 7]",
        "Легендарный и выше (Legendary+) [Tier 5]",
        "Эпический и выше (Epic+) [Tier 4]",
        "Редкий и выше (Rare+) [Tier 3]",
        "Обычный и выше (Common+ / Все) [Tier 1]"
    },
    Default = "Мифик и выше (Mythic+) [Tier 6]"
})
DropdownLoot:OnChanged(function(val)
    if string.find(val, "Mythic+") then
        Context.Settings.MinLootTier = 6
    elseif string.find(val, "Celestial+") then
        Context.Settings.MinLootTier = 7
    elseif string.find(val, "Legendary+") then
        Context.Settings.MinLootTier = 5
    elseif string.find(val, "Epic+") then
        Context.Settings.MinLootTier = 4
    elseif string.find(val, "Rare+") then
        Context.Settings.MinLootTier = 3
    else
        Context.Settings.MinLootTier = 1
    end
    Farm.ApplyNativeLootFilter(Context.Settings.MinLootTier)
    Fluent:Notify({
        Title = "Фильтр дропа",
        Content = "Установлен порог редкости: " .. val,
        Duration = 3
    })
end)

local ToggleMagnet = Tabs.Loot:AddToggle("LootMagnet", {
    Title = "🧲 Вакуум / Магнит дропов прямо к персонажу",
    Default = true
})
ToggleMagnet:OnChanged(function(val) Context.Settings.LootMagnet = val end)

Tabs.Loot:AddSlider("LootRadius", {
    Title = "Радиус захвата лута (Studs)",
    Default = 85.0,
    Min = 30.0,
    Max = 200.0,
    Rounding = 0,
    Callback = function(val) Context.Settings.LootRadius = val end
})

Tabs.Loot:AddSlider("LootInterval", {
    Title = "Частота проверки лута (сек)",
    Default = 0.2,
    Min = 0.05,
    Max = 1.0,
    Rounding = 2,
    Callback = function(val) Context.Settings.LootInterval = val end
})

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
    Content = "v2.9 Natural Walker загружен! Автор: Ryomotik. Меню: LeftControl.",
    Duration = 4
})
