--[[
    ═══════════════════════════════════════════════════════════════
    ⚔️ [+1 Sword Loot Monarch] - Universal GitHub Loader
    👑 Author: Ryomotik
    🔬 Version: v4.0 Ultimate Edition (Cache-Busting Enabled)
    ═══════════════════════════════════════════════════════════════
]]

local rawUrl = "https://raw.githubusercontent.com/ryomotik/SwordLootMonarch-Autofarm/main/main.lua?v=" .. tostring(os.time())

local success, result = pcall(function()
    return game:HttpGet(rawUrl, true)
end)

if not success or not result or #result < 1000 then
    pcall(function()
        result = game:HttpGet("https://raw.githubusercontent.com/ryomotik/SwordLootMonarch-Autofarm/main/main.lua", true)
    end)
end

if result and #result > 1000 then
    local fn, err = loadstring(result)
    if fn then
        fn()
    else
        warn("[Loader Error]: Ошибка компиляции main.lua:", tostring(err))
    end
else
    warn("[Loader Error]: Не удалось загрузить скрипт с GitHub. Проверьте подключение к сети.")
end
