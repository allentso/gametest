--- 全局配置 + 质量分级
local Config = {}

-- 画质等级: 0=低 / 1=中 / 2=高
Config.QUALITY = 1
Config.MAX_PARTICLES = 15
Config.TILE_DETAIL = true
Config.ATMOSPHERE = true
Config.INK_FIBERS = true
Config.DEVICE_ID = ""

-- 地图规格（竖屏 20×30）
Config.MAP_WIDTH = 20
Config.MAP_HEIGHT = 30

-- 玩家
Config.VISION_RADIUS = 4.5
Config.PLAYER_SPEED = 5

-- 灾变
Config.GAME_DURATION = 480  -- 8 分钟

-- 自动降级
local frameHistory = {}
local adjustCooldown = 0

function Config.autoAdjust(dt)
    if Config.performanceLocked then return end
    adjustCooldown = adjustCooldown - dt
    table.insert(frameHistory, dt)
    if #frameHistory > 90 then table.remove(frameHistory, 1) end
    if #frameHistory < 45 or adjustCooldown > 0 then return end

    local avg = 0
    for _, d in ipairs(frameHistory) do avg = avg + d end
    avg = avg / #frameHistory

    if avg > 1 / 40 and Config.QUALITY > 0 then
        Config.QUALITY = Config.QUALITY - 1
        Config.MAX_PARTICLES = math.max(5, Config.MAX_PARTICLES - 5)
        Config.TILE_DETAIL = Config.QUALITY >= 1
        Config.ATMOSPHERE = Config.QUALITY >= 1
        Config.INK_FIBERS = Config.QUALITY >= 2
        adjustCooldown = 5
    elseif avg < 1 / 55 and Config.QUALITY < 2 then
        Config.QUALITY = Config.QUALITY + 1
        Config.MAX_PARTICLES = math.min(30, Config.MAX_PARTICLES + 5)
        Config.TILE_DETAIL = Config.QUALITY >= 1
        Config.ATMOSPHERE = Config.QUALITY >= 1
        Config.INK_FIBERS = Config.QUALITY >= 2
        adjustCooldown = 10
    end
end

Config.performanceLocked = false
function Config.lockPerformance() Config.performanceLocked = true end
function Config.unlockPerformance()
    Config.performanceLocked = false
    frameHistory = {}
end

return Config
