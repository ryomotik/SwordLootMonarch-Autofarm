--[[
    ═══════════════════════════════════════════════════════════════
    ⚔️ [+1 Sword Loot Monarch] - Universal GitHub Loader
    👑 Author: Abror
    ═══════════════════════════════════════════════════════════════
]]

local rawUrl = "https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/SwordLootMonarch-Autofarm/main/main.lua"

local success, result = pcall(function()
    return game:HttpGet(rawUrl, true)
end)

if success and result and #result > 0 then
    loadstring(result)()
else
    warn("[Loader Error]: Не удалось загрузить скрипт с GitHub. Проверьте ссылку и статус репозитория.")
end
