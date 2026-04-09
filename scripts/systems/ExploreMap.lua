--- 地图生成 - 不规则有机地形 (Voronoi 群落 + 噪声轮廓)
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

------------------------------------------------------------
-- 噪声工具（Value Noise + FBM）
------------------------------------------------------------

local noiseSeed = 0

local function hash2(x, y)
    local n = (x * 374761393 + y * 668265263 + noiseSeed * 1013904223) & 0x7fffffff
    n = ((n ~ (n >> 13)) * 1274126177) & 0x7fffffff
    n = (n ~ (n >> 16)) & 0x7fffffff
    return n / 0x7fffffff
end

local function valueNoise(x, y)
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    local v00 = hash2(ix, iy)
    local v10 = hash2(ix + 1, iy)
    local v01 = hash2(ix, iy + 1)
    local v11 = hash2(ix + 1, iy + 1)
    return (v00 + (v10 - v00) * fx) * (1 - fy) + (v01 + (v11 - v01) * fx) * fy
end

local function fbm(x, y, octaves)
    local val, amp, freq, maxAmp = 0, 1, 1, 0
    for _ = 1, octaves do
        val = val + valueNoise(x * freq, y * freq) * amp
        maxAmp = maxAmp + amp
        amp = amp * 0.5
        freq = freq * 2
    end
    return val / maxAmp
end

------------------------------------------------------------
-- 构造
------------------------------------------------------------

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
    self.occupiedList = {}
    self.occupiedSet = {}
    return self
end

------------------------------------------------------------
-- 占用位管理（防重叠）
------------------------------------------------------------

function ExploreMap:markOccupied(x, y)
    table.insert(self.occupiedList, { x = x, y = y })
    self.occupiedSet[x .. "," .. y] = true
end

function ExploreMap:isOccupied(x, y)
    return self.occupiedSet[x .. "," .. y] == true
end

function ExploreMap:isTooClose(x, y, minDist)
    for _, pos in ipairs(self.occupiedList) do
        local d = math.abs(pos.x - x) + math.abs(pos.y - y)
        if d < minDist then return true end
    end
    return false
end

------------------------------------------------------------
-- 主生成
------------------------------------------------------------

function ExploreMap:generate(seed)
    seed = seed or os.time()
    math.randomseed(seed)
    noiseSeed = seed % 10000
    local w, h = self.width, self.height
    self.occupiedList = {}
    self.occupiedSet = {}

    -- 1) 不规则轮廓蒙版
    local shapeMask = self:buildShapeMask(w, h)

    -- 2) Voronoi 群落种子
    local biomeSeeds = self:placeBiomeSeeds(w, h, shapeMask)

    -- 3) 逐格生成瓦片
    for y = 1, h do
        self.tiles[y] = {}
        for x = 1, w do
            local tile
            if not shapeMask[y][x] then
                tile = { type = "wall", blocked = true }
            else
                tile = self:tileFromBiome(x, y, w, h, biomeSeeds)
            end
            tile.gx = x - 1
            tile.gy = y - 1
            tile.seed = math.random(0, 999)
            if tile.type == "grass" then
                tile.grassStrokes = self:precomputeGrassStrokes(tile)
            elseif tile.type == "rock" then
                tile.cunCount = 4 + math.random(0, 3)
            end
            tile.fibers = self:precomputeFibers()
            self.tiles[y][x] = tile
        end
    end

    -- 4) 出生点（底部中央）
    self.spawnPoint = { x = math.floor(w / 2), y = 2 }

    -- 清空出生区域（5×5）
    for dy = -2, 2 do
        for dx = -2, 2 do
            local tx = self.spawnPoint.x + 1 + dx
            local ty = self.spawnPoint.y + 1 + dy
            if tx >= 2 and tx <= w - 1 and ty >= 2 and ty <= h - 1 then
                self.tiles[ty][tx].type = "path"
                self.tiles[ty][tx].blocked = false
            end
        end
    end
    self:markOccupied(self.spawnPoint.x, self.spawnPoint.y)

    -- 出生走廊：从出生点向上开辟 3 格宽、12 格长的保证通道
    local corridorCX = self.spawnPoint.x + 1  -- tile 坐标
    local corridorLen = 12
    for dy = 0, corridorLen do
        for dx = -1, 1 do
            local tx = corridorCX + dx
            local ty = self.spawnPoint.y + 1 + dy
            if tx >= 2 and tx <= w - 1 and ty >= 2 and ty <= h - 1 then
                if self.tiles[ty][tx].blocked or self.tiles[ty][tx].type == "wall" or self.tiles[ty][tx].type == "water" then
                    self.tiles[ty][tx].type = "path"
                    self.tiles[ty][tx].blocked = false
                end
            end
        end
    end

    -- BFS 连通性验证：确保出生点可达足够多的可通行区域
    self:ensureSpawnConnectivity(w, h, shapeMask)

    -- 计算可达性地图（所有实体只放在可达格子上）
    self.reachable = self:buildReachabilityMap(w, h)

    -- 5) 放置实体（共用 occupiedSet 防重叠）
    self:generateCluePositions()
    self:generateResourceNodes()
    self:generateEvacuationPoints()
end

------------------------------------------------------------
-- 不规则轮廓（噪声扰动椭圆）
------------------------------------------------------------

function ExploreMap:buildShapeMask(w, h)
    local cx, cy = w * 0.5 + 0.5, h * 0.5 + 0.5
    local rx, ry = (w - 4) * 0.5, (h - 4) * 0.5
    local mask = {}
    for y = 1, h do
        mask[y] = {}
        for x = 1, w do
            if x <= 1 or x >= w or y <= 1 or y >= h then
                mask[y][x] = false
            else
                local dx = (x - cx) / rx
                local dy = (y - cy) / ry
                local dist = math.sqrt(dx * dx + dy * dy)
                local n = fbm(x * 0.18, y * 0.18, 3)
                local threshold = 0.90 + n * 0.24
                mask[y][x] = dist < threshold
            end
        end
    end
    -- 保证出生区始终可通行
    local spawnTX = math.floor(w / 2) + 1
    for dy = -3, 3 do
        for dx = -3, 3 do
            local tx, ty = spawnTX + dx, 3 + dy
            if tx >= 2 and tx <= w - 1 and ty >= 2 and ty <= h - 1 then
                mask[ty][tx] = true
            end
        end
    end
    return mask
end

------------------------------------------------------------
-- Voronoi 群落种子
------------------------------------------------------------

function ExploreMap:placeBiomeSeeds(w, h, shapeMask)
    local seeds = {}
    local count = 14 + math.random(0, 6)
    for _ = 1, count do
        for _ = 1, 40 do
            local sx = math.random(3, w - 2)
            local sy = math.random(3, h - 2)
            if shapeMask[sy][sx] then
                local depth = sy / h
                local biome = self:pickBiomeForDepth(depth)
                table.insert(seeds, { x = sx, y = sy, biome = biome })
                break
            end
        end
    end
    return seeds
end

function ExploreMap:pickBiomeForDepth(depth)
    local r = math.random()
    if depth <= 0.15 then
        return r < 0.55 and "path" or "grass"
    elseif depth <= 0.40 then
        if r < 0.35 then return "grass"
        elseif r < 0.55 then return "rock"
        elseif r < 0.75 then return "bamboo"
        elseif r < 0.88 then return "path"
        else return "water" end
    elseif depth <= 0.70 then
        if r < 0.30 then return "grass"
        elseif r < 0.50 then return "rock"
        elseif r < 0.65 then return "bamboo"
        elseif r < 0.78 then return "water"
        else return "danger" end
    else
        if r < 0.28 then return "danger"
        elseif r < 0.48 then return "rock"
        elseif r < 0.65 then return "grass"
        elseif r < 0.80 then return "bamboo"
        else return "water" end
    end
end

------------------------------------------------------------
-- 根据最近群落种子生成瓦片
------------------------------------------------------------

function ExploreMap:tileFromBiome(x, y, w, h, biomeSeeds)
    local tile = { blocked = false }
    -- 找最近种子
    local minD2 = math.huge
    local biome = "grass"
    for _, s in ipairs(biomeSeeds) do
        local d2 = (x - s.x) ^ 2 + (y - s.y) ^ 2
        if d2 < minD2 then minD2 = d2; biome = s.biome end
    end
    -- 15% 概率局部变异
    if math.random() < 0.15 then
        local depth = y / h
        if depth > 0.70 and math.random() < 0.30 then
            biome = "danger"
        elseif math.random() < 0.5 then
            biome = "grass"
        end
    end
    tile.type = biome
    -- blocked 概率
    if biome == "rock" then
        tile.blocked = math.random() < 0.35
    elseif biome == "bamboo" then
        tile.blocked = math.random() < 0.50
    elseif biome == "water" then
        tile.blocked = true
    end
    return tile
end

------------------------------------------------------------
-- 预计算渲染数据（保持不变）
------------------------------------------------------------

function ExploreMap:precomputeGrassStrokes(tile)
    local strokes = {}
    local count = 3 + (tile.seed or 0) % 3
    for _ = 1, count do
        table.insert(strokes, {
            x1 = (math.random() - 0.5) * 0.8,
            y1 = (math.random() - 0.5) * 0.8,
            cx = (math.random() - 0.5) * 0.6,
            cy = (math.random() - 0.5) * 0.6,
            x2 = (math.random() - 0.5) * 0.7,
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
    for _ = 1, 2 do
        table.insert(fibers, {
            x1 = math.random() * 0.8 - 0.4,
            y1 = math.random() * 0.8 - 0.4,
            x2 = math.random() * 0.8 - 0.4,
            y2 = math.random() * 0.8 - 0.4,
        })
    end
    return fibers
end

------------------------------------------------------------
-- 线索（8 个）
------------------------------------------------------------

function ExploreMap:generateCluePositions()
    self.clues = {}
    local clueTypes = { "footprint", "resonance", "nest", "scentMark" }
    for _ = 1, 8 do
        local wx, wy = self:findPlaceable(4, self.height - 2, 3)
        if wx then
            self:markOccupied(wx, wy)
            table.insert(self.clues, {
                x = wx, y = wy,
                type = clueTypes[math.random(#clueTypes)],
                investigated = false,
            })
        end
    end
end

------------------------------------------------------------
-- 资源（15 个）
------------------------------------------------------------

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
        { type = "busicao",    weight = 1,  zone = "danger" },
    }

    for _ = 1, 15 do
        local wx, wy = self:findPlaceable(3, self.height - 2, 2)
        if wx then
            local depth = (wy + 1) / self.height
            local pool = {}
            for _, rt in ipairs(resourceTypes) do
                local valid = false
                if rt.zone == "all" then valid = true
                elseif rt.zone == "deep" and depth > 0.4 then valid = true
                elseif rt.zone == "danger" and depth > 0.7 then valid = true
                end
                if valid then
                    for _ = 1, rt.weight do table.insert(pool, rt.type) end
                end
            end
            if #pool > 0 then
                self:markOccupied(wx, wy)
                table.insert(self.resources, {
                    x = wx, y = wy,
                    type = pool[math.random(#pool)],
                    collected = false,
                    amount = math.random(1, 3),
                })
            end
        end
    end
end

------------------------------------------------------------
-- 撤离点（1 个，随机位置）
------------------------------------------------------------

function ExploreMap:generateEvacuationPoints()
    self.evacuationPoints = {}
    -- 避开出生附近，选深度 20%-80% 区间
    local minY = math.max(4, math.floor(self.height * 0.20))
    local maxY = math.min(self.height - 3, math.floor(self.height * 0.80))
    local wx, wy = self:findPlaceable(minY, maxY, 4)
    if wx then
        local tx, ty = wx + 1, wy + 1
        if self.tiles[ty] and self.tiles[ty][tx] then
            self.tiles[ty][tx].blocked = false
            self.tiles[ty][tx].type = "path"
        end
        self:markOccupied(wx, wy)
        table.insert(self.evacuationPoints, {
            x = wx, y = wy,
            duration = 3,
            type = "fixed",
        })
    end
end

------------------------------------------------------------
-- BFS 出生连通性保障
------------------------------------------------------------

function ExploreMap:ensureSpawnConnectivity(w, h, shapeMask)
    local spawnTX = self.spawnPoint.x + 1
    local spawnTY = self.spawnPoint.y + 1

    -- BFS 从出生点扩散，统计可达的非阻塞格数
    local visited = {}
    for y = 1, h do visited[y] = {} end

    local queue = { { spawnTX, spawnTY } }
    visited[spawnTY][spawnTX] = true
    local reachable = 0
    local dirs = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        reachable = reachable + 1
        for _, d in ipairs(dirs) do
            local nx, ny = cur[1] + d[1], cur[2] + d[2]
            if nx >= 1 and nx <= w and ny >= 1 and ny <= h
               and not visited[ny][nx] then
                local t = self.tiles[ny][nx]
                if t and not t.blocked and t.type ~= "wall" then
                    visited[ny][nx] = true
                    queue[#queue + 1] = { nx, ny }
                end
            end
        end
    end

    -- 统计蒙版内总可用格数
    local totalInMask = 0
    for y = 1, h do
        for x = 1, w do
            if shapeMask[y][x] then totalInMask = totalInMask + 1 end
        end
    end

    -- 如果可达区域不足蒙版面积的 30%，沿走廊继续向上打通
    local threshold = math.floor(totalInMask * 0.30)
    if reachable < threshold then
        -- 策略：向走廊左右拓宽并继续向上打通，直到连通改善
        local corridorCX = spawnTX
        -- 第二遍：5 格宽、延伸到地图顶部
        for ty = spawnTY, h - 1 do
            for dx = -2, 2 do
                local tx = corridorCX + dx
                if tx >= 2 and tx <= w - 1 then
                    local t = self.tiles[ty][tx]
                    if t and (t.blocked or t.type == "wall" or t.type == "water") then
                        t.type = "path"
                        t.blocked = false
                    end
                end
            end
        end
        -- 每隔 8 行向左右各伸出 5 格横支路，连接周围区域
        for ty = spawnTY + 5, h - 2, 8 do
            for dx = -7, 7 do
                local tx = corridorCX + dx
                if tx >= 2 and tx <= w - 1 and ty >= 2 and ty <= h - 1 then
                    local t = self.tiles[ty][tx]
                    if t and (t.blocked or t.type == "wall" or t.type == "water") then
                        t.type = "path"
                        t.blocked = false
                    end
                end
            end
        end
    end
end

------------------------------------------------------------
-- 可达性地图（BFS from spawn）
------------------------------------------------------------

function ExploreMap:buildReachabilityMap(w, h)
    local spawnTX = self.spawnPoint.x + 1
    local spawnTY = self.spawnPoint.y + 1
    local visited = {}
    for y = 1, h do visited[y] = {} end

    local queue = { { spawnTX, spawnTY } }
    visited[spawnTY][spawnTX] = true
    local dirs = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        for _, d in ipairs(dirs) do
            local nx, ny = cur[1] + d[1], cur[2] + d[2]
            if nx >= 1 and nx <= w and ny >= 1 and ny <= h
               and not visited[ny][nx] then
                local t = self.tiles[ny][nx]
                if t and not t.blocked and t.type ~= "wall" then
                    visited[ny][nx] = true
                    queue[#queue + 1] = { nx, ny }
                end
            end
        end
    end
    return visited
end

------------------------------------------------------------
-- 通用放置查找（防重叠 + 可达性）
------------------------------------------------------------

function ExploreMap:findPlaceable(minY, maxY, minDist)
    for _ = 1, 60 do
        local x = math.random(3, self.width - 2)
        local y = math.random(minY, maxY)
        local tile = self.tiles[y] and self.tiles[y][x]
        local wx, wy = x - 1, y - 1
        if tile and not tile.blocked
           and tile.type ~= "wall" and tile.type ~= "water"
           and not self:isTooClose(wx, wy, minDist)
           and (not self.reachable or (self.reachable[y] and self.reachable[y][x])) then
            return wx, wy
        end
    end
    return nil, nil
end

------------------------------------------------------------
-- 查询接口
------------------------------------------------------------

function ExploreMap:getTile(gx, gy)
    local x, y = gx + 1, gy + 1
    if x < 1 or x > self.width or y < 1 or y > self.height then return nil end
    return self.tiles[y][x]
end

function ExploreMap:isBlocked(gx, gy)
    local tile = self:getTile(gx, gy)
    if not tile then return true end
    return tile.blocked
end

return ExploreMap
