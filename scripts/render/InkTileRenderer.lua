--- 水墨瓦片渲染 - 双遍渲染体系：色块层 + 细节层
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local FogOfWar = require("systems.FogOfWar")
local Config = require("Config")

local InkTileRenderer = {}

------------------------------------------------------------
-- Pass 1: 色块层 — 大半径低 alpha 底色晕染，让相邻瓦片自然渗透
------------------------------------------------------------

--- 小路专用暖土色
local PATH_COLOR = { r = 0.65, g = 0.55, b = 0.38 }

--- 每种地形的底色配置 { color, innerR, outerR, alpha }
--- outerR 拉到 1.4~1.6 倍 ppu，确保相邻瓦片充分重叠消除网格感
local BASE_WASH = {
    grass  = function(P) return P.jade,       0.05, 1.50, 0.25 end,
    rock   = function(P) return P.inkMedium,  0.08, 1.40, 0.35 end,  -- 岩石更浓
    water  = function(P) return P.azure,      0.05, 1.55, 0.35 end,  -- 水面更鲜明
    path   = function(P) return PATH_COLOR,   0.05, 1.45, 0.28 end,  -- 小路更明显
    bamboo = function(P) return P.jade,       0.05, 1.45, 0.28 end,  -- 竹林更浓
    danger = function(P) return P.miasmaDark, 0.05, 1.50, 0.35 end,  -- 瘴气更深
}

--- Pass 1: 绘制瓦片底色晕染（大半径，重叠产生连续画面）
function InkTileRenderer.drawBase(vg, tile, sx, sy, ppu, t, fogState)
    if not tile or tile.type == "wall" then return end
    if fogState == FogOfWar.DARK then return end

    local alphaScale = fogState == FogOfWar.EXPLORED and 0.30 or 1.0
    local fn = BASE_WASH[tile.type]
    if not fn then return end

    local color, innerMul, outerMul, baseAlpha = fn(InkPalette)

    -- 瘴气区域脉冲
    if tile.type == "danger" then
        baseAlpha = baseAlpha + math.sin(t * 2.5 + (tile.seed or 0) * 0.3) * 0.08
    end

    BrushStrokes.inkWash(vg, sx, sy,
        ppu * innerMul, ppu * outerMul,
        color, baseAlpha * alphaScale)
end

------------------------------------------------------------
-- Pass 2: 细节层 — 笔触、纹理、动态效果
------------------------------------------------------------

function InkTileRenderer.drawDetail(vg, tile, sx, sy, ppu, t, fogState)
    if not tile or tile.type == "wall" then return end
    if fogState == FogOfWar.DARK then return end

    local alphaScale = fogState == FogOfWar.EXPLORED and 0.30 or 1.0

    if tile.type == "grass" then
        InkTileRenderer.drawGrassDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    elseif tile.type == "rock" then
        InkTileRenderer.drawRockDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    elseif tile.type == "water" then
        InkTileRenderer.drawWaterDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    elseif tile.type == "path" then
        InkTileRenderer.drawPathDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    elseif tile.type == "bamboo" then
        InkTileRenderer.drawBambooDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    elseif tile.type == "danger" then
        InkTileRenderer.drawDangerDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    end

    -- 被阻挡的 rock/bamboo 叠加交叉皴纹阻挡标记
    if tile.blocked and (tile.type == "rock" or tile.type == "bamboo") then
        InkTileRenderer.drawBlockedOverlay(vg, tile, sx, sy, ppu, alphaScale)
    end

    -- EXPLORED 态叠加淡墨径向晕染
    if fogState == FogOfWar.EXPLORED then
        BrushStrokes.inkWash(vg, sx, sy, ppu * 0.1, ppu * 0.6,
            InkPalette.inkMedium, 0.15)
    end
end

--- 草地细节: 仅绘制前 2 笔兰草弧线（稀疏留白），线宽加粗，alpha 降低
function InkTileRenderer.drawGrassDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    if not tile.grassStrokes then return end
    if not Config.TILE_DETAIL then return end

    -- 只画前 2 笔（即使预计算了 3-5 笔），稀疏胜过密集
    local maxStrokes = math.min(2, #tile.grassStrokes)
    -- 50% 的格子只画 1 笔（进一步稀疏化）
    local seed = tile.seed or 0
    if seed % 3 == 0 then maxStrokes = math.min(1, maxStrokes) end

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    for si = 1, maxStrokes do
        local stroke = tile.grassStrokes[si]
        local wind = math.sin(t * 1.5 + stroke.phase) * ppu * 0.04
        local x1 = sx + stroke.x1 * ppu
        local y1 = sy + stroke.y1 * ppu
        local cx = sx + stroke.cx * ppu + wind
        local cy = sy + stroke.cy * ppu
        local x2 = sx + stroke.x2 * ppu + wind * 1.5
        local y2 = sy + stroke.y2 * ppu

        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgQuadTo(vg, cx, cy, x2, y2)
        -- 线宽加粗 1.5 倍，alpha 降低，更像写意淡笔
        nvgStrokeWidth(vg, stroke.width * 1.5)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            stroke.alpha * 0.6 * alphaScale))
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

--- 岩石细节: 皴法纹理 + 浓墨山石轮廓
function InkTileRenderer.drawRockDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    local cunCount = math.min(5, tile.cunCount or 4)
    -- 皴法纹理
    BrushStrokes.cunTexture(vg, sx, sy, ppu * 0.65,
        InkPalette.inkStrong, 0.22 * alphaScale, seed, cunCount)
    -- 添加不规则山石轮廓弧线（强化岩石感）
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local hash = seed * 7 % 100
    local arcR = ppu * (0.30 + hash / 500)
    local startA = (hash % 60) * math.pi / 180
    nvgBeginPath(vg)
    nvgArc(vg, sx, sy, arcR, startA, startA + math.pi * 0.7, NVG_CW)
    nvgStrokeWidth(vg, 1.8)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.28 * alphaScale))
    nvgStroke(vg)
    nvgRestore(vg)
end

--- 小路细节: 淡色踏痕足迹 + 细碎卵石
function InkTileRenderer.drawPathDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    nvgSave(vg)
    -- 2-3 个淡色椭圆踏痕（模拟脚印压过的泥土）
    for i = 1, 2 + seed % 2 do
        local hash = (seed * 11 + i * 23) % 100
        local dx = (hash % 30 - 15) * ppu * 0.02
        local dy = ((hash * 3) % 30 - 15) * ppu * 0.02
        nvgBeginPath(vg)
        nvgEllipse(vg, sx + dx, sy + dy,
            ppu * (0.08 + (hash % 10) / 200),
            ppu * (0.05 + (hash % 8) / 300))
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkWash.r, InkPalette.inkWash.g, InkPalette.inkWash.b,
            0.18 * alphaScale))
        nvgFill(vg)
    end
    -- 细碎卵石点（更小的墨点散布在路面上）
    for i = 1, 3 do
        local hash = (seed * 7 + i * 41) % 100
        local dx = (hash % 24 - 12) * ppu * 0.025
        local dy = ((hash * 5) % 24 - 12) * ppu * 0.025
        nvgBeginPath(vg)
        nvgCircle(vg, sx + dx, sy + dy, 1.0 + hash % 2 * 0.5)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b,
            0.20 * alphaScale))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

--- 被阻挡地形叠加层: 交叉皴纹 + 浓墨晕染（标识不可通行）
function InkTileRenderer.drawBlockedOverlay(vg, tile, sx, sy, ppu, alphaScale)
    local seed = tile.seed or 0
    -- 浓墨底层晕染，让被阻挡格子整体更暗
    BrushStrokes.inkWash(vg, sx, sy, ppu * 0.05, ppu * 0.50,
        InkPalette.inkStrong, 0.15 * alphaScale)
    -- 交叉短线（×标记）表示不可通行
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local r = ppu * 0.22
    local hash = seed * 13 % 100
    local offX = (hash % 10 - 5) * ppu * 0.01
    local offY = ((hash * 3) % 10 - 5) * ppu * 0.01
    -- 对角线 1
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + offX - r, sy + offY - r * 0.8)
    nvgLineTo(vg, sx + offX + r, sy + offY + r * 0.8)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
        0.25 * alphaScale))
    nvgStroke(vg)
    -- 对角线 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + offX + r, sy + offY - r * 0.8)
    nvgLineTo(vg, sx + offX - r, sy + offY + r * 0.8)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
        0.25 * alphaScale))
    nvgStroke(vg)
    nvgRestore(vg)
end

--- 水面细节: 3条贝塞尔水纹 + 涟漪环 + 水面光斑
function InkTileRenderer.drawWaterDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local c = InkPalette.azure
    local seed = tile.seed or 0

    -- 水纹线条（增加到 3 条，更密集）
    for i = 1, 3 do
        local offset = (i - 2) * ppu * 0.22
        local flow = t * 0.5 + seed * 0.1
        local waveAmp = ppu * 0.10

        nvgBeginPath(vg)
        local startX = sx - ppu * 0.48
        local startY = sy + offset
        nvgMoveTo(vg, startX, startY)
        nvgBezierTo(vg,
            sx - ppu * 0.15, startY + math.sin(flow + i) * waveAmp,
            sx + ppu * 0.15, startY - math.sin(flow + i * 0.7) * waveAmp,
            sx + ppu * 0.48, startY + math.sin(flow + i * 1.3) * waveAmp * 0.5)
        nvgStrokeWidth(vg, 1.0 + (3 - i) * 0.3)
        nvgStrokeColor(vg, nvgRGBAf(c.r, c.g, c.b, (0.30 - i * 0.05) * alphaScale))
        nvgStroke(vg)
    end

    -- 水面光斑（中心一个微亮椭圆，模拟反光）
    local sparkle = math.sin(t * 2.0 + seed) * 0.08 + 0.12
    nvgBeginPath(vg)
    nvgEllipse(vg, sx + ppu * 0.05, sy - ppu * 0.05,
        ppu * 0.12, ppu * 0.07)
    nvgFillColor(vg, nvgRGBAf(0.85, 0.90, 0.95, sparkle * alphaScale))
    nvgFill(vg)

    nvgRestore(vg)
end

--- 竹林细节: 每格绘制 2-3 根竹竿 + 竹节 + 竹叶簇，形成密竹林
function InkTileRenderer.drawBambooDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)

    local stalkCount = 2 + seed % 2
    local inkS = InkPalette.inkStrong
    local inkM = InkPalette.inkMedium

    for si = 1, stalkCount do
        local hash = (seed * 13 + si * 37) % 100
        local xOff = ((hash % 20) - 10) * ppu * 0.04
        local wind = math.sin(t * 0.8 + seed * 0.5 + si * 1.1) * ppu * 0.03
        local bx = sx + xOff + wind
        local by1 = sy + ppu * 0.72
        local by2 = sy - ppu * 0.72

        nvgBeginPath(vg)
        nvgMoveTo(vg, bx, by1)
        nvgLineTo(vg, bx + wind * 0.6, by2)
        local sw = 2.5 + (hash % 4) * 0.5
        nvgStrokeWidth(vg, sw)
        nvgStrokeColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b, 0.65 * alphaScale))
        nvgStroke(vg)

        local nodeCount = 2 + hash % 2
        for n = 1, nodeCount do
            local nodeY = by1 + (by2 - by1) * n / (nodeCount + 1) + (hash % 5 - 2)
            local nodeX = bx + wind * 0.3 * n / nodeCount
            nvgBeginPath(vg)
            nvgMoveTo(vg, nodeX - sw * 0.9, nodeY)
            nvgLineTo(vg, nodeX + sw * 0.9, nodeY)
            nvgStrokeWidth(vg, 1.2)
            nvgStrokeColor(vg, nvgRGBAf(inkM.r, inkM.g, inkM.b, 0.45 * alphaScale))
            nvgStroke(vg)

            if hash % 3 ~= 0 then
                local leafDir = (n % 2 == 0) and 1 or -1
                local lx = nodeX + leafDir * ppu * 0.12
                local ly = nodeY - ppu * 0.06
                local leafWind = math.sin(t * 1.2 + n * 0.7 + seed) * ppu * 0.015
                nvgBeginPath(vg)
                nvgMoveTo(vg, nodeX, nodeY)
                nvgQuadTo(vg,
                    nodeX + leafDir * ppu * 0.07, nodeY - ppu * 0.10,
                    lx + leafWind, ly)
                nvgStrokeWidth(vg, 1.6)
                nvgStrokeColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b, 0.50 * alphaScale))
                nvgStroke(vg)
            end
        end
    end
    nvgRestore(vg)
end

--- 瘴气细节: 朱砂散点 + 毒雾漩涡 + 警告符号
function InkTileRenderer.drawDangerDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    local cin = InkPalette.cinnabar
    local miasma = InkPalette.miasmaLight

    -- 底层暗红漩涡弧线（旋转的瘴气）
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local swirl = t * 0.6 + seed * 0.3
    for i = 1, 2 do
        local startA = swirl + (i - 1) * math.pi
        local arcR = ppu * (0.20 + i * 0.08)
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, arcR, startA, startA + math.pi * 0.8, NVG_CW)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(miasma.r, miasma.g, miasma.b,
            (0.25 - i * 0.05) * alphaScale))
        nvgStroke(vg)
    end
    nvgRestore(vg)

    -- 3-4个散落朱砂墨点（加大加浓）
    for i = 1, 3 + seed % 2 do
        local hash = (seed * 3 + i * 17) % 100
        local dx = (hash % 24 - 12) * ppu * 0.03
        local dy = ((hash * 7) % 24 - 12) * ppu * 0.03
        BrushStrokes.inkDotStable(vg, sx + dx, sy + dy,
            2.0 + hash % 3, cin, 0.22 * alphaScale, hash)
    end

    -- 中心朱砂警告点（脉冲闪烁）
    local pulse = math.sin(t * 3.0 + seed) * 0.15 + 0.35
    BrushStrokes.inkDotStable(vg, sx, sy, 3.0, cin, pulse * alphaScale, seed + 99)
end

------------------------------------------------------------
-- 坐标抖动：打破网格死板感
------------------------------------------------------------

--- 计算瓦片渲染中心的抖动偏移（确定性，不用random）
function InkTileRenderer.jitter(gx, gy, ppu)
    -- 基于格子坐标的伪随机偏移（±0.125 ppu），打破网格排列
    local hash = (gx * 73 + gy * 137) % 1000
    local jx = ((hash % 100) / 100 - 0.5) * ppu * 0.25
    local jy = (((hash * 7) % 100) / 100 - 0.5) * ppu * 0.25
    return jx, jy
end

------------------------------------------------------------
-- 兼容旧接口（单遍渲染，低画质回退用）
------------------------------------------------------------

function InkTileRenderer.drawTile(vg, tile, sx, sy, ppu, t, fogState)
    InkTileRenderer.drawBase(vg, tile, sx, sy, ppu, t, fogState)
    InkTileRenderer.drawDetail(vg, tile, sx, sy, ppu, t, fogState)
end

return InkTileRenderer
