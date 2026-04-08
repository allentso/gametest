--- 地图生成 - 20×30竖屏纵深地图
local Config = require("Config")

local ExploreMap = {}
ExploreMap.__index = ExploreMap

-- 地形类型
ExploreMap.TYPES = {
    GRASS  = "grass",
    ROCK   = "rock",
    WATER  = "water",
    PATH   = "path",
    BAMBOO = "bamboo",
    DANGER = "danger",
    WALL   = "wall",
}

function ExploreMap.new()
    local self = setmetatable({}, ExploreMap)
    self.width = Config.MAP_WIDTH
    self.height = Config.MAP_HEIGHT
    self.tiles = {}
    self.clues = {}
    self.resources = {}
    self.evacuationPoints = {}
    self.beasts = {}
    self.spawnPoint = { x = 0, y = 0 }
    return self
end

function ExploreMap:generate(seed)
    math.randomseed(seed or os.time())
    local w, h = self.width, self.height

    -- 初始化瓦片
    for y = 1, h do
        self.tiles[y] = {}
        for x = 1, w do
            local tile = self:generateTile(x, y, w, h)
            tile.gx = x - 1  -- 世界坐标(0-based)
            tile.gy = y - 1
            tile.seed = math.random(0, 999)
            -- 预计算装饰数据
            if tile.type == "grass" then
                tile.grassStrokes = self:precomputeGrassStrokes(tile)
            elseif tile.type == "rock" then
                tile.cunCount = 4 + math.random(0, 3)
            end
            tile.fibers = self:precomputeFibers()
            self.tiles[y][x] = tile
        end
    end

    -- 出生点（底部中央）
    self.spawnPoint = { x = math.floor(w / 2), y = 2 }

    -- 确保出生点周围可通行
    for dy = -1, 1 do
        for dx = -1, 1 do
            local tx = self.spawnPoint.x + 1 + dx
            local ty = self.spawnPoint.y + 1 + dy
            if tx >= 1 and tx <= w and ty >= 1 and ty <= h then
                self.tiles[ty][tx].type = "path"
                self.tiles[ty][tx].blocked = false
            end
        end
    end

    self:generateCluePositions()
    self:generateResourceNodes()
    self:generateEvacuationPoints()
end

function ExploreMap:generateTile(x, y, w, h)
    local tile = { blocked = false }
    -- 区域划分: 安全区(边缘2格) → 搜索区 → 稀有区 → 高危区
    local depth = y  -- 从底部向上深入
    local distFromEdge = math.min(x, w - x + 1, y, h - y + 1)

    -- 边界墙
    if x == 1 or x == w or y == 1 or y == h then
        tile.type = "wall"
        tile.blocked = true
        return tile
    end

    -- 按深度和随机分配地形
    local roll = math.random()
    if distFromEdge <= 3 then
        -- 安全区: 主要是草地和小径
        if roll < 0.35 then tile.type = "path"
        elseif roll < 0.85 then tile.type = "grass"
        else tile.type = "bamboo"; tile.blocked = (math.random() < 0.6) end
    elseif depth <= h * 0.4 then
        -- 搜索区
        if roll < 0.50 then tile.type = "grass"
        elseif roll < 0.70 then tile.type = "rock"; tile.blocked = (math.random() < 0.35)
        elseif roll < 0.85 then tile.type = "bamboo"; tile.blocked = (math.random() < 0.5)
        elseif roll < 0.93 then tile.type = "water"; tile.blocked = true
        else tile.type = "path" end
    elseif depth <= h * 0.7 then
        -- 稀有区
        if roll < 0.40 then tile.type = "grass"
        elseif roll < 0.65 then tile.type = "rock"; tile.blocked = (math.random() < 0.4)
        elseif roll < 0.80 then tile.type = "bamboo"; tile.blocked = (math.random() < 0.55)
        elseif roll < 0.90 then tile.type = "water"; tile.blocked = true
        else tile.type = "danger" end
    else
        -- 高危区
        if roll < 0.30 then tile.type = "grass"
        elseif roll < 0.55 then tile.type = "rock"; tile.blocked = (math.random() < 0.45)
        elseif roll < 0.70 then tile.type = "danger"
        elseif roll < 0.85 then tile.type = "bamboo"; tile.blocked = (math.random() < 0.6)
        else tile.type = "water"; tile.blocked = true end
    end

    return tile
end

function ExploreMap:precomputeGrassStrokes(tile)
    local strokes = {}
    local count = 3 + (tile.seed or 0) % 3  -- 3-5笔
    for i = 1, count do
        table.insert(strokes, {
            x1 = (math.random() - 0.5) * 0.8,   -- 起点可超出格子
            y1 = (math.random() - 0.5) * 0.8,
            cx = (math.random() - 0.5) * 0.6,    -- 控制点更分散
            cy = (math.random() - 0.5) * 0.6,
            x2 = (math.random() - 0.5) * 0.7,    -- 终点可伸入邻格
            y2 = (math.random() - 0.5) * 1.0,
            alpha = 0.18 + math.random() * 0.18,
            width = 0.8 + math.random() * 0.8,
            phase = math.random() * math.pi * 2,
        })
    end
    return strokes
end

function ExploreMap:precomputeFibers()
    local fibers = {}
    for i = 1, 2 do
        table.insert(fibers, {
            x1 = math.random() * 0.8 - 0.4,
            y1 = math.random() * 0.8 - 0.4,
            x2 = math.random() * 0.8 - 0.4,
            y2 = math.random() * 0.8 - 0.4,
        })
    end
    return fibers
end

function ExploreMap:generateCluePositions()
    self.clues = {}
    local clueTypes = { "footprint", "resonance", "nest", "scentMark" }
    for i = 1, 14 do
        for attempt = 1, 20 do
            local x = math.random(3, self.width - 2)
            local y = math.random(4, self.height - 2)
            local tile = self.tiles[y][x]
            if not tile.blocked and tile.type ~= "wall" and tile.type ~= "water" then
                local tooClose = false
                for _, c in ipairs(self.clues) do
                    if math.abs(c.x - (x - 1)) + math.abs(c.y - (y - 1)) < 3 then
                        tooClose = true
                        break
                    end
                end
                if not tooClose then
                    table.insert(self.clues, {
                        x = x - 1, y = y - 1,  -- 世界坐标
                        type = clueTypes[math.random(#clueTypes)],
                        investigated = false,
                    })
                    break
                end
            end
        end
    end
end

function ExploreMap:generateResourceNodes()
    self.resources = {}
    local resourceTypes = {
        { type = "lingshi",    weight = 55, zone = "all" },
        { type = "traceAsh",   weight = 18, zone = "all" },
        { type = "shouhun",    weight = 12, zone = "deep" },
        { type = "tianjing",   weight = 5,  zone = "danger" },
        { type = "mirrorSand", weight = 7,  zone = "deep" },
        { type = "soulCharm",  weight = 5,  zone = "danger" },
        { type = "beastEye",   weight = 4,  zone = "deep" },
        { type = "sealEcho",   weight = 2,  zone = "danger" },
    }

    for i = 1, 28 do
        for attempt = 1, 20 do
            local x = math.random(3, self.width - 2)
            local y = math.random(3, self.height - 2)
            local tile = self.tiles[y][x]
            if not tile.blocked and tile.type ~= "wall" and tile.type ~= "water" then
                -- 根据深度选择资源类型
                local depth = y / self.height
                local pool = {}
                for _, rt in ipairs(resourceTypes) do
                    local valid = false
                    if rt.zone == "all" then valid = true
                    elseif rt.zone == "deep" and depth > 0.4 then valid = true
                    elseif rt.zone == "danger" and depth > 0.7 then valid = true
                    end
                    if valid then
                        for w = 1, rt.weight do
                            table.insert(pool, rt.type)
                        end
                    end
                end
                if #pool > 0 then
                    table.insert(self.resources, {
                        x = x - 1, y = y - 1,
                        type = pool[math.random(#pool)],
                        collected = false,
                        amount = math.random(1, 3),
                    })
                    break
                end
            end
        end
    end
end

function ExploreMap:generateEvacuationPoints()
    self.evacuationPoints = {}
    -- 在地图边缘安全区放撤离点
    local positions = {
        { x = 3,              y = 3 },
        { x = self.width - 4, y = 3 },
        { x = 3,              y = math.floor(self.height / 2) },
        { x = self.width - 4, y = math.floor(self.height / 2) },
    }
    for _, pos in ipairs(positions) do
        -- 确保撤离点可通行
        if self.tiles[pos.y + 1] and self.tiles[pos.y + 1][pos.x + 1] then
            self.tiles[pos.y + 1][pos.x + 1].blocked = false
            self.tiles[pos.y + 1][pos.x + 1].type = "path"
        end
        table.insert(self.evacuationPoints, {
            x = pos.x, y = pos.y,
            duration = 3,
            type = "fixed",
        })
    end
end

--- 获取瓦片（世界坐标 0-based）
function ExploreMap:getTile(gx, gy)
    local x = gx + 1
    local y = gy + 1
    if x < 1 or x > self.width or y < 1 or y > self.height then
        return nil
    end
    return self.tiles[y][x]
end

--- 判定碰撞（世界坐标 0-based）
function ExploreMap:isBlocked(gx, gy)
    local tile = self:getTile(gx, gy)
    if not tile then return true end
    return tile.blocked
end

return ExploreMap
