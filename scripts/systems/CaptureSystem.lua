--- 捕获判定 - 5级封灵器 + 偷袭加成 + 手动选择
local EventBus = require("systems.EventBus")
local PitySystem = require("systems.PitySystem")
local SessionState = require("systems.SessionState")

local CaptureSystem = {}

CaptureSystem.SEALER_RATES = {
    T1 = 0.75,
    T2 = 0.85,
    T3 = 0.92,
    T4 = 0.98,
    T5 = 1.00,
}

CaptureSystem.SEALER_NAMES = {
    T1 = "素灵符", T2 = "青玉壶", T3 = "金缕珠", T4 = "天命盘", T5 = "混沌印",
}

--- 获取可用封灵器列表（用于手动选择弹窗）
function CaptureSystem.getAvailableSealers(inventory)
    local available = {}
    local tiers = { "T1", "T2", "T3", "T4", "T5" }
    local keys = {
        T1 = "sealer_free", T2 = "sealer_t2", T3 = "sealer_t3",
        T4 = "sealer_t4", T5 = "sealer_t5",
    }
    for _, tier in ipairs(tiers) do
        local key = keys[tier]
        local count = inventory[key] or 0
        if count > 0 then
            table.insert(available, {
                tier = tier,
                key = key,
                name = CaptureSystem.SEALER_NAMES[tier],
                rate = CaptureSystem.SEALER_RATES[tier],
                count = count,
            })
        end
    end
    return available
end

--- 尝试捕获
function CaptureSystem.attemptCapture(beast, sealerTier, inventory, sealerKey)
    local baseRate = CaptureSystem.SEALER_RATES[sealerTier] or 0.75
    if beast.ambushBonus then
        baseRate = math.min(1.0, baseRate + 0.20)
    end

    -- T5混沌印：使用后本局无法再合成
    if sealerTier == "T5" then
        SessionState.t5Used = true
    end

    if math.random() < baseRate then
        -- 成功：消耗封灵器
        inventory[sealerKey] = inventory[sealerKey] - 1

        local result = {
            beastId = beast.id,
            type = beast.type,
            name = beast.name,
            quality = beast.quality,
            stable = false,
            biome = SessionState.selectedBiome,
        }

        -- T3金缕珠：成功后额外给予1追迹灰
        if sealerTier == "T3" then
            SessionState.addItem("traceAsh", 1)
        end

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
        -- 失败
        if sealerTier == "T4" and not SessionState.t4FailUsed then
            SessionState.t4FailUsed = true
        else
            inventory[sealerKey] = inventory[sealerKey] - 1
        end
        EventBus.emit("capture_failed", beast)
        return nil
    end
end

return CaptureSystem
