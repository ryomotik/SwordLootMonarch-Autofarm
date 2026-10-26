--[[
    ═══════════════════════════════════════════════════════════════
    ⚔️ [+1 Sword Loot Monarch] - Universal GitHub Loader
    👑 Author: Ryomotik
    ⚡ Version: v3.1 Ground Walker Edition
    ═══════════════════════════════════════════════════════════════
]]

local rawUrl = "https://raw.githubusercontent.com/ryomotik/SwordLootMonarch-Autofarm/main/main.lua"

local success, result = pcall(function()
    return game:HttpGet(rawUrl, true)
end)

if success and result and #result > 0 then
    loadstring(result)()
else
    warn("[Loader Error]: Не удалось загрузить скрипт с GitHub. Проверьте ссылку и статус репозитория.")
end
