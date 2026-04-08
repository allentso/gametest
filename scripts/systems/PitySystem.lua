--- 保底系统 - SSR硬保底40次 / SR硬保底10次
local SaveGuard = require("systems.SaveGuard")
local Config = require("Config")

local PitySystem = {}

PitySystem.ssrCount = 0
PitySystem.srCount = 0

local SSR_FLASH_BONUS = {
    { threshold = 15, bonus = 0.10 },
    { threshold = 25, bonus = 0.20 },
    { threshold = 35, bonus = 0.35 },
    { threshold = 40, bonus = 1.00 },
}

function PitySystem.getSSRFlashBonus()
    if PitySystem.ssrCount >= 40 then return 1.0 end
    for i = #SSR_FLASH_BONUS, 1, -1 do
        if PitySystem.ssrCount >= SSR_FLASH_BONUS[i].threshold then
            return SSR_FLASH_BONUS[i].bonus
        end
    end
    return 0
end

function PitySystem.getSRCluesNeeded()
    if PitySystem.srCount >= 10 then return 0 end
    return 3
end

function PitySystem.isSRGuaranteed()
    return PitySystem.srCount >= 10
end

function PitySystem.incrementSSR() PitySystem.ssrCount = PitySystem.ssrCount + 1 end
function PitySystem.incrementSR()  PitySystem.srCount = PitySystem.srCount + 1 end
function PitySystem.resetSSR()     PitySystem.ssrCount = 0 end
function PitySystem.resetSR()      PitySystem.srCount = 0 end

function PitySystem.save()
    fileSystem:CreateDir("saves")
    SaveGuard.save("saves/pity.json", {
        ssr = PitySystem.ssrCount,
        sr = PitySystem.srCount,
    }, Config.DEVICE_ID)
end

function PitySystem.load()
    local data = SaveGuard.load("saves/pity.json", Config.DEVICE_ID)
    if data then
        PitySystem.ssrCount = data.ssr or 0
        PitySystem.srCount = data.sr or 0
    end
end

return PitySystem
