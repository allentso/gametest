--- 战争迷雾系统 - DARK/EXPLORED/VISIBLE 三态
local FogOfWar = {}

FogOfWar.DARK     = 0
FogOfWar.EXPLORED = 1
FogOfWar.VISIBLE  = 2

FogOfWar.VISION_RADIUS = 4.5
FogOfWar.grid = nil
FogOfWar.width = 0
FogOfWar.height = 0

function FogOfWar.init(mapWidth, mapHeight)
    FogOfWar.width = mapWidth
    FogOfWar.height = mapHeight
    FogOfWar.grid = {}
    for y = 1, mapHeight do
        FogOfWar.grid[y] = {}
        for x = 1, mapWidth do
            FogOfWar.grid[y][x] = FogOfWar.DARK
        end
    end
end

--- 每帧更新：将 VISIBLE→EXPLORED，然后以玩家为中心点亮新视野
function FogOfWar.update(playerX, playerY, overrideRadius)
    for y = 1, FogOfWar.height do
        for x = 1, FogOfWar.width do
            if FogOfWar.grid[y][x] == FogOfWar.VISIBLE then
                FogOfWar.grid[y][x] = FogOfWar.EXPLORED
            end
        end
    end
    local r = overrideRadius or FogOfWar.VISION_RADIUS
    local cx = math.floor(playerX) + 1
    local cy = math.floor(playerY) + 1
    local ri = math.ceil(r)
    for dy = -ri, ri do
        for dx = -ri, ri do
            local gx = cx + dx
            local gy = cy + dy
            if gx >= 1 and gx <= FogOfWar.width
               and gy >= 1 and gy <= FogOfWar.height then
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= r then
                    FogOfWar.grid[gy][gx] = FogOfWar.VISIBLE
                end
            end
        end
    end
end

--- 查询迷雾状态（世界坐标，0-based → 1-based）
function FogOfWar.getState(gx, gy)
    local x = gx + 1
    local y = gy + 1
    if x < 1 or x > FogOfWar.width or y < 1 or y > FogOfWar.height then
        return FogOfWar.DARK
    end
    return FogOfWar.grid[y][x]
end

--- 灾变边缘吞噬
function FogOfWar.collapseEdge(progress)
    local border = math.floor(progress * math.min(FogOfWar.width, FogOfWar.height) * 0.4)
    for y = 1, FogOfWar.height do
        for x = 1, FogOfWar.width do
            if x <= border or x > FogOfWar.width - border
               or y <= border or y > FogOfWar.height - border then
                FogOfWar.grid[y][x] = FogOfWar.DARK
            end
        end
    end
end

--- 随机揭示地图的一定比例（用于迷雾残图道具）
--- @param fraction number 0~1，揭示比例
function FogOfWar.revealRandom(fraction)
    if not FogOfWar.grid then return end
    -- 收集所有DARK格子
    local darkCells = {}
    for y = 1, FogOfWar.height do
        for x = 1, FogOfWar.width do
            if FogOfWar.grid[y][x] == FogOfWar.DARK then
                table.insert(darkCells, { x = x, y = y })
            end
        end
    end
    -- 按比例揭示
    local revealCount = math.floor(#darkCells * fraction)
    -- Fisher-Yates 洗牌取前 N 个
    for i = #darkCells, 2, -1 do
        local j = math.random(1, i)
        darkCells[i], darkCells[j] = darkCells[j], darkCells[i]
    end
    for i = 1, math.min(revealCount, #darkCells) do
        local cell = darkCells[i]
        FogOfWar.grid[cell.y][cell.x] = FogOfWar.EXPLORED
    end
end

--- 判断实体是否可见
function FogOfWar.isEntityVisible(wx, wy)
    return FogOfWar.getState(math.floor(wx), math.floor(wy)) == FogOfWar.VISIBLE
end

return FogOfWar
