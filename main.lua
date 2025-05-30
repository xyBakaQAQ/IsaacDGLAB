local mod = RegisterMod("DGLAB", 1)

-- === 配置项 ===
local CONFIG = {
    controller_url = "http://127.0.0.1:8920/",
    controller_id = "all",
    
    -- === 伤害项 ===
    strength = {
        hurt = { value = 3, duration = 3 },
        card = { value = 2, duration = 2 },
        item = { value = 2, duration = 2 },
        pill = { value = 2, duration = 2 }
    },
    
    -- === 一键开火配置 ===
    fire = {
        death_strength = 10,
        death_time = 3  -- 3000毫秒 = 3秒
    }
}

-- === 状态变量 ===
local state = {
    current_strength = 0,
    strength_buffs = {}
}

-- === 工具函数 ===
local headers = { ["Content-Type"] = "application/json" }
local json = require("json")

local function getStrengthUrl()
    return CONFIG.controller_url .. "api/v2/game/" .. CONFIG.controller_id .. "/strength"
end

local function getFireUrl()
    return CONFIG.controller_url .. "api/v2/game/" .. CONFIG.controller_id .. "/action/fire"
end

local function updateStrengthFromServer()
    IsaacSocket.HttpClient.GetAsync(getStrengthUrl(), {}).Then(function(task)
        local response = task.GetResult()
        local parsed = json.decode(response.body)
        if parsed and parsed.strengthConfig and parsed.strengthConfig.strength then
            state.current_strength = parsed.strengthConfig.strength
        end
    end)
end

local function addStrengthTemporarily(addValue, durationFrames, name)
    local body = json.encode({ strength = { add = addValue } })
    IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
        table.insert(state.strength_buffs, { 
            value = addValue, 
            timer = durationFrames, 
            name = name or "Buff" 
        })
        updateStrengthFromServer()
    end)
end

local function revertStrength(subValue)
    local body = json.encode({ strength = { sub = subValue } })
    IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
        updateStrengthFromServer()
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

-- === 回调函数 ===
local function onPlayerHurt(_, entity, amount, flags, source, countdown)
    if entity.Type == EntityType.ENTITY_PLAYER then
        local player = entity:ToPlayer()
        if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
            addStrengthTemporarily(
                CONFIG.strength.hurt.value, 
                CONFIG.strength.hurt.duration * 30, 
                "Hurt"
            )
        end
    end
end

local function onCardUse(_, card, player, useFlags)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        addStrengthTemporarily(
            CONFIG.strength.card.value, 
            CONFIG.strength.card.duration * 30, 
            "Card"
        )
    end
end

local function onItemUse(_, item, rng, player, useFlags, activeSlot, varData)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        addStrengthTemporarily(
            CONFIG.strength.item.value, 
            CONFIG.strength.item.duration * 30, 
            "Item"
        )
    end
end

local function onPillUse(_, pillEffect, player, useFlags)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        addStrengthTemporarily(
            CONFIG.strength.pill.value, 
            CONFIG.strength.pill.duration * 30, 
            "Pill"
        )
    end
end

local function onGameEnd(isGameOver)
    if isGameOver then
        triggerFire(CONFIG.fire.death_strength, CONFIG.fire.death_time * 1000)  -- 将秒转换为毫秒
    end
end

local function onRender()
    local x, y = 220, 15
    Isaac.RenderText("Strength: " .. tostring(state.current_strength), x, y, 1, 1, 0, 255)

    local buff_y = y + 20
    for i, buff in ipairs(state.strength_buffs) do
        local buff_text = string.format("%s(%s): %d", buff.name, buff.value, buff.timer)
        Isaac.RenderText(buff_text, x, buff_y, 1, 1, 1, 255)
        buff_y = buff_y + 15
    end
end

local function onUpdate()
    local need_update = false
    for i = #state.strength_buffs, 1, -1 do
        local buff = state.strength_buffs[i]
        buff.timer = buff.timer - 1
        if buff.timer <= 0 then
            revertStrength(buff.value)
            table.remove(state.strength_buffs, i)
            need_update = true
        end
    end
    
    if Game():GetFrameCount() % 30 == 0 and #state.strength_buffs == 0 then
        updateStrengthFromServer()
    end
end

local function onGameStart()
    updateStrengthFromServer()
    state.strength_buffs = {}
end

-- === 注册回调 ===
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, onPlayerHurt)
mod:AddCallback(ModCallbacks.MC_USE_CARD, onCardUse)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, onItemUse)
mod:AddCallback(ModCallbacks.MC_USE_PILL, onPillUse)
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, onGameEnd)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, onRender)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onGameStart)