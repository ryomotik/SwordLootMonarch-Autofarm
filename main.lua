--[[
    ═══════════════════════════════════════════════════════════════
    🎮 Game: [+1 Sword Loot Monarch] (PlaceId: 93239606899307)
    ⚡ Engine: Fluent UI (Amethyst Purple Edition)
    👑 Author: Ryomotik
    🛠️ Co-Developer: Antigravity Automation
    🔬 Version: v4.0 Ultimate Edition — Flight & Ground Modes + Stage Selector + Auto-Sell + FPS Boost + Discord Webhook
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
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

-- 2. ПОДКЛЮЧЕНИЕ К ВНУТРЕННИМ МОДУЛЯМ ИГРЫ
local Shared = ReplicatedStorage:WaitForChild("Shared", 15)
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))
local Protocol = require(Shared:WaitForChild("Net"):WaitForChild("Protocol"))
local Enums = require(Shared:WaitForChild("Enums"))
local Msg = Protocol.Msg

local Inventory = require(Shared:WaitForChild("Util"):WaitForChild("Inventory"))

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
    OriginalSettings = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows
    },
    Settings = {
        -- Фарм
        AutoSwing = false,
        SwingDelay = 0.08,
        CombatDistance = 8.0,
        AutoLoot = true,
        MinLootTier = 6,
        LootRadius = 60.0,
        LootInterval = 0.3,
        AutoRebirth = false,
        RebirthDelay = 2.0,

        -- Этапы & Движение
        AutoStageRun = true,
        MoveMode = "Fly", -- "Fly" (полет / парение над мобами) или "Ground" (пешком)
        FlyHeight = 5.5,
        DodgeRadius = 7.0,
        StageMode = "PushNew", -- "PushNew" (новые этапы) или "LoopStage" (фиксированный)
        TargetStageNumber = 1,
        FarmMobsOnly = false,
        MaxTargetRange = 55.0,
        AutoDash = false,
        SmartHeal = true,

        -- Инвентарь & Авто-продажа
        AutoEquipBest = true,
        EquipInterval = 6.0,
        AutoSellEnabled = false,
        SellCommon = true,
        SellUncommon = true,
        SellRare = true,
        SellEpic = true,
        SellLegendary = false,
        SellMythic = false,
        SellInterval = 4.0,

        -- Визуал & FPS
        FPSBoost = false,
        PotatoMode = false,
        FullBright = false,
        FPSCap = 60,
        AntiAFK = true,

        -- Discord Webhook
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
    local char = GetCharacter()
    if char then
        RaycastParams_Ground.FilterDescendantsInstances = {char, Workspace:FindFirstChild("DropsClient"), Workspace:FindFirstChild("EnemiesClient")}
    end

    local origin = Vector3.new(position.X, position.Y + 8, position.Z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -60, 0), RaycastParams_Ground)
    if result then
        return result.Position.Y + 3
    end

    local resultHigh = Workspace:Raycast(Vector3.new(position.X, 200, position.Z), Vector3.new(0, -400, 0), RaycastParams_Ground)
    if resultHigh then
        return resultHigh.Position.Y + 3
    end

    return position.Y
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

-- Точнейшее определение редкости лута
function Farm.GetDropRarity(dropObj)
    if not dropObj then return 1 end

    local light = dropObj:IsA("PointLight") and dropObj or dropObj:FindFirstChildOfClass("PointLight")
    if not light then
        light = dropObj:FindFirstChildWhichIsA("PointLight", true)
    end

    if light then
        if light.Range and light.Range >= 6.5 and light.Range <= 16.5 then
            local r = math.round(light.Range - 6)
            if r >= 1 and r <= 10 then
                return r
            end
        end

        local c = light.Color
        local r, g, b = c.R, c.G, c.B

        if r > 0.85 and g > 0.85 and b > 0.85 then return 10 end
        if r > 0.8 and g < 0.2 and b < 0.2 then return 9 end
        if r > 0.8 and g > 0.7 and b < 0.2 then return 8 end
        if r < 0.3 and g > 0.7 and b > 0.8 then return 7 end
        if r > 0.7 and g < 0.3 and b > 0.7 then return 6 end
        if r > 0.9 and g > 0.5 and b < 0.2 then return 5 end
        if r > 0.5 and g < 0.3 and b > 0.6 then return 4 end
        if r < 0.3 and g > 0.4 and b > 0.8 then return 3 end
        if r < 0.3 and g > 0.8 and b < 0.4 then return 2 end
        return 1
    end

    local name = string.lower(dropObj.Name)
    if string.find(name, "chest") or string.find(name, "сундук") or string.find(name, "crate") or string.find(name, "box") then
        return 999
    end

    return 1
end

-- Мгновенный перехват и подбор дропа
local LastPickupTime = 0
function Farm.ProcessDrop(dropObj)
    if not dropObj or not dropObj.Parent then return end

    local rarity = Farm.GetDropRarity(dropObj)
    local minTier = Context.Settings.MinLootTier or 6
    if rarity < minTier and rarity ~= 999 then
        return
    end

    local prompt = dropObj:FindFirstChildOfClass("ProximityPrompt") or dropObj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled then
        local now = os.clock()
        if (now - LastPickupTime) < 0.35 then
            return
        end
        LastPickupTime = now
        pcall(function()
            fireproximityprompt(prompt, 0)
        end)
    end
end

-- ЧЕЛОВЕЧЕСКИЙ ПОДХОД К ЦЕННОМУ ДРОПУ С ПАУЗОЙ
local LastLootTargetUID = nil
local LootPauseStartTime = 0

function Farm.ProcessLootStep()
    local dropsFolder = Workspace:FindFirstChild("DropsClient")
    if not dropsFolder then return false end

    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return false end

    local myPos = root.Position
    local bestDrop = nil
    local bestDist = math.huge
    local minTier = Context.Settings.MinLootTier or 6

    for _, child in ipairs(dropsFolder:GetChildren()) do
        if child:IsA("BasePart") or child:IsA("Model") then
            local pos = child:IsA("BasePart") and child.Position or (child.PrimaryPart and child.PrimaryPart.Position or child:GetPivot().Position)
            local dist = (pos - myPos).Magnitude

            if dist <= (Context.Settings.LootRadius or 60.0) then
                local rarity = Farm.GetDropRarity(child)
                if rarity >= minTier or rarity == 999 then
                    if dist < bestDist then
                        bestDist = dist
                        bestDrop = child
                    end
                end
            end
        end
    end

    if not bestDrop or not bestDrop.Parent then
        LastLootTargetUID = nil
        return false
    end

    local dropPos = bestDrop:IsA("BasePart") and bestDrop.Position or (bestDrop.PrimaryPart and bestDrop.PrimaryPart.Position or bestDrop:GetPivot().Position)
    local distToDrop = (dropPos - myPos).Magnitude

    if distToDrop > 5.5 then
        if Context.Settings.MoveMode == "Fly" then
            local flyPos = Vector3.new(dropPos.X, dropPos.Y + (Context.Settings.FlyHeight or 5.5), dropPos.Z)
            root.CFrame = CFrame.lookAt(flyPos, dropPos)
            root.AssemblyLinearVelocity = Vector3.zero
        else
            hum:MoveTo(dropPos)
        end
        LootPauseStartTime = 0
        return true
    else
        Farm.ProcessDrop(bestDrop)

        if LastLootTargetUID ~= bestDrop then
            LastLootTargetUID = bestDrop
            LootPauseStartTime = os.clock()
        end

        local elapsed = os.clock() - LootPauseStartTime
        if elapsed < 1.0 then
            if Context.Settings.MoveMode == "Ground" then
                hum:MoveTo(myPos)
            end
            return true
        else
            return false
        end
    end
end

-- КАСТ СКИЛЛОВ
local LastSkillTimes = { [1] = 0, [2] = 0, [3] = 0 }
function Farm.TryCastSkill(slot)
    local now = os.clock()
    if (now - (LastSkillTimes[slot] or 0)) < 1.5 then return end

    if SkillInput and SkillInput.TryCastBySlot then
        pcall(function()
            local ok = SkillInput.TryCastBySlot(slot)
            if ok then LastSkillTimes[slot] = now end
        end)
    end
end

-- ПОИСК БЛИЖАЙШЕГО ВРАГА
function Farm.GetTargetEnemy(maxDist)
    local enemiesFolder = Workspace:FindFirstChild("EnemiesClient")
    if not enemiesFolder then return nil end

    local root = GetRootPart()
    if not root then return nil end

    local myPos = root.Position
    local bestTarget = nil
    local bestDist = maxDist or 55.0

    for _, model in ipairs(enemiesFolder:GetChildren()) do
        if model:IsA("Model") and model ~= LocalPlayer.Character then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local mRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart

            if hum and mRoot and hum.Health > 0 then
                local dist = (mRoot.Position - myPos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestTarget = { Model = model, Root = mRoot, Hum = hum, Distance = dist }
                end
            end
        end
    end

    return bestTarget
end

-- ═══════════════════════════════════════════════════════════
-- РЕЖИМ 1: ПОЛЁТ / ПАРЕНИЕ НАД МОБАМИ (FLY & ORBIT EVASION)
-- ═══════════════════════════════════════════════════════════
function Farm.AttackTargetFlight(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not target or not target.Root or target.Hum.Health <= 0 then return end

    local targetPos = target.Root.Position
    local myPos = root.Position

    -- Безопасный откат при критическом HP (<35%)
    if Context.Settings.SmartHeal and hum and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.35 then
        local safeSpot = target.Root.CFrame * CFrame.new(0, 15, 25)
        root.CFrame = safeSpot
        root.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.3)
        return
    end

    -- Круговой стрейф в воздухе над мобом
    local angle = (os.clock() * 3.5)
    local radius = Context.Settings.DodgeRadius or 7.0
    local height = Context.Settings.FlyHeight or 5.5

    local offsetX = math.cos(angle) * radius
    local offsetZ = math.sin(angle) * radius
    local attackSpot = Vector3.new(targetPos.X + offsetX, targetPos.Y + height, targetPos.Z + offsetZ)

    root.CFrame = CFrame.lookAt(attackSpot, targetPos)
    root.AssemblyLinearVelocity = Vector3.zero

    pcall(function()
        Net.FireServer(Msg.TrainManualClick)
    end)
    Farm.TryCastSkill(1)
    Farm.TryCastSkill(2)
    Farm.TryCastSkill(3)
end

-- Полёт вперёд по коридору к порталу / воротам
function Farm.AdvanceCorridorFlight()
    local root = GetRootPart()
    if not root then return end
    local currentPos = root.Position

    local portalPos = nil
    local portalNames = { "StageGate", "Portal", "StageTeleporter", "Gate", "Finish", "NextStage" }
    for _, name in ipairs(portalNames) do
        local obj = Workspace:FindFirstChild(name, true)
        if obj and (obj:IsA("BasePart") or obj:IsA("Model")) then
            local pos = obj:IsA("BasePart") and obj.Position or (obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position)
            if (pos - currentPos).Magnitude < 250 then
                portalPos = pos
                break
            end
        end
    end

    local height = Context.Settings.FlyHeight or 5.5
    if portalPos then
        local flySpot = Vector3.new(portalPos.X, portalPos.Y + height, portalPos.Z)
        local dir = (flySpot - currentPos)
        if dir.Magnitude > 3 then
            local step = dir.Unit * math.min(18, dir.Magnitude)
            root.CFrame = CFrame.lookAt(currentPos + step, flySpot)
            root.AssemblyLinearVelocity = Vector3.zero
        end
    else
        local nextZ = currentPos.Z - 20
        local groundY = GetGroundY(Vector3.new(-1.2, currentPos.Y, nextZ))
        local flyY = groundY + height
        local nextSpot = Vector3.new(-1.2, flyY, nextZ)
        root.CFrame = CFrame.lookAt(nextSpot, Vector3.new(-1.2, flyY, nextZ - 15))
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- ═══════════════════════════════════════════════════════════
-- РЕЖИМ 2: НАЗЕМНЫЙ БЕГ (GROUND WALKER)
-- ═══════════════════════════════════════════════════════════
function Farm.AttackTargetLegit(target)
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum or not target or not target.Root or target.Hum.Health <= 0 then return end

    local myPos = root.Position
    local targetPos = target.Root.Position
    local toTarget = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    local dist = toTarget.Magnitude

    if Context.Settings.SmartHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) < 0.35 then
        if dist > 0.1 then
            local runAwayPos = myPos - toTarget.Unit * 25
            hum:MoveTo(runAwayPos)
        end
        task.wait(0.3)
        return
    end

    local desiredDist = Context.Settings.CombatDistance or 8.0

    if dist > desiredDist + 2.5 then
        hum:MoveTo(targetPos)
    elseif dist < desiredDist - 2.0 then
        local backPos = myPos - toTarget.Unit * 3
        hum:MoveTo(backPos)
    else
        local perp = Vector3.new(-toTarget.Z, 0, toTarget.X).Unit
        local strafeDir = math.sin(os.clock() * 2.8)
        local strafePos = targetPos + (toTarget.Unit * desiredDist) + (perp * strafeDir * 4.5)
        hum:MoveTo(strafePos)
    end

    local lookTarget = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
    root.CFrame = CFrame.lookAt(myPos, lookTarget)

    pcall(function()
        Net.FireServer(Msg.TrainManualClick)
    end)
    Farm.TryCastSkill(1)
    Farm.TryCastSkill(2)
    Farm.TryCastSkill(3)
end

function Farm.WalkForward()
    local root = GetRootPart()
    local hum = GetHumanoid()
    if not root or not hum then return end

    local currentPos = root.Position
    local nextPoint = Vector3.new(-1.2, currentPos.Y, currentPos.Z - 30)
    hum:MoveTo(nextPoint)

    if root.AssemblyLinearVelocity.Magnitude < 1.0 and hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
    end
end

-- ═══════════════════════════════════════════════════════════
-- АВТО-ОБРАБОТКА ЭКРАНА СМЕРТИ (DeathGui)
-- ═══════════════════════════════════════════════════════════
local LastDeathClickTime = 0
function Farm.HandleDeathScreen()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end

    local deathGui = playerGui:FindFirstChild("DeathGui")
    if deathGui and deathGui.Enabled then
        local root = deathGui:FindFirstChild("Root")
        local panel = root and root:FindFirstChild("Panel")
        local returnObj = panel and panel:FindFirstChild("Return")
        local btn = returnObj and returnObj:FindFirstChild("Btn")

        local now = os.clock()
        if (now - LastDeathClickTime) >= 0.8 then
            LastDeathClickTime = now

            if btn and btn:IsA("GuiButton") then
                pcall(function()
                    if firesignal then
                        firesignal(btn.Activated)
                    end
                end)
            end

            pcall(function()
                Net.FireServer(Msg.StageReturnTown)
            end)
        end
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
-- АВТО-ВХОД НА ЭТАП (СПАВН ЭТАПА ИЗ ГОРОДА / ЛОББИ)
-- ═══════════════════════════════════════════════════════════
local LastStageSpawnTime = 0
function Farm.CheckStageEntry()
    local stage = LocalPlayer:GetAttribute("Stage")
    if stage == nil or stage == 0 then
        local now = os.clock()
        if (now - LastStageSpawnTime) >= 2.5 then
            LastStageSpawnTime = now
            local targetStage = 1
            if Context.Settings.StageMode == "LoopStage" then
                targetStage = math.max(1, Context.Settings.TargetStageNumber or 1)
            else
                local maxClear = LocalPlayer:GetAttribute("RunMaxClear") or 0
                targetStage = math.max(1, maxClear + 1)
            end
            pcall(function()
                Net.FireServer(Msg.StageSpawnRequest, targetStage)
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- АВТО-ПРОДАЖА ХЛАМА ПО ВЫБРАННЫМ РЕДКОСТЯМ
-- ═══════════════════════════════════════════════════════════
local function SellTrashGear()
    local data = ClientData and ClientData.Get and ClientData.Get()
    if not data or type(data.Gear) ~= "table" then return 0 end

    local equippedSpirit = Inventory.EquippedUid(data, Enums.GearSlot.Spirit)
    local equippedArmor = Inventory.EquippedUid(data, Enums.GearSlot.Armor)

    local toSell = {}
    for uid, gear in pairs(data.Gear) do
        if type(gear) == "table" and not gear.locked then
            if uid ~= equippedSpirit and uid ~= equippedArmor then
                local rarity = Inventory.GearRarity(gear) or 1
                local shouldSell = false

                if rarity == 1 and Context.Settings.SellCommon then
                    shouldSell = true
                elseif rarity == 2 and Context.Settings.SellUncommon then
                    shouldSell = true
                elseif rarity == 3 and Context.Settings.SellRare then
                    shouldSell = true
                elseif rarity == 4 and Context.Settings.SellEpic then
                    shouldSell = true
                elseif rarity == 5 and Context.Settings.SellLegendary then
                    shouldSell = true
                elseif rarity == 6 and Context.Settings.SellMythic then
                    shouldSell = true
                end

                if shouldSell then
                    table.insert(toSell, uid)
                    if #toSell >= 20 then
                        break
                    end
                end
            end
        end
    end

    if #toSell > 0 then
        pcall(function()
            Net.InvokeServer(Msg.InvSellGear, toSell)
        end)
    end
    return #toSell
end

-- ═══════════════════════════════════════════════════════════
-- НАСТРОЙКИ ВИЗУАЛА И FPS
-- ═══════════════════════════════════════════════════════════
local function ApplyPotatoMode(enabled)
    Lighting.GlobalShadows = not enabled
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") or obj:IsA("Smoke") then
            pcall(function() obj.Enabled = not enabled end)
        end
    end
end

local function ApplyFullBright(enabled)
    if enabled then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
    else
        Lighting.Brightness = Context.OriginalSettings.Brightness
        Lighting.ClockTime = Context.OriginalSettings.ClockTime
        Lighting.FogEnd = Context.OriginalSettings.FogEnd
    end
end

-- ═══════════════════════════════════════════════════════════
-- DISCORD WEBHOOK (ПРЕМИАЛЬНЫЙ АМЕТИСТОВЫЙ EMBED)
-- ═══════════════════════════════════════════════════════════
local function SendWebhook()
    if not Context.Settings.WebhookEnabled or Context.Settings.WebhookURL == "" or not HttpRequest then return end

    local stats = GetStats()
    local uptimeSec = math.floor(os.clock() - Context.StartTime)
    local uptime = string.format("%02dч %02dм %02dс", math.floor(uptimeSec / 3600), math.floor((uptimeSec % 3600) / 60), uptimeSec % 60)

    local currentStage = LocalPlayer:GetAttribute("Stage") or 0
    local stageText = currentStage > 0 and ("Этап " .. tostring(currentStage)) or "В городе (Lobby)"

    local data = ClientData and ClientData.Get and ClientData.Get()
    local equippedWeaponName = "Стандартный"
    if data then
        local uid, gear = Inventory.EquippedGear(data, Enums.GearSlot.Spirit)
        if gear then
            equippedWeaponName = Inventory.GearName(gear)
        end
    end

    local payload = {
        username = "Sword Monarch AutoFarm",
        avatar_url = "https://tr.rbxcdn.com/180DAY-e8eb1c3e387c9ad5e22822a76f28eb00/150/150/Image/Png/noFilter",
        embeds = {{
            title = "⚔️ [+1 Sword Loot Monarch] • Премиум Статистика",
            description = "🚀 **Автофарм успешно функционирует на максимальной эффективности!**",
            color = 10181046, -- Amethyst Purple (0x9B59B6)
            fields = {
                { name = "👑 Разработчик", value = "`Ryomotik`", inline = true },
                { name = "👤 Игрок", value = "`" .. LocalPlayer.Name .. " (" .. LocalPlayer.DisplayName .. ")`", inline = true },
                { name = "⏱️ Время сессии", value = "`" .. uptime .. "`", inline = true },
                { name = "⚡ Сила (Power)", value = "`" .. tostring(math.floor(stats.Power)) .. "`", inline = true },
                { name = "🔄 Перерождения", value = "`" .. tostring(stats.Rebirth) .. "`", inline = true },
                { name = "💰 Монеты (Coins)", value = "`" .. tostring(stats.Coins) .. "`", inline = true },
                { name = "🗺️ Локация / Этап", value = "`" .. stageText .. "`", inline = true },
                { name = "🏆 Макс. Этап (Рекорд)", value = "`Этап " .. tostring(stats.CareerMaxStage) .. "`", inline = true },
                { name = "🗡️ Экипированный меч", value = "`" .. equippedWeaponName .. "`", inline = true },
                { name = "🕊️ Режим движения", value = "`" .. (Context.Settings.MoveMode == "Fly" and "Полет / Парение" or "Наземный бег") .. "`", inline = true },
                { name = "🛡️ Авто-лут / Продажа", value = "`" .. (Context.Settings.AutoLoot and "🟢 Лут вкл" or "🔴 Лут выкл") .. " | " .. (Context.Settings.AutoSellEnabled and "🟢 Продажа вкл" or "🔴 Продажа выкл") .. "`", inline = true }
            },
            footer = { text = "Sword Loot Monarch • v4.0 Ultimate Edition by Ryomotik" },
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

-- ═══════════════════════════════════════════════════════════
-- 6. ГЛАВНЫЕ ФОНОВЫЕ ПОТОКИ
-- ═══════════════════════════════════════════════════════════

-- Фоновый Anti-AFK
TrackConnection(LocalPlayer.Idled:Connect(function()
    if Context.Settings.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end
end))

-- Перехват новых дропов на лету
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
    if child.Name == "DropsClient" then
        HookDropsFolder(child)
    end
end))

-- ГЛАВНЫЙ ПОТОК: Единый цикл действий (Смерть > Вход на этап > Автолут > Бой > Продвижение)
SpawnThread(function()
    while Context.Running do
        local isDead = Farm.HandleDeathScreen()

        if isDead then
            task.wait(1.0)
        elseif Context.Settings.AutoStageRun or Context.Settings.AutoSwing or Context.Settings.AutoLoot then
            Farm.CheckStageEntry()

            local lootingActive = false
            if Context.Settings.AutoLoot then
                lootingActive = Farm.ProcessLootStep()
            end

            if lootingActive then
                task.wait(0.1)
            else
                local target = Farm.GetTargetEnemy(Context.Settings.MaxTargetRange or 55.0)

                if target then
                    if Context.Settings.MoveMode == "Fly" then
                        Farm.AttackTargetFlight(target)
                    else
                        Farm.AttackTargetLegit(target)
                    end
                    task.wait(Context.Settings.SwingDelay)
                else
                    if Context.Settings.AutoStageRun and not Context.Settings.FarmMobsOnly then
                        if Context.Settings.MoveMode == "Fly" then
                            Farm.AdvanceCorridorFlight()
                        else
                            Farm.WalkForward()
                        end
                    end
                    task.wait(0.2)
                end
            end
        else
            task.wait(0.3)
        end
    end
end)

-- Поток авто-клик / тренировка силы
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoSwing then
            Farm.ClickTrain()
            task.wait(Context.Settings.SwingDelay)
        else
            task.wait(0.5)
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

-- Поток авто-экипировки лучшего меча
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

-- Поток авто-продажи снаряжения
SpawnThread(function()
    while Context.Running do
        if Context.Settings.AutoSellEnabled then
            SellTrashGear()
            task.wait(Context.Settings.SellInterval or 4.0)
        else
            task.wait(2.0)
        end
    end
end)

-- Поток Discord Webhook
SpawnThread(function()
    while Context.Running do
        if Context.Settings.WebhookEnabled and Context.Settings.WebhookURL ~= "" then
            task.wait(Context.Settings.WebhookInterval or 300)
            SendWebhook()
        else
            task.wait(5.0)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- 7. FLUENT UI (Amethyst Purple Edition)
-- ═══════════════════════════════════════════════════════════
local function LoadFluent()
    local fluentSource = nil
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
    SubTitle = "by Ryomotik • v4.0 Ultimate Edition",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 480),
    Acrylic = false,
    Theme = "Amethyst",
    MinimizeKey = Enum.KeyCode.LeftControl
})
Fluent:SetTheme("Amethyst")

local Tabs = {
    Farm = Window:AddTab({ Title = "Фарм", Icon = "swords" }),
    Stages = Window:AddTab({ Title = "Этапы & Полёт", Icon = "map-pin" }),
    Inventory = Window:AddTab({ Title = "Инвентарь & Продажа", Icon = "package" }),
    Visuals = Window:AddTab({ Title = "Визуал & FPS", Icon = "monitor" }),
    Webhook = Window:AddTab({ Title = "Discord", Icon = "bell" }),
    Settings = Window:AddTab({ Title = "Настройки", Icon = "settings" })
}

-- ───────────────────────────────────────────────────────────
-- ВКЛАДКА 1: ФАРМ
-- ───────────────────────────────────────────────────────────
local ToggleSwing = Tabs.Farm:AddToggle("AutoSwing", {
    Title = "⚔️ Авто-клик / Тренировка силы (Native)",
    Default = false
})
ToggleSwing:OnChanged(function(val) Context.Settings.AutoSwing = val end)

Tabs.Farm:AddSlider("SwingSpeed", {
    Title = "Задержка клика / атаки (сек)",
    Default = 0.08,
    Min = 0.04,
    Max = 0.5,
    Rounding = 2,
    Callback = function(val) Context.Settings.SwingDelay = val end
})

local ToggleLoot = Tabs.Farm:AddToggle("AutoLoot", {
    Title = "👣 Авто-подбор ценного дропа (Mythic+ / Сундуки)",
    Default = true
})
ToggleLoot:OnChanged(function(val) Context.Settings.AutoLoot = val end)

local DropdownLoot = Tabs.Farm:AddDropdown("MinLootTier", {
    Title = "Минимальная редкость дропа для подбора",
    Values = {
        "Мифик и выше (Mythic+) [Tier 6]",
        "Строго выше мификов (Celestial+) [Tier 7]",
        "Легендарный и выше (Legendary+) [Tier 5]",
        "Эпический и выше (Epic+) [Tier 4]",
        "Редкий и выше (Rare+) [Tier 3]",
        "Обычный и выше (Все подряд) [Tier 1]"
    },
    Default = "Мифик и выше (Mythic+) [Tier 6]"
})
DropdownLoot:OnChanged(function(val)
    if string.find(val, "Mythic+") then Context.Settings.MinLootTier = 6
    elseif string.find(val, "Celestial+") then Context.Settings.MinLootTier = 7
    elseif string.find(val, "Legendary+") then Context.Settings.MinLootTier = 5
    elseif string.find(val, "Epic+") then Context.Settings.MinLootTier = 4
    elseif string.find(val, "Rare+") then Context.Settings.MinLootTier = 3
    else Context.Settings.MinLootTier = 1 end
    Farm.ApplyNativeLootFilter(Context.Settings.MinLootTier)
end)

Tabs.Farm:AddSlider("CombatDist", {
    Title = "Дистанция удара мечом от моба (Studs)",
    Default = 8.0,
    Min = 5.0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.CombatDistance = val end
})

local ToggleRebirth = Tabs.Farm:AddToggle("AutoRebirth", {
    Title = "🔄 Авто-перерождение (PlayerRebirth)",
    Default = false
})
ToggleRebirth:OnChanged(function(val) Context.Settings.AutoRebirth = val end)

Tabs.Farm:AddSlider("RebirthDelay", {
    Title = "Задержка проверки перерождения (сек)",
    Default = 2.0,
    Min = 1.0,
    Max = 10.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.RebirthDelay = val end
})

-- ───────────────────────────────────────────────────────────
-- ВКЛАДКА 2: ЭТАПЫ & ПОЛЁТ
-- ───────────────────────────────────────────────────────────
local ToggleStageRun = Tabs.Stages:AddToggle("AutoStageRun", {
    Title = "🚀 Авто-прохождение этапов (Зачистка мобов + продвижение)",
    Default = true
})
ToggleStageRun:OnChanged(function(val) Context.Settings.AutoStageRun = val end)

local DropdownMove = Tabs.Stages:AddDropdown("MoveMode", {
    Title = "Режим перемещения / боя",
    Values = {
        "🕊️ Полёт над мобами (Fly Orbit Evasion)",
        "🚶 Наземная ходьба (Ground Walker)"
    },
    Default = "🕊️ Полёт над мобами (Fly Orbit Evasion)"
})
DropdownMove:OnChanged(function(val)
    if string.find(val, "Ground") then
        Context.Settings.MoveMode = "Ground"
    else
        Context.Settings.MoveMode = "Fly"
    end
    Fluent:Notify({
        Title = "Режим перемещения",
        Content = "Установлен: " .. val,
        Duration = 3
    })
end)

Tabs.Stages:AddSlider("FlyHeight", {
    Title = "Высота парения над мобами / землёй (Studs)",
    Default = 5.5,
    Min = 3.0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(val) Context.Settings.FlyHeight = val end
})

local DropdownStage = Tabs.Stages:AddDropdown("StageMode", {
    Title = "Выбор этапа",
    Values = {
        "📈 Пробивать новые этапы (Max Stage + 1)",
        "🎯 Фармить конкретный выбранный этап (Loop Stage)"
    },
    Default = "📈 Пробивать новые этапы (Max Stage + 1)"
})
DropdownStage:OnChanged(function(val)
    if string.find(val, "Loop") then
        Context.Settings.StageMode = "LoopStage"
    else
        Context.Settings.StageMode = "PushNew"
    end
end)

Tabs.Stages:AddSlider("TargetStage", {
    Title = "Номер этапа для постоянного фарма",
    Default = 1,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Callback = function(val) Context.Settings.TargetStageNumber = val end
})

local ToggleMobsOnly = Tabs.Stages:AddToggle("FarmMobsOnly", {
    Title = "🛑 Оставаться в одной зоне (не переходить через двери)",
    Default = false
})
ToggleMobsOnly:OnChanged(function(val) Context.Settings.FarmMobsOnly = val end)

Tabs.Stages:AddSlider("TargetRange", {
    Title = "Радиус обнаружения врагов (Studs)",
    Default = 55.0,
    Min = 20.0,
    Max = 90.0,
    Rounding = 0,
    Callback = function(val) Context.Settings.MaxTargetRange = val end
})

local ToggleHeal = Tabs.Stages:AddToggle("SmartHeal", {
    Title = "🛡️ Отлёт / отход при низком HP (<35%)",
    Default = true
})
ToggleHeal:OnChanged(function(val) Context.Settings.SmartHeal = val end)

-- ───────────────────────────────────────────────────────────
-- ВКЛАДКА 3: ИНВЕНТАРЬ & АВТО-ПРОДАЖА
-- ───────────────────────────────────────────────────────────
local ToggleEquip = Tabs.Inventory:AddToggle("AutoEquip", {
    Title = "👑 Авто-экипировка лучшего меча (InvEquipBest)",
    Default = true
})
ToggleEquip:OnChanged(function(val) Context.Settings.AutoEquipBest = val end)

Tabs.Inventory:AddButton({
    Title = "⚔️ Надеть лучший меч сейчас",
    Callback = function()
        Farm.EquipBest()
        Fluent:Notify({ Title = "Инвентарь", Content = "InvEquipBest выполнен!", Duration = 2.5 })
    end
})

local ToggleAutoSell = Tabs.Inventory:AddToggle("AutoSellEnabled", {
    Title = "💰 Авто-продажа лишнего снаряжения (InvSellGear)",
    Default = false
})
ToggleAutoSell:OnChanged(function(val)
    Context.Settings.AutoSellEnabled = val
    if val then
        Fluent:Notify({
            Title = "Авто-продажа",
            Content = "Авто-продажа активирована! Надетое и заблокированное снаряжение в безопасности.",
            Duration = 3.5
        })
    end
end)

local ToggleS1 = Tabs.Inventory:AddToggle("SellCommon", { Title = "Продавать Обычные (Common - Tier 1)", Default = true })
ToggleS1:OnChanged(function(val) Context.Settings.SellCommon = val end)

local ToggleS2 = Tabs.Inventory:AddToggle("SellUncommon", { Title = "Продавать Необычные (Uncommon - Tier 2)", Default = true })
ToggleS2:OnChanged(function(val) Context.Settings.SellUncommon = val end)

local ToggleS3 = Tabs.Inventory:AddToggle("SellRare", { Title = "Продавать Редкие (Rare - Tier 3)", Default = true })
ToggleS3:OnChanged(function(val) Context.Settings.SellRare = val end)

local ToggleS4 = Tabs.Inventory:AddToggle("SellEpic", { Title = "Продавать Эпические (Epic - Tier 4)", Default = true })
ToggleS4:OnChanged(function(val) Context.Settings.SellEpic = val end)

local ToggleS5 = Tabs.Inventory:AddToggle("SellLegendary", { Title = "Продавать Легендарные (Legendary - Tier 5)", Default = false })
ToggleS5:OnChanged(function(val) Context.Settings.SellLegendary = val end)

local ToggleS6 = Tabs.Inventory:AddToggle("SellMythic", { Title = "Продавать Мифические (Mythic - Tier 6)", Default = false })
ToggleS6:OnChanged(function(val) Context.Settings.SellMythic = val end)

Tabs.Inventory:AddButton({
    Title = "💸 Продать хлам прямо сейчас",
    Callback = function()
        local count = SellTrashGear()
        Fluent:Notify({
            Title = "Продажа",
            Content = count > 0 and ("Продано предметов: " .. tostring(count)) or "Подходящих предметов для продажи не найдено.",
            Duration = 3
        })
    end
})

-- ───────────────────────────────────────────────────────────
-- ВКЛАДКА 4: ВИЗУАЛ & FPS
-- ───────────────────────────────────────────────────────────
local ToggleFPS = Tabs.Visuals:AddToggle("FPSBoost", {
    Title = "⚡ FPS Boost (Отключение 3D-рендеринга для AFK)",
    Default = false
})
ToggleFPS:OnChanged(function(val)
    Context.Settings.FPSBoost = val
    RunService:Set3dRenderingEnabled(not val)
    if val and setfpscap then setfpscap(15) elseif setfpscap then setfpscap(Context.Settings.FPSCap or 60) end
end)

local TogglePotato = Tabs.Visuals:AddToggle("PotatoMode", {
    Title = "🥔 Режим картошки (Убрать тени, частицы и эффекты)",
    Default = false
})
TogglePotato:OnChanged(function(val)
    Context.Settings.PotatoMode = val
    ApplyPotatoMode(val)
end)

local ToggleBright = Tabs.Visuals:AddToggle("FullBright", {
    Title = "☀️ FullBright (Максимальное яркое освещение без темноты)",
    Default = false
})
ToggleBright:OnChanged(function(val)
    Context.Settings.FullBright = val
    ApplyFullBright(val)
end)

Tabs.Visuals:AddSlider("FPSCap", {
    Title = "Ограничение FPS (FPS Cap)",
    Default = 60,
    Min = 15,
    Max = 240,
    Rounding = 0,
    Callback = function(val)
        Context.Settings.FPSCap = val
        if setfpscap and not Context.Settings.FPSBoost then
            setfpscap(val)
        end
    end
})

-- ───────────────────────────────────────────────────────────
-- ВКЛАДКА 5: DISCORD WEBHOOK
-- ───────────────────────────────────────────────────────────
local ToggleWebhook = Tabs.Webhook:AddToggle("WebhookActive", {
    Title = "📡 Включить отправку премиум-отчётов в Discord",
    Default = false
})
ToggleWebhook:OnChanged(function(val) Context.Settings.WebhookEnabled = val end)

Tabs.Webhook:AddInput("WebhookURL", {
    Title = "Discord Webhook URL",
    Default = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Finished = true,
    Callback = function(val) Context.Settings.WebhookURL = val end
})

Tabs.Webhook:AddSlider("WebhookInterval", {
    Title = "Интервал отправки отчёта (сек)",
    Default = 300,
    Min = 60,
    Max = 1800,
    Rounding = 0,
    Callback = function(val) Context.Settings.WebhookInterval = val end
})

Tabs.Webhook:AddButton({
    Title = "🚀 Отправить тестовый отчёт сейчас",
    Callback = function()
        if Context.Settings.WebhookURL ~= "" then
            SendWebhook()
            Fluent:Notify({ Title = "Webhook", Content = "Тестовый пакет отправлен в Discord!", Duration = 3 })
        else
            Fluent:Notify({ Title = "Ошибка", Content = "Сначала вставьте URL вебхука!", Duration = 3 })
        end
    end
})

-- ───────────────────────────────────────────────────────────
-- ВКЛАДКА 6: НАСТРОЙКИ
-- ───────────────────────────────────────────────────────────
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
    ApplyPotatoMode(false)
    ApplyFullBright(false)

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

Window:SelectTab(1)
Fluent:Notify({
    Title = "Sword Loot Monarch",
    Content = "v4.0 Ultimate Edition загружен! Меню: LeftControl.",
    Duration = 4
})
