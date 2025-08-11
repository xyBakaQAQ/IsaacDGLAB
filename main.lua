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
        pill = { value = 2, duration = 2 },

        -- mode:
        -- "timed" -> 按时间
        -- "stack" -> 累积
        mode = "stack",

        -- 累计模式在下一层清空累积
        reset_on_new_level = true
    },
    
    -- === 自动增加设置 ===
    -- enabled: 是否开启自动增加
    -- value: 每次自动增加的强度值
    -- duration: 该自动增加的持续时间（秒）
    auto_increase = {
        enabled = false,
        value = 3,
        duration = 3
    },

    -- === 一键开火配置 ===
    fire = {
        death_strength = 10,
        death_time = 3  -- 3 秒
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

-- 统一添加强度的函数：根据 CONFIG.strength.mode 行为不同
local function addStrengthTemporarily(addValue, durationFrames, name)
    name = name or "Buff"

    if CONFIG.strength.mode == "stack" then
        -- stack 模式：累积，永久（timer = nil），每次都 add，不会替换旧层
        local body = json.encode({ strength = { add = addValue } })
        IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
            table.insert(state.strength_buffs, { 
                value = addValue, 
                timer = nil,  -- 永久（不会在 onUpdate 中倒计时）
                name = name
            })
            updateStrengthFromServer()
        end)
    else
        -- timed 模式：按时长到期
        local body = json.encode({ strength = { add = addValue } })
        IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
            table.insert(state.strength_buffs, { 
                value = addValue, 
                timer = durationFrames, 
                name = name 
            })
            updateStrengthFromServer()
        end)
    end
end

-- 保持原有 revertStrength（供 onUpdate / 重置使用）
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
    if entity and entity:ToPlayer() then
        -- 计算本次应该增加的强度值（使用简化后的 auto_increase 设置）
        local addVal
        if CONFIG.auto_increase.enabled then
            addVal = CONFIG.auto_increase.value
        else
            addVal = CONFIG.strength.hurt.value
        end

        -- durationFrames 在 timed 模式下有意义，否则为 nil（stack 模式忽视时间）
        local durationFrames = nil
        if CONFIG.strength.mode == "timed" then
            local durSec = CONFIG.auto_increase.enabled and CONFIG.auto_increase.duration or CONFIG.strength.hurt.duration
            durationFrames = durSec * 30
        end

        addStrengthTemporarily(addVal, durationFrames, "Hurt")
    end
end

local function onCardUse(_, card, player, useFlags)
    if player and player:ToPlayer() then  
        local durationFrames = nil
        if CONFIG.strength.mode == "timed" then
            durationFrames = CONFIG.strength.card.duration * 30
        end
        addStrengthTemporarily(
            CONFIG.strength.card.value, 
            durationFrames, 
            "Card"
        )
    end
end

local function onItemUse(_, item, rng, player, useFlags, activeSlot, varData)
    if player and player:ToPlayer() then  
        local durationFrames = nil
        if CONFIG.strength.mode == "timed" then
            durationFrames = CONFIG.strength.item.duration * 30
        end
        addStrengthTemporarily(
            CONFIG.strength.item.value, 
            durationFrames, 
            "Item"
        )
    end
end

local function onPillUse(_, pillEffect, player, useFlags)
    if player and player:ToPlayer() then  
        local durationFrames = nil
        if CONFIG.strength.mode == "timed" then
            durationFrames = CONFIG.strength.pill.duration * 30
        end
        addStrengthTemporarily(
            CONFIG.strength.pill.value, 
            durationFrames, 
            "Pill"
        )
    end
end

-- 新关卡回调：当为 stack 模式且 reset_on_new_level 为 true 时，清空所有累积层（并向服务器 sub 回退每层）
local function onNewLevel()
    if CONFIG.strength.mode == "stack" and CONFIG.strength.reset_on_new_level then
        -- 逐层撤销
        for i = #state.strength_buffs, 1, -1 do
            local buff = state.strength_buffs[i]
            if buff and buff.value then
                revertStrength(buff.value)
            end
            table.remove(state.strength_buffs, i)
        end
        -- 从服务器拉取最新强度
        updateStrengthFromServer()
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
    local startIndex = 1
    if CONFIG.strength.mode == "stack" then
        -- stack 模式只显示最后 3 层（最近加入的三层）
        local total = #state.strength_buffs
        if total > 3 then
            startIndex = total - 3 + 1
        end
    end

    for i = startIndex, #state.strength_buffs do
        local buff = state.strength_buffs[i]
        local timerText = buff.timer and tostring(buff.timer) or "∞"
        local buff_text = string.format("%s(%s): %d", buff.name, timerText, buff.value)
        Isaac.RenderText(buff_text, x, buff_y, 1, 1, 1, 255)
        buff_y = buff_y + 15
    end
end

local function onUpdate()
    local need_update = false
    for i = #state.strength_buffs, 1, -1 do
        local buff = state.strength_buffs[i]
        if buff.timer then
            buff.timer = buff.timer - 1
            if buff.timer <= 0 then
                -- timed 模式下到期撤销
                revertStrength(buff.value)
                table.remove(state.strength_buffs, i)
                need_update = true
            end
        end
    end
    
    -- 每秒（约30帧）当没有定时 buff 时向服务器拉取一次当前强度（保留原逻辑）
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
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, onNewLevel)
