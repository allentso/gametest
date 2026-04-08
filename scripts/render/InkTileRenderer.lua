--- 水墨瓦片渲染 - 双遍渲染体系：色块层 + 细节层
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local FogOfWar = require("systems.FogOfWar")
local Config = require("Config")

local InkTileRenderer = {}

------------------------------------------------------------
-- Pass 1: 色块层 — 大半径低 alpha 底色晕染，让相邻瓦片自然渗透
------------------------------------------------------------

--- 每种地形的底色配置 { color, innerR, outerR, alpha }
--- outerR 拉到 1.4~1.6 倍 ppu，确保相邻瓦片充分重叠消除网格感
local BASE_WASH = {
    grass  = function(P) return P.jade,     0.05, 1.50, 0.10 end,
    rock   = function(P) return P.inkMedium, 0.08, 1.40, 0.12 end,
    water  = function(P) return P.azure,    0.05, 1.55, 0.10 end,
    path   = function(P) return { r = 0.60, g = 0.50, b = 0.35 }, 0.05, 1.40, 0.07 end,
    bamboo = function(P) return P.jade,     0.05, 1.45, 0.08 end,
    danger = function(P) return P.miasmaDark, 0.05, 1.45, 0.10 end,
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
        baseAlpha = baseAlpha + math.sin(t * 2.5 + (tile.seed or 0) * 0.3) * 0.05
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
    elseif tile.type == "bamboo" then
        InkTileRenderer.drawBambooDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    elseif tile.type == "danger" then
        InkTileRenderer.drawDangerDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    end
    -- path: 极淡融入宣纸，无额外笔触

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

--- 岩石细节: 皴法纹理（减少笔画数量，加大区域）
function InkTileRenderer.drawRockDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local cunCount = math.min(4, tile.cunCount or 4)  -- 最多 4 笔，不再 6-8
    BrushStrokes.cunTexture(vg, sx, sy, ppu * 0.60,
        InkPalette.inkStrong, 0.18 * alphaScale, tile.seed or 0, cunCount)
end

--- 水面细节: 2条贝塞尔水纹 + 波纹扩展到邻格
function InkTileRenderer.drawWaterDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local c = InkPalette.azure
    local seed = tile.seed or 0

    for i = 1, 2 do
        local offset = (i - 1.5) * ppu * 0.25
        local flow = t * 0.4 + seed * 0.1
        local waveAmp = ppu * 0.08

        nvgBeginPath(vg)
        local startX = sx - ppu * 0.45  -- 超出格子边界
        local startY = sy + offset
        nvgMoveTo(vg, startX, startY)
        nvgBezierTo(vg,
            sx - ppu * 0.12, startY + math.sin(flow + i) * waveAmp,
            sx + ppu * 0.12, startY - math.sin(flow + i * 0.7) * waveAmp,
            sx + ppu * 0.45, startY + math.sin(flow + i * 1.3) * waveAmp * 0.5)
        nvgStrokeWidth(vg, 0.8 + i * 0.3)
        nvgStrokeColor(vg, nvgRGBAf(c.r, c.g, c.b, (0.20 - i * 0.03) * alphaScale))
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

--- 竹林细节: 隔格绘制 1 根竹竿 + 少量竹节，避免密集阵列感
function InkTileRenderer.drawBambooDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    -- 只有约 60% 的竹林格子画竹竿（稀疏化）
    if seed % 5 < 2 then return end

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)

    -- 只画 1 根竹竿
    local xOff = ((seed * 7) % 10 - 5) * ppu * 0.03
    local wind = math.sin(t * 0.8 + seed * 0.5) * ppu * 0.025
    local bx = sx + xOff + wind
    local by1 = sy + ppu * 0.65   -- 超出格子下边
    local by2 = sy - ppu * 0.65   -- 超出格子上边

    nvgBeginPath(vg)
    nvgMoveTo(vg, bx, by1)
    nvgLineTo(vg, bx + wind * 0.5, by2)
    nvgStrokeWidth(vg, 1.8 + (seed % 3) * 0.4)
    nvgStrokeColor(vg, nvgRGBAf(
        InkPalette.inkStrong.r, InkPalette.inkStrong.g, InkPalette.inkStrong.b,
        0.35 * alphaScale))
    nvgStroke(vg)

    -- 竹节：1~2 个
    local nodeCount = 1 + seed % 2
    for n = 1, nodeCount do
        local nodeY = by1 + (by2 - by1) * n / (nodeCount + 1) + (seed % 5 - 2)
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx - 2.5, nodeY)
        nvgLineTo(vg, bx + 2.5, nodeY)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(
            InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b,
            0.25 * alphaScale))
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

--- 瘴气细节: 朱砂散点 + 暗色微尘
function InkTileRenderer.drawDangerDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    -- 2-3个散落朱砂墨点
    for i = 1, 2 + seed % 2 do
        local hash = (seed * 3 + i * 17) % 100
        local dx = (hash % 20 - 10) * ppu * 0.03
        local dy = ((hash * 7) % 20 - 10) * ppu * 0.03
        BrushStrokes.inkDotStable(vg, sx + dx, sy + dy,
            1.5 + hash % 2, InkPalette.cinnabar, 0.14 * alphaScale, hash)
    end
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
