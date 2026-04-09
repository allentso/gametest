--- CombatSystem - 战斗系统核心模块
--- 管理玩家HP、异兽HP、Debuff、溃散、瘴气伤害、受击反馈
local EventBus = require("systems.EventBus")
local SchoolEffects = require("systems.SchoolEffects")
local GameState = require("systems.GameState")

local CombatSystem = {}

------------------------------------------------------------
-- 常量
------------------------------------------------------------
CombatSystem.MAX_HP = 10
CombatSystem.COLLAPSE_DURATION = 8.0  -- 灵气溃散持续秒数
CombatSystem.COLLAPSE_SPEED_MUL = 0.5
CombatSystem.COLLAPSE_VISION = 2.5

-- 瘴气伤害间隔（秒/滴）
CombatSystem.MIASMA_INTERVAL = {
    normal  = 4.0,
    warning = 4.0,
    danger  = 2.5,
    collapse = 1.5,
}

-- 异兽品质HP
CombatSystem.BEAST_HP = { R = 4, SR = 6, SSR = 8 }
CombatSystem.BEAST_WEAK_DURATION = 60  -- 虚弱持续秒数

------------------------------------------------------------
-- 玩家状态
------------------------------------------------------------
---@type number
CombatSystem.hp = 10
---@type number
CombatSystem.hitFlashTimer = 0       -- 受击屏幕泛红计时
---@type number
CombatSystem.miasmaTimer = 0         -- 瘴气累计计时
---@type number
CombatSystem.miasmaDmgFlash = 0      -- 瘴气墨染动画计时
---@type boolean
CombatSystem.collapsed = false       -- 是否处于灵气溃散
---@type number
CombatSystem.collapseTimer = 0       -- 溃散剩余时间
---@type boolean
CombatSystem.collapseHandled = false -- 溃散结算是否已执行
---@type boolean
CombatSystem.revived = false         -- 本局是否已使用复苏符

-- Debuff 表: { [debuffId] = { timer=秒, ... } }
---@type table<string, table>
CombatSystem.debuffs = {}

-- Debuff 定义
CombatSystem.DEBUFF_DEFS = {
    petrify   = { name = "石化",   maxDuration = 3.0,  speedMul = 0.50 },
    sticky    = { name = "黏滞",   maxDuration = 5.0,  speedMul = 0.70 },
    burn      = { name = "火灼",   maxDuration = 1.0,  speedMul = 0.70 },
    dizzy     = { name = "迷向",   maxDuration = 2.0,  speedMul = 1.0  },
    ink       = { name = "墨迹",   maxDuration = 20.0, speedMul = 1.0, maxStacks = 2 },
}

------------------------------------------------------------
-- 初始化/重置（每局开始调用）
------------------------------------------------------------
function CombatSystem.reset()
    -- 从持久存档读取 HP（跨局不自动恢复）
    CombatSystem.hp = math.max(1, math.min(CombatSystem.MAX_HP, GameState.data.hp or CombatSystem.MAX_HP))
    CombatSystem.hitFlashTimer = 0
    CombatSystem.miasmaTimer = 0
    CombatSystem.miasmaDmgFlash = 0
    CombatSystem.collapsed = false
    CombatSystem.collapseTimer = 0
    CombatSystem.collapseHandled = false
    CombatSystem.revived = false
    CombatSystem.debuffs = {}
end

------------------------------------------------------------
-- 玩家受伤
------------------------------------------------------------
---@param amount number 伤害值
---@param source string 来源标识 "beast"/"miasma"/"suppress_fail"
---@return boolean isDead 是否触发溃散
function CombatSystem.takeDamage(amount, source)
    if CombatSystem.collapsed then return false end
    if amount <= 0 then return false end

    CombatSystem.hp = math.max(0, CombatSystem.hp - amount)

    -- 受击反馈
    if source == "miasma" then
        CombatSystem.miasmaDmgFlash = 1.0  -- 瘴气墨染1秒
    else
        CombatSystem.hitFlashTimer = 0.3   -- 普通受击闪红0.3秒
    end

    EventBus.emit("player_damaged", { amount = amount, source = source, hpLeft = CombatSystem.hp })

    -- 检查溃散
    if CombatSystem.hp <= 0 then
        return CombatSystem.tryCollapse()
    end
    return false
end

------------------------------------------------------------
-- 玩家恢复HP
------------------------------------------------------------
---@param amount number
function CombatSystem.heal(amount)
    if CombatSystem.collapsed then return end
    CombatSystem.hp = math.min(CombatSystem.MAX_HP, CombatSystem.hp + amount)
    EventBus.emit("player_healed", { amount = amount, hpNow = CombatSystem.hp })
end

------------------------------------------------------------
-- 灵气溃散
------------------------------------------------------------
function CombatSystem.tryCollapse()
    -- 检查复苏符
    local SessionState = require("systems.SessionState")
    if not CombatSystem.revived and SessionState.hasItem("fusufu") then
        SessionState.addItem("fusufu", -1)
        CombatSystem.revived = true
        -- 撤离流大成：复苏符额外+2HP（4→6）
        local effect = SchoolEffects.get()
        local healAmt = 4
        if effect and effect.reviveHPBonus then
            healAmt = healAmt + effect.reviveHPBonus
        end
        CombatSystem.hp = math.min(CombatSystem.MAX_HP, healAmt)
        CombatSystem.clearAllDebuffs()
        EventBus.emit("fusufu_triggered", { healed = healAmt })
        return false
    end

    -- 进入溃散
    CombatSystem.collapsed = true
    -- 撤离流初学+：溃散虚弱时间延长至12秒
    local effect = SchoolEffects.get()
    local collapseDur = CombatSystem.COLLAPSE_DURATION
    if effect and effect.weakenDurationOverride then
        collapseDur = effect.weakenDurationOverride
    end
    CombatSystem.collapseTimer = collapseDur
    CombatSystem.collapseHandled = false
    EventBus.emit("spirit_collapse_start", { duration = collapseDur })
    return true
end

------------------------------------------------------------
-- 每帧更新
------------------------------------------------------------
---@param dt number
---@param phase string Timer阶段 "explore"/"warning"/"danger"/"collapse"
---@param inMiasma boolean 玩家是否在瘴气地格
---@param miasmaImmune boolean 瘴气是否免疫
---@param miasmaHalf boolean 瘴气是否减半
function CombatSystem.update(dt, phase, inMiasma, miasmaImmune, miasmaHalf)
    -- 受击闪红倒计时
    if CombatSystem.hitFlashTimer > 0 then
        CombatSystem.hitFlashTimer = CombatSystem.hitFlashTimer - dt
    end
    -- 瘴气墨染倒计时
    if CombatSystem.miasmaDmgFlash > 0 then
        CombatSystem.miasmaDmgFlash = CombatSystem.miasmaDmgFlash - dt
    end

    -- Debuff 倒计时
    for id, deb in pairs(CombatSystem.debuffs) do
        deb.timer = deb.timer - dt
        if deb.timer <= 0 then
            CombatSystem.debuffs[id] = nil
        end
    end

    -- 瘴气伤害
    if inMiasma and not miasmaImmune and not CombatSystem.collapsed then
        local interval = CombatSystem.MIASMA_INTERVAL[phase] or 4.0
        -- 贪渊初学：瘴气频率降低30%
        if miasmaHalf then
            interval = interval * 1.3
        end
        CombatSystem.miasmaTimer = CombatSystem.miasmaTimer + dt
        if CombatSystem.miasmaTimer >= interval then
            CombatSystem.miasmaTimer = CombatSystem.miasmaTimer - interval
            CombatSystem.takeDamage(1, "miasma")
        end
    else
        CombatSystem.miasmaTimer = 0
    end

    -- 溃散倒计时
    if CombatSystem.collapsed then
        CombatSystem.collapseTimer = CombatSystem.collapseTimer - dt
        if CombatSystem.collapseTimer <= 0 and not CombatSystem.collapseHandled then
            CombatSystem.collapseHandled = true
            EventBus.emit("spirit_collapse_end")
        end
    end
end

------------------------------------------------------------
-- 移速乘数（综合所有debuff）
------------------------------------------------------------
function CombatSystem.getSpeedMultiplier()
    local mul = 1.0
    if CombatSystem.collapsed then
        mul = mul * CombatSystem.COLLAPSE_SPEED_MUL
    end
    for id, deb in pairs(CombatSystem.debuffs) do
        local def = CombatSystem.DEBUFF_DEFS[id]
        if def and def.speedMul then
            mul = mul * def.speedMul
        end
    end
    return mul
end

------------------------------------------------------------
-- 视野乘数（溃散+墨迹debuff）
------------------------------------------------------------
function CombatSystem.getVisionMultiplier()
    local mul = 1.0
    local ink = CombatSystem.debuffs["ink"]
    if ink then
        local stacks = ink.stacks or 1
        mul = mul * (1.0 - 0.5 * stacks / 2)  -- 每层-25%视野
    end
    return mul
end

------------------------------------------------------------
-- Debuff 操作
------------------------------------------------------------
function CombatSystem.applyDebuff(debuffId, duration, extra)
    local def = CombatSystem.DEBUFF_DEFS[debuffId]
    if not def then return end
    local dur = duration or def.maxDuration

    local existing = CombatSystem.debuffs[debuffId]
    if existing then
        -- 叠层逻辑
        if def.maxStacks and (existing.stacks or 1) < def.maxStacks then
            existing.stacks = (existing.stacks or 1) + 1
            existing.timer = dur  -- 刷新时间
        else
            existing.timer = math.max(existing.timer, dur)  -- 刷新不叠层
        end
    else
        CombatSystem.debuffs[debuffId] = { timer = dur, stacks = 1 }
        if extra then
            for k, v in pairs(extra) do
                CombatSystem.debuffs[debuffId][k] = v
            end
        end
    end
end

function CombatSystem.clearDebuff(debuffId)
    CombatSystem.debuffs[debuffId] = nil
end

function CombatSystem.clearAllDebuffs()
    CombatSystem.debuffs = {}
end

function CombatSystem.hasDebuff(debuffId)
    return CombatSystem.debuffs[debuffId] ~= nil
end

------------------------------------------------------------
-- 异兽HP操作
------------------------------------------------------------
--- 初始化异兽HP（在createBeast中调用）
function CombatSystem.initBeastHP(beast)
    local maxHP = beast.baseHP or CombatSystem.BEAST_HP[beast.quality] or 4
    beast.combatHP = maxHP
    beast.combatMaxHP = maxHP
    beast.weakened = false
    beast.weakenTimer = 0
end

--- 对异兽造成伤害
---@return boolean isWeakened 是否刚进入虚弱
function CombatSystem.damageBeast(beast, amount)
    if not beast.combatHP then CombatSystem.initBeastHP(beast) end
    if beast.weakened then return false end

    beast.combatHP = math.max(0, beast.combatHP - amount)
    if beast.combatHP <= 0 then
        beast.weakened = true
        beast.weakenTimer = CombatSystem.BEAST_WEAK_DURATION
        EventBus.emit("beast_weakened", { beast = beast })
        return true
    end
    return false
end

--- 更新异兽虚弱计时
function CombatSystem.updateBeastWeaken(beast, dt)
    if beast.weakened then
        beast.weakenTimer = (beast.weakenTimer or 0) - dt
        if beast.weakenTimer <= 0 then
            beast.weakened = false
            beast.combatHP = beast.combatMaxHP or 4
            beast.weakenTimer = 0
        end
    end
end

--- 虚弱状态下封灵加成
function CombatSystem.getBeastSealBonus(beast)
    if beast.weakened then return 0.15 end
    return 0
end

return CombatSystem
