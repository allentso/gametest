--- 撤离系统 - 站定3秒 + 灵契稳定QTE
local EventBus = require("systems.EventBus")

local EvacuationSystem = {}

EvacuationSystem.fixedPoints = {}
EvacuationSystem.evacuating = false
EvacuationSystem.evacuateTimer = 0
EvacuationSystem.evacuateDuration = 3
EvacuationSystem.currentPoint = nil

function EvacuationSystem.init(mapData)
    EvacuationSystem.fixedPoints = mapData.evacuationPoints or {}
    EvacuationSystem.evacuating = false
    EvacuationSystem.evacuateTimer = 0
    EvacuationSystem.currentPoint = nil
end

function EvacuationSystem.getNearestPoint(playerX, playerY)
    local best, bestDist = nil, math.huge
    for _, pt in ipairs(EvacuationSystem.fixedPoints) do
        local dx = pt.x - playerX
        local dy = pt.y - playerY
        local d = math.sqrt(dx * dx + dy * dy)
        if d < bestDist then best = pt; bestDist = d end
    end
    return best, bestDist
end

function EvacuationSystem.startEvacuation(point, options)
    options = options or {}
    EvacuationSystem.evacuating = true
    EvacuationSystem.evacuateTimer = 0
    EvacuationSystem.currentPoint = point
    local duration = point.duration or 3
    -- 土偶灵契效果：1.5秒
    if options.hasTuou then duration = 1.5 end
    -- collapse阶段：1.5秒
    if options.isCollapse then duration = 1.5 end
    -- 疾风符：2秒
    if options.hasRushWard then duration = math.min(duration, 2.0) end
    EvacuationSystem.evacuateDuration = duration
    EventBus.emit("evacuation_start", point.type)
end

--- 紧急逃脱（collapse阶段，距撤离点>8格时可触发）
function EvacuationSystem.emergencyEscape(contracts)
    local lostContracts = {}
    -- 按品质权重丢失一只灵契：SSR优先
    if #contracts > 0 then
        local sorted = {}
        for _, c in ipairs(contracts) do table.insert(sorted, c) end
        table.sort(sorted, function(a, b)
            local rank = { R = 1, SR = 2, SSR = 3 }
            return (rank[a.quality] or 0) > (rank[b.quality] or 0)
        end)
        table.insert(lostContracts, sorted[1])
    end
    EventBus.emit("evacuation_result", true, lostContracts)
    return lostContracts
end

function EvacuationSystem.update(dt, playerX, playerY)
    if not EvacuationSystem.evacuating then return end
    local pt = EvacuationSystem.currentPoint
    local dx = pt.x - playerX
    local dy = pt.y - playerY
    if math.sqrt(dx * dx + dy * dy) > 1.5 then
        EvacuationSystem.cancel()
        return
    end
    EvacuationSystem.evacuateTimer = EvacuationSystem.evacuateTimer + dt
    if EvacuationSystem.evacuateTimer >= EvacuationSystem.evacuateDuration then
        EvacuationSystem.complete()
    end
end

function EvacuationSystem.complete()
    EvacuationSystem.evacuating = false
    EventBus.emit("evacuation_complete")
end

function EvacuationSystem.cancel()
    EvacuationSystem.evacuating = false
    EvacuationSystem.evacuateTimer = 0
end

function EvacuationSystem.getProgress()
    if not EvacuationSystem.evacuating then return 0 end
    return math.min(1, EvacuationSystem.evacuateTimer / EvacuationSystem.evacuateDuration)
end

--- 计算灵契不稳定列表
function EvacuationSystem.checkContractStability(contracts, soulCharmCount, hasIceSilk)
    local unstable = {}
    for _, contract in ipairs(contracts) do
        local triggerChance = ({ R = 0.05, SR = 0.30, SSR = 0.50 })[contract.quality] or 0.05
        if soulCharmCount > 0 then
            local reduction = ({ R = 0.05, SR = 0.20, SSR = 0.30 })[contract.quality] or 0
            triggerChance = math.max(0, triggerChance - reduction)
        end
        -- 冰蚕被动效果：全灵契不稳定率-10%
        if hasIceSilk then
            triggerChance = math.max(0, triggerChance - 0.10)
        end
        if math.random() < triggerChance then
            table.insert(unstable, contract)
        end
    end
    return unstable
end

-- 灵契QTE
EvacuationSystem.contractQTE = {
    active = false,
    contracts = {},
    currentIdx = 0,
    warningTimer = 0,
    WARNING_DURATION = 1.0,
    pointer = 0,
    direction = 1,
    speed = 1.2,
    targetZone = { 0.25, 0.75 },
    lostContracts = {},
}

function EvacuationSystem.startContractQTE(contracts)
    local qte = EvacuationSystem.contractQTE
    qte.active = true
    qte.contracts = contracts
    qte.currentIdx = 1
    qte.lostContracts = {}
    qte.warningTimer = qte.WARNING_DURATION
    qte.pointer = 0
    qte.direction = 1
end

function EvacuationSystem.updateContractQTE(dt)
    local qte = EvacuationSystem.contractQTE
    if not qte.active then return end
    if qte.warningTimer > 0 then
        qte.warningTimer = qte.warningTimer - dt
        return
    end
    qte.pointer = qte.pointer + qte.direction * qte.speed * dt
    if qte.pointer >= 1.0 then qte.pointer = 1.0; qte.direction = -1 end
    if qte.pointer <= 0.0 then qte.pointer = 0.0; qte.direction = 1 end
end

function EvacuationSystem.tapContractQTE()
    local qte = EvacuationSystem.contractQTE
    if not qte.active or qte.warningTimer > 0 then return end

    local contract = qte.contracts[qte.currentIdx]
    if not (qte.pointer >= qte.targetZone[1] and qte.pointer <= qte.targetZone[2]) then
        table.insert(qte.lostContracts, contract)
    end

    qte.currentIdx = qte.currentIdx + 1
    if qte.currentIdx > #qte.contracts then
        qte.active = false
        EventBus.emit("evacuation_result", true, qte.lostContracts)
    else
        qte.warningTimer = qte.WARNING_DURATION
        qte.pointer = 0
        qte.direction = 1
    end
end

return EvacuationSystem
