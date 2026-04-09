--- 背刺技能系统 (v2.1 §五)
--- 玩家探索前选择1种技能，探索中主动使用
local EventBus = require("systems.EventBus")
local CombatSystem = require("systems.CombatSystem")
local GameState = require("systems.GameState")
local SchoolEffects = require("systems.SchoolEffects")

local SkillSystem = {}

------------------------------------------------------------
-- 技能定义
------------------------------------------------------------

SkillSystem.SKILLS = {
    lingfudan = {
        id = "lingfudan",
        name = "灵符弹",
        category = "throw",   -- 投掷类
        maxUses = 3,
        range = 5,             -- 直线距离（格）
        desc = "眩晕异兽2秒",
        effect = {
            type = "stun",
            duration = 2.0,
        },
        backstab = {
            duration = 3.5,    -- 眩晕延长到3.5秒
            qteZoneBonus = 0.10,
        },
        vsAmbush = true,       -- 可揭示伏击型异兽
    },

    zhuijidan = {
        id = "zhuijidan",
        name = "追迹弹",
        category = "throw",
        maxUses = 4,
        range = 6,
        desc = "减速异兽70%持续6秒",
        effect = {
            type = "slow",
            speedMul = 0.30,   -- 剩余速度比例
            duration = 6.0,
        },
        backstab = {
            duration = 10.0,
            trackDust = true,  -- 加速调查
        },
        vsAggressive = true,   -- 让追击型放弃追击
    },

    baoyanfu = {
        id = "baoyanfu",
        name = "爆炎符",
        category = "throw",
        maxUses = 2,
        range = 5,
        explosionRadius = 1.5,
        desc = "范围内所有异兽-2HP",
        effect = {
            type = "explosion",
            damage = 2,
        },
        backstab = {
            explosionRadius = 2.5,
            captureBonus = 0.10,
        },
    },

    fengyinzhen = {
        id = "fengyinzhen",
        name = "封印阵",
        category = "spell",
        maxUses = 2,
        radius = 2,            -- 阵法半径
        duration = 10.0,       -- 持续时间
        desc = "范围减速40%+感知-2格",
        effect = {
            type = "zone",
            speedMul = 0.60,
            perceptionReduce = 2,
        },
        backstab = {
            autoQteFirst = true,  -- 阵内发起压制自动命中首次QTE
        },
        vsTerritorial = true,     -- 领地型不会进入攻击状态
    },

    dingshenzou = {
        id = "dingshenzou",
        name = "定身咒",
        category = "spell",
        maxUses = 3,
        range = 4,
        arc = 60,              -- 60度锥形
        desc = "定身首个命中异兽3秒",
        effect = {
            type = "freeze",
            duration = 3.0,
        },
        backstab = {
            duration = 5.0,
            autoBackstab = true,  -- 绕到背后自动触发背刺状态
        },
        canInterrupt = true,      -- 可打断蓄力（如饕餮无尽贪食）
    },

    qusanfa = {
        id = "qusanfa",
        name = "驱散法",
        category = "spell",
        maxUses = 4,
        radius = 2,             -- 以玩家为中心
        desc = "清除debuff/墨染/净化瘴气",
        effect = {
            type = "dispel",
            clearDebuffs = true,
            clearInk = true,
            purifyMiasma = true,
            miasmaDuration = 8.0,
        },
        backstab = {
            radius = 3.5,
            miasmaDuration = 20.0,
        },
    },
}

-- 技能ID有序列表（UI显示用）
SkillSystem.SKILL_ORDER = {
    "lingfudan", "zhuijidan", "baoyanfu",
    "fengyinzhen", "dingshenzou", "qusanfa",
}

------------------------------------------------------------
-- 解锁条件 (#10)
------------------------------------------------------------

--- 检查技能是否已解锁
--- @param skillId string
--- @return boolean, string|nil
function SkillSystem.isUnlocked(skillId)
    if skillId == "lingfudan" then
        return true, nil  -- 默认解锁
    elseif skillId == "zhuijidan" then
        -- 境界3（调灵者）
        local level = GameState.getSealerLevel()
        if level >= 3 then return true, nil end
        return false, "需达到境界3（调灵者）"
    elseif skillId == "baoyanfu" then
        -- 捕获应龙1次
        local entry = GameState.data.bestiary["002"]
        if entry and entry.captured and entry.count >= 1 then return true, nil end
        return false, "需捕获应龙1次"
    elseif skillId == "fengyinzhen" then
        -- 境界4（封灵师）
        local level = GameState.getSealerLevel()
        if level >= 4 then return true, nil end
        return false, "需达到境界4（封灵师）"
    elseif skillId == "dingshenzou" then
        -- 捕获任意SSR品质异兽1次
        for _, entry in pairs(GameState.data.bestiary) do
            if entry.qualities and (entry.qualities.SSR or 0) >= 1 then
                return true, nil
            end
        end
        return false, "需捕获任意SSR异兽1次"
    elseif skillId == "qusanfa" then
        -- 被异兽攻击后成功撤退3次
        local count = GameState.data.moyaRetreatCount or 0
        if count >= 3 then return true, nil end
        return false, "需被异兽攻击后成功撤退" .. (3 - count) .. "次"
    end
    return false, "未知技能"
end

--- 获取所有已解锁技能列表
function SkillSystem.getUnlockedSkills()
    local result = {}
    for _, skillId in ipairs(SkillSystem.SKILL_ORDER) do
        local unlocked = SkillSystem.isUnlocked(skillId)
        if unlocked then
            table.insert(result, SkillSystem.SKILLS[skillId])
        end
    end
    return result
end

------------------------------------------------------------
-- 局内状态
------------------------------------------------------------

-- 当前选中的技能ID
SkillSystem.activeSkill = nil
-- 剩余使用次数
SkillSystem.usesLeft = 0
-- 放置的封印阵列表 { {x, y, timer, radius, effect} }
SkillSystem.zones = {}
-- 技能冷却计时（防止连续按）
SkillSystem.cooldownTimer = 0

--- 初始化单局技能状态（在PrepareScreen选择后调用）
function SkillSystem.initSession(skillId)
    local skill = SkillSystem.SKILLS[skillId]
    if not skill then
        SkillSystem.activeSkill = nil
        SkillSystem.usesLeft = 0
        SkillSystem.zones = {}
        SkillSystem.cooldownTimer = 0
        return
    end
    SkillSystem.activeSkill = skillId
    SkillSystem.usesLeft = skill.maxUses

    -- 流派加成：压制流技能次数+1
    local effect = SchoolEffects.get()
    if effect and effect.skillUsesBonus then
        SkillSystem.usesLeft = SkillSystem.usesLeft + effect.skillUsesBonus
    end

    SkillSystem.zones = {}
    SkillSystem.cooldownTimer = 0
end

--- 每帧更新（封印阵倒计时、冷却）
function SkillSystem.update(dt)
    -- 冷却
    if SkillSystem.cooldownTimer > 0 then
        SkillSystem.cooldownTimer = SkillSystem.cooldownTimer - dt
    end

    -- 封印阵倒计时
    for i = #SkillSystem.zones, 1, -1 do
        local zone = SkillSystem.zones[i]
        zone.timer = zone.timer - dt
        if zone.timer <= 0 then
            table.remove(SkillSystem.zones, i)
        end
    end
end

------------------------------------------------------------
-- 技能使用
------------------------------------------------------------

--- 判断背刺角度（玩家在异兽背后）
--- @param playerX number
--- @param playerY number
--- @param beast table 异兽（需要x,y,facing字段）
--- @return boolean
function SkillSystem.isBackstab(playerX, playerY, beast)
    if not beast.facing then return false end
    -- 异兽面朝方向 vs 玩家相对异兽方向
    local dx = playerX - beast.x
    local dy = playerY - beast.y
    local angleToPlayer = math.atan2(dy, dx)
    local facingAngle = beast.facing
    -- 背刺角度：玩家在异兽面朝方向的反面±60度范围
    local diff = math.abs(angleToPlayer - facingAngle)
    if diff > math.pi then diff = 2 * math.pi - diff end
    return diff > math.rad(120)  -- 面朝反方向±60° = >120°
end

--- 查找范围内的异兽
--- @param beasts table 异兽列表
--- @param centerX number
--- @param centerY number
--- @param radius number
--- @param playerFacing number|nil 玩家朝向（锥形技能用）
--- @param arc number|nil 锥形角度
--- @return table 命中的异兽列表
local function findBeastsInRange(beasts, centerX, centerY, radius, playerFacing, arc)
    local hits = {}
    for _, beast in ipairs(beasts) do
        if beast.aiState ~= "captured" then
            local dist = math.sqrt((beast.x - centerX)^2 + (beast.y - centerY)^2)
            if dist <= radius then
                if arc and playerFacing then
                    -- 锥形判定
                    local angleToB = math.atan2(beast.y - centerY, beast.x - centerX)
                    local diff = math.abs(angleToB - playerFacing)
                    if diff > math.pi then diff = 2 * math.pi - diff end
                    if diff <= math.rad(arc / 2) then
                        table.insert(hits, beast)
                    end
                else
                    table.insert(hits, beast)
                end
            end
        end
    end
    return hits
end

--- 使用当前技能
--- @param playerX number
--- @param playerY number
--- @param playerFacing number 玩家朝向（弧度）
--- @param beasts table 场上异兽列表
--- @param inDangerZone boolean 玩家是否处于瘴气区
--- @return boolean 是否成功使用
function SkillSystem.useSkill(playerX, playerY, playerFacing, beasts, inDangerZone)
    if not SkillSystem.activeSkill then return false end
    if SkillSystem.usesLeft <= 0 then
        EventBus.emit("skill_fail", { reason = "uses_depleted" })
        return false
    end
    if SkillSystem.cooldownTimer > 0 then
        EventBus.emit("skill_fail", { reason = "cooldown" })
        return false
    end
    if CombatSystem.collapsed then
        EventBus.emit("skill_fail", { reason = "collapsed" })
        return false
    end

    local skill = SkillSystem.SKILLS[SkillSystem.activeSkill]
    if not skill then return false end

    -- 流派战斗加成
    local effect = SchoolEffects.get()

    -- 贪渊流大成：仅在瘴气区内不消耗次数
    local consumed = true
    if effect and effect.dangerUnlimitedSkills and inDangerZone then
        consumed = false
    end

    -- 追迹流精通+：投掷类射程+2格（临时修改）
    local rangeBonus = 0
    if effect and effect.throwRangeBonus and skill.category == "throw" then
        rangeBonus = effect.throwRangeBonus
        skill = setmetatable({ range = skill.range + rangeBonus }, { __index = skill })
    end

    local success = false

    if skill.id == "lingfudan" then
        success = SkillSystem._useLingfudan(skill, playerX, playerY, playerFacing, beasts)
    elseif skill.id == "zhuijidan" then
        success = SkillSystem._useZhuijidan(skill, playerX, playerY, playerFacing, beasts)
    elseif skill.id == "baoyanfu" then
        success = SkillSystem._useBaoyanfu(skill, playerX, playerY, playerFacing, beasts, effect)
    elseif skill.id == "fengyinzhen" then
        success = SkillSystem._useFengyinzhen(skill, playerX, playerY)
    elseif skill.id == "dingshenzou" then
        success = SkillSystem._useDingshenzou(skill, playerX, playerY, playerFacing, beasts)
    elseif skill.id == "qusanfa" then
        success = SkillSystem._useQusanfa(skill, playerX, playerY, beasts)
    end

    if success then
        if consumed then
            SkillSystem.usesLeft = SkillSystem.usesLeft - 1
        end
        SkillSystem.cooldownTimer = 0.5  -- 全局0.5秒冷却防连按
        EventBus.emit("skill_used", {
            skillId = skill.id,
            name = skill.name,
            usesLeft = SkillSystem.usesLeft,
        })
    end

    return success
end

------------------------------------------------------------
-- 各技能实现
------------------------------------------------------------

--- 灵符弹：眩晕
function SkillSystem._useLingfudan(skill, px, py, facing, beasts)
    local hits = findBeastsInRange(beasts, px, py, skill.range, facing, 90)
    if #hits == 0 then
        EventBus.emit("skill_fail", { reason = "no_target" })
        return false
    end
    -- 只命中最近的一只
    table.sort(hits, function(a, b)
        local da = (a.x - px)^2 + (a.y - py)^2
        local db = (b.x - px)^2 + (b.y - py)^2
        return da < db
    end)
    local target = hits[1]
    local isBack = SkillSystem.isBackstab(px, py, target)
    local duration = isBack and skill.backstab.duration or skill.effect.duration

    -- 应用眩晕
    EventBus.emit("beast_stunned", {
        beast = target,
        duration = duration,
        skillId = skill.id,
        isBackstab = isBack,
    })

    -- 对伏击型：揭示隐身
    if skill.vsAmbush and target.combatType == "ambush" then
        EventBus.emit("beast_revealed", { beast = target })
    end

    EventBus.emit("skill_hit", {
        skillId = skill.id, name = skill.name,
        target = target, isBackstab = isBack,
        effectDesc = "眩晕" .. string.format("%.1f", duration) .. "秒",
    })
    return true
end

--- 追迹弹：减速
function SkillSystem._useZhuijidan(skill, px, py, facing, beasts)
    local hits = findBeastsInRange(beasts, px, py, skill.range, facing, 90)
    if #hits == 0 then
        EventBus.emit("skill_fail", { reason = "no_target" })
        return false
    end
    table.sort(hits, function(a, b)
        local da = (a.x - px)^2 + (a.y - py)^2
        local db = (b.x - px)^2 + (b.y - py)^2
        return da < db
    end)
    local target = hits[1]
    local isBack = SkillSystem.isBackstab(px, py, target)
    local duration = isBack and skill.backstab.duration or skill.effect.duration

    EventBus.emit("beast_slowed", {
        beast = target,
        speedMul = skill.effect.speedMul,
        duration = duration,
        skillId = skill.id,
        isBackstab = isBack,
    })

    -- 对追击型：放弃追击
    if skill.vsAggressive and target.combatType == "aggressive" and target.aiState == "chase" then
        EventBus.emit("beast_abandon_chase", { beast = target })
    end

    EventBus.emit("skill_hit", {
        skillId = skill.id, name = skill.name,
        target = target, isBackstab = isBack,
        effectDesc = "减速" .. string.format("%.0f%%", (1 - skill.effect.speedMul) * 100) .. " " .. string.format("%.0f", duration) .. "秒",
    })
    return true
end

--- 爆炎符：范围伤害
function SkillSystem._useBaoyanfu(skill, px, py, facing, beasts, schoolEffect)
    -- 投掷到面朝方向最远点，或最近异兽位置
    local targetX, targetY = px + math.cos(facing) * skill.range, py + math.sin(facing) * skill.range

    -- 查找面前最近的异兽作为爆炸中心
    local nearHits = findBeastsInRange(beasts, px, py, skill.range, facing, 45)
    if #nearHits > 0 then
        table.sort(nearHits, function(a, b)
            local da = (a.x - px)^2 + (a.y - py)^2
            local db = (b.x - px)^2 + (b.y - py)^2
            return da < db
        end)
        targetX, targetY = nearHits[1].x, nearHits[1].y
    end

    local isBack = false  -- 爆炎符不判定单体背刺，用爆炸中心
    local radius = skill.explosionRadius
    -- 背刺增强：如果最近目标处于背刺位
    if #nearHits > 0 and SkillSystem.isBackstab(px, py, nearHits[1]) then
        isBack = true
        radius = skill.backstab.explosionRadius
    end

    local blastHits = findBeastsInRange(beasts, targetX, targetY, radius)
    local hitCount = 0
    -- 压制流大成：爆炎符伤害翻倍
    local dmg = skill.effect.damage
    if schoolEffect and schoolEffect.baoyanDamageMul then
        dmg = dmg * schoolEffect.baoyanDamageMul
    end
    for _, beast in ipairs(blastHits) do
        CombatSystem.damageBeast(beast, dmg)
        hitCount = hitCount + 1
        if isBack and skill.backstab.captureBonus then
            -- 标记捕获加成（临时）
            beast.captureBonus = (beast.captureBonus or 0) + skill.backstab.captureBonus
        end
    end

    EventBus.emit("skill_explosion", {
        x = targetX, y = targetY,
        radius = radius,
        hitCount = hitCount,
        isBackstab = isBack,
    })

    if hitCount == 0 then
        EventBus.emit("skill_hit", {
            skillId = skill.id, name = skill.name,
            isBackstab = isBack,
            effectDesc = "爆炸未命中",
        })
    else
        EventBus.emit("skill_hit", {
            skillId = skill.id, name = skill.name,
            isBackstab = isBack,
            effectDesc = "命中" .. hitCount .. "只异兽，各-2HP",
        })
    end
    return true  -- 爆炎符无论是否命中都消耗
end

--- 封印阵：放置持续区域
function SkillSystem._useFengyinzhen(skill, px, py)
    table.insert(SkillSystem.zones, {
        x = px,
        y = py,
        radius = skill.radius,
        timer = skill.duration,
        maxTime = skill.duration,
        effect = skill.effect,
        backstab = skill.backstab,
        skillId = skill.id,
    })

    EventBus.emit("skill_zone_placed", {
        skillId = skill.id, name = skill.name,
        x = px, y = py, radius = skill.radius,
        duration = skill.duration,
    })
    return true
end

--- 定身咒：锥形定身
function SkillSystem._useDingshenzou(skill, px, py, facing, beasts)
    local hits = findBeastsInRange(beasts, px, py, skill.range, facing, skill.arc)
    if #hits == 0 then
        EventBus.emit("skill_fail", { reason = "no_target" })
        return false
    end
    table.sort(hits, function(a, b)
        local da = (a.x - px)^2 + (a.y - py)^2
        local db = (b.x - px)^2 + (b.y - py)^2
        return da < db
    end)
    local target = hits[1]  -- 只定身第一只
    local isBack = SkillSystem.isBackstab(px, py, target)
    local duration = isBack and skill.backstab.duration or skill.effect.duration

    EventBus.emit("beast_frozen", {
        beast = target,
        duration = duration,
        skillId = skill.id,
        isBackstab = isBack,
        autoBackstab = isBack and skill.backstab.autoBackstab,
    })

    -- 打断蓄力
    if skill.canInterrupt and target.attackState == "warmup" then
        EventBus.emit("beast_interrupted", { beast = target })
    end

    EventBus.emit("skill_hit", {
        skillId = skill.id, name = skill.name,
        target = target, isBackstab = isBack,
        effectDesc = "定身" .. string.format("%.0f", duration) .. "秒",
    })
    return true
end

--- 驱散法：自身范围净化
function SkillSystem._useQusanfa(skill, px, py, beasts)
    local isBack = false
    -- 驱散法不需要背刺判定，但如果附近有异兽且背刺位则增强范围
    local nearBeasts = findBeastsInRange(beasts, px, py, 3)
    for _, b in ipairs(nearBeasts) do
        if SkillSystem.isBackstab(px, py, b) then
            isBack = true
            break
        end
    end

    local radius = isBack and skill.backstab.radius or skill.radius
    local miasmaDur = isBack and skill.backstab.miasmaDuration or skill.effect.miasmaDuration

    -- 清除玩家debuff
    EventBus.emit("player_debuffs_cleared", { radius = radius })

    -- 清除异兽墨染/地面debuff
    EventBus.emit("ink_cleared", { x = px, y = py, radius = radius })

    -- 净化瘴气
    EventBus.emit("miasma_purified", {
        x = px, y = py,
        radius = radius,
        duration = miasmaDur,
    })

    EventBus.emit("skill_hit", {
        skillId = skill.id, name = skill.name,
        isBackstab = isBack,
        effectDesc = "净化半径" .. string.format("%.1f", radius) .. "格",
    })
    return true
end

------------------------------------------------------------
-- 封印阵对异兽的影响（由BeastAI每帧调用）
------------------------------------------------------------

--- 检查异兽是否在任何封印阵范围内
--- @param beastX number
--- @param beastY number
--- @return table|nil 封印阵效果，nil表示不在
function SkillSystem.getZoneEffect(beastX, beastY)
    for _, zone in ipairs(SkillSystem.zones) do
        local dist = math.sqrt((beastX - zone.x)^2 + (beastY - zone.y)^2)
        if dist <= zone.radius then
            return zone.effect
        end
    end
    return nil
end

--- 检查坐标是否在封印阵内（用于封印阵+压制联动）
function SkillSystem.isInZone(x, y)
    for _, zone in ipairs(SkillSystem.zones) do
        local dist = math.sqrt((x - zone.x)^2 + (y - zone.y)^2)
        if dist <= zone.radius then
            return true, zone
        end
    end
    return false
end

return SkillSystem
