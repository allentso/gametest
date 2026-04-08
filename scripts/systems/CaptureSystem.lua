--- 捕获判定 - 4级封灵器 + 偷袭加成
local EventBus = require("systems.EventBus")
local PitySystem = require("systems.PitySystem")

local CaptureSystem = {}

CaptureSystem.SEALER_RATES = {
    T1 = 0.75,
    T2 = 0.85,
    T3 = 0.92,
    T4 = 0.98,
}

--- 自动选择最佳封灵器
function CaptureSystem.selectBestSealer(inventory)
    local tiers = { "T4", "T3", "T2", "T1" }
    for _, tier in ipairs(tiers) do
        local key = "sealer_" .. tier:lower()
        if (inventory[key] or 0) > 0 then
            return tier, key
        end
    end
    -- 免费素灵符
    if (inventory.sealer_free or 0) > 0 then
        return "T1", "sealer_free"
    end
    return nil, nil
end

--- 尝试捕获
function CaptureSystem.attemptCapture(beast, sealerTier, inventory, sealerKey)
    local baseRate = CaptureSystem.SEALER_RATES[sealerTier] or 0.75
    -- 偷袭加成
    if beast.ambushBonus then
        baseRate = math.min(1.0, baseRate + 0.20)
    end
    -- 消耗封灵器
    inventory[sealerKey] = inventory[sealerKey] - 1

    if math.random() < baseRate then
        local result = {
            beastId = beast.id,
            type = beast.type,
            name = beast.name,
            quality = beast.quality,
            stable = false,
        }
        -- 更新保底计数
        if beast.quality == "SSR" then
            PitySystem.resetSSR()
            PitySystem.resetSR()
        elseif beast.quality == "SR" then
            PitySystem.incrementSSR()
            PitySystem.resetSR()
        else
            PitySystem.incrementSSR()
            PitySystem.incrementSR()
        end
        EventBus.emit("beast_captured", result, beast.quality)
        return result
    else
        EventBus.emit("capture_failed", beast)
        return nil
    end
end

return CaptureSystem
