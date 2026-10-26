# ⚔️ [+1 Sword Loot Monarch] — Ultimate Autofarm

<div align="center">

![Status](https://img.shields.io/badge/Status-Working%20&%20Undetected-brightgreen?style=for-the-badge)
![Game](https://img.shields.io/badge/Roblox-%2B1%20Sword%20Loot%20Monarch-purple?style=for-the-badge)
![Theme](https://img.shields.io/badge/UI-Amethyst%20Purple%20Fluent-8A2BE2?style=for-the-badge)
![Author](https://img.shields.io/badge/Author-Ryomotik-blueviolet?style=for-the-badge)

**Идеальный скрипт для полной автоматизации прохождения подземелий, фарма силы и мгновенного сбора лучшего лута.**

</div>

---

## 🚀 Быстрый запуск (Loadstring)

Скопируйте и вставьте строку в любой современный Luau-экзекутор (Wave, Synapse, Solara, Arceus, Delta, Fluxus и др.):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ryomotik/SwordLootMonarch-Autofarm/main/main.lua"))()
```

---

## ✨ Основной функционал v2.7

- 🟣 **Amethyst Purple Fluent UI**: Стильный фиолетовый неоновый интерфейс с плавным перетаскиванием окна (Smooth Dragging).
- 🧲 **Supercharged Auto-Loot Vacuum (v2.7)**: Полностью пересобранный модуль авто-лута! Мгновенный вакуум предметов к персонажу (`Loot Magnet`), перехват новых дропов на лету (`ChildAdded Event`), извлечение сетевых ID (`UID`) из памяти и 5-уровневый запуск сбора через `Net.FireServer(Msg.DropPickup)`, `firesignal`, `getconnections` и `fireproximityprompt`.
- 💎 **Гибкий фильтр лута**: Возможность включить сбор абсолютно всего лута (`All Tiers`) или настроить фильтрацию от Мифика и выше (Mythic, Celestial, Secret, Divine, Zenith) + авто-подбор всех сундуков.
- 🚶 **Smart Corridor Runner**: Персонаж уверенно идёт прямо по коридору этапов, заходит в комнаты и останавливается бить мобов только тогда, когда они рядом (<45 studs).
- 🗡️ **100% Legit Ground Combat**: Полностью легитимный наземный бой (MoveTo + Dash). Никаких полётов, зависаний в воздухе и телепортов — **полная защита от киков (Error Code 267)**.
- ⚡ **Native Remote Power Train**: Фарм силы через прямой сетевой протокол `TrainManualClick = 220` на максимальной скорости.
- 🔄 **Auto Rebirth**: Автоматическое перерождение сразу при достижении нужного баланса.
- 🛡️ **Auto Equip Best**: Автоматическая экипировка сильнейшего меча из инвентаря.
- 🕒 **Built-in Anti-AFK**: Встроенная защита от 20-минутного кика Roblox через `VirtualUser`.
- 📉 **FPS Boost / Ultra Potato Mode**: Возможность отключения 3D-рендеринга для круглосуточного фарма на слабых ПК и дедиках.
- 📡 **Discord Webhook**: Отправка детальной статистики о фарме, балансе и этапах прямо в ваш Discord.
- 🗑️ **Clean Unload**: Полная и бесследная выгрузка скрипта и интерфейса в один клик.

---

## ⌨️ Управление

| Клавиша / Элемент | Действие |
| :--- | :--- |
| `LeftControl` | Скрыть / Показать меню чита |
| `Заголовок окна` | Плавное перетаскивание GUI мышкой |
| `Unload` (в настройках) | Полное закрытие и удаление скрипта из памяти |

---

<div align="center">

👑 **Created with ❤️ by Ryomotik**

</div>
