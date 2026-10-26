--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Amethyst Purple Edition)
    👑 Author: Ryomotik
    🛠️ Co-Developer: Antigravity Automation
    🔬 Version: v3.1 Ground Walker — Raycast Grounded Movement + Human Loot + Fixed Capability
    ═══════════════════════════════════════════════════════════════
]]

-- 0. ПРЕДОТВРАЩЕНИЕ ДУБЛИРОВАНИЯ И ОЧИСТКА СТАРЫХ МОТОРОВ
if getgenv().__FluentActiveMotors then
    for _, m in pairs(getgenv().__FluentActiveMotors) do
        pcall(function() m:stop() end)
    end
    table.clear(getgenv().__FluentActiveMotors)
end

if getgenv().SwordMonarchInstance then
    pcall(function()
        getgenv().SwordMonarchInstance:Unload()
    end)
    task.wait(0.2)
end

if getgenv().Fluent then
    pcall(function() getgenv().Fluent:Destroy() end)
    getgenv().Fluent = nil
end

local function CleanupOldGuis()
    local lp = game:GetService('Players').LocalPlayer
    if lp then
        local pg = lp:FindFirstChild('PlayerGui')
        if pg then
            for _, child in ipairs(pg:GetChildren()) do
                if child:IsA('ScreenGui') and (child.Name == 'SwordMonarchGui' or child.Name:find('ScreenGui') and child:FindFirstChild('AcrylicPaint', true)) then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
    if gethui then
        pcall(function()
            for _, child in ipairs(gethui():GetChildren()) do
                if child:IsA('ScreenGui') and (child.Name == 'SwordMonarchGui' or child.Name:find('ScreenGui') and child:FindFirstChild('AcrylicPaint', true)) then
                    pcall(function() child:Destroy() end)
                end
            end
        end)
    end
end
CleanupOldGuis()

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
    LastDashTime = 0,
    StartTime = os.clock(),
    Settings = {
        AutoSwing = false,
        SwingDelay = 0.24,
        AutoStageRun = true,
        AutoMobs = false,
        CombatDistance = 8.0,
        MaxTargetRange = 45.0,
        AutoDash = false,
        SmartHeal = true,
        AutoRebirth = false,
        RebirthDelay = 2.0,
        AutoEquipBest = false,
        EquipInterval = 8.0,
        AutoLoot = true,
        LootAll = false,
        MinLootTier = 6,
        LootRadius = 60.0,
        LootInterval = 0.3,
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

-- ═══════════════════════════════════════════════════════════
-- RAYCAST GROUND CLAMP — определение реальной поверхности земли
-- ═══════════════════════════════════════════════════════════
local RaycastParams_Ground = RaycastParams.new()
RaycastParams_Ground.FilterType = Enum.RaycastFilterType.Exclude

local function GetGroundY(position)
    -- Обновляем фильтр каждый раз (персонаж может респавниться)
    local char = GetCharacter()
    if char then
        RaycastParams_Ground.FilterDescendantsInstances = {char, Workspace:FindFirstChild("DropsClient"), Workspace:FindFirstChild("EnemiesClient")}
    end

    -- Кастуем луч вниз от позиции + 5 studs вверх
    local origin = Vector3.new(position.X, position.Y + 5, position.Z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -50, 0), RaycastParams_Ground)
    if result then
        return result.Position.Y + 3 -- +3 studs = примерная высота HumanoidRootPart над землёй
    end

    -- Фоллбэк: кастуем с высоты 200
    local resultHigh = Workspace:Raycast(Vector3.new(position.X, 200, position.Z), Vector3.new(0, -400, 0), RaycastParams_Ground)
    if resultHigh then
        return resultHigh.Position.Y + 3
    end

    return position.Y -- Если ничего не нашли, оставляем как есть
end

local function GetGroundPosition(x, z)
    local y = GetGroundY(Vector3.new(x, 100, z))
    return Vector3.new(x, y, z)
end

-- ═══════════════════════════════════════════════════════════
-- GROUND ENFORCEMENT — принудительное удержание на земле
-- Фоновый цикл: если персонаж в воздухе без причины -> возвращаем на землю
-- ═══════════════════════════════════════════════════════════
local function EnforceGroundState()
    local hum = GetHumanoid()
    local root = GetRootPart()
    if not hum or not root then return end

    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end
    hum.AutoRotate = true
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

-- Извлечение UID из дропа
local function ExtractDropUID(obj)
    local uid = nil
    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)

    if prompt then
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
    end

    if not uid then
        local rawUid = obj:GetAttribute("UID") or obj:GetAttribute("uid") or obj:GetAttribute("Id")
        uid = tonumber(rawUid) or tonumber(string.match(obj.Name, "%d+"))
    end

    return uid
end

-- Подобрать конкретный дроп (отправить серверу запрос на подбор)
local LastLootPickupTime = 0

-- Безопасный подбор дропа (ровно 1 запрос с жестким интервалом >= 0.35s)
local function FirePickup(obj)
    if not obj or not obj.Parent then return false end

    local now = os.clock()
    -- Лимит: максимум ~2.8 подборов/сек (серверный лимит кика = 15/сек)
    if (now - LastLootPickupTime) < 0.35 then return false end
    LastLootPickupTime = now

    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)

    -- Способ 1: Родной ProximityPrompt через fireproximityprompt (ровно 1 вызов)
    if prompt and fireproximityprompt then
        local ok = false
        pcall(function()
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false
            fireproximityprompt(prompt, 1, true)
            ok = true
        end)
        if ok then return true end
    end

    -- Способ 2: firesignal на событие Triggered
    if prompt and firesignal then
        local ok = false
        pcall(function()
            firesignal(prompt.Triggered)
            ok = true
        end)
        if ok then return true end
    end

    -- Способ 3: Прямой сетевой вызов Net.FireServer ровно 1 раз
    local uid = ExtractDropUID(obj)
    if uid then
        pcall(function()
            Net.FireServer(Msg.DropPickup, uid)
        end)
        return true
    end

    return false
end

-- Проверка: допустим ли дроп по фильтру
local function IsDropAllowed(obj)
    if not obj or not obj.Parent then return false end

    -- Сундуки, боссы, ящики ВСЕГДА подбираем
    local objNameLower = string.lower(obj.Name)
    if string.find(objNameLower, "chest") or string.find(objNameLower, "boss") or string.find(objNameLower, "box") or string.find(objNameLower, "crate") then
        return true
    end

    local prompt = obj:FindFirstChildOfClass("ProximityPrompt", true)
    if prompt then
        local pText = string.lower(prompt.ObjectText .. " " .. prompt.ActionText)
        if string.find(pText, "chest") or string.find(pText, "boss") or string.find(pText, "box") or string.find(pText, "crate") then
            return true
        end
    end

    if Context.Settings.LootAll then
        return true
    end

    local rarity = Farm.GetDropRarity(obj)
    local minTier = Context.Settings.MinLootTier or 6 -- По умолчанию Tier 6 (Mythic и выше)
    return rarity >= minTier
end

-- ═══════════════════════════════════════════════════════════
-- ЧЕЛОВЕЧЕСКИЙ АВТОЛУТ: персонаж лично доходит ногами (<= 5.5 studs) и подбирает
-- ═══════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════
-- ЧЕЛОВЕЧЕСКИЙ ВИЗИТ К ДРОПУ: подойти ногами, постоять 1 сек и идти дальше
-- Никакого спама пакетами! Личный подход игрока к ценному предмету.
-- ═══════════════════════════════════════════════════════════
local VisitedDrops = setmetatable({}, { __mode = "k" })
local CurrentLootingDrop = nil
local CurrentLootStartTime = 0

function Farm.FindBestLootTarget()
    local root = GetRootPart()
    if not root then return nil end

    local maxRadius = Context.Settings.LootRadius or 50.0
    local bestDrop = nil
    local bestDist = maxRadius

    local function ScanFolder(folder)
        if not folder then return end
        for _, obj in ipairs(folder:GetChildren()) do
            if obj and obj.Parent and not VisitedDrops[obj] then
                local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local dist = (Vector3.new(part.Position.X, 0, part.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
                    if dist <= maxRadius and dist < bestDist then
                        if IsDropAllowed(obj) then
                            bestDist = dist
                            bestDrop = obj
                        end
                    end
                end
            end
        end
    end

    ScanFolder(Workspace:FindFirstChild("DropsClient"))
    ScanFolder(Workspace:FindFirstChild("Drops"))

    return bestDrop
end

-- Шаг подхода к дропу: если есть предмет выше легендарки — персонаж подходит, ждёт 1 сек и идёт дальше
function Farm.ProcessLootStep()
    if not Context.Settings.AutoLoot then
        CurrentLootingDrop = nil
        return false
    end

    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return false end

    -- Если текущий предмет исчез или уже был посещён — сбрасываем
    if CurrentLootingDrop and (not CurrentLootingDrop.Parent or VisitedDrops[CurrentLootingDrop]) then
        CurrentLootingDrop = nil
    end

    -- Ищем ближайший ценный предмет
    if not CurrentLootingDrop then
        CurrentLootingDrop = Farm.FindBestLootTarget()
        CurrentLootStartTime = os.clock()
    end

    local dropObj = CurrentLootingDrop
    if not dropObj or not dropObj.Parent or VisitedDrops[dropObj] then
        CurrentLootingDrop = nil
        return false
    end

    -- Защита от долгого пути (не более 5 сек на дорогу к предмету)
    if (os.clock() - CurrentLootStartTime) > 5.0 then
        VisitedDrops[dropObj] = true
        CurrentLootingDrop = nil
        return false
    end

    local part = dropObj:IsA("BasePart") and dropObj or dropObj:FindFirstChildWhichIsA("BasePart", true)
    if not part then
        VisitedDrops[dropObj] = true
        CurrentLootingDrop = nil
        return false
    end

    local dropPos = part.Position
    local myPos = root.Position
    local dist = (Vector3.new(dropPos.X, 0, dropPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude

    EnforceGroundState()

    -- Если подошли вплотную (<= 4.5 studs) — стоим 1 сек и двигаемся дальше к новым локациям!
    if dist <= 4.5 then
        -- Одиночное нажатие промпта (если поддерживается инжектором)
        local prompt = dropObj:FindFirstChildOfClass("ProximityPrompt", true)
        if prompt and fireproximityprompt then
            pcall(function()
                prompt.HoldDuration = 0
                prompt.RequiresLineOfSight = false
                fireproximityprompt(prompt, 1, true)
            end)
        end

        -- Стоим ровно 1 секунду на месте, как просил пользователь
        task.wait(1.0)

        -- Помечаем предмет как посещённый, чтобы сразу переключиться на следующие зоны/мобов
        VisitedDrops[dropObj] = true
        CurrentLootingDrop = nil
        return true
    end

    -- Идём к предмету ногами по земле (через Raycast)
    local groundTarget = GetGroundPosition(dropPos.X, dropPos.Z)
    hum:MoveTo(groundTarget)

    return true
end

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

-- 100% Естественная ходьба ногами по земле к врагу и бой
function Farm.AttackTargetLegit(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum or not target or not target.Root or target.Hum.Health <= 0 then return end

    EnforceGroundState()

    local myPos = root.Position
    local targetPos = target.Root.Position
    local flatDelta = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = flatDelta.Magnitude

    -- 1. Failsafe: отбегаем назад по земле, если HP < 30%
    if Context.Settings.SmartHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.30 then
        if dist > 0.1 then
            local retreatPos = GetGroundPosition(myPos.X - flatDelta.Unit.X * 18, myPos.Z - flatDelta.Unit.Z * 18)
            hum:MoveTo(retreatPos)
        end
        task.wait(0.25)
        return
    end

    local desiredDist = Context.Settings.CombatDistance or 8.0

    -- 2. Движение ногами к мобу (по ЗЕМЛЕ через Raycast!)
    if dist > desiredDist + 1.5 then
        -- Идём к врагу — цель на ЗЕМЛЕ
        local walkTarget = GetGroundPosition(targetPos.X, targetPos.Z)
        hum:MoveTo(walkTarget)
    elseif dist < desiredDist - 2.5 then
        -- Отходим назад
        local stepBack = GetGroundPosition(myPos.X - flatDelta.Unit.X * 3.0, myPos.Z - flatDelta.Unit.Z * 3.0)
        hum:MoveTo(stepBack)
    end
    -- На дистанции удара: НЕ вызываем Move/MoveTo — Humanoid сам остановится

    -- 3. Атака
    local now = os.clock()
    if (now - LastAttackTime) >= (Context.Settings.SwingDelay or 0.24) then
        LastAttackTime = now
        pcall(function()
            SkillInput.Press(Enums.SkillSlot.NormalAttack)
        end)
    end

    -- Навыки по таймерам
    if (now - LastSkill1Time) >= 4.5 then
        LastSkill1Time = now
        pcall(function() SkillInput.Press(Enums.SkillSlot.Skill1) end)
    end

    if (now - LastSkill2Time) >= 6.5 then
        LastSkill2Time = now
        pcall(function() SkillInput.Press(Enums.SkillSlot.Skill2) end)
    end

    if (now - LastSkill3Time) >= 8.5 then
        LastSkill3Time = now
        pcall(function() SkillInput.Press(Enums.SkillSlot.Skill3) end)
    end

    -- Dash только если включён вручную
    if Context.Settings.AutoDash and (now - Context.LastDashTime) >= 5.0 then
        Context.LastDashTime = now
        pcall(function() SkillInput.Press(Enums.SkillSlot.Dash) end)
    end
end

-- ЕСТЕСТВЕННЫЙ БЕГ ВПЕРЁД ПО ДОРОЖКЕ
function Farm.WalkForward()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    EnforceGroundState()

    -- Точка шага по коридору (-Z направление), Y через Raycast
    local nextZ = root.Position.Z - 28
    local nextPoint = GetGroundPosition(-1.2, nextZ)

    hum:MoveTo(nextPoint)

    -- Прыжок ТОЛЬКО если застрял (скорость ~0 и есть пол)
    if root.AssemblyLinearVelocity.Magnitude < 0.5 and hum.FloorMaterial ~= Enum.Material.Air then
        task.wait(0.3)
        if root.AssemblyLinearVelocity.Magnitude < 0.5 then
            hum.Jump = true
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
                { name = "🛡️ Режим боя", value = "🟢 Ground Walker v3.0", inline = true }
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

-- 8. ГЛАВНЫЕ ПОТОКИ

-- Фоновый поток: Ground Enforcement (каждые 0.2 сек)
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoStageRun or Context.Settings.AutoMobs then
            EnforceGroundState()
        end
        task.wait(0.2)
    end
end)

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

-- ═══════════════════════════════════════════════════════════
-- АВТО-ВОЗРОЖДЕНИЕ И ВХОД В ЭТАП (Бесконечный фарм без остановок)
-- ═══════════════════════════════════════════════════════════
local LastStageSpawnTime = 0

function Farm.HandleDeathScreen()
    local lp = LocalPlayer
    local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:FindFirstChild("PlayerGui")
    if not pg then return false end

    local handled = false

    -- 1. DeathGui (Окно "Вы умерли" с серой кнопкой "Вернуться в город")
    local deathGui = pg:FindFirstChild("DeathGui")
    if deathGui and deathGui.Enabled then
        local root = deathGui:FindFirstChild("Root")
        local panel = root and root:FindFirstChild("Panel")
        local ret = panel and panel:FindFirstChild("Return")
        local btn = ret and ret:FindFirstChild("Btn")

        if btn then
            if firesignal then
                pcall(function() firesignal(btn.Activated) end)
                pcall(function() firesignal(btn.MouseButton1Click) end)
            end
            if getconnections then
                pcall(function()
                    for _, c in ipairs(getconnections(btn.Activated)) do
                        if c.Fire then pcall(function() c:Fire() end)
                        elseif c.Function then pcall(c.Function) end
                    end
                    for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
                        if c.Fire then pcall(function() c:Fire() end)
                        elseif c.Function then pcall(c.Function) end
                    end
                end)
            end
            handled = true
        end

        pcall(function()
            Net.FireServer(Msg.StageReturnTown)
        end)
    end

    -- 2. Окно "Dead" (резервный экран)
    local deadGui = pg:FindFirstChild("Dead")
    if deadGui and deadGui.Enabled then
        for _, desc in ipairs(deadGui:GetDescendants()) do
            if desc:IsA("GuiButton") and (desc.Name == "Button" or desc.Name:find("Give")) then
                if firesignal then pcall(function() firesignal(desc.MouseButton1Click) end) end
                if getconnections then
                    pcall(function()
                        for _, c in ipairs(getconnections(desc.MouseButton1Click)) do
                            if c.Fire then pcall(function() c:Fire() end)
                            elseif c.Function then pcall(c.Function) end
                        end
                    end)
                end
                handled = true
            end
        end
        pcall(function() Net.FireServer(Msg.StageReturnTown) end)
    end

    return handled
end

function Farm.CheckStageEntry()
    if not Context.Settings.AutoStageRun then return end

    local stage = LocalPlayer:GetAttribute("Stage")
    -- Если stage == 0 или nil — персонаж находится в городе!
    if stage == nil or stage == 0 then
        local now = os.clock()
        if (now - LastStageSpawnTime) >= 2.5 then
            LastStageSpawnTime = now
            local maxClear = LocalPlayer:GetAttribute("RunMaxClear") or 0
            local targetStage = math.max(1, maxClear + 1)
            pcall(function()
                Net.FireServer(Msg.StageSpawnRequest, targetStage)
            end)
        end
    end
end

-- ГЛАВНЫЙ ПОТОК: Единый цикл действий (Автолут > Бой > Коридор) — никаких конфликтов MoveTo!
SpawnThread(function()
    while Context.Running do
        -- 0. ПРОВЕРКА СМЕРТИ: если открыт экран смерти — нажимаем серую кнопку "Вернуться в город"!
        local isDead = Farm.HandleDeathScreen()

        if isDead then
            task.wait(1.0)
        elseif Context.Settings.AutoStageRun or Context.Settings.AutoMobs or Context.Settings.AutoLoot then
            -- 1. Если персонаж в городе — автоматически заходим на нужный этап!
            Farm.CheckStageEntry()

            -- 2. Человеческий визит к ценному дропу (Mythic+ / сундуки): подойти, постоять 1 сек и идти дальше
            local lootingActive = false
            if Context.Settings.AutoLoot then
                lootingActive = Farm.ProcessLootStep()
            end

            if lootingActive then
                task.wait(0.1)
            else
                -- 3. Бой с мобами на пути
                local target = (Context.Settings.AutoStageRun or Context.Settings.AutoMobs) and Farm.GetTargetEnemy(Context.Settings.MaxTargetRange or 45.0)

                if target then
                    Farm.AttackTargetLegit(target)
                    task.wait(Context.Settings.SwingDelay)
                else
                    -- 4. Бег вперёд по коридору к новым этапам
                    if Context.Settings.AutoStageRun then
                        Farm.WalkForward()
                    end
                    task.wait(0.25)
                end
            end
        else
            task.wait(0.3)
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

-- 9. FLUENT UI (Amethyst Purple Edition — With Capability & CoreGui Protection)
local function LoadFluent()
    local fluentSource = nil
    -- Загружаем пропатченную Fluent UI напрямую из репозитория
    pcall(function()
        local url = "https://raw.githubusercontent.com/ryomotik/SwordLootMonarch-Autofarm/main/fluent.lua?v=" .. tostring(os.time())
        fluentSource = game:HttpGet(url, true)
    end)

    if not fluentSource or #fluentSource < 1000 then
        pcall(function()
            fluentSource = game:HttpGet("https://raw.githubusercontent.com/ryomotik/SwordLootMonarch-Autofarm/main/fluent.lua", true)
        end)
    end

    if fluentSource and #fluentSource > 1000 then
        local fn, loadErr = loadstring(fluentSource)
        if fn then
            local success, lib = pcall(fn)
            if success and lib then
                return lib
            end
        end
    end
    error("[Fluent Error]: Не удалось загрузить GUI библиотеку.")
end

local Fluent = LoadFluent()

local Window = Fluent:CreateWindow({
    Title = "Sword Loot Monarch",
    SubTitle = "by Ryomotik • v3.1 Ground Walker",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Amethyst",
    MinimizeKey = Enum.KeyCode.LeftControl
})
Fluent:SetTheme("Amethyst")

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
    Title = "🚀 Проход по локациям (Идти вперёд -> Убить мобов -> Дальше)",
    Default = true
})
ToggleStageRun:OnChanged(function(val)
    Context.Settings.AutoStageRun = val
    if val then
        Fluent:Notify({
            Title = "Этапы",
            Content = "Коридорный бег запущен! Персонаж идёт ногами, зачищает мобов и идёт дальше.",
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

-- Вкладка 3: Фильтр Лута
local ToggleLoot = Tabs.Loot:AddToggle("AutoLoot", {
    Title = "👣 Подходить к ценному дропу (подождать 1 сек и идти дальше)",
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

Tabs.Loot:AddSlider("LootRadius", {
    Title = "Радиус захвата лута (Studs)",
    Default = 60.0,
    Min = 15.0,
    Max = 150.0,
    Rounding = 0,
    Callback = function(val) Context.Settings.LootRadius = val end
})

Tabs.Loot:AddSlider("LootInterval", {
    Title = "Частота проверки лута (сек)",
    Default = 0.3,
    Min = 0.1,
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
    if Fluent then
        pcall(function() Fluent:Destroy() end)
    end
    if getgenv().__FluentActiveMotors then
        for _, m in pairs(getgenv().__FluentActiveMotors) do
            pcall(function() m:stop() end)
        end
        table.clear(getgenv().__FluentActiveMotors)
    end
    CleanupOldGuis()
    getgenv().SwordMonarchInstance = nil
    print("[Sword Monarch]: Выгружен из памяти.")
end

Window:SelectTab(2)
Fluent:Notify({
    Title = "Sword Loot Monarch",
    Content = "v3.1 Ground Walker загружен! Автор: Ryomotik. Меню: LeftControl.",
    Duration = 4
})
