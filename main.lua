local mod = RegisterMod("DGLAB", 1)

-- === 配置项 ===
local coyote_controller_url = "http://127.0.0.1:8920/"
local coyote_target_client_id = "all"
-- === 伤害项 ===
local strength_add_on_hurt = 3 -- 受伤强度
local strength_add_duration = 90 -- 受伤时间
local strength_add_on_card = 2 -- 卡牌强度
local strength_add_card_duration = 60 -- 卡牌时间
local strength_add_on_item = 2 -- 主动强度
local strength_add_item_duration = 60-- 主动时间
local strength_add_on_death = 10 -- 死亡强度
local strength_add_death_duration = 120 -- 死亡时间

-- === 状态变量 ===
local current_strength = 0
local strength_timer = 0
local temp_strength_added = 0

-- === 工具函数 ===
local function getStrengthUrl()
    return coyote_controller_url .. "api/v2/game/" .. coyote_target_client_id .. "/strength"
end

local function updateStrengthFromServer()
    IsaacSocket.HttpClient.GetAsync(getStrengthUrl(), {}).Then(function(task)
        if task.IsCompletedSuccessfully() then
            local response = task.GetResult()
            local json = require("json").decode(response.body)
            if json and json.strengthConfig and json.strengthConfig.strength then
                current_strength = json.strengthConfig.strength
            end
        end
    end)
end

local function addStrengthTemporarily(addValue, durationFrames)
    -- 临时加strength
    local headers = { ["Content-Type"] = "application/json" }
    local body = require("json").encode({ strength = { add = addValue } })
    IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
        if task.IsCompletedSuccessfully() then
            temp_strength_added = addValue
            strength_timer = durationFrames
            updateStrengthFromServer()
        end
    end)
end

local function revertStrength()
    if temp_strength_added ~= 0 then
        -- 减去之前加的数
        local headers = { ["Content-Type"] = "application/json" }
        local body = require("json").encode({ strength = { sub = temp_strength_added } })
        IsaacSocket.HttpClient.PostAsync(getStrengthUrl(), headers, body).Then(function(task)
            if task.IsCompletedSuccessfully() then
                temp_strength_added = 0
                updateStrengthFromServer()
            end
        end)
    end
end

-- === 受伤回调 ===
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source, countdown)
    if entity.Type == EntityType.ENTITY_PLAYER then
        local player = entity:ToPlayer()
        if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
            if strength_timer == 0 then
                addStrengthTemporarily(strength_add_on_hurt, strength_add_duration)
            else
                strength_timer = strength_add_duration
            end
        end
    end
end)

-- === 卡牌回调 ===
mod:AddCallback(ModCallbacks.MC_USE_CARD, function(_, card, player, useFlags)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        if strength_timer == 0 then
            addStrengthTemporarily(strength_add_on_card, strength_add_card_duration)
        else
            strength_timer = strength_add_card_duration
        end
    end
end)

-- === 主动回调 ===
mod:AddCallback(ModCallbacks.MC_USE_ITEM, function(_, item, rng, player, useFlags, activeSlot, varData)
    if player:GetPlayerType() == PlayerType.PLAYER_ISAAC then
        if strength_timer == 0 then
            addStrengthTemporarily(strength_add_on_item, strength_add_item_duration)
        else
            strength_timer = strength_add_item_duration
        end
    end
end)

-- === 游戏结算回调（死亡） ===
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function(isGameOver)
    if isGameOver then
        addStrengthTemporarily(strength_add_on_death, strength_add_death_duration)
    end
end)

-- === 渲染回调===
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    local text = "Strength: " .. tostring(current_strength)
    local x = 330
    local y = 15
    Isaac.RenderText(text, x, y, 1, 1, 0, 255)
    if strength_timer > 0 then
        strength_timer = strength_timer - 1
        if strength_timer == 0 then
            revertStrength()
        end
    end
end)

-- === 游戏启动时初始化 ===
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    updateStrengthFromServer()
    temp_strength_added = 0
    strength_timer = 0
end)

-- === 每30帧同步一次强度 ===
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if Game():GetFrameCount() % 30 == 0 and strength_timer == 0 then
        updateStrengthFromServer()
    end
end)