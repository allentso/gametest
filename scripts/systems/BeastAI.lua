--- 异兽 AI 状态机 + 朝向系统 + 个性行为 — v3.0
--- 白泽凝视、应龙高速冲刺、梼杌/穷奇CC免疫
local CollisionSystem = require("systems.CollisionSystem")
local Config = require("Config")
local EventBus = require("systems.EventBus")
local CombatSystem = require("systems.CombatSystem")

local BeastAI = {}

BeastAI.STATE = {
    IDLE       = "idle",
    WANDER     = "wander",
    ALERT      = "alert",
    FLEE       = "flee",
    HIDDEN     = "hidden",
    SUPPRESS   = "suppress",
    CAPTURED   = "captured",
    PANIC      = "panic",
    GAZE       = "gaze",
    BURST      = "burst",
    BURST_STOP = "burst_stop",
    -- 战斗新状态
    WARN       = "warn",
    CHASE      = "chase",
    ATTACK     = "attack",
}

-- 品质额外感知加成（叠加到异兽自身 senseRange 上）
BeastAI.QUALITY_SENSE_BONUS = { R = 0, SR = 1, SSR = 2 }

-- 警告事件冷却（秒）：同一异兽在此间隔内只发射一次 beast_warn
local WARN_COOLDOWN = 3.0

--- 带冷却的警告事件发射
local function emitWarnThrottled(beast)
    local now = os.clock()
    if (beast.lastWarnEmitTime or 0) + WARN_COOLDOWN > now then return end
    beast.lastWarnEmitTime = now
    EventBus.emit("beast_warn", { beast = beast })
end

------------------------------------------------------------
-- 获取实际战斗类型（考虑品质变体）
------------------------------------------------------------
function BeastAI.getCombatType(beast)
    if beast.combatTypeSsr and beast.quality == "SSR" then
        return beast.combatTypeSsr
    end
    return beast.combatType or "passive"
end

------------------------------------------------------------
-- 攻击定义表（v3.0 · 24只异兽）
-- 每个攻击: { name, damage, range, warmup, cooldown, effect, qualityMin }
------------------------------------------------------------
BeastAI.ATTACK_DEFS = {
    -- SSR · 六灵
    ["001"] = { -- 烛龙 (territorial)
        { name = "昼夜之瞳",   damage = 2, range = 4.0, warmup = 1.0, cooldown = 6.0,
          aoeType = "circle", aoeRadius = 4.0,
          effect = { visionShrink = 1.0, duration = 4.0 }, backstabAfter = 2.0 },
        { name = "烛火之息",   damage = 1, range = 3.0, warmup = 0.5, cooldown = 4.0,
          aoeType = "line", effect = { debuff = "burn", duration = 2.0 } },
    },
    ["002"] = { -- 应龙 (aggressive)
        { name = "风压横扫",   damage = 2, range = 3.0, warmup = 0.5, cooldown = 5.0,
          arc = 120, effect = { knockback = 2.0 } },
        { name = "雷霆怒吼",   damage = 3, range = 99, warmup = 0, cooldown = 0,
          trigger = "chaseTime", triggerVal = 8,
          aoeType = "circle", aoeRadius = 3.0, backstabAfter = 2.0 },
    },
    ["003"] = { -- 凤凰 (passive, rarely attacks)
        { name = "涅槃焰翼",   damage = 1, range = 2.0, warmup = 0.3, cooldown = 8.0,
          aoeType = "circle", aoeRadius = 2.0,
          effect = { knockback = 1.5 } },
    },
    ["004"] = { -- 白泽 (passive, gaze)
        { name = "知物之光",   damage = 0, range = 3.0, warmup = 0, cooldown = 10.0,
          effect = { debuff = "reveal", duration = 5.0 } },
    },
    ["005"] = { -- 白虎 (aggressive)
        { name = "肃杀扑击",   damage = 2, range = 2.0, warmup = 0.4, cooldown = 4.0,
          arc = 90, effect = { knockback = 1.0 } },
        { name = "金爪压制",   damage = 3, range = 1.0, warmup = 0.8, cooldown = 6.0,
          backstabAfter = 1.5 },
        { name = "虎啸",       damage = 1, range = 99, warmup = 0, cooldown = 0,
          trigger = "chaseTime", triggerVal = 6,
          aoeType = "circle", aoeRadius = 3.0 },
    },
    ["006"] = { -- 麒麟 (passive, minimal attack)
        { name = "祥瑞护体",   damage = 0, range = 2.0, warmup = 0.3, cooldown = 12.0,
          aoeType = "circle", aoeRadius = 2.0,
          effect = { knockback = 2.0 } },
    },
    -- SR · 十异
    ["007"] = { -- 饕餮 (aggressive)
        { name = "虎齿啃咬",   damage = 2, range = 1.5, warmup = 0.3, cooldown = 3.5, arc = 60 },
        { name = "无尽贪食",   damage = 3, range = 1.0, warmup = 0, cooldown = 0,
          trigger = "chaseTime", triggerVal = 10, backstabAfter = 1.5 },
    },
    ["008"] = { -- 穷奇 (aggressive)
        { name = "猬毛冲撞",   damage = 2, range = 2.5, warmup = 0.5, cooldown = 4.0,
          aoeType = "line", effect = { knockback = 1.5 } },
        { name = "嗥狗乱吠",   damage = 1, range = 99, warmup = 0, cooldown = 0,
          trigger = "chaseTime", triggerVal = 8,
          aoeType = "circle", aoeRadius = 3.0 },
    },
    ["009"] = { -- 梼杌 (territorial)
        { name = "蛮力挥爪",   damage = 2, range = 2.0, warmup = 0.8, cooldown = 5.0,
          arc = 120, backstabAfter = 1.0 },
        { name = "狂暴冲撞",   damage = 2, range = 3.0, warmup = 1.2, cooldown = 7.0,
          aoeType = "line", backstabAfter = 1.5 },
    },
    ["010"] = { -- 混沌 (passive)
        { name = "歌舞旋风",   damage = 1, range = 2.0, warmup = 0.5, cooldown = 8.0,
          aoeType = "circle", aoeRadius = 2.0,
          effect = { knockback = 1.0 } },
    },
    ["011"] = { -- 九婴 (aggressive)
        { name = "水火交侵",   damage = 2, range = 3.0, warmup = 0.5, cooldown = 4.0,
          aoeType = "line" },
        { name = "九首齐鸣",   damage = 1, range = 99, warmup = 0, cooldown = 0,
          trigger = "chaseTime", triggerVal = 8,
          aoeType = "circle", aoeRadius = 3.5, backstabAfter = 2.0 },
        { name = "头颈喷吐",   damage = 1, range = 2.0, warmup = 0, cooldown = 0,
          trigger = "onHit", effect = { debuff = "burn", duration = 1.5 } },
    },
    ["012"] = { -- 猰貐 (territorial)
        { name = "毒牙咬击",   damage = 2, range = 1.5, warmup = 0.5, cooldown = 4.0,
          effect = { debuff = "poison", duration = 3.0 } },
        { name = "死复之力",   damage = 1, range = 2.0, warmup = 0.3, cooldown = 6.0,
          backstabAfter = 1.0 },
    },
    ["013"] = { -- 毕方 (ambush)
        { name = "讹火灼足",   damage = 1, range = 1.5, warmup = 0.0, cooldown = 0,
          backstabAfter = 0.8 },
        { name = "火焰喷射",   damage = 2, range = 3.0, warmup = 0.5, cooldown = 5.0,
          aoeType = "line", effect = { debuff = "burn", duration = 2.0 } },
    },
    ["014"] = { -- 乘黄 (passive)
        { name = "角力冲刺",   damage = 1, range = 2.0, warmup = 0.3, cooldown = 6.0,
          effect = { knockback = 2.0 } },
    },
    ["015"] = { -- 文鳐鱼 (passive)
        { name = "鸾鸣音波",   damage = 1, range = 2.5, warmup = 0.5, cooldown = 6.0,
          aoeType = "circle", aoeRadius = 2.5 },
    },
    ["016"] = { -- 九尾狐 (ambush)
        { name = "魅惑之爪",   damage = 1, range = 1.5, warmup = 0.0, cooldown = 0,
          backstabAfter = 0.5, effect = { debuff = "charm", duration = 2.0 } },
        { name = "幻化脱身",   damage = 0, range = 99, warmup = 0, cooldown = 0,
          trigger = "chaseTime", triggerVal = 6 },
    },
    -- R · 八兆
    ["017"] = { -- 帝江 (passive)
        { name = "旋转冲撞",   damage = 1, range = 1.5, warmup = 0.3, cooldown = 6.0,
          effect = { knockback = 1.0 } },
    },
    ["018"] = { -- 当康 (passive)
        { name = "獠牙顶撞",   damage = 1, range = 1.0, warmup = 0.5, cooldown = 5.0 },
    },
    ["019"] = { -- 狸力 (territorial)
        { name = "鸡爪扒击",   damage = 1, range = 1.5, warmup = 0.5, cooldown = 4.0, arc = 90 },
    },
    ["020"] = { -- 旋龟 (territorial)
        { name = "蛇尾横扫",   damage = 1, range = 2.0, warmup = 0.6, cooldown = 5.0, arc = 120,
          backstabAfter = 0.8 },
    },
    ["021"] = { -- 并封 (territorial)
        { name = "双头夹击",   damage = 2, range = 1.5, warmup = 0.5, cooldown = 4.0 },
    },
    ["022"] = { -- 何罗鱼 (passive)
        { name = "十身缠绕",   damage = 1, range = 1.0, warmup = 0.3, cooldown = 5.0 },
    },
    ["023"] = { -- 化蛇 (ambush)
        { name = "叱呼突袭",   damage = 1, range = 1.5, warmup = 0.0, cooldown = 0,
          backstabAfter = 0.8, effect = { debuff = "daze", duration = 0.8 } },
    },
    ["024"] = { -- 蜚 (territorial)
        { name = "毒息喷吐",   damage = 1, range = 2.0, warmup = 0.5, cooldown = 4.0,
          aoeType = "line", effect = { debuff = "poison", duration = 3.0 } },
        { name = "蛇尾鞭击",   damage = 1, range = 1.5, warmup = 0.4, cooldown = 5.0 },
    },
}

-- 品质排序用于 qualityMin 判断
local QUALITY_RANK = { R = 1, SR = 2, SSR = 3 }

function BeastAI.meetsQuality(beast, qualityMin)
    if not qualityMin then return true end
    return (QUALITY_RANK[beast.quality] or 1) >= (QUALITY_RANK[qualityMin] or 1)
end

--- 获取异兽当前可用的主攻击（排除触发型，按品质过滤）
function BeastAI.getPrimaryAttack(beast)
    local defs = BeastAI.ATTACK_DEFS[beast.id]
    if not defs then return nil end
    for _, atk in ipairs(defs) do
        if BeastAI.meetsQuality(beast, atk.qualityMin) and not atk.trigger and atk.cooldown > 0 then
            return atk
        end
    end
    for _, atk in ipairs(defs) do
        if BeastAI.meetsQuality(beast, atk.qualityMin) then
            return atk
        end
    end
    return nil
end

--- 获取特定触发类型的攻击
function BeastAI.getTriggeredAttack(beast, triggerType)
    local defs = BeastAI.ATTACK_DEFS[beast.id]
    if not defs then return nil end
    for _, atk in ipairs(defs) do
        if atk.trigger == triggerType and BeastAI.meetsQuality(beast, atk.qualityMin) then
            return atk
        end
    end
    return nil
end

------------------------------------------------------------
-- Main update
------------------------------------------------------------
function BeastAI.update(beast, dt, playerX, playerY, map, options)
    options = options or {}
    local state = beast.aiState
    local playerInBamboo = options.playerInBamboo or false
    local playerMoving = options.playerMoving
    if playerMoving == nil then playerMoving = true end

    -- 背刺窗口倒计时
    if beast.backstabWindow and beast.backstabWindow > 0 then
        beast.backstabWindow = beast.backstabWindow - dt
        if beast.backstabWindow <= 0 then
            beast.backstabWindow = 0
        end
    end

    -- 减速效果倒计时
    if beast.slowTimer and beast.slowTimer > 0 then
        beast.slowTimer = beast.slowTimer - dt
        if beast.slowTimer <= 0 then
            beast.slowTimer = 0
            beast.slowMul = nil
        end
    end

    -- 白泽庇护光晕攻击力减弱倒计时
    if beast.atkReductionTimer and beast.atkReductionTimer > 0 then
        beast.atkReductionTimer = beast.atkReductionTimer - dt
        if beast.atkReductionTimer <= 0 then
            beast.atkReductionTimer = 0
            beast.atkReduction = nil
        end
    end

    -- 猰貐假死状态
    if beast.fakeDeath and beast.fakeDeathTimer then
        beast.fakeDeathTimer = beast.fakeDeathTimer - dt
        if beast.fakeDeathTimer <= 0 then
            beast.fakeDeath = false
            beast.fakeDeathTimer = nil
            beast.aiState = "idle"
            beast.idleDuration = 1
        end
    end

    -- 眩晕/冻结：跳过所有行动
    if state == "stunned" or state == "frozen" then
        return
    end

    -- 封印阵效果：检查是否在阵内
    local SkillSystem = require("systems.SkillSystem")
    local zoneEffect = SkillSystem.getZoneEffect(beast.x, beast.y)
    if zoneEffect then
        beast.inZone = true
        beast.zoneSpeedMul = zoneEffect.speedMul or 0.60
        beast.zonePerceptionReduce = zoneEffect.perceptionReduce or 2
    else
        beast.inZone = false
        beast.zoneSpeedMul = nil
        beast.zonePerceptionReduce = nil
    end

    if state == "idle" then
        beast.idleTimer = (beast.idleTimer or 0) + dt
        if beast.idleTimer > (beast.idleDuration or 3) then
            beast.aiState = "wander"
            beast.idleTimer = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        end

    elseif state == "wander" then
        local speed = beast.baseSpeed or 1.5
        if beast.slowMul and beast.slowTimer and beast.slowTimer > 0 then
            speed = speed * beast.slowMul
        end
        if beast.zoneSpeedMul then
            speed = speed * beast.zoneSpeedMul
        end
        local arrived = BeastAI.moveToward(beast, beast.wanderTarget, dt, speed, map)
        if arrived then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 3
        end

        local dist = BeastAI.distTo(beast, playerX, playerY)
        local senseRange = (beast.senseRange or 3) + (BeastAI.QUALITY_SENSE_BONUS[beast.quality] or 0)
        if playerInBamboo then senseRange = senseRange - 2 end
        if options.playerInDanger then senseRange = senseRange - 1 end
        if beast.zonePerceptionReduce then
            senseRange = senseRange - beast.zonePerceptionReduce
        end
        senseRange = math.max(1, senseRange)

        if dist < senseRange then
            local contactType = BeastAI.getContactType(beast, playerX, playerY)
            BeastAI.onSensed(beast, contactType, playerX, playerY, map)
        end

    elseif state == "alert" then
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        beast.alertTimer = (beast.alertTimer or 0) + dt
        local dist = BeastAI.distTo(beast, playerX, playerY)
        local cType = BeastAI.getCombatType(beast)

        if dist < 2 then
            if cType == "passive" then
                beast.aiState = "flee"
            elseif cType == "territorial" then
                beast.aiState = "warn"
                beast.warnTimer = 0
                emitWarnThrottled(beast)
            elseif cType == "aggressive" then
                beast.aiState = "chase"
                beast.chaseTimer = 0
                beast.chaseTriggered = false
                beast.attackCooldown = 1.0
            elseif cType == "ambush" then
                beast.aiState = "chase"
                beast.chaseTimer = 0
                beast.chaseTriggered = false
                beast.attackCooldown = 1.0
            end
        elseif beast.alertTimer > 5 then
            beast.aiState = "wander"
            beast.alertTimer = 0
        end

    elseif state == "flee" then
        local angle = math.atan2(beast.y - playerY, beast.x - playerX)
        beast.facing = angle
        local speed = beast.fleeSpeed or 3.5
        local dx = math.cos(angle) * speed * dt
        local dy = math.sin(angle) * speed * dt
        CollisionSystem.tryMove(beast, dx, dy, map)
        BeastAI.clampToMap(beast)
        if BeastAI.distTo(beast, playerX, playerY) > 8 then
            beast.aiState = "idle"
            beast.idleDuration = 2 + math.random() * 2
            beast.alertTimer = 0
        end

    elseif state == "gaze" then
        -- 白泽凝视
        if not beast.gazePhase then beast.gazePhase = "approach" end

        if beast.gazePhase == "approach" then
            local dist = BeastAI.distTo(beast, playerX, playerY)
            if dist > 3.0 then
                local target = {
                    x = playerX + (beast.x - playerX) / dist * 3.0,
                    y = playerY + (beast.y - playerY) / dist * 3.0,
                }
                BeastAI.moveToward(beast, target, dt, 1.0, map)
                beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
            else
                beast.gazePhase = "watching"
                beast.gazeWatchTimer = 0
            end
        elseif beast.gazePhase == "watching" then
            beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
            if playerMoving then
                beast.aiState = "flee"
                beast.gazePhase = nil
                beast.gazeWatchTimer = nil
            else
                beast.gazeWatchTimer = (beast.gazeWatchTimer or 0) + dt
                if beast.gazeWatchTimer >= 3.0 then
                    beast.guardLowered = true
                    beast.ambushBonus = true
                    beast.aiState = "idle"
                    beast.idleDuration = 8
                    beast.gazePhase = nil
                    beast.gazeWatchTimer = nil
                end
            end
        end

    elseif state == "burst" then
        -- 应龙/其他burst行为：高速冲刺3秒
        beast.burstTimer = (beast.burstTimer or 0) + dt
        if not beast.burstTarget then
            local angle = math.random() * math.pi * 2
            beast.burstTarget = {
                x = beast.x + math.cos(angle) * 8,
                y = beast.y + math.sin(angle) * 8,
            }
        end
        local speed = (beast.baseSpeed or 2.5) * 2
        BeastAI.moveToward(beast, beast.burstTarget, dt, speed, map)
        if beast.burstTimer >= 3.0 then
            beast.aiState = "burst_stop"
            beast.burstTimer = 0
            beast.burstTarget = nil
        end

    elseif state == "burst_stop" then
        beast.burstStopTimer = (beast.burstStopTimer or 0) + dt
        beast.burstWindow = true
        beast.backstabWindow = math.max(beast.backstabWindow or 0, 1.5 - beast.burstStopTimer)
        if beast.burstStopTimer >= 1.5 then
            beast.aiState = "chase"
            beast.burstStopTimer = 0
            beast.burstWindow = false
            beast.chaseTimer = 0
            beast.chaseTriggered = false
            beast.attackCooldown = 2.0
        end

    elseif state == "warn" then
        beast.warnTimer = (beast.warnTimer or 0) + dt
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)
        local tRadius = beast.territoryRadius or 5

        local tdx = playerX - (beast.territoryX or beast.x)
        local tdy = playerY - (beast.territoryY or beast.y)
        local tDist = math.sqrt(tdx * tdx + tdy * tdy)

        if tDist > tRadius then
            beast.aiState = "wander"
            beast.warnTimer = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        elseif beast.warnTimer >= 1.5 then
            beast.aiState = "attack"
            beast.warnTimer = 0
            beast.attackCooldown = 0
            beast.attackTimer = 0
            beast.attackState = nil
        end

    elseif state == "chase" then
        beast.chaseTimer = (beast.chaseTimer or 0) + dt
        beast.attackCooldown = (beast.attackCooldown or 0) - dt
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)

        local dist = BeastAI.distTo(beast, playerX, playerY)

        if dist > 12 then
            beast.aiState = "wander"
            beast.chaseTimer = 0
            beast.attackCooldown = 0
            beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
        else
            local speed = (beast.baseSpeed or 1.5) * 1.3
            if beast.slowMul and beast.slowTimer and beast.slowTimer > 0 then
                speed = speed * beast.slowMul
            end
            if beast.zoneSpeedMul then
                speed = speed * beast.zoneSpeedMul
            end
            local target = { x = playerX, y = playerY }
            BeastAI.moveToward(beast, target, dt, speed, map)

            local chaseAtk = BeastAI.getTriggeredAttack(beast, "chaseTime")
            if chaseAtk and beast.chaseTimer >= (chaseAtk.triggerVal or 99) and not beast.chaseTriggered then
                beast.chaseTriggered = true
                beast.aiState = "attack"
                beast.attackState = chaseAtk.name
                beast.attackTimer = chaseAtk.warmup or 0
                beast.currentAttack = chaseAtk
            elseif dist <= 1.0 then
                local chanceAtk = BeastAI.getTriggeredAttack(beast, "chance")
                if chanceAtk and math.random() < (chanceAtk.triggerVal or 0) and beast.attackCooldown <= 0 then
                    beast.aiState = "attack"
                    beast.attackState = chanceAtk.name
                    beast.attackTimer = chanceAtk.warmup or 0
                    beast.currentAttack = chanceAtk
                    beast.attackCooldown = 3.0
                end
            end

            if beast.aiState == "chase" and beast.attackCooldown <= 0 then
                local primaryAtk = BeastAI.getPrimaryAttack(beast)
                if primaryAtk and dist <= (primaryAtk.range or 2.0) then
                    beast.aiState = "attack"
                    beast.attackState = primaryAtk.name
                    beast.attackTimer = primaryAtk.warmup or 0
                    beast.currentAttack = primaryAtk
                end
            end
        end

    elseif state == "attack" then
        beast.attackTimer = (beast.attackTimer or 0) - dt
        beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)

        if beast.attackTimer <= 0 then
            local atk = beast.currentAttack or BeastAI.getPrimaryAttack(beast)
            if atk then
                local dist = BeastAI.distTo(beast, playerX, playerY)
                local hit = false

                if atk.aoeType == "circle" then
                    hit = dist <= (atk.aoeRadius or 2.0)
                elseif atk.arc then
                    if dist <= (atk.range or 2.5) then
                        local toPlayer = math.atan2(playerY - beast.y, playerX - beast.x)
                        local diff = toPlayer - (beast.facing or 0)
                        while diff > math.pi do diff = diff - math.pi * 2 end
                        while diff < -math.pi do diff = diff + math.pi * 2 end
                        hit = math.abs(diff) <= math.rad(atk.arc / 2)
                    end
                else
                    hit = dist <= (atk.range or 2.0)
                end

                if hit and atk.damage > 0 then
                    local finalDmg = atk.damage
                    if beast.atkReduction and beast.atkReductionTimer and beast.atkReductionTimer > 0 then
                        finalDmg = math.max(1, math.floor(finalDmg * (1 - beast.atkReduction)))
                    end
                    CombatSystem.takeDamage(finalDmg, "beast")
                    EventBus.emit("beast_attack_hit", {
                        beast = beast, attack = atk.name, damage = atk.damage,
                    })
                    local onHitAtk = BeastAI.getTriggeredAttack(beast, "onHit")
                    if onHitAtk then
                        if onHitAtk.damage > 0 then
                            CombatSystem.takeDamage(onHitAtk.damage, "beast")
                        end
                        if onHitAtk.effect and onHitAtk.effect.debuff then
                            CombatSystem.applyDebuff(onHitAtk.effect.debuff, onHitAtk.effect.duration)
                        end
                    end
                end

                if hit and atk.effect then
                    if atk.effect.debuff then
                        CombatSystem.applyDebuff(atk.effect.debuff, atk.effect.duration)
                    end
                    if atk.effect.knockback then
                        EventBus.emit("player_knockback", {
                            fromX = beast.x, fromY = beast.y, dist = atk.effect.knockback,
                        })
                    end
                    if atk.effect.visionShrink then
                        EventBus.emit("vision_shrink", {
                            radius = atk.effect.visionShrink, duration = atk.effect.duration,
                        })
                    end
                end

                if atk.backstabAfter and atk.backstabAfter > 0 then
                    beast.backstabWindow = atk.backstabAfter
                end

                local cd = atk.cooldown or 4.0
                if cd <= 0 then cd = 4.0 end
                beast.attackCooldown = cd
            end

            local cType = BeastAI.getCombatType(beast)
            if cType == "territorial" then
                beast.aiState = "wander"
                beast.wanderTarget = { x = beast.territoryX or beast.x, y = beast.territoryY or beast.y }
            elseif cType == "aggressive" or cType == "ambush" then
                beast.aiState = "chase"
            else
                beast.aiState = "wander"
                beast.wanderTarget = BeastAI.randomNearby(beast, map, 3)
            end
            beast.attackState = nil
            beast.currentAttack = nil
            beast.attackTimer = 0
        end

    elseif state == "panic" then
        if not beast.panicTarget then
            beast.panicTarget = BeastAI.randomNearby(beast, map, 6)
        end
        local arrived = BeastAI.moveToward(beast, beast.panicTarget, dt, 3.5, map)
        if arrived then
            beast.panicTarget = BeastAI.randomNearby(beast, map, 6)
        end

    elseif state == "hidden" then
        -- 等待追踪系统触发
    elseif state == "suppress" or state == "captured" then
        -- 不做任何事
    end
end

------------------------------------------------------------
-- 感知后的反应（基于战斗行为类型 + 个性化）
------------------------------------------------------------
function BeastAI.onSensed(beast, contactType, playerX, playerY, map)
    local beastId = beast.id
    local cType = BeastAI.getCombatType(beast)

    beast.facing = math.atan2(playerY - beast.y, playerX - beast.x)

    -- 白泽：特殊凝视（被动型但有独特机制）
    if beastId == "004" then
        if contactType == "front" or contactType == "side" then
            beast.aiState = "gaze"
            beast.gazePhase = "approach"
        end
        return
    end

    -- 应龙：感知后先burst（高速冲刺）再追击
    if beastId == "002" then
        if contactType == "front" then
            beast.aiState = "burst"
            beast.burstTimer = 0
            beast.burstTarget = nil
            beast.facing = math.atan2(beast.y - playerY, beast.x - playerX)
        elseif contactType == "side" then
            beast.aiState = "burst"
            beast.burstTimer = 0
            beast.burstTarget = nil
        else
            beast.aiState = "alert"
        end
        return
    end

    -- 根据战斗行为类型分发
    if cType == "passive" then
        if contactType == "front" or contactType == "side" then
            beast.aiState = "alert"
        end

    elseif cType == "territorial" then
        if beast.inZone then
            -- 封印阵内不攻击
        elseif contactType == "front" then
            beast.aiState = "warn"
            beast.warnTimer = 0
            emitWarnThrottled(beast)
        elseif contactType == "side" then
            beast.aiState = "alert"
        end

    elseif cType == "aggressive" then
        if contactType == "front" or contactType == "side" then
            beast.aiState = "chase"
            beast.chaseTimer = 0
            beast.chaseTriggered = false
            beast.attackCooldown = 1.5
        elseif contactType == "back" and beast.quality == "SSR" then
            beast.aiState = "chase"
            beast.chaseTimer = 0
            beast.chaseTriggered = false
            beast.attackCooldown = 2.0
        end

    elseif cType == "ambush" then
        local dist = BeastAI.distTo(beast, playerX, playerY)
        local ambushR = beast.ambushRange or 1.5
        local SchoolEffects = require("systems.SchoolEffects")
        local sEffect = SchoolEffects.get()
        local pTile = map and map:getTile(math.floor(playerX), math.floor(playerY))
        local pInBamboo = pTile and pTile.type == "bamboo"
        if sEffect and sEffect.ambushRadiusOverride and pInBamboo then
            ambushR = sEffect.ambushRadiusOverride
        end
        if dist <= ambushR then
            beast.invisible = false
            beast.aiState = "attack"
            beast.attackTimer = 0
            local ambushAtk = BeastAI.getPrimaryAttack(beast)
            beast.currentAttack = ambushAtk
            beast.attackState = ambushAtk and ambushAtk.name or nil
            EventBus.emit("beast_ambush", { beast = beast })
        else
            beast.aiState = "alert"
        end
    end
end

------------------------------------------------------------
-- 猰貐假死（HP归零后触发）
------------------------------------------------------------
function BeastAI.triggerFakeDeath(beast)
    if beast.id ~= "012" then return false end
    if beast.hasRevived then return false end
    beast.fakeDeath = true
    beast.fakeDeathTimer = 3.0
    beast.hasRevived = true
    beast.aiState = "idle"
    return true
end

------------------------------------------------------------
-- 白泽庇护光晕（白泽凝视期间玩家被攻击时触发）
------------------------------------------------------------
function BeastAI.triggerBaizeProtection(beast, allBeasts, playerX, playerY)
    if beast.id ~= "004" then return false end
    if beast.aiState ~= "gaze" then return false end

    for _, other in ipairs(allBeasts) do
        if other ~= beast and other.aiState ~= "captured" then
            local dx = other.x - beast.x
            local dy = other.y - beast.y
            if dx * dx + dy * dy <= 4 then
                other.atkReduction = 0.50
                other.atkReductionTimer = 3.0
            end
        end
    end

    beast.aiState = "flee"
    beast.gazePhase = nil
    beast.gazeWatchTimer = nil

    EventBus.emit("baize_protection", { beast = beast })
    return true
end

------------------------------------------------------------
-- 强制所有异兽进入panic状态
------------------------------------------------------------
function BeastAI.panicAll(beasts)
    for _, beast in ipairs(beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "suppress"
           and beast.aiState ~= "hidden" then
            beast.aiState = "panic"
            beast.panicTarget = nil
        end
    end
end

------------------------------------------------------------
-- 移动 / 工具函数
------------------------------------------------------------
function BeastAI.moveToward(beast, target, dt, speed, map)
    if not target then return true end
    local dx = target.x - beast.x
    local dy = target.y - beast.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.1 then return true end
    beast.facing = math.atan2(dy, dx)
    local step = math.min(speed * dt, dist)
    local mx = (dx / dist) * step
    local my = (dy / dist) * step
    if map then
        CollisionSystem.tryMove(beast, mx, my, map)
    else
        beast.x = beast.x + mx
        beast.y = beast.y + my
    end
    BeastAI.clampToMap(beast)
    return false
end

function BeastAI.clampToMap(beast)
    local mapW = Config.MAP_WIDTH or 20
    local mapH = Config.MAP_HEIGHT or 30
    beast.x = math.max(1.5, math.min(mapW - 2.5, beast.x))
    beast.y = math.max(1.5, math.min(mapH - 2.5, beast.y))
end

function BeastAI.distTo(beast, px, py)
    local dx = beast.x - px
    local dy = beast.y - py
    return math.sqrt(dx * dx + dy * dy)
end

function BeastAI.randomNearby(beast, map, radius)
    local mapW = Config.MAP_WIDTH or 20
    local mapH = Config.MAP_HEIGHT or 30
    for attempt = 1, 10 do
        local tx = beast.x + (math.random() - 0.5) * radius * 2
        local ty = beast.y + (math.random() - 0.5) * radius * 2
        tx = math.max(2, math.min(mapW - 3, tx))
        ty = math.max(2, math.min(mapH - 3, ty))
        if not map:isBlocked(math.floor(tx), math.floor(ty)) then
            return { x = tx, y = ty }
        end
    end
    return { x = beast.x, y = beast.y }
end

function BeastAI.getContactType(beast, playerX, playerY)
    local toPlayerAngle = math.atan2(playerY - beast.y, playerX - beast.x)
    local diff = toPlayerAngle - (beast.facing or 0)
    while diff > math.pi do diff = diff - math.pi * 2 end
    while diff < -math.pi do diff = diff + math.pi * 2 end
    local absDiff = math.abs(diff)
    if absDiff > math.pi * 2 / 3 then return "back"
    elseif absDiff > math.pi / 3 then return "side"
    else return "front" end
end

------------------------------------------------------------
-- 水面判定工具（可供多系统复用）
------------------------------------------------------------
function BeastAI.isNearWater(beast, map)
    if not map or not map.getTile then return false end
    for dy = -3, 3 do
        for dx = -3, 3 do
            if dx * dx + dy * dy <= 9 then
                local tile = map:getTile(math.floor(beast.x) + dx, math.floor(beast.y) + dy)
                if tile and tile.type == "water" then
                    return true
                end
            end
        end
    end
    return false
end

------------------------------------------------------------
-- 创建异兽实体（v3.0: quality从BeastData固定）
------------------------------------------------------------
function BeastAI.createBeast(beastData, x, y, quality)
    local q = beastData.quality or quality or "R"
    local beast = {
        id = beastData.id,
        type = beastData.id,
        name = beastData.name,
        element = beastData.element,
        quality = q,
        x = x, y = y,
        halfW = (beastData.bodySize or 0.4) * 0.8,
        halfH = (beastData.bodySize or 0.4) * 0.8,
        facing = math.random() * math.pi * 2,
        aiState = (q == "R") and "wander" or "hidden",
        idleTimer = 0,
        idleDuration = 2 + math.random() * 3,
        alertTimer = 0,
        wanderTarget = nil,
        ambushBonus = false,
        guardLowered = false,
        burstWindow = false,
        invisible = false,
        baseSpeed = beastData.baseSpeed or 1.5,
        fleeSpeed = beastData.fleeSpeed or 3.5,
        bodySize = beastData.bodySize or 0.4,
        senseRange = beastData.senseRange or 3,
        fleeChance = beastData.fleeChance or 0,
        baseHP = beastData.hp,
        -- 战斗行为字段
        combatType = beastData.combatType or "passive",
        combatTypeSsr = beastData.combatTypeSsr,
        territoryRadius = beastData.territoryRadius or 5,
        ambushRange = beastData.ambushRange or 1.5,
        -- 领地原点
        territoryX = x,
        territoryY = y,
        -- 战斗状态
        warnTimer = 0,
        chaseTimer = 0,
        attackCooldown = 0,
        attackState = nil,
        attackTimer = 0,
        backstabWindow = 0,
        -- v3.0 特殊标记
        skillImmune = beastData.skillImmune or false,
        ccImmune = beastData.ccImmune or false,
        revivable = beastData.revivable or false,
        flying = beastData.flying or false,
        dualHead = beastData.dualHead or false,
        poisonTrail = beastData.poisonTrail or false,
    }
    CombatSystem.initBeastHP(beast)
    return beast
end

return BeastAI
