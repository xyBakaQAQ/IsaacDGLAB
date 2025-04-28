local mod = RegisterMod("DGLAB", 1)

-- === 配置项 ===
local coyote_controller_url = "http://127.0.0.1:8920/"
local coyote_target_client_id = "all"

-- === 伤害项 ===
local strength_add_on_hurt = 3              -- 受伤强度
local strength_add_on_hurt_duration = 90    -- 受伤时间
local strength_add_on_card = 2              -- 卡牌强度
local strength_add_card_duration = 60       -- 卡牌时间
local strength_add_on_item = 2              -- 主动强度
local strength_add_item_duration = 60       -- 主动时间
local strength_add_on_pill = 2              -- 药丸强度
local strength_add_pill_duration = 60       -- 药丸时间

-- === 一键开火配置 ===
local fire_add_on_death = 20                -- 一键开火强度
local fire_time_on_death = 3000             -- 一键开火时间(ms)

-- === 状态变量 ===
local current_strength = 0
local strength_timer = 0
local temp_strength_added = 0

-- 所有临时加成的表，每项结构：{value=加成强度, timer=剩余帧数}
local strength_buffs = {}

-- === 工具函数 ===
local headers = { ["Content-Type"] = "application/json" }
local json = require("json")

local function getStrengthUrl()
    return coyote_controller_url .. "api/v2/game/" .. coyote_target_client_id .. "/strength"
end

local function getFireUrl()
    return coyote_controller_url .. "api/v2/game/" .. coyote_target_client_id .. "/action/fire"
end

local function updateStrengthFromServer()
    IsaacSocket.HttpClient.GetAsync(getStrengthUrl(), {}).Then(function(task)
        if task.IsCompletedSuccessfully() then
            local response = task.GetResult()
            local parsed = json.decode(response.body)
            if parsed and parsed.strengthConfig and parsed.strengthConfig.strength then
                current_strength = parsed.strengthConfig.strength
            end
        end
    end)
end

local function addStrengthTemporarily(addValue, durationFrames, name)
    local body = json.encode({ strength = { add = addValue } })
    IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
        if task.IsCompletedSuccessfully() then
            table.insert(strength_buffs, { value = addValue, timer = durationFrames, name = name or "Buff" })
            updateStrengthFromServer()
        end
    end)
end

local function revertStrength(subValue)
    -- 从服务器减去
    local body = json.encode({ strength = { sub = subValue } })
    IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
        if task.IsCompletedSuccessfully() then
            updateStrengthFromServer()
        end
    end)
end

-- === 一键开火 ===
local function triggerFire(strength, time)
    local body = json.encode({
        strength = strength,
        time = time
    })
    IsaacSocket.HttpClient.PostAsync(getFireUrl(), headers, body)
end

-- === 受伤回调 ===
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source, countdown)
    if entity.Type == EntityType.ENTITY_PLAYER then
        local player = entity:ToPlayer()
        if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
            addStrengthTemporarily(strength_add_on_hurt, strength_add_on_hurt_duration, "Hurt")
        end
    end
end)

-- === 卡牌回调 ===
mod:AddCallback(ModCallbacks.MC_USE_CARD, function(_, card, player, useFlags)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        addStrengthTemporarily(strength_add_on_card, strength_add_card_duration, "Card")
    end
end)

-- === 主动回调 ===
mod:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, item, rng, player, useFlags, activeSlot, varData)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        addStrengthTemporarily(strength_add_on_item, strength_add_item_duration, "Item")
    end
end)

-- === 药丸回调 ===
mod:AddCallback(ModCallbacks.MC_USE_PILL, function(_, pillEffect, player, useFlags)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        addStrengthTemporarily(strength_add_on_pill, strength_add_pill_duration, "Pill")
    end
end)

-- === 游戏结算回调（死亡） ===
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function(isGameOver)
    if isGameOver then
        triggerFire(fire_add_on_death, fire_time_on_death)
    end
end)

-- === 渲染回调 ===
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    local text = "Strength: " .. tostring(current_strength)
    local x = 220
    local y = 15
    Isaac.RenderText(text, x, y, 1, 1, 0, 255)

    -- 渲染强度以及时间
    local buff_y = y + 20
    for i, buff in ipairs(strength_buffs) do
        local buff_text = string.format("%s(%s): %d", buff.name, buff.value, buff.timer)
        Isaac.RenderText(buff_text, x, buff_y, 1, 1, 1, 255)
        buff_y = buff_y + 15
    end
end)

-- === 每帧刷新后执行 ===
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local need_update = false
    for i = #strength_buffs, 1, -1 do
        local buff = strength_buffs[i]
        buff.timer = buff.timer - 1
        if buff.timer <= 0 then
            revertStrength(buff.value)
            table.remove(strength_buffs, i)
            need_update = true
        end
    end
    -- 每30帧同步一次强度
    if Game():GetFrameCount() % 30 == 0 and #strength_buffs == 0 then
        updateStrengthFromServer()
    end
end)

-- === 游戏启动时初始化 ===
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    updateStrengthFromServer()
    strength_buffs = {}
end)