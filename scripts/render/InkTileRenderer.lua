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
    if not tile then return end
    if fogState == FogOfWar.DARK then return end

    -- 边界墙：浓墨填充，形成地图边框
    if tile.type == "wall" then
        BrushStrokes.inkWash(vg, sx, sy, ppu * 0.05, ppu * 0.75,
            InkPalette.inkDark, 0.85)
        return
    end

    local alphaScale = fogState == FogOfWar.EXPLORED and 0.30 or 1.0
    local fn = BASE_WASH[tile.type]
    if not fn then return end

    local color, innerMul, outerMul, baseAlpha = fn(InkPalette)

    -- 不可通行地形底色加深 40%
    if tile.blocked then
        baseAlpha = baseAlpha * 1.4
    end

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
    if not tile then return end
    if fogState == FogOfWar.DARK then return end

    -- 边界墙：厚重皴纹 + 裂痕线
    if tile.type == "wall" then
        InkTileRenderer.drawWallDetail(vg, tile, sx, sy, ppu, t,
            fogState == FogOfWar.EXPLORED and 0.30 or 1.0)
        return
    end

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

--- 岩石细节（3/4侧面）: 可通行=散碎卵石 / 不可通行=侧面嶙峋山石
function InkTileRenderer.drawRockDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    local inkS = InkPalette.inkStrong
    local inkM = InkPalette.inkMedium

    if tile.blocked then
        local hash = seed * 7 % 100
        -- 侧面巨石轮廓：从底部隆起的山石剪影
        -- 底线在瓦片下半部，顶部随机起伏
        local baseY = sy + ppu * 0.35
        local peakY = sy - ppu * (0.30 + (hash % 20) / 100)
        local leftX  = sx - ppu * 0.40
        local rightX = sx + ppu * 0.40
        local midX = sx + (hash % 10 - 5) * ppu * 0.02

        nvgBeginPath(vg)
        nvgMoveTo(vg, leftX, baseY)
        -- 左坡（贝塞尔弧线上升到顶）
        nvgBezierTo(vg,
            leftX + ppu * 0.08, baseY - ppu * 0.15,
            midX - ppu * 0.15, peakY + ppu * 0.05,
            midX, peakY)
        -- 右坡（贝塞尔弧线下降到底）
        nvgBezierTo(vg,
            midX + ppu * 0.12, peakY + ppu * 0.03,
            rightX - ppu * 0.05, baseY - ppu * 0.10,
            rightX, baseY)
        nvgClosePath(vg)
        -- 填充+描边
        nvgFillColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b, 0.25 * alphaScale))
        nvgFill(vg)
        nvgStrokeWidth(vg, 2.0)
        nvgStrokeColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b, 0.55 * alphaScale))
        nvgStroke(vg)

        -- 皴法纹理（在石体内部）
        local cunCount = math.min(6, (tile.cunCount or 4) + 1)
        BrushStrokes.cunTexture(vg, sx, sy - ppu * 0.05, ppu * 0.35,
            inkS, 0.30 * alphaScale, seed, cunCount)

        -- 横向裂隙线（山石层理）
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        for i = 1, 2 do
            local crackY = baseY + (peakY - baseY) * (0.3 + i * 0.25)
            local crackX1 = sx - ppu * (0.15 + (hash % 8) / 100)
            local crackX2 = sx + ppu * (0.12 + ((hash * 3) % 8) / 100)
            nvgBeginPath(vg)
            nvgMoveTo(vg, crackX1, crackY + (hash % 3) - 1)
            nvgLineTo(vg, crackX2, crackY)
            nvgStrokeWidth(vg, 0.8 + (i % 2) * 0.4)
            nvgStrokeColor(vg, nvgRGBAf(InkPalette.inkWash.r, InkPalette.inkWash.g,
                InkPalette.inkWash.b, 0.28 * alphaScale))
            nvgStroke(vg)
        end
        nvgRestore(vg)
    else
        -- 可通行碎岩：地面小卵石 + 轻微皴纹
        local cunCount = math.min(3, tile.cunCount or 3)
        BrushStrokes.cunTexture(vg, sx, sy + ppu * 0.1, ppu * 0.35,
            inkM, 0.15 * alphaScale, seed, cunCount)
        for i = 1, 3 do
            local hash = (seed * 11 + i * 31) % 100
            local dx = (hash % 20 - 10) * ppu * 0.03
            local dy = ((hash * 3) % 14 - 4) * ppu * 0.03 + ppu * 0.15
            local r = 1.0 + hash % 2
            nvgBeginPath(vg)
            nvgEllipse(vg, sx + dx, sy + dy, r * 1.2, r * 0.8)
            nvgFillColor(vg, nvgRGBAf(inkM.r, inkM.g, inkM.b, 0.22 * alphaScale))
            nvgFill(vg)
        end
    end
end

--- 小路细节: 暖色路面 + 行人踏痕 + 两侧碎草边缘
function InkTileRenderer.drawPathDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    local pathC = PATH_COLOR
    nvgSave(vg)

    -- 路面暖色带状填充（明确的行走路径感）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx - ppu * 0.30, sy - ppu * 0.45,
        ppu * 0.60, ppu * 0.90, ppu * 0.10)
    nvgFillColor(vg, nvgRGBAf(pathC.r, pathC.g, pathC.b, 0.10 * alphaScale))
    nvgFill(vg)

    -- 踏痕足迹（暖色椭圆，沿路面方向排列）
    for i = 1, 2 + seed % 2 do
        local hash = (seed * 11 + i * 23) % 100
        local dx = (hash % 16 - 8) * ppu * 0.015
        local dy = (i - 1.5) * ppu * 0.28
        nvgBeginPath(vg)
        nvgEllipse(vg, sx + dx, sy + dy,
            ppu * 0.07, ppu * 0.04)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkWash.r, InkPalette.inkWash.g, InkPalette.inkWash.b,
            0.20 * alphaScale))
        nvgFill(vg)
    end

    -- 路边碎草（两侧轻微的绿色弧线暗示草地边缘）
    local jade = InkPalette.jade
    for side = -1, 1, 2 do
        local edgeX = sx + side * ppu * 0.28
        local hash = (seed * 7 + side * 41) % 100
        nvgBeginPath(vg)
        nvgMoveTo(vg, edgeX, sy + ppu * 0.25)
        nvgQuadTo(vg,
            edgeX + side * ppu * 0.06, sy,
            edgeX, sy - ppu * 0.25)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(jade.r, jade.g, jade.b, 0.15 * alphaScale))
        nvgStroke(vg)
    end

    -- 散落卵石点
    for i = 1, 2 do
        local hash = (seed * 7 + i * 41) % 100
        local dx = (hash % 16 - 8) * ppu * 0.02
        local dy = ((hash * 5) % 16 - 8) * ppu * 0.02
        nvgBeginPath(vg)
        nvgCircle(vg, sx + dx, sy + dy, 0.8 + hash % 2 * 0.4)
        nvgFillColor(vg, nvgRGBAf(
            InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b,
            0.18 * alphaScale))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

--- 水面细节: 多层水纹 + 涟漪 + 水雾 + 光斑（始终不可通行）
function InkTileRenderer.drawWaterDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local c = InkPalette.azure
    local seed = tile.seed or 0

    -- 水面底色填充（半透明蓝色圆形，让水域一眼可辨）
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, ppu * 0.48)
    nvgFillColor(vg, nvgRGBAf(c.r, c.g, c.b, 0.12 * alphaScale))
    nvgFill(vg)

    -- 4 条贝塞尔水纹（密集波浪感）
    for i = 1, 4 do
        local offset = (i - 2.5) * ppu * 0.18
        local flow = t * 0.5 + seed * 0.1
        local waveAmp = ppu * (0.08 + i * 0.02)

        nvgBeginPath(vg)
        local startX = sx - ppu * 0.48
        local startY = sy + offset
        nvgMoveTo(vg, startX, startY)
        nvgBezierTo(vg,
            sx - ppu * 0.15, startY + math.sin(flow + i) * waveAmp,
            sx + ppu * 0.15, startY - math.sin(flow + i * 0.7) * waveAmp,
            sx + ppu * 0.48, startY + math.sin(flow + i * 1.3) * waveAmp * 0.5)
        nvgStrokeWidth(vg, 1.2 + (4 - i) * 0.3)
        nvgStrokeColor(vg, nvgRGBAf(c.r, c.g, c.b, (0.35 - i * 0.05) * alphaScale))
        nvgStroke(vg)
    end

    -- 涟漪环（缓慢扩散的同心圆）
    local rippleT = (t * 0.3 + seed * 0.7) % 1.0
    local rippleR = ppu * (0.10 + rippleT * 0.30)
    local rippleA = (1.0 - rippleT) * 0.20
    nvgBeginPath(vg)
    nvgCircle(vg, sx + ppu * 0.08, sy - ppu * 0.05, rippleR)
    nvgStrokeWidth(vg, 0.8)
    nvgStrokeColor(vg, nvgRGBAf(c.r, c.g, c.b, rippleA * alphaScale))
    nvgStroke(vg)

    -- 水面光斑（改为淡蓝微光弧线，不画中心白点）
    local sparkle = math.sin(t * 2.0 + seed) * 0.08 + 0.12
    nvgBeginPath(vg)
    nvgArc(vg, sx + ppu * 0.05, sy - ppu * 0.04,
        ppu * 0.18, -0.6, 0.6, NVG_CW)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(c.r, c.g + 0.08, c.b + 0.06, sparkle * alphaScale))
    nvgStroke(vg)

    -- 水雾效果（淡墨飘渺边缘）
    BrushStrokes.inkWash(vg, sx, sy - ppu * 0.25, ppu * 0.20, ppu * 0.55,
        InkPalette.inkWash, 0.10 * alphaScale)

    nvgRestore(vg)
end

--- 竹林细节（3/4侧面）: 可通行=稀疏竹竿 / 不可通行=密竹丛
--- 侧面视角：竖直竹竿 + 竹节 + 侧展竹叶
function InkTileRenderer.drawBambooDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    local inkS = InkPalette.inkStrong
    local inkM = InkPalette.inkMedium
    local jade = InkPalette.jade

    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)

    local stalkCount, stalkAlpha, stalkW, leafPerNode
    if tile.blocked then
        stalkCount = 4 + seed % 2
        stalkAlpha = 0.72
        stalkW = 3.0
        leafPerNode = 2
        BrushStrokes.inkWash(vg, sx, sy, ppu * 0.05, ppu * 0.50,
            jade, 0.18 * alphaScale)
    else
        stalkCount = 1 + seed % 2
        stalkAlpha = 0.42
        stalkW = 2.0
        leafPerNode = 1
    end

    for si = 1, stalkCount do
        local hash = (seed * 13 + si * 37) % 100
        local spread = tile.blocked and 0.06 or 0.04
        local xOff = ((hash % 20) - 10) * ppu * spread
        local wind = math.sin(t * 0.8 + seed * 0.5 + si * 1.1) * ppu * 0.03
        local bx = sx + xOff + wind
        -- 竹竿从底部长到顶部（侧面视角）
        local footY = sy + ppu * 0.48
        local tipY  = sy - ppu * (tile.blocked and 0.72 or 0.55)

        -- 竹竿主干
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx, footY)
        nvgLineTo(vg, bx + wind * 0.6, tipY)
        local sw = stalkW + (hash % 3) * 0.4
        nvgStrokeWidth(vg, sw)
        nvgStrokeColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b, stalkAlpha * alphaScale))
        nvgStroke(vg)

        -- 竹节（2-3 个横纹）
        local nodeCount = tile.blocked and (2 + hash % 2) or (1 + hash % 2)
        for n = 1, nodeCount do
            local frac = n / (nodeCount + 1)
            local nodeY = footY + (tipY - footY) * frac + (hash % 5 - 2)
            local nodeX = bx + wind * 0.3 * frac
            nvgBeginPath(vg)
            nvgMoveTo(vg, nodeX - sw * 0.9, nodeY)
            nvgLineTo(vg, nodeX + sw * 0.9, nodeY)
            nvgStrokeWidth(vg, 1.2)
            nvgStrokeColor(vg, nvgRGBAf(inkM.r, inkM.g, inkM.b, 0.45 * alphaScale))
            nvgStroke(vg)

            -- 从竹节处长出侧叶
            for li = 1, leafPerNode do
                local leafDir = ((n + li) % 2 == 0) and 1 or -1
                local leafWind = math.sin(t * 1.2 + n * 0.7 + seed + li) * ppu * 0.015
                local lTipX = nodeX + leafDir * ppu * 0.18 + leafWind
                local lTipY = nodeY - ppu * 0.08
                nvgBeginPath(vg)
                nvgMoveTo(vg, nodeX, nodeY)
                nvgQuadTo(vg,
                    nodeX + leafDir * ppu * 0.10, nodeY - ppu * 0.12,
                    lTipX, lTipY)
                nvgStrokeWidth(vg, tile.blocked and 1.8 or 1.2)
                nvgStrokeColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b,
                    (tile.blocked and 0.55 or 0.30) * alphaScale))
                nvgStroke(vg)
            end
        end

        -- 竹竿顶部叶簇（2-3 笔向外伸展的弧线）
        local topLeafCount = tile.blocked and 3 or 2
        for li = 1, topLeafCount do
            local dir = (li % 2 == 0) and 1 or -1
            local leafWind = math.sin(t * 1.0 + si * 0.9 + li * 1.3) * ppu * 0.02
            local tipLX = bx + wind * 0.6 + dir * ppu * 0.15 + leafWind
            local tipLY = tipY - ppu * 0.06 * li
            nvgBeginPath(vg)
            nvgMoveTo(vg, bx + wind * 0.6, tipY)
            nvgQuadTo(vg,
                bx + wind * 0.6 + dir * ppu * 0.08, tipY - ppu * 0.05,
                tipLX, tipLY)
            nvgStrokeWidth(vg, tile.blocked and 1.6 or 1.0)
            nvgStrokeColor(vg, nvgRGBAf(inkS.r, inkS.g, inkS.b,
                (tile.blocked and 0.48 or 0.25) * alphaScale))
            nvgStroke(vg)
        end
    end

    -- 不可通行密竹：底部灌木横线
    if tile.blocked then
        for i = 1, 3 do
            local hash = (seed * 7 + i * 19) % 100
            local bsx = sx + (hash % 20 - 10) * ppu * 0.04
            local bsy = sy + ppu * 0.40
            nvgBeginPath(vg)
            nvgMoveTo(vg, bsx - ppu * 0.18, bsy)
            nvgQuadTo(vg, bsx, bsy - ppu * 0.06, bsx + ppu * 0.18, bsy + ppu * 0.02)
            nvgStrokeWidth(vg, 1.4)
            nvgStrokeColor(vg, nvgRGBAf(inkM.r, inkM.g, inkM.b, 0.30 * alphaScale))
            nvgStroke(vg)
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

--- 边界墙细节（3/4侧面）: 崖壁层理 + 皴法纹理
function InkTileRenderer.drawWallDetail(vg, tile, sx, sy, ppu, t, alphaScale)
    local seed = tile.seed or 0
    local inkD = InkPalette.inkDark
    local inkS = InkPalette.inkStrong
    local inkM = InkPalette.inkMedium

    -- 横向层理线（岩层纹路，侧面崖壁感）
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 4 do
        local hash = (seed * 7 + i * 23) % 100
        local ly = sy + (i - 2.5) * ppu * 0.22 + (hash % 6 - 3)
        local lx1 = sx - ppu * 0.48
        local lx2 = sx + ppu * 0.48
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx1, ly)
        nvgLineTo(vg, lx2, ly + (hash % 4 - 2))
        nvgStrokeWidth(vg, 1.0 + (hash % 3) * 0.3)
        nvgStrokeColor(vg, nvgRGBAf(inkM.r, inkM.g, inkM.b,
            (0.30 + (hash % 10) / 100) * alphaScale))
        nvgStroke(vg)
    end
    nvgRestore(vg)

    -- 皴法纹理（密集）
    BrushStrokes.cunTexture(vg, sx, sy, ppu * 0.50,
        inkD, 0.40 * alphaScale, seed, 7)
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
