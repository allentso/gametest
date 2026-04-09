--- 流派战斗/探索效果查询模块（共享）
local SessionState = require("systems.SessionState")
local GameState = require("systems.GameState")

local SchoolEffects = {}

------------------------------------------------------------
-- 流派层级效果定义（3层：初学/精通/大成）
-- 每层包含探索加成 + 战斗加成
------------------------------------------------------------
SchoolEffects.EFFECTS = {
    trace = {
        { name = "初学·追迹", desc = "调查速度+15%，竹林伏击触发缩小",
            clueSpeedMul = 1.15, ambushRadiusOverride = 0.8 },
        { name = "精通·追迹", desc = "调查速度+25%，线索可见+1，投掷射程+2",
            clueSpeedMul = 1.25, clueVision = 1, throwRangeBonus = 2 },
        { name = "大成·追迹", desc = "调查速度+40%，SSR线索-1，追迹弹命中+15%封灵率",
            clueSpeedMul = 1.40, clueVision = 1, ssrReduce = 1, xuancaiBonus = 0.10, beastEyeDuration = 30,
            throwRangeBonus = 2, traceHitSealBonus = 0.15, traceHitSealDuration = 10 },
    },
    suppress = {
        { name = "初学·压制", desc = "QTE速度-10%，技能次数+1",
            qteSpeedMul = 0.90, skillUsesBonus = 1 },
        { name = "精通·压制", desc = "QTE速度-20%，目标区+10%，QTE免疫反击",
            qteSpeedMul = 0.80, qteZoneMul = 1.10, skillUsesBonus = 1, qteCounterImmune = true },
        { name = "大成·压制", desc = "QTE速度-30%，失败重试，爆炎符×2，法术封灵+20%",
            qteSpeedMul = 0.70, qteZoneMul = 1.10, qteRetry = 1, skillUsesBonus = 1,
            qteCounterImmune = true, baoyanDamageMul = 2, spellSealBonus = 0.20, spellSealDuration = 3 },
    },
    evac = {
        { name = "初学·撤离", desc = "撤离时间-0.5s，溃散虚弱延至12s",
            evacTimeSave = 0.5, weakenDurationOverride = 12 },
        { name = "精通·撤离", desc = "撤离-1s，灵契保护1只，恢复道具耗时减半",
            evacTimeSave = 1.0, contractProtect = 1, weakenDurationOverride = 12, recoveryCastMul = 0.5 },
        { name = "大成·撤离", desc = "撤离-1.5s，紧急逃脱仅损灵石，复苏符+2HP",
            evacTimeSave = 1.5, contractProtect = 1, safeEscape = true,
            weakenDurationOverride = 12, recoveryCastMul = 0.5, reviveHPBonus = 2 },
    },
    greed = {
        { name = "初学·贪渊", desc = "高危区资源+20%，瘴气频率-30%",
            dangerResMul = 1.20, dangerDrainHalf = true },
        { name = "精通·贪渊", desc = "资源+30%，瘴气频率-30%，虚弱封灵耗器-50%",
            dangerResMul = 1.30, dangerDrainHalf = true, weakSealSaverChance = 0.50 },
        { name = "大成·贪渊", desc = "资源+50%，瘴气免疫，高危区技能无限",
            dangerResMul = 1.50, dangerImmune = true, weakSealSaverChance = 0.50, dangerUnlimitedSkills = true },
    },
}

--- 获取当前流派层级 (0=无/1=初学/2=精通/3=大成)
function SchoolEffects.getTier()
    local school = SessionState.selectedSchool
    if not school then return 0 end
    local progress = GameState.data.schoolProgress[school] or 0
    local level = GameState.getSealerLevel()
    if progress >= 10 and level >= 5 then return 3
    elseif progress >= 5 and level >= 3 then return 2
    elseif progress >= 1 then return 1
    else return 0 end
end

--- 获取当前流派效果表（nil 表示无效果）
---@return table|nil
function SchoolEffects.get()
    local school = SessionState.selectedSchool
    if not school then return nil end
    local tier = SchoolEffects.getTier()
    if tier == 0 then return nil end
    local effects = SchoolEffects.EFFECTS[school]
    return effects and effects[tier] or nil
end

return SchoolEffects
