--- 异兽水墨绘制 v3.0 — 24 只异兽白描骨架体系
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")

local BeastRenderer = {}
BeastRenderer.shapes = {}

------------------------------------------------------------
-- 白描原语
------------------------------------------------------------

local function drawWhiteSketch(vg, pts, cx, cy, color, fillAlpha, strokeAlpha, strokeW, seed)
    seed = seed or 0
    strokeW = strokeW or 1.2
    local n = #pts
    if n < 3 then return end

    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + pts[1][1], cy + pts[1][2])
    for i = 2, n do
        local prev = pts[i - 1]
        local curr = pts[i]
        local mx = (prev[1] + curr[1]) * 0.5
        local my = (prev[2] + curr[2]) * 0.5
        nvgQuadTo(vg, cx + prev[1], cy + prev[2], cx + mx, cy + my)
    end
    local last = pts[n]
    local first = pts[1]
    local mx = (last[1] + first[1]) * 0.5
    local my = (last[2] + first[2]) * 0.5
    nvgQuadTo(vg, cx + last[1], cy + last[2], cx + mx, cy + my)
    nvgClosePath(vg)

    if fillAlpha > 0 then
        nvgFillColor(vg, nvgRGBAf(color.r, color.g, color.b, fillAlpha))
        nvgFill(vg)
    end

    if strokeAlpha > 0 then
        nvgLineCap(vg, NVG_ROUND)
        nvgLineJoin(vg, NVG_ROUND)
        for i = 1, n do
            local p1 = pts[i]
            local p2 = pts[i % n + 1]
            local hash = (seed * 7 + i * 31) % 100
            if hash > 10 then
                local thickVar = 1.0 + ((hash % 40) - 20) / 100
                nvgBeginPath(vg)
                nvgMoveTo(vg, cx + p1[1], cy + p1[2])
                nvgLineTo(vg, cx + p2[1], cy + p2[2])
                nvgStrokeWidth(vg, strokeW * thickVar)
                nvgStrokeColor(vg, nvgRGBAf(color.r, color.g, color.b, strokeAlpha))
                nvgStroke(vg)
            end
        end
    end
end

------------------------------------------------------------
-- 主绘制入口
------------------------------------------------------------

function BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
    local r = (beast.bodySize or 0.55) * ppu
    local qColor = InkPalette.qualColor(beast.quality)

    local breathe = 1.0 + math.sin(t * math.pi * 2 / 0.8) * 0.03
    nvgSave(vg)
    nvgTranslate(vg, sx, sy)
    nvgScale(vg, breathe, breathe)
    nvgTranslate(vg, -sx, -sy)

    BeastRenderer.drawQualityGlow(vg, beast.quality, sx, sy, r, qColor, t)
    BeastRenderer.drawFacingCone(vg, beast, sx, sy, r, t)

    local shapeFn = BeastRenderer.shapes[beast.type]
    if shapeFn then
        shapeFn(vg, sx, sy, r, t, beast)
    else
        BeastRenderer.drawDefaultShape(vg, sx, sy, r, t, beast)
    end

    if beast.aiState == "alert" then
        BeastRenderer.drawAlertMark(vg, sx, sy, r, t)
    elseif beast.aiState == "warn" then
        BeastRenderer.drawWarnMark(vg, sx, sy, r, t)
    elseif beast.aiState == "chase" then
        BeastRenderer.drawChaseMark(vg, sx, sy, r, t)
    elseif beast.aiState == "stunned" or beast.aiState == "frozen" then
        BeastRenderer.drawStunnedMark(vg, sx, sy, r, t)
    elseif beast.aiState == "flee" then
        BeastRenderer.drawSpeedLines(vg, beast, sx, sy, r, t)
    end

    local beastHP = beast.combatHP or beast.hp
    local beastMaxHP = beast.combatMaxHP or beast.maxHP
    if beastHP and beastMaxHP and beastHP < beastMaxHP and beastHP > 0 then
        BeastRenderer.drawBeastHPBar(vg, beast, sx, sy, r, beastHP, beastMaxHP)
    end

    if beast.aiState == "attack" and beast.attackTimer and beast.attackTimer > 0 then
        BeastRenderer.drawAttackWarning(vg, beast, sx, sy, r, ppu, t)
    end

    nvgRestore(vg)
end

------------------------------------------------------------
-- 共用绘制辅助（品质光晕/朝向锥/状态标记/HP条/攻击预警）
------------------------------------------------------------

function BeastRenderer.drawQualityGlow(vg, quality, sx, sy, r, color, t)
    if quality == "R" then return end
    if quality == "SR" then
        local pulse = 1.0 + math.sin(t * 2) * 0.08
        BrushStrokes.inkWash(vg, sx, sy, r * 0.8 * pulse, r * 2.0 * pulse, color, 0.12)
    elseif quality == "SSR" then
        for i = 1, 3 do
            local scale = 1.0 + (i - 1) * 0.4
            local pulse = 1.0 + math.sin(t * 2 + i * 0.7) * 0.06
            BrushStrokes.inkWash(vg, sx, sy,
                r * scale * pulse, r * (scale + 0.8) * pulse,
                color, 0.10 - (i - 1) * 0.02)
        end
        for i = 1, 6 do
            local angle = (i / 6) * math.pi * 2 + t * 2.0
            local dist = r * 2.2 + math.sin(t * 3 + i * 1.2) * r * 0.3
            local px = sx + math.cos(angle) * dist
            local py = sy + math.sin(angle) * dist
            BrushStrokes.inkDotStable(vg, px, py, 1.5, InkPalette.gold, 0.30, i * 7)
        end
    end
end

function BeastRenderer.drawFacingCone(vg, beast, sx, sy, r, t)
    local facing = beast.facing or 0
    local coneAngle = math.pi / 3
    local coneR = r * 2.5
    local alpha = 0.07 + math.sin(t * 1.5) * 0.02
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy)
    nvgArc(vg, sx, sy, coneR, -facing - coneAngle, -facing + coneAngle, NVG_CW)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(InkPalette.inkLight.r, InkPalette.inkLight.g, InkPalette.inkLight.b, alpha))
    nvgFill(vg)
    nvgRestore(vg)
end

function BeastRenderer.drawDefaultShape(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local seed = beast.facing and math.floor(beast.facing * 100) or 0
    local pts = {}
    for i = 1, 6 do
        local angle = (i - 1) / 6 * math.pi * 2 - math.pi / 2
        local hash = (seed * 7 + i * 31) % 100
        local rVar = r * (0.55 + hash / 300)
        table.insert(pts, { math.cos(angle) * rVar, math.sin(angle) * rVar * 0.75 })
    end
    drawWhiteSketch(vg, pts, sx, sy, ink, 0.45, 0.65, 1.2, seed)
    local facing = beast.facing or 0
    local eyeDist = r * 0.3
    local eyeX = sx + math.cos(-facing) * eyeDist
    local eyeY = sy + math.sin(-facing) * eyeDist
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, eyeX, eyeY, r * 0.07)
    nvgFillColor(vg, nvgRGBAf(0.96, 0.93, 0.87, 0.85))
    nvgFill(vg)
    nvgRestore(vg)
end

function BeastRenderer.drawAlertMark(vg, sx, sy, r, t)
    local bounce = math.sin(t * 4) * r * 0.15
    local markY = sy - r * 1.5 + bounce
    nvgSave(vg)
    nvgFontSize(vg, r * 1.5)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.90))
    nvgText(vg, sx, markY, "!")
    nvgRestore(vg)
end

function BeastRenderer.drawSpeedLines(vg, beast, sx, sy, r, t)
    local facing = beast.facing or 0
    local backAngle = facing + math.pi
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 3 do
        local spread = (i - 2) * 0.25
        local angle = backAngle + spread
        local len = r * (1.2 - i * 0.2)
        local startX = sx + math.cos(-angle) * r * 0.6
        local startY = sy + math.sin(-angle) * r * 0.6
        local endX = startX + math.cos(-angle) * len
        local endY = startY + math.sin(-angle) * len
        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, startY)
        nvgLineTo(vg, endX, endY)
        nvgStrokeWidth(vg, 1.2 - i * 0.2)
        nvgStrokeColor(vg, nvgRGBAf(InkPalette.inkMedium.r, InkPalette.inkMedium.g, InkPalette.inkMedium.b, 0.45 - i * 0.12))
        nvgStroke(vg)
    end
    nvgRestore(vg)
end

function BeastRenderer.drawWarnMark(vg, sx, sy, r, t)
    local shake = math.sin(t * 6) * r * 0.08
    local markY = sy - r * 1.5 + shake
    local markSize = r * 0.35
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    local ink = InkPalette.inkStrong
    local alpha = 0.75 + math.sin(t * 3) * 0.15
    nvgStrokeWidth(vg, 2.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, alpha))
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - markSize, markY - markSize)
    nvgLineTo(vg, sx + markSize, markY + markSize)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + markSize, markY - markSize)
    nvgLineTo(vg, sx - markSize, markY + markSize)
    nvgStroke(vg)
    nvgRestore(vg)
end

function BeastRenderer.drawChaseMark(vg, sx, sy, r, t)
    local markY = sy - r * 1.6
    local flicker = math.sin(t * 8) * r * 0.05
    nvgSave(vg)
    local cin = InkPalette.cinnabar
    local alpha = 0.70 + math.sin(t * 5) * 0.20
    for i = -1, 1 do
        local fx = sx + i * r * 0.15
        local baseY = markY + r * 0.2
        local tipY = markY - r * 0.25 + flicker * (1 + math.abs(i) * 0.5)
        nvgBeginPath(vg)
        nvgMoveTo(vg, fx - r * 0.08, baseY)
        nvgQuadTo(vg, fx - r * 0.02, markY + r * 0.05, fx, tipY)
        nvgQuadTo(vg, fx + r * 0.02, markY + r * 0.05, fx + r * 0.08, baseY)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, alpha - math.abs(i) * 0.15))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

function BeastRenderer.drawStunnedMark(vg, sx, sy, r, t)
    local markY = sy - r * 1.5
    local bob = math.sin(t * 2) * r * 0.06
    nvgSave(vg)
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    local ink = InkPalette.inkMedium
    for i = 1, 3 do
        local zx = sx + (i - 1) * r * 0.25 - r * 0.15
        local zy = markY - (i - 1) * r * 0.2 + bob * i * 0.3
        nvgFontSize(vg, r * (0.5 + i * 0.15))
        nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55 - (i - 1) * 0.12))
        nvgText(vg, zx, zy, "Z")
    end
    nvgRestore(vg)
end

function BeastRenderer.drawBeastHPBar(vg, beast, sx, sy, r, hp, maxHP)
    local barW = r * 1.6
    local barH = 3
    local barX = sx - barW * 0.5
    local barY = sy + r * 0.8
    local hpFrac = hp / maxHP
    local P = InkPalette
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 1.5)
    nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40))
    nvgFill(vg)
    local fillColor = hpFrac > 0.3 and P.cinnabar or P.gold
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * hpFrac, barH, 1.5)
    nvgFillColor(vg, nvgRGBAf(fillColor.r, fillColor.g, fillColor.b, 0.70))
    nvgFill(vg)
    nvgRestore(vg)
end

function BeastRenderer.drawAttackWarning(vg, beast, sx, sy, r, ppu, t)
    local atk = beast.currentAttack
    if not atk then return end
    local warmup = atk.warmup or 0
    if warmup <= 0 then return end
    local progress = math.min(1.0, 1.0 - (beast.attackTimer or 0) / warmup)
    local flashHz = 3 + progress * 8
    local flash = 0.5 + 0.5 * math.sin(t * flashHz * math.pi * 2)
    local baseAlpha = 0.15 + progress * 0.45
    local facing = beast.facing or 0
    local P = InkPalette
    if atk.aoeType == "line" then
        local range = (atk.range or 3.0) * ppu
        local arrowLen = range * progress
        local dx = math.cos(facing)
        local dy = math.sin(facing)
        local lineAlpha = baseAlpha * flash
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgLineTo(vg, sx + dx * arrowLen, sy + dy * arrowLen)
        nvgStrokeWidth(vg, 2.5 + progress * 2.0)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, lineAlpha))
        nvgStroke(vg)
        if progress > 0.3 then
            local tipX = sx + dx * arrowLen
            local tipY = sy + dy * arrowLen
            local perpX = -dy
            local perpY = dx
            local headSize = (6 + progress * 6)
            nvgBeginPath(vg)
            nvgMoveTo(vg, tipX + dx * headSize, tipY + dy * headSize)
            nvgLineTo(vg, tipX + perpX * headSize * 0.6, tipY + perpY * headSize * 0.6)
            nvgLineTo(vg, tipX - perpX * headSize * 0.6, tipY - perpY * headSize * 0.6)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, lineAlpha * 0.8))
            nvgFill(vg)
        end
        nvgRestore(vg)
    elseif atk.aoeType == "circle" then
        local aoeR = (atk.aoeRadius or 2.0) * ppu
        local expandR = aoeR * progress
        nvgSave(vg)
        local ringAlpha = baseAlpha * flash * 0.7
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, expandR)
        nvgStrokeWidth(vg, 1.5 + progress * 1.5)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, ringAlpha))
        nvgStroke(vg)
        if progress > 0.4 then
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, expandR)
            nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, (progress - 0.4) * 0.15 * flash))
            nvgFill(vg)
        end
        nvgRestore(vg)
    else
        local range = (atk.range or 2.0) * ppu
        local arcHalf = math.rad((atk.arc or 60) / 2)
        local expandRange = range * progress
        nvgSave(vg)
        local arcAlpha = baseAlpha * flash * 0.5
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy)
        nvgArc(vg, sx, sy, expandRange, facing - arcHalf, facing + arcHalf, NVG_CW)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, arcAlpha))
        nvgFill(vg)
        nvgRestore(vg)
    end
    if progress > 0.6 then
        local bangAlpha = (progress - 0.6) / 0.4 * flash * 0.8
        local bangY = sy - r * 1.8
        nvgSave(vg)
        nvgFontSize(vg, r * (1.0 + progress * 0.5))
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, bangAlpha))
        nvgText(vg, sx, bangY, "!")
        nvgRestore(vg)
    end
end

------------------------------------------------------------
-- SSR · 六灵 形态
------------------------------------------------------------

-- 001 烛龙 — 人面蛇身，赤红，竖瞳，极大体型
BeastRenderer.shapes["001"] = function(vg, sx, sy, r, t, beast)
    local cin = InkPalette.cinnabar
    local ink = InkPalette.inkDark
    local wave = math.sin(t * 1.5) * r * 0.18
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 蛇身S形（赤红，极粗）
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 1.0, sy + wave * 0.5)
    nvgBezierTo(vg, sx - r * 0.35, sy - r * 0.5 + wave, sx + r * 0.35, sy + r * 0.5 - wave, sx + r * 1.0, sy - wave * 0.3)
    nvgStrokeWidth(vg, r * 0.4)
    nvgStrokeColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.50))
    nvgStroke(vg)
    -- 人面（头部圆形+五官暗示）
    local headX = sx + r * 0.95
    local headY = sy - wave * 0.3
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, r * 0.28)
    nvgFillColor(vg, nvgRGBAf(cin.r, cin.g, cin.b, 0.40))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgStroke(vg)
    -- 竖瞳
    for side = -1, 1, 2 do
        local ex = headX + side * r * 0.1
        local ey = headY - r * 0.03
        nvgBeginPath(vg)
        nvgEllipse(vg, ex, ey, r * 0.03, r * 0.07)
        nvgFillColor(vg, nvgRGBAf(InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, 0.85))
        nvgFill(vg)
    end
    -- 暗/光双元素气场
    BrushStrokes.inkWash(vg, sx, sy, r * 0.3, r * 2.0, InkPalette.dark, 0.12)
    BrushStrokes.inkWash(vg, headX, headY, r * 0.1, r * 0.6, InkPalette.light, 0.10)
    nvgRestore(vg)
end

-- 002 应龙 — 有翼金龙，鳞甲金褐
BeastRenderer.shapes["002"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local gld = InkPalette.ochre
    local wingFlap = math.sin(t * 2.5) * r * 0.2
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 龙身
    local body = {
        {-r*0.5, r*0.15}, {-r*0.3, -r*0.4}, {r*0.2, -r*0.45},
        {r*0.7, -r*0.2}, {r*0.65, r*0.15}, {r*0.2, r*0.4}, {-r*0.3, r*0.3},
    }
    drawWhiteSketch(vg, body, sx, sy, gld, 0.40, 0.55, 1.4, 102)
    -- 双翼
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 0.15, sy - r * 0.1)
        nvgQuadTo(vg, sx + side * r * 1.0, sy - r * 0.8 - wingFlap, sx + side * r * 1.4, sy - r * 0.2 + wingFlap * 0.5)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBAf(gld.r, gld.g, gld.b, 0.50))
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 1.4, sy - r * 0.2 + wingFlap * 0.5)
        nvgLineTo(vg, sx + side * r * 1.2, sy + r * 0.15)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(gld.r, gld.g, gld.b, 0.35))
        nvgStroke(vg)
    end
    -- 龙角
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + r * 0.55 + side * r * 0.08, sy - r * 0.35)
        nvgLineTo(vg, sx + r * 0.5 + side * r * 0.1, sy - r * 0.65)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
        nvgStroke(vg)
    end
    -- 龙目
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.4
    local ey = sy + math.sin(-facing) * r * 0.2 - r * 0.15
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.06, InkPalette.thunder, 0.80, 12)
    -- 雷电晕光
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 1.0, InkPalette.thunder, 0.08)
    nvgRestore(vg)
end

-- 003 凤凰 — 五彩鸡形
BeastRenderer.shapes["003"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    nvgSave(vg)
    -- 身体
    local body = {
        {r*0.3, -r*0.15}, {r*0.15, -r*0.45}, {-r*0.15, -r*0.45},
        {-r*0.4, -r*0.25}, {-r*0.45, r*0.1}, {-r*0.2, r*0.35},
        {r*0.1, r*0.35}, {r*0.3, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.35, 0.50, 1.3, 103)
    -- 五彩尾羽
    local colors = { InkPalette.cinnabar, InkPalette.gold, InkPalette.jade, InkPalette.azure, InkPalette.indigo }
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 5 do
        local spread = (i - 3) * 0.25
        local sway = math.sin(t * 2 + i * 0.8) * r * 0.08
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - r * 0.4, sy + r * 0.1)
        nvgBezierTo(vg,
            sx - r * 0.8, sy + spread * r + sway,
            sx - r * 1.1, sy + spread * r * 1.5 + sway,
            sx - r * 1.0, sy + spread * r * 2.0 + sway * 1.5)
        nvgStrokeWidth(vg, 1.8 - math.abs(i - 3) * 0.2)
        local c = colors[i]
        nvgStrokeColor(vg, nvgRGBAf(c.r, c.g, c.b, 0.45))
        nvgStroke(vg)
    end
    -- 冠羽
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy - r * 0.45)
    nvgLineTo(vg, sx + r * 0.1, sy - r * 0.75)
    nvgLineTo(vg, sx - r * 0.05, sy - r * 0.7)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.50))
    nvgStroke(vg)
    -- 眼
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.2
    local ey = sy + math.sin(-facing) * r * 0.1 - r * 0.2
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, InkPalette.gold, 0.75, 33)
    -- 五德光晕
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.9, InkPalette.gold, 0.10)
    nvgRestore(vg)
end

-- 004 白泽 — 白毛龙角大犬，澄澈眼神
BeastRenderer.shapes["004"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local P = InkPalette.paper
    nvgSave(vg)
    local body = {
        {-r*0.55, -r*0.35}, {-r*0.1, -r*0.5}, {r*0.45, -r*0.4},
        {r*0.6, -r*0.05}, {r*0.5, r*0.3}, {-r*0.1, r*0.4},
        {-r*0.5, r*0.25}, {-r*0.6, 0},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.25, 0.55, 1.3, 104)
    -- 白毛填充
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy, r * 0.45, r * 0.35)
    nvgFillColor(vg, nvgRGBAf(P.r, P.g, P.b, 0.30))
    nvgFill(vg)
    -- 龙角
    nvgLineCap(vg, NVG_ROUND)
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.1, sy - r * 0.48)
    nvgQuadTo(vg, sx, sy - r * 1.0, sx + r * 0.15, sy - r * 0.85)
    nvgStrokeWidth(vg, 1.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgStroke(vg)
    -- 四肢
    local legs = {{-0.4, 0.35}, {0.3, 0.35}, {-0.35, 0.3}, {0.4, 0.3}}
    for _, l in ipairs(legs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1] * r, sy + l[2] * r)
        nvgLineTo(vg, sx + l[1] * r * 1.1, sy + r * 0.6)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end
    -- 角顶白芒
    local hornPulse = 0.20 + math.sin(t * 2.5) * 0.08
    BrushStrokes.inkWash(vg, sx, sy - r * 0.9, r * 0.05, r * 0.45, P, hornPulse)
    BrushStrokes.inkDotStable(vg, sx, sy - r * 0.9, r * 0.04, P, 0.75, 44)
    -- 澄澈双眼
    local facing = beast.facing or 0
    for side = -1, 1, 2 do
        local ex = sx + math.cos(-facing) * r * 0.3 + side * r * 0.08
        local ey = sy + math.sin(-facing) * r * 0.15 - r * 0.15
        BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, InkPalette.azure, 0.70, 45 + side)
    end
    nvgRestore(vg)
end

-- 005 白虎 — 纯白大虎，王字纹，金爪
BeastRenderer.shapes["005"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local P = InkPalette.paper
    nvgSave(vg)
    -- 虎躯
    local body = {
        {-r*0.6, -r*0.3}, {-r*0.2, -r*0.5}, {r*0.3, -r*0.5},
        {r*0.65, -r*0.2}, {r*0.6, r*0.2}, {r*0.2, r*0.4},
        {-r*0.3, r*0.4}, {-r*0.6, r*0.15},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.20, 0.55, 1.5, 105)
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy, r * 0.5, r * 0.38)
    nvgFillColor(vg, nvgRGBAf(P.r, P.g, P.b, 0.35))
    nvgFill(vg)
    -- 四肢
    nvgLineCap(vg, NVG_ROUND)
    local limbs = {{-0.45,-0.25}, {0.4,-0.2}, {-0.4,0.3}, {0.45,0.3}}
    for _, l in ipairs(limbs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1]*r, sy + l[2]*r)
        nvgLineTo(vg, sx + l[1]*r*1.15, sy + r*0.6)
        nvgStrokeWidth(vg, 2.2)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
        BrushStrokes.inkDotStable(vg, sx + l[1]*r*1.15, sy + r*0.6, r*0.04, InkPalette.goldMetal, 0.60, 50 + _)
    end
    -- 额头"王"字纹
    local hx, hy = sx, sy - r * 0.35
    nvgBeginPath(vg)
    nvgMoveTo(vg, hx - r*0.12, hy - r*0.08)
    nvgLineTo(vg, hx + r*0.12, hy - r*0.08)
    nvgMoveTo(vg, hx - r*0.1, hy)
    nvgLineTo(vg, hx + r*0.1, hy)
    nvgMoveTo(vg, hx - r*0.08, hy + r*0.08)
    nvgLineTo(vg, hx + r*0.08, hy + r*0.08)
    nvgMoveTo(vg, hx, hy - r*0.1)
    nvgLineTo(vg, hx, hy + r*0.1)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.65))
    nvgStroke(vg)
    -- 虎眼
    local facing = beast.facing or 0
    for side = -1, 1, 2 do
        local ex = sx + math.cos(-facing) * r * 0.3 + side * r * 0.1
        local ey = sy + math.sin(-facing) * r * 0.1 - r * 0.25
        BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, InkPalette.goldMetal, 0.80, 55 + side)
    end
    -- 金气晕光
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.8, InkPalette.goldMetal, 0.08)
    nvgRestore(vg)
end

-- 006 麒麟 — 鹿身牛尾马蹄，独角，金光
BeastRenderer.shapes["006"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local gld = InkPalette.gold
    nvgSave(vg)
    -- 鹿身
    local body = {
        {-r*0.45, -r*0.3}, {0, -r*0.5}, {r*0.5, -r*0.35},
        {r*0.55, r*0.1}, {r*0.3, r*0.35}, {-r*0.2, r*0.35},
        {-r*0.5, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.30, 0.50, 1.3, 106)
    -- 金光填充
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy, r * 0.4, r * 0.3)
    nvgFillColor(vg, nvgRGBAf(gld.r, gld.g, gld.b, 0.15))
    nvgFill(vg)
    -- 四蹄
    nvgLineCap(vg, NVG_ROUND)
    local hooves = {{-0.35, 0.3}, {0.3, 0.3}, {-0.3, 0.25}, {0.35, 0.25}}
    for i, h in ipairs(hooves) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + h[1]*r, sy + h[2]*r)
        nvgLineTo(vg, sx + h[1]*r, sy + r*0.6)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end
    -- 独角
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy - r * 0.5)
    nvgLineTo(vg, sx, sy - r * 0.95)
    nvgStrokeWidth(vg, 2.0)
    nvgStrokeColor(vg, nvgRGBAf(gld.r, gld.g, gld.b, 0.55))
    nvgStroke(vg)
    BrushStrokes.inkDotStable(vg, sx, sy - r * 0.95, r * 0.04, gld, 0.70, 66)
    -- 牛尾
    local tailSway = math.sin(t * 2) * r * 0.08
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.45, sy + r * 0.05)
    nvgQuadTo(vg, sx - r * 0.7, sy + r * 0.1 + tailSway, sx - r * 0.65, sy + r * 0.3)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgStroke(vg)
    -- 柔和金光晕
    local pulse = 0.10 + math.sin(t * 2) * 0.04
    BrushStrokes.inkWash(vg, sx, sy, r * 0.3, r * 1.5, gld, pulse)
    nvgRestore(vg)
end

------------------------------------------------------------
-- SR · 十异 形态
------------------------------------------------------------

-- 007 饕餮 — 羊身人面(胸前), 腋下双目
BeastRenderer.shapes["007"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    nvgSave(vg)
    local body = {
        {-r*0.5, -r*0.35}, {0, -r*0.5}, {r*0.5, -r*0.35},
        {r*0.55, r*0.15}, {r*0.3, r*0.4}, {-r*0.3, r*0.4}, {-r*0.55, r*0.15},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.40, 0.55, 1.4, 107)
    -- 胸前人面
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy + r * 0.05, r * 0.18)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.30))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
    nvgStroke(vg)
    -- 虎齿
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r*0.06, sy + r*0.15)
    nvgLineTo(vg, sx - r*0.03, sy + r*0.22)
    nvgMoveTo(vg, sx + r*0.06, sy + r*0.15)
    nvgLineTo(vg, sx + r*0.03, sy + r*0.22)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(InkPalette.paper.r, InkPalette.paper.g, InkPalette.paper.b, 0.70))
    nvgStroke(vg)
    -- 腋下双目
    for side = -1, 1, 2 do
        local ex = sx + side * r * 0.35
        local ey = sy - r * 0.05
        BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, InkPalette.cinnabar, 0.70, 70 + side)
    end
    -- 暗气场
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.8, InkPalette.dark, 0.10)
    nvgRestore(vg)
end

-- 008 穷奇 — 牛形刺猬毛
BeastRenderer.shapes["008"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    nvgSave(vg)
    local body = {
        {-r*0.55, -r*0.3}, {0, -r*0.5}, {r*0.55, -r*0.3},
        {r*0.6, r*0.15}, {r*0.3, r*0.4}, {-r*0.3, r*0.4}, {-r*0.6, r*0.15},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.42, 0.55, 1.4, 108)
    -- 刺猬毛（放射状短线）
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 12 do
        local angle = (i / 12) * math.pi * 2
        local baseR = r * 0.45
        local tipR = r * (0.6 + ((i * 17) % 20) / 100)
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + math.cos(angle) * baseR, sy + math.sin(angle) * baseR * 0.75)
        nvgLineTo(vg, sx + math.cos(angle) * tipR, sy + math.sin(angle) * tipR * 0.75)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
    end
    -- 牛角
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 0.2, sy - r * 0.45)
        nvgQuadTo(vg, sx + side * r * 0.35, sy - r * 0.7, sx + side * r * 0.25, sy - r * 0.75)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
        nvgStroke(vg)
    end
    -- 眼
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.25
    local ey = sy + math.sin(-facing) * r * 0.15 - r * 0.2
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.06, InkPalette.cinnabar, 0.70, 80)
    nvgRestore(vg)
end

-- 009 梼杌 — 似虎似犬，蓬乱长毛，面目模糊
BeastRenderer.shapes["009"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkMedium
    local seed = 109
    nvgSave(vg)
    local body = {
        {-r*0.6, -r*0.3}, {-r*0.2, -r*0.5}, {r*0.3, -r*0.45},
        {r*0.6, -r*0.15}, {r*0.55, r*0.25}, {r*0.1, r*0.4},
        {-r*0.3, r*0.35}, {-r*0.55, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.45, 0.50, 1.6, seed)
    -- 蓬乱毛发（放射弧线）
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 10 do
        local angle = (i / 10) * math.pi * 2
        local dist = r * 0.4
        local len = r * (0.2 + ((seed * 3 + i * 19) % 30) / 100)
        local sway = math.sin(t * 2 + i) * r * 0.03
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + math.cos(angle) * dist, sy + math.sin(angle) * dist * 0.8)
        nvgLineTo(vg, sx + math.cos(angle) * (dist + len) + sway, sy + math.sin(angle) * (dist + len) * 0.8)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.30))
        nvgStroke(vg)
    end
    -- 面目模糊（墨晕遮蔽面部区域）
    BrushStrokes.inkWash(vg, sx + r * 0.15, sy - r * 0.2, r * 0.1, r * 0.3, ink, 0.25)
    -- 暗气场
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.9, InkPalette.dark, 0.08)
    nvgRestore(vg)
end

-- 010 混沌 — 黄囊，六足四翼，无面目
BeastRenderer.shapes["010"] = function(vg, sx, sy, r, t, beast)
    local chaos = InkPalette.chaos
    local ink = InkPalette.inkStrong
    nvgSave(vg)
    -- 圆囊身体
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, r * 0.5)
    nvgFillColor(vg, nvgRGBAf(chaos.r, chaos.g, chaos.b, 0.40))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
    nvgStroke(vg)
    -- 六足
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 6 do
        local angle = (i / 6) * math.pi * 2 + t * 0.5
        local sway = math.sin(t * 3 + i * 1.1) * r * 0.04
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + math.cos(angle) * r * 0.45, sy + math.sin(angle) * r * 0.45)
        nvgLineTo(vg, sx + math.cos(angle) * r * 0.75 + sway, sy + math.sin(angle) * r * 0.75)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
    end
    -- 四翼（小弧线）
    for i = 1, 4 do
        local angle = (i / 4) * math.pi * 2 + math.pi / 4
        local flutter = math.sin(t * 4 + i) * r * 0.06
        nvgBeginPath(vg)
        local bx = sx + math.cos(angle) * r * 0.35
        local by = sy + math.sin(angle) * r * 0.35
        nvgMoveTo(vg, bx, by)
        nvgQuadTo(vg, bx + math.cos(angle) * r * 0.3, by + math.sin(angle) * r * 0.3 + flutter,
            bx + math.cos(angle + 0.3) * r * 0.25, by + math.sin(angle + 0.3) * r * 0.25)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(chaos.r, chaos.g, chaos.b, 0.35))
        nvgStroke(vg)
    end
    -- 赤红光晕
    local pulse = 0.12 + math.sin(t * 2) * 0.05
    BrushStrokes.inkWash(vg, sx, sy, r * 0.15, r * 0.7, InkPalette.cinnabar, pulse)
    nvgRestore(vg)
end

-- 011 九婴 — 九头蛇龙
BeastRenderer.shapes["011"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    nvgSave(vg)
    -- 中心躯体
    nvgBeginPath(vg)
    nvgEllipse(vg, sx, sy, r * 0.4, r * 0.35)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.3)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
    nvgStroke(vg)
    -- 九头颈
    local headColors = {
        InkPalette.azure, InkPalette.azure, InkPalette.dark, InkPalette.inkMedium,
        InkPalette.cinnabar, InkPalette.flame, InkPalette.gold, InkPalette.paper,
        InkPalette.goldMetal,
    }
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 9 do
        local angle = (i / 9) * math.pi * 2 - math.pi / 2
        local sway = math.sin(t * 2.5 + i * 0.7) * r * 0.06
        local neckLen = r * 0.55
        local headX = sx + math.cos(angle) * neckLen + sway
        local headY = sy + math.sin(angle) * neckLen * 0.8
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + math.cos(angle) * r * 0.3, sy + math.sin(angle) * r * 0.25)
        nvgLineTo(vg, headX, headY)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
        nvgStroke(vg)
        local c = headColors[i]
        BrushStrokes.inkDotStable(vg, headX, headY, r * 0.06, c, 0.55, 110 + i)
    end
    -- 水火交侵晕光
    BrushStrokes.inkWash(vg, sx - r*0.3, sy, r*0.1, r*0.5, InkPalette.azure, 0.08)
    BrushStrokes.inkWash(vg, sx + r*0.3, sy, r*0.1, r*0.5, InkPalette.cinnabar, 0.08)
    nvgRestore(vg)
end

-- 012 猰貐 — 蛇身人面，灰黑
BeastRenderer.shapes["012"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkDark
    local wave = math.sin(t * 2) * r * 0.12
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 蛇身
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.8, sy + wave)
    nvgBezierTo(vg, sx - r * 0.25, sy - r * 0.35 + wave, sx + r * 0.25, sy + r * 0.35 - wave, sx + r * 0.8, sy - wave * 0.3)
    nvgStrokeWidth(vg, r * 0.3)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
    nvgStroke(vg)
    -- 人面（头部）
    local headX = sx + r * 0.8
    local headY = sy - wave * 0.3
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, r * 0.2)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgStroke(vg)
    -- 扭曲面容（交叉线暗示）
    nvgBeginPath(vg)
    nvgMoveTo(vg, headX - r*0.06, headY - r*0.04)
    nvgLineTo(vg, headX + r*0.06, headY + r*0.04)
    nvgMoveTo(vg, headX + r*0.06, headY - r*0.04)
    nvgLineTo(vg, headX - r*0.06, headY + r*0.04)
    nvgStrokeWidth(vg, 0.8)
    nvgStrokeColor(vg, nvgRGBAf(InkPalette.paper.r, InkPalette.paper.g, InkPalette.paper.b, 0.50))
    nvgStroke(vg)
    -- 暗气场
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.8, ink, 0.10)
    nvgRestore(vg)
end

-- 013 毕方 — 鹤形单足，青身赤纹白喙
BeastRenderer.shapes["013"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local azure = InkPalette.azure
    nvgSave(vg)
    -- 鹤身
    local body = {
        {r*0.2, -r*0.3}, {r*0.05, -r*0.5}, {-r*0.2, -r*0.45},
        {-r*0.35, -r*0.15}, {-r*0.3, r*0.2}, {0, r*0.3}, {r*0.2, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, azure, 0.30, 0.50, 1.3, 113)
    -- 赤色花纹
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 4 do
        local fx = sx + (i / 5 - 0.5) * r * 0.5
        local fy = sy + math.sin(i * 1.5) * r * 0.15
        nvgBeginPath(vg)
        nvgMoveTo(vg, fx - r * 0.05, fy)
        nvgLineTo(vg, fx + r * 0.05, fy + r * 0.03)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.40))
        nvgStroke(vg)
    end
    -- 单足（跳跃感）
    local hop = math.abs(math.sin(t * 3)) * r * 0.05
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy + r * 0.3)
    nvgLineTo(vg, sx, sy + r * 0.7 - hop)
    nvgStrokeWidth(vg, 2.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
    nvgStroke(vg)
    -- 白喙
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + r * 0.2, sy - r * 0.3)
    nvgLineTo(vg, sx + r * 0.4, sy - r * 0.35)
    nvgLineTo(vg, sx + r * 0.2, sy - r * 0.25)
    nvgFillColor(vg, nvgRGBAf(InkPalette.paper.r, InkPalette.paper.g, InkPalette.paper.b, 0.65))
    nvgFill(vg)
    -- 翅膀
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.15, sy - r * 0.1)
    nvgQuadTo(vg, sx - r * 0.6, sy - r * 0.5, sx - r * 0.7, sy - r * 0.1)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(azure.r, azure.g, azure.b, 0.40))
    nvgStroke(vg)
    -- 火焰气场
    BrushStrokes.inkWash(vg, sx, sy + r * 0.5, r * 0.1, r * 0.4, InkPalette.cinnabar, 0.12)
    nvgRestore(vg)
end

-- 014 乘黄 — 金黄狐形，背生弯角
BeastRenderer.shapes["014"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local gld = InkPalette.gold
    nvgSave(vg)
    local body = {
        {-r*0.55, r*0.1}, {-r*0.3, -r*0.35}, {r*0.1, -r*0.4},
        {r*0.6, -r*0.15}, {r*0.55, r*0.15}, {r*0.1, r*0.3}, {-r*0.3, r*0.25},
    }
    drawWhiteSketch(vg, body, sx, sy, gld, 0.35, 0.50, 1.3, 114)
    -- 双耳
    nvgLineCap(vg, NVG_ROUND)
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 0.15, sy - r * 0.35)
        nvgLineTo(vg, sx + side * r * 0.22, sy - r * 0.55)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(gld.r, gld.g, gld.b, 0.50))
        nvgStroke(vg)
    end
    -- 背部弯角
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 0.05, sy - r * 0.35)
        nvgQuadTo(vg, sx + side * r * 0.15, sy - r * 0.65, sx + side * r * 0.25, sy - r * 0.6)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
        nvgStroke(vg)
    end
    -- 尾巴
    local tailSway = math.sin(t * 2.5) * r * 0.08
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.5, sy + r * 0.05)
    nvgBezierTo(vg, sx - r * 0.8, sy - r * 0.1 + tailSway, sx - r * 0.9, sy - r * 0.3 + tailSway, sx - r * 0.7, sy - r * 0.35)
    nvgStrokeWidth(vg, 2.0)
    nvgStrokeColor(vg, nvgRGBAf(gld.r, gld.g, gld.b, 0.40))
    nvgStroke(vg)
    -- 眼
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.3
    local ey = sy + math.sin(-facing) * r * 0.15 - r * 0.1
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, gld, 0.70, 140)
    -- 金光迹
    BrushStrokes.inkWash(vg, sx, sy, r * 0.15, r * 0.6, gld, 0.08)
    nvgRestore(vg)
end

-- 015 文鳐鱼 — 鲤鱼鸟翼，白头红嘴
BeastRenderer.shapes["015"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local azure = InkPalette.azure
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 鱼身
    local body = {
        {-r*0.6, 0}, {-r*0.3, -r*0.3}, {r*0.2, -r*0.3},
        {r*0.55, -r*0.1}, {r*0.55, r*0.1}, {r*0.2, r*0.3},
        {-r*0.3, r*0.3},
    }
    drawWhiteSketch(vg, body, sx, sy, azure, 0.30, 0.50, 1.2, 115)
    -- 苍色纹路
    for i = 1, 5 do
        local fx = sx + (i / 6 - 0.5) * r * 0.8
        local fy = sy + math.sin(i * 2 + t) * r * 0.08
        nvgBeginPath(vg)
        nvgMoveTo(vg, fx, fy - r * 0.1)
        nvgLineTo(vg, fx + r * 0.03, fy + r * 0.1)
        nvgStrokeWidth(vg, 0.7)
        nvgStrokeColor(vg, nvgRGBAf(azure.r, azure.g, azure.b, 0.30))
        nvgStroke(vg)
    end
    -- 鸟翼
    local wingFlap = math.sin(t * 3) * r * 0.12
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx, sy + side * r * 0.1)
        nvgQuadTo(vg, sx - r * 0.3, sy + side * r * 0.5 + wingFlap, sx - r * 0.5, sy + side * r * 0.2)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
    end
    -- 白头
    nvgBeginPath(vg)
    nvgCircle(vg, sx + r * 0.45, sy, r * 0.14)
    nvgFillColor(vg, nvgRGBAf(InkPalette.paper.r, InkPalette.paper.g, InkPalette.paper.b, 0.50))
    nvgFill(vg)
    -- 红嘴
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + r * 0.55, sy - r * 0.03)
    nvgLineTo(vg, sx + r * 0.7, sy)
    nvgLineTo(vg, sx + r * 0.55, sy + r * 0.03)
    nvgFillColor(vg, nvgRGBAf(InkPalette.cinnabar.r, InkPalette.cinnabar.g, InkPalette.cinnabar.b, 0.60))
    nvgFill(vg)
    -- 鱼尾
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.55, sy)
    nvgLineTo(vg, sx - r * 0.8, sy - r * 0.2)
    nvgMoveTo(vg, sx - r * 0.55, sy)
    nvgLineTo(vg, sx - r * 0.8, sy + r * 0.2)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(azure.r, azure.g, azure.b, 0.40))
    nvgStroke(vg)
    nvgRestore(vg)
end

-- 016 九尾狐 — 狐形六尾(SR)
BeastRenderer.shapes["016"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local cin = InkPalette.cinnabar
    nvgSave(vg)
    local body = {
        {-r*0.5, r*0.1}, {-r*0.25, -r*0.35}, {r*0.15, -r*0.4},
        {r*0.6, -r*0.15}, {r*0.55, r*0.15}, {r*0.1, r*0.3}, {-r*0.25, r*0.25},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.40, 0.55, 1.3, 116)
    -- 双耳
    nvgLineCap(vg, NVG_ROUND)
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + side * r * 0.15 + r * 0.2, sy - r * 0.35)
        nvgLineTo(vg, sx + side * r * 0.2 + r * 0.2, sy - r * 0.55)
        nvgStrokeWidth(vg, 1.2)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end
    -- 六条尾巴（SR级别）
    for i = 1, 6 do
        local spread = (i - 3.5) * 0.2
        local sway = math.sin(t * 2 + i * 0.9) * r * 0.1
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - r * 0.45, sy + r * 0.05)
        nvgBezierTo(vg,
            sx - r * 0.8, sy + spread * r + sway,
            sx - r * 1.05, sy + spread * r * 1.3 + sway,
            sx - r * 0.9, sy + spread * r * 1.8 + sway)
        nvgStrokeWidth(vg, 1.8)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
        nvgStroke(vg)
        BrushStrokes.inkDotStable(vg,
            sx - r * 0.9, sy + spread * r * 1.8 + sway,
            r * 0.03, cin, 0.40, 160 + i)
    end
    -- 眼（朱砂）
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.35
    local ey = sy + math.sin(-facing) * r * 0.15 - r * 0.1
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, cin, 0.75, 169)
    -- 暗焰气场
    BrushStrokes.inkWash(vg, sx, sy, r * 0.15, r * 0.6, cin, 0.08)
    nvgRestore(vg)
end

------------------------------------------------------------
-- R · 八兆 形态
------------------------------------------------------------

-- 017 帝江 — 小型混沌幼体
BeastRenderer.shapes["017"] = function(vg, sx, sy, r, t, beast)
    local chaos = InkPalette.chaos
    local ink = InkPalette.inkMedium
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, sx, sy, r * 0.4)
    nvgFillColor(vg, nvgRGBAf(chaos.r, chaos.g, chaos.b, 0.35))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgStroke(vg)
    nvgLineCap(vg, NVG_ROUND)
    for i = 1, 6 do
        local angle = (i / 6) * math.pi * 2 + t * 0.8
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + math.cos(angle) * r * 0.35, sy + math.sin(angle) * r * 0.35)
        nvgLineTo(vg, sx + math.cos(angle) * r * 0.55, sy + math.sin(angle) * r * 0.55)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
        nvgStroke(vg)
    end
    for i = 1, 4 do
        local angle = (i / 4) * math.pi * 2 + math.pi / 4 + t * 0.5
        local flutter = math.sin(t * 4 + i) * r * 0.04
        nvgBeginPath(vg)
        nvgArc(vg, sx, sy, r * 0.35, angle, angle + 0.5, NVG_CW)
        nvgStrokeWidth(vg, 0.8)
        nvgStrokeColor(vg, nvgRGBAf(chaos.r, chaos.g, chaos.b, 0.30))
        nvgStroke(vg)
    end
    BrushStrokes.inkWash(vg, sx, sy, r * 0.1, r * 0.4, InkPalette.cinnabar, 0.08)
    nvgRestore(vg)
end

-- 018 当康 — 小猪形，獠牙
BeastRenderer.shapes["018"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local ochre = InkPalette.ochre
    nvgSave(vg)
    local body = {
        {-r*0.4, -r*0.2}, {0, -r*0.35}, {r*0.4, -r*0.25},
        {r*0.45, r*0.1}, {r*0.25, r*0.3}, {-r*0.25, r*0.3}, {-r*0.45, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ochre, 0.35, 0.50, 1.2, 118)
    -- 短腿
    nvgLineCap(vg, NVG_ROUND)
    local legs = {{-0.3, 0.25}, {0.2, 0.25}, {-0.25, 0.2}, {0.25, 0.2}}
    for _, l in ipairs(legs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1]*r, sy + l[2]*r)
        nvgLineTo(vg, sx + l[1]*r, sy + r*0.45)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
    end
    -- 獠牙
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx + r*0.3, sy - r*0.15)
    nvgLineTo(vg, sx + r*0.35, sy - r*0.3)
    nvgMoveTo(vg, sx + r*0.35, sy - r*0.1)
    nvgLineTo(vg, sx + r*0.42, sy - r*0.25)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(InkPalette.paper.r, InkPalette.paper.g, InkPalette.paper.b, 0.60))
    nvgStroke(vg)
    -- 猪鼻（圆点）
    local facing = beast.facing or 0
    local nx = sx + math.cos(-facing) * r * 0.3
    local ny = sy + math.sin(-facing) * r * 0.1
    BrushStrokes.inkDotStable(vg, nx, ny, r * 0.06, ink, 0.45, 180)
    nvgRestore(vg)
end

-- 019 狸力 — 猪形，鸡爪
BeastRenderer.shapes["019"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local ochre = InkPalette.ochre
    nvgSave(vg)
    local body = {
        {-r*0.45, -r*0.25}, {0, -r*0.4}, {r*0.45, -r*0.25},
        {r*0.5, r*0.1}, {r*0.25, r*0.3}, {-r*0.25, r*0.3}, {-r*0.5, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ochre, 0.35, 0.50, 1.3, 119)
    nvgLineCap(vg, NVG_ROUND)
    -- 鸡爪脚
    local claws = {{-0.25, 0.3}, {0.25, 0.3}}
    for _, c in ipairs(claws) do
        local bx = sx + c[1]*r
        local by = sy + c[2]*r
        nvgBeginPath(vg)
        nvgMoveTo(vg, bx, by)
        nvgLineTo(vg, bx, by + r*0.25)
        nvgMoveTo(vg, bx, by + r*0.25)
        nvgLineTo(vg, bx - r*0.06, by + r*0.32)
        nvgMoveTo(vg, bx, by + r*0.25)
        nvgLineTo(vg, bx + r*0.06, by + r*0.32)
        nvgStrokeWidth(vg, 1.3)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end
    -- 眼
    local facing = beast.facing or 0
    local ex = sx + math.cos(-facing) * r * 0.25
    local ey = sy + math.sin(-facing) * r * 0.1 - r * 0.1
    BrushStrokes.inkDotStable(vg, ex, ey, r * 0.05, ink, 0.55, 190)
    nvgRestore(vg)
end

-- 020 旋龟 — 龟壳鸟头蛇尾
BeastRenderer.shapes["020"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    nvgSave(vg)
    -- 龟壳
    local shell = {
        {-r*0.2, -r*0.45}, {r*0.3, -r*0.4}, {r*0.5, -r*0.05},
        {r*0.4, r*0.3}, {-r*0.1, r*0.4}, {-r*0.45, r*0.2}, {-r*0.5, -r*0.1},
    }
    drawWhiteSketch(vg, shell, sx, sy, ink, 0.38, 0.55, 1.4, 120)
    BrushStrokes.cunTexture(vg, sx, sy, r * 0.35, ink, 0.18, 120, 4)
    nvgLineCap(vg, NVG_ROUND)
    -- 鸟头
    local facing = beast.facing or 0
    local headX = sx + math.cos(-facing) * r * 0.5
    local headY = sy + math.sin(-facing) * r * 0.3
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, r * 0.13)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgFill(vg)
    -- 鸟喙
    nvgBeginPath(vg)
    nvgMoveTo(vg, headX + math.cos(-facing) * r * 0.12, headY + math.sin(-facing) * r * 0.08)
    nvgLineTo(vg, headX + math.cos(-facing) * r * 0.25, headY + math.sin(-facing) * r * 0.12)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgStroke(vg)
    -- 蛇尾
    local tailWave = math.sin(t * 2.5) * r * 0.08
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.4, sy + r * 0.15)
    nvgBezierTo(vg, sx - r * 0.65, sy + r * 0.1 + tailWave, sx - r * 0.75, sy - r * 0.05 + tailWave, sx - r * 0.65, sy - r * 0.1)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgStroke(vg)
    -- 眼
    BrushStrokes.inkDotStable(vg, headX, headY - r * 0.03, r * 0.04, InkPalette.paper, 0.70, 200)
    nvgRestore(vg)
end

-- 021 并封 — 黑猪，前后双头
BeastRenderer.shapes["021"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkDark
    nvgSave(vg)
    local body = {
        {-r*0.35, -r*0.3}, {0, -r*0.4}, {r*0.35, -r*0.3},
        {r*0.4, r*0.1}, {r*0.2, r*0.35}, {-r*0.2, r*0.35}, {-r*0.4, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.50, 0.60, 1.4, 121)
    nvgLineCap(vg, NVG_ROUND)
    -- 前头
    local headR = r * 0.18
    nvgBeginPath(vg)
    nvgCircle(vg, sx + r * 0.45, sy, headR)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgFill(vg)
    BrushStrokes.inkDotStable(vg, sx + r * 0.48, sy - r * 0.03, r * 0.04, InkPalette.paper, 0.65, 210)
    -- 后头
    nvgBeginPath(vg)
    nvgCircle(vg, sx - r * 0.45, sy, headR)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.55))
    nvgFill(vg)
    BrushStrokes.inkDotStable(vg, sx - r * 0.48, sy - r * 0.03, r * 0.04, InkPalette.paper, 0.65, 211)
    -- 短腿
    local legs = {{-0.2, 0.3}, {0.2, 0.3}}
    for _, l in ipairs(legs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1]*r, sy + l[2]*r)
        nvgLineTo(vg, sx + l[1]*r, sy + r*0.5)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
        nvgStroke(vg)
    end
    -- 暗气场
    BrushStrokes.inkWash(vg, sx, sy, r * 0.15, r * 0.6, ink, 0.08)
    nvgRestore(vg)
end

-- 022 何罗鱼 — 一头十身
BeastRenderer.shapes["022"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local azure = InkPalette.azure
    nvgSave(vg)
    nvgLineCap(vg, NVG_ROUND)
    -- 十条身体（扇形展开）
    for i = 1, 10 do
        local spread = (i - 5.5) * 0.15
        local sway = math.sin(t * 2 + i * 0.6) * r * 0.05
        local tailX = sx - r * 0.7
        local tailY = sy + spread * r * 1.5 + sway
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + r * 0.15, sy)
        nvgBezierTo(vg,
            sx - r * 0.1, sy + spread * r * 0.5 + sway,
            sx - r * 0.4, sy + spread * r + sway,
            tailX, tailY)
        nvgStrokeWidth(vg, 1.5 - math.abs(i - 5.5) * 0.1)
        nvgStrokeColor(vg, nvgRGBAf(azure.r, azure.g, azure.b, 0.30))
        nvgStroke(vg)
    end
    -- 鱼头
    nvgBeginPath(vg)
    nvgCircle(vg, sx + r * 0.25, sy, r * 0.18)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.2)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.50))
    nvgStroke(vg)
    BrushStrokes.inkDotStable(vg, sx + r * 0.3, sy - r * 0.04, r * 0.04, InkPalette.paper, 0.65, 220)
    nvgRestore(vg)
end

-- 023 化蛇 — 人面豺身，收翅蛇行
BeastRenderer.shapes["023"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local wave = math.sin(t * 3) * r * 0.06
    nvgSave(vg)
    -- 豺身（低矮匍匐）
    local body = {
        {-r*0.5, -r*0.15}, {-r*0.2, -r*0.3}, {r*0.2, -r*0.3},
        {r*0.5, -r*0.1}, {r*0.45, r*0.15}, {0, r*0.2}, {-r*0.45, r*0.15},
    }
    drawWhiteSketch(vg, body, sx, sy + wave, ink, 0.38, 0.50, 1.2, 123)
    nvgLineCap(vg, NVG_ROUND)
    -- 收拢翅膀
    for side = -1, 1, 2 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx - r * 0.1, sy + side * r * 0.05 + wave)
        nvgQuadTo(vg, sx - r * 0.3, sy + side * r * 0.2 + wave, sx - r * 0.35, sy + side * r * 0.08 + wave)
        nvgStrokeWidth(vg, 1.0)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
        nvgStroke(vg)
    end
    -- 人面
    local headX = sx + r * 0.4
    local headY = sy - r * 0.15 + wave
    nvgBeginPath(vg)
    nvgCircle(vg, headX, headY, r * 0.14)
    nvgFillColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.35))
    nvgFill(vg)
    BrushStrokes.inkDotStable(vg, headX + r * 0.04, headY - r * 0.02, r * 0.03, InkPalette.paper, 0.60, 230)
    -- 水气晕
    BrushStrokes.inkWash(vg, sx, sy, r * 0.1, r * 0.4, InkPalette.azure, 0.06)
    nvgRestore(vg)
end

-- 024 蜚 — 白头独眼牛形蛇尾
BeastRenderer.shapes["024"] = function(vg, sx, sy, r, t, beast)
    local ink = InkPalette.inkStrong
    local poison = InkPalette.poison
    nvgSave(vg)
    local body = {
        {-r*0.5, -r*0.3}, {0, -r*0.45}, {r*0.5, -r*0.3},
        {r*0.55, r*0.1}, {r*0.3, r*0.35}, {-r*0.3, r*0.35}, {-r*0.55, r*0.1},
    }
    drawWhiteSketch(vg, body, sx, sy, ink, 0.38, 0.50, 1.4, 124)
    nvgLineCap(vg, NVG_ROUND)
    -- 四蹄
    local legs = {{-0.35, 0.3}, {0.3, 0.3}, {-0.3, 0.25}, {0.35, 0.25}}
    for _, l in ipairs(legs) do
        nvgBeginPath(vg)
        nvgMoveTo(vg, sx + l[1]*r, sy + l[2]*r)
        nvgLineTo(vg, sx + l[1]*r, sy + r*0.55)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
        nvgStroke(vg)
    end
    -- 白头
    nvgBeginPath(vg)
    nvgCircle(vg, sx + r * 0.45, sy - r * 0.2, r * 0.16)
    nvgFillColor(vg, nvgRGBAf(InkPalette.paper.r, InkPalette.paper.g, InkPalette.paper.b, 0.50))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.0)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.45))
    nvgStroke(vg)
    -- 独眼
    BrushStrokes.inkDotStable(vg, sx + r * 0.47, sy - r * 0.22, r * 0.06, InkPalette.cinnabar, 0.75, 240)
    -- 蛇尾
    local tailWave = math.sin(t * 2.5) * r * 0.08
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx - r * 0.5, sy + r * 0.1)
    nvgBezierTo(vg, sx - r * 0.7, sy + tailWave, sx - r * 0.85, sy - r * 0.1 + tailWave, sx - r * 0.75, sy - r * 0.2)
    nvgStrokeWidth(vg, 1.8)
    nvgStrokeColor(vg, nvgRGBAf(ink.r, ink.g, ink.b, 0.40))
    nvgStroke(vg)
    -- 毒气晕
    local toxPulse = 0.08 + math.sin(t * 2) * 0.04
    BrushStrokes.inkWash(vg, sx, sy, r * 0.2, r * 0.8, poison, toxPulse)
    nvgRestore(vg)
end

return BeastRenderer
