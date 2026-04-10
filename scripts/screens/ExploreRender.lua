--- ExploreScreen 渲染层 —— 从 ExploreScreen.lua 拆分
--- 通过 require("screens.ExploreRender")(ExploreScreen) 注入方法
local InkPalette = require("data.InkPalette")
local BrushStrokes = require("render.BrushStrokes")
local InkTileRenderer = require("render.InkTileRenderer")
local InkRenderer = require("render.InkRenderer")
local BeastRenderer = require("render.BeastRenderer")
local Camera = require("systems.Camera")
local FogOfWar = require("systems.FogOfWar")
local Timer = require("systems.Timer")
local EvacuationSystem = require("systems.EvacuationSystem")
local CombatSystem = require("systems.CombatSystem")
local SessionState = require("systems.SessionState")
local TrackingSystem = require("systems.TrackingSystem")
local SkillSystem = require("systems.SkillSystem")
local VirtualJoystick = require("systems.VirtualJoystick")
local Config = require("Config")

------------------------------------------------------------
-- 小地图配色
------------------------------------------------------------

local MINIMAP_COLORS = {
    grass  = { 0.45, 0.55, 0.35 },
    path   = { 0.65, 0.58, 0.45 },
    rock   = { 0.50, 0.48, 0.45 },
    bamboo = { 0.30, 0.48, 0.30 },
    water  = { 0.30, 0.40, 0.60 },
    danger = { 0.50, 0.25, 0.35 },
    wall   = { 0.12, 0.10, 0.08 },
}

------------------------------------------------------------
-- 注入函数
------------------------------------------------------------

return function(ES)

------------------------------------------------------------
-- 主渲染入口
------------------------------------------------------------

function ES:render(vg, logW, logH, t)
    Camera.resize(logW, logH)
    local P = InkPalette
    local ppu = Camera.ppu

    local shakeOX, shakeOY = 0, 0
    if self.shakeTimer > 0 then
        shakeOX = math.sin(t * 40) * self.shakeIntensity
        shakeOY = math.cos(t * 50) * self.shakeIntensity * 0.7
    end

    nvgSave(vg)
    nvgTranslate(vg, shakeOX, shakeOY)

    InkRenderer.drawPaperBase(vg, logW, logH, t)
    self:renderTiles(vg, logW, logH, t)
    self:renderEntities(vg, logW, logH, t)

    local psx, psy = Camera.toScreen(self.playerX, self.playerY)
    local visionPx = Config.VISION_RADIUS * ppu
    InkRenderer.drawFog(vg, logW, logH, psx, psy, visionPx, t, Timer.getCollapseProgress())

    if Config.ATMOSPHERE then
        InkRenderer.drawAtmosphere(vg, logW, logH, t)
    end
    InkRenderer.drawEdgeWhitespace(vg, logW, logH)

    self:renderHUD(vg, logW, logH, t)
    self:renderBottomBar(vg, logW, logH, t)
    self:renderControls(vg, logW, logH, t)
    self:renderMinimap(vg, logW, logH, t)
    self:renderToasts(vg, logW, logH, t)

    -- 受击闪红叠层
    if CombatSystem.hitFlashTimer > 0 then
        local flashAlpha = math.min(0.35, CombatSystem.hitFlashTimer / 0.3 * 0.35)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(0.8, 0.1, 0.05, flashAlpha))
        nvgFill(vg)
    end

    -- 瘴气墨染叠层
    if CombatSystem.miasmaDmgFlash > 0 then
        local inkAlpha = math.min(0.25, CombatSystem.miasmaDmgFlash / 1.0 * 0.25)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(0.05, 0.03, 0.08, inkAlpha))
        nvgFill(vg)
    end

    -- 溃散倒计时
    if CombatSystem.collapsed then
        local remain = math.ceil(CombatSystem.collapseTimer)
        local pulse = 0.7 + math.sin(t * 5) * 0.3
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(0.8, 0.15, 0.1, pulse))
        nvgText(vg, logW * 0.5, logH * 0.3, "灵气溃散")
        nvgFontSize(vg, 28)
        nvgText(vg, logW * 0.5, logH * 0.3 + 45, remain .. " 秒")
    end

    if self.sealerSelectActive then
        self:renderSealerSelect(vg, logW, logH, t)
    end

    if self.realmLegend and self.realmLegendAlpha > 0.01 then
        self:renderRealmLegend(vg, logW, logH, t)
    end

    nvgRestore(vg)
end

------------------------------------------------------------
-- Layer 1.5: 瓦片渲染
------------------------------------------------------------

function ES:renderTiles(vg, logW, logH, t)
    local bounds = Camera.getViewBounds()
    local ppu = Camera.ppu

    for gy = bounds.minY, bounds.maxY do
        for gx = bounds.minX, bounds.maxX do
            local tile = self.map:getTile(gx, gy)
            if tile then
                local fogState = FogOfWar.getState(gx, gy)
                if fogState ~= FogOfWar.DARK then
                    local sx, sy = Camera.toScreen(gx + 0.5, gy + 0.5)
                    local jx, jy = InkTileRenderer.jitter(gx, gy, ppu)
                    InkTileRenderer.drawBase(vg, tile, sx + jx, sy + jy, ppu, t, fogState)
                end
            end
        end
    end

    for gy = bounds.minY, bounds.maxY do
        for gx = bounds.minX, bounds.maxX do
            local tile = self.map:getTile(gx, gy)
            if tile then
                local fogState = FogOfWar.getState(gx, gy)
                if fogState ~= FogOfWar.DARK then
                    local sx, sy = Camera.toScreen(gx + 0.5, gy + 0.5)
                    local jx, jy = InkTileRenderer.jitter(gx, gy, ppu)
                    InkTileRenderer.drawDetail(vg, tile, sx + jx, sy + jy, ppu, t, fogState)
                end
            end
        end
    end
end

------------------------------------------------------------
-- Layer 2: 实体渲染
------------------------------------------------------------

function ES:renderEntities(vg, logW, logH, t)
    local ppu = Camera.ppu

    -- 行迹墨尘
    for _, trail in ipairs(self.playerTrails) do
        if Camera.inView(trail.x, trail.y) then
            local sx, sy = Camera.toScreen(trail.x, trail.y)
            local a = trail.alpha * (trail.life / trail.maxLife)
            BrushStrokes.inkDotStable(vg, sx, sy, 2, InkPalette.inkLight, a, 0)
        end
    end

    -- 线索
    for _, clue in ipairs(self.map.clues) do
        if not clue.investigated and FogOfWar.isEntityVisible(clue.x, clue.y) then
            if Camera.inView(clue.x, clue.y) then
                local sx, sy = Camera.toScreen(clue.x, clue.y)
                InkRenderer.drawClue(vg, clue, sx, sy, ppu, t)
            end
        end
    end

    -- 资源
    local resSeeThroughFog = false
    for _, res in ipairs(self.map.resources) do
        if not res.collected and (FogOfWar.isEntityVisible(res.x, res.y) or resSeeThroughFog) then
            if Camera.inView(res.x, res.y) then
                local sx, sy = Camera.toScreen(res.x, res.y)
                local playerDist = math.sqrt(
                    (res.x - self.playerX) ^ 2 + (res.y - self.playerY) ^ 2
                )
                InkRenderer.drawResource(vg, res, sx, sy, ppu, t, playerDist)
            end
        end
    end

    -- 撤离点
    for _, ep in ipairs(self.map.evacuationPoints) do
        if Camera.inView(ep.x, ep.y) then
            local sx, sy = Camera.toScreen(ep.x, ep.y)
            local progress = 0
            if EvacuationSystem.evacuating and EvacuationSystem.currentPoint == ep then
                progress = EvacuationSystem.getProgress()
            end
            InkRenderer.drawEvacPoint(vg, sx, sy, ppu, t, progress)
        end
    end

    -- 地面墨迹/毒迹区域
    for _, patch in ipairs(self.inkPatches) do
        if Camera.inView(patch.x, patch.y) then
            local sx, sy = Camera.toScreen(patch.x, patch.y)
            local alpha = math.min(0.5, patch.life / patch.maxLife * 0.5)
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, ppu * 1.2)
            nvgFillColor(vg, nvgRGBAf(0.05, 0.03, 0.08, alpha))
            nvgFill(vg)
        end
    end

    -- 异兽
    local beastEyeActive = self.beastEyeTimer and self.beastEyeTimer > 0
    for _, beast in ipairs(self.beasts) do
        if beast.aiState ~= "captured" and beast.aiState ~= "hidden" then
            local normalVisible = FogOfWar.isEntityVisible(beast.x, beast.y) and Camera.inView(beast.x, beast.y)
            local eyeRevealed = beastEyeActive and Camera.inView(beast.x, beast.y)
            if normalVisible or eyeRevealed then
                local sx, sy = Camera.toScreen(beast.x, beast.y)
                if eyeRevealed then
                    local baseR = ppu * beast.bodySize * 1.8
                    local pulseR = baseR + math.sin(t * 4) * ppu * 0.15
                    local glowPaint = nvgRadialGradient(vg, sx, sy, pulseR * 0.3, pulseR,
                        nvgRGBAf(0.90, 0.75, 0.15, 0.35 + math.sin(t * 3) * 0.1),
                        nvgRGBAf(0.85, 0.65, 0.10, 0))
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, pulseR)
                    nvgFillPaint(vg, glowPaint)
                    nvgFill(vg)
                    nvgBeginPath(vg)
                    nvgCircle(vg, sx, sy, baseR * 0.6)
                    nvgStrokeColor(vg, nvgRGBAf(0.95, 0.80, 0.20, 0.6 + math.sin(t * 5) * 0.15))
                    nvgStrokeWidth(vg, 2.0)
                    nvgStroke(vg)
                end
                if beast.invisible and not eyeRevealed then
                    for pi = 1, 3 do
                        local px = sx + math.sin(t * 2 + pi * 2.1) * ppu * 0.4
                        local py = sy + math.cos(t * 1.5 + pi * 1.7) * ppu * 0.3
                        local pa = 0.15 + math.sin(t * 3 + pi) * 0.08
                        nvgBeginPath(vg)
                        nvgCircle(vg, px, py, 2)
                        nvgFillColor(vg, nvgRGBAf(0.3, 0.5, 0.2, pa))
                        nvgFill(vg)
                    end
                elseif beast.fakeDeath then
                    nvgSave(vg)
                    nvgGlobalAlpha(vg, 0.3)
                    BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
                    nvgRestore(vg)
                else
                    BeastRenderer.draw(vg, beast, sx, sy, ppu, t)
                end
            end
        end
    end

    -- 玩家
    local psx, psy = Camera.toScreen(self.playerX, self.playerY)
    if CombatSystem.hp <= 3 and CombatSystem.hp > 0 then
        local shakeAmt = (4 - CombatSystem.hp) * 0.4
        psx = psx + math.sin(t * 17.3) * shakeAmt
        psy = psy + math.cos(t * 13.7) * shakeAmt * 0.6
    end
    InkRenderer.drawPlayer(vg, psx, psy, ppu, self.playerFacing, t)

    -- Debuff指示
    local P = InkPalette
    local activeDebuffs = CombatSystem.debuffs
    if activeDebuffs then
        local debuffIdx = 0
        local debuffColors = {
            petrify = P.inkMedium,
            sticky  = P.jade,
            burn    = P.cinnabar,
            dizzy   = P.gold,
            ink     = P.inkDark,
        }
        for debuffId, debuff in pairs(activeDebuffs) do
            if debuff.timer and debuff.timer > 0 then
                debuffIdx = debuffIdx + 1
                local ringR = ppu * 0.5 + debuffIdx * 4
                local dColor = debuffColors[debuffId] or P.inkMedium
                local remain = debuff.timer
                local pulse = 0.4 + math.sin(t * 3 + debuffIdx * 1.5) * 0.15

                nvgBeginPath(vg)
                nvgCircle(vg, psx, psy, ringR)
                nvgStrokeWidth(vg, 2.0)
                nvgStrokeColor(vg, nvgRGBAf(dColor.r, dColor.g, dColor.b, pulse))
                nvgStroke(vg)

                local def = CombatSystem.DEBUFF_DEFS[debuffId]
                local label = (def and def.name or debuffId) .. string.format("%.0f", remain)
                nvgFontFace(vg, "sans")
                nvgFontSize(vg, 9)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(vg, nvgRGBAf(dColor.r, dColor.g, dColor.b, pulse + 0.15))
                nvgText(vg, psx, psy + ringR + 2, label)
            end
        end
    end

    -- 恢复道具施法进度
    if self.recoveryUsing then
        local castProg = 1.0 - (self.recoveryUsing.timer / (self.recoveryUsing.maxTime or 2.0))
        castProg = math.max(0, math.min(1, castProg))
        nvgBeginPath(vg)
        nvgArc(vg, psx, psy - ppu * 0.8, 12,
            -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2 * castProg, NVG_CW)
        nvgStrokeWidth(vg, 2.5)
        nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.75))
        nvgStroke(vg)
    end

    -- 疾风符视觉
    if self.rushWardTimer and self.rushWardTimer > 0 then
        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        local windAlpha = math.min(0.5, self.rushWardTimer / 10)
        for wi = 1, 3 do
            local angle = t * 3.0 + wi * 2.09
            local wr = ppu * 0.7 + math.sin(t * 2 + wi) * ppu * 0.15
            nvgBeginPath(vg)
            nvgArc(vg, psx, psy, wr, angle, angle + 0.8, NVG_CW)
            nvgStrokeWidth(vg, 1.2)
            nvgStrokeColor(vg, nvgRGBAf(InkPalette.jade.r, InkPalette.jade.g, InkPalette.jade.b, windAlpha * (0.3 + wi * 0.1)))
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end

    -- 撤离路径指引箭头
    local curPhase = Timer.getPhase()
    if curPhase == "warning" or curPhase == "danger" or curPhase == "collapse" then
        local nearPt, nearDist = EvacuationSystem.getNearestPoint(self.playerX, self.playerY)
        if nearPt and nearDist > 2.0 then
            local dx = nearPt.x - self.playerX
            local dy = nearPt.y - self.playerY
            local angle = math.atan2(dy, dx)
            local arrowDist = ppu * 2.0
            local ax = psx + math.cos(angle) * arrowDist
            local ay = psy + math.sin(angle) * arrowDist

            local urgency = (curPhase == "warning") and 0.5 or 0.8
            local pulse = urgency * (0.5 + math.sin(t * 3) * 0.3)

            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)

            local segments = 4
            for si = 1, segments do
                local frac0 = (si - 1) / segments * 0.8 + 0.2
                local frac1 = frac0 + 0.12
                local x0 = psx + math.cos(angle) * arrowDist * frac0
                local y0 = psy + math.sin(angle) * arrowDist * frac0
                local x1 = psx + math.cos(angle) * arrowDist * frac1
                local y1 = psy + math.sin(angle) * arrowDist * frac1
                nvgBeginPath(vg)
                nvgMoveTo(vg, x0, y0)
                nvgLineTo(vg, x1, y1)
                nvgStrokeWidth(vg, 1.5)
                nvgStrokeColor(vg, nvgRGBAf(InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, pulse))
                nvgStroke(vg)
            end

            local aSize = 5
            local a1x = ax + math.cos(angle) * aSize
            local a1y = ay + math.sin(angle) * aSize
            local a2x = ax + math.cos(angle + 2.5) * aSize
            local a2y = ay + math.sin(angle + 2.5) * aSize
            local a3x = ax + math.cos(angle - 2.5) * aSize
            local a3y = ay + math.sin(angle - 2.5) * aSize
            nvgBeginPath(vg)
            nvgMoveTo(vg, a1x, a1y)
            nvgLineTo(vg, a2x, a2y)
            nvgLineTo(vg, a3x, a3y)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBAf(InkPalette.gold.r, InkPalette.gold.g, InkPalette.gold.b, pulse))
            nvgFill(vg)

            nvgRestore(vg)
        end
    end
end

------------------------------------------------------------
-- Layer 4: HUD
------------------------------------------------------------

function ES:renderHUD(vg, logW, logH, t)
    local P = InkPalette

    local timeStr = Timer.formatRemaining()
    local phase = Timer.getPhase()
    local phaseName = Timer.getPhaseName()

    local timeColor = P.inkStrong
    local timeAlpha = 1.0
    if phase == "warning" then
        timeColor = P.gold
    elseif phase == "danger" or phase == "collapse" or phase == "collapsed" then
        timeColor = P.cinnabar
        timeAlpha = math.sin(t * 4) * 0.2 + 0.75
    end

    local timeY = logH * 0.04
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 36)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(timeColor.r, timeColor.g, timeColor.b, timeAlpha))
    nvgText(vg, logW * 0.5, timeY, timeStr)

    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
    nvgText(vg, logW * 0.5, timeY + 40, phaseName)

    self:renderHPBar(vg, logW, logH, t)

    if self.qualityStamp and self.qualityStampAlpha > 0.01 then
        local stampColor = self.qualityStamp == "SSR" and P.gold or P.azure
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(stampColor.r, stampColor.g, stampColor.b, self.qualityStampAlpha))
        nvgText(vg, 12, timeY + 4, self.qualityStamp)
    end
end

------------------------------------------------------------
-- 底部信息条
------------------------------------------------------------

function ES:renderBottomBar(vg, logW, logH, t)
    local P = InkPalette
    local barY = logH * 0.74
    local barH = logH * 0.09
    local barX = logW * 0.05
    local barW = logW * 0.90

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 0.78))
    nvgFill(vg)
    BrushStrokes.inkRect(vg, barX, barY, barW, barH, P.inkLight, 0.30, 51)

    local row1Y = barY + barH * 0.30
    local dotStartX = barX + 16

    for i = 1, 5 do
        local dotSeed = i * 37 + 11
        local sizeJitter = 1.0 + ((dotSeed % 10) - 5) * 0.01
        local cx = dotStartX + (i - 1) * 20
        local dotR = 7 * sizeJitter
        if i <= TrackingSystem.clueCount then
            BrushStrokes.inkDotStable(vg, cx, row1Y, dotR, P.cinnabar, 0.85, dotSeed)
        else
            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)
            for seg = 1, 3 do
                local startA = (seg - 1) * math.pi * 2 / 3 + ((dotSeed * seg) % 30) * 0.02
                nvgBeginPath(vg)
                nvgArc(vg, cx, row1Y, dotR * 0.85, startA, startA + math.pi * 0.55, NVG_CW)
                nvgStrokeWidth(vg, 1.0 + (seg % 2) * 0.4)
                nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.40))
                nvgStroke(vg)
            end
            nvgRestore(vg)
        end
    end

    local sealerTypes = {
        { key = "sealer_free", label = "素", color = P.inkMedium },
        { key = "sealer_t2",   label = "玉", color = P.jade },
        { key = "sealer_t3",   label = "金", color = P.gold },
        { key = "sealer_t4",   label = "命", color = P.azure },
        { key = "sealer_t5",   label = "沌", color = P.cinnabar },
    }
    local sealerX = dotStartX + 5 * 20 + 14
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    for _, st in ipairs(sealerTypes) do
        local cnt = SessionState.getItemCount(st.key)
        if cnt > 0 then
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBAf(st.color.r, st.color.g, st.color.b, 0.65))
            nvgText(vg, sealerX, row1Y, st.label)
            nvgFontSize(vg, 10)
            nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.70))
            nvgText(vg, sealerX + 13, row1Y, tostring(cnt))
            sealerX = sealerX + 28
        end
    end

    local contractCount = SessionState.getContractCount()
    local cntLabel = ({ [0]="零",[1]="壹",[2]="贰",[3]="叁",[4]="肆",[5]="伍" })[contractCount] or tostring(contractCount)
    do
        local stampSize = 30
        local stampX = barX + barW - stampSize - 10
        local stampY = row1Y - stampSize * 0.5
        nvgBeginPath(vg)
        nvgRoundedRect(vg, stampX, stampY, stampSize, stampSize, 3)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, contractCount > 0 and 0.18 or 0.08))
        nvgFill(vg)
        BrushStrokes.inkRect(vg, stampX, stampY, stampSize, stampSize, P.cinnabar, contractCount > 0 and 0.60 or 0.25, 88)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local stampCX = stampX + stampSize * 0.5
        local stampCY = stampY + stampSize * 0.5
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, contractCount > 0 and 0.85 or 0.35))
        nvgText(vg, stampCX, stampCY - 6, "灵契")
        nvgFontSize(vg, 13)
        nvgText(vg, stampCX, stampCY + 7, cntLabel)
    end

    local row2Y = barY + barH * 0.74
    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local items = {
        { label = "灰", count = SessionState.getItemCount("traceAsh"), color = P.inkMedium, icon = "ash" },
        { label = "砂", count = SessionState.getItemCount("mirrorSand"), color = P.azure, icon = "sand" },
        { label = "符", count = SessionState.getItemCount("soulCharm"), color = P.gold, icon = "charm" },
    }
    local ix = barX + 14
    for idx, item in ipairs(items) do
        local icx = ix + 2
        local icy = row2Y
        local iconS = 8

        if item.icon == "ash" then
            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)
            for li = 1, 3 do
                local yOff = (li - 2) * iconS * 0.35
                nvgBeginPath(vg)
                nvgMoveTo(vg, icx - iconS * 0.5, icy + yOff)
                nvgQuadTo(vg, icx, icy + yOff - iconS * 0.2, icx + iconS * 0.5, icy + yOff + iconS * 0.1)
                nvgStrokeWidth(vg, 1.0 + li * 0.3)
                nvgStrokeColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.65 - li * 0.1))
                nvgStroke(vg)
            end
            nvgRestore(vg)
        elseif item.icon == "sand" then
            nvgSave(vg)
            for ci = 1, 4 do
                local hash = (ci * 31 + idx * 7) % 20
                local dx = (hash - 10) * iconS * 0.06
                local dy = ((ci - 2.5)) * iconS * 0.28
                local ds = iconS * 0.22
                nvgBeginPath(vg)
                nvgMoveTo(vg, icx + dx, icy + dy - ds)
                nvgLineTo(vg, icx + dx + ds * 0.7, icy + dy)
                nvgLineTo(vg, icx + dx, icy + dy + ds)
                nvgLineTo(vg, icx + dx - ds * 0.7, icy + dy)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.55))
                nvgFill(vg)
            end
            nvgRestore(vg)
        elseif item.icon == "charm" then
            nvgSave(vg)
            local cw = iconS * 0.55
            local ch = iconS * 0.85
            nvgBeginPath(vg)
            nvgRect(vg, icx - cw, icy - ch, cw * 2, ch * 2)
            nvgFillColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.18))
            nvgFill(vg)
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBAf(item.color.r, item.color.g, item.color.b, 0.55))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, icx, icy - ch * 0.6)
            nvgLineTo(vg, icx, icy + ch * 0.6)
            nvgStrokeWidth(vg, 0.8)
            nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.50))
            nvgStroke(vg)
            nvgRestore(vg)
        end

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.75))
        nvgText(vg, ix + 14, row2Y, item.label)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.90))
        nvgText(vg, ix + 28, row2Y, "×" .. item.count)
        ix = ix + 62
    end

    local row3Y = barY + barH + 6
    self.itemButtons = {}
    local specialItems = {}

    local rushCount = SessionState.getItemCount("rushWard")
    if rushCount > 0 or (self.rushWardTimer and self.rushWardTimer > 0) then
        table.insert(specialItems, {
            id = "rushWard", label = "疾风符",
            count = rushCount,
            active = self.rushWardTimer and self.rushWardTimer > 0,
            timer = self.rushWardTimer,
            color = P.jade,
            usable = rushCount > 0 and not (self.rushWardTimer and self.rushWardTimer > 0),
        })
    end

    local fogCount = SessionState.getItemCount("fogMap")
    if fogCount > 0 or self.fogMapUsed then
        table.insert(specialItems, {
            id = "fogMap", label = "残图",
            count = fogCount,
            active = self.fogMapUsed,
            color = P.azure,
            usable = false,
        })
    end

    local eyeCount = SessionState.getItemCount("beastEye")
    if eyeCount > 0 or (self.beastEyeTimer and self.beastEyeTimer > 0) then
        table.insert(specialItems, {
            id = "beastEye", label = "兽瞳",
            count = eyeCount,
            active = self.beastEyeTimer and self.beastEyeTimer > 0,
            timer = self.beastEyeTimer,
            color = P.gold,
            usable = eyeCount > 0 and not (self.beastEyeTimer and self.beastEyeTimer > 0),
        })
    end

    local echoCount = SessionState.getItemCount("sealEcho")
    if echoCount > 0 or SessionState.sealEchoUsed then
        table.insert(specialItems, {
            id = "sealEcho", label = "回响",
            count = echoCount,
            active = false,
            used = SessionState.sealEchoUsed,
            color = P.gold,
            usable = false,
        })
    end

    local lqCount = SessionState.getItemCount("lingquanWan")
    local lqCasting = self.recoveryUsing and self.recoveryUsing.itemId == "lingquanWan"
    if lqCount > 0 or lqCasting then
        table.insert(specialItems, {
            id = "lingquanWan", label = "灵泉",
            count = lqCount,
            active = lqCasting,
            timer = lqCasting and self.recoveryUsing.timer or nil,
            color = P.azure,
            usable = lqCount > 0 and not self.recoveryUsing and not CombatSystem.collapsed
                and CombatSystem.hp < CombatSystem.MAX_HP,
        })
    end

    local jzCount = SessionState.getItemCount("jianzhulu")
    local jzCasting = self.recoveryUsing and self.recoveryUsing.itemId == "jianzhulu"
    if jzCount > 0 or jzCasting then
        table.insert(specialItems, {
            id = "jianzhulu", label = "绛珠",
            count = jzCount,
            active = jzCasting,
            timer = jzCasting and self.recoveryUsing.timer or nil,
            color = P.cinnabar,
            usable = jzCount > 0 and not self.recoveryUsing and not CombatSystem.collapsed
                and CombatSystem.hp < CombatSystem.MAX_HP,
        })
    end

    if #specialItems > 0 then
        local itemW = 70
        local itemH = 28
        local startX = barX + 8
        for idx, si in ipairs(specialItems) do
            local ix2 = startX + (idx - 1) * (itemW + 6)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, ix2, row3Y, itemW, itemH, 4)
            if si.active then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.15))
            elseif si.usable then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.08))
            else
                nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.06))
            end
            nvgFill(vg)

            if si.usable then
                nvgStrokeWidth(vg, 1.0)
                nvgStrokeColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.5))
                nvgStroke(vg)
            end

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local labelAlpha = (si.active or si.usable) and 0.85 or 0.45
            nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, labelAlpha))
            nvgText(vg, ix2 + 6, row3Y + itemH * 0.5, si.label)

            nvgFontSize(vg, 10)
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            if si.active and si.timer and si.timer > 0 then
                local secStr = string.format("%ds", math.ceil(si.timer))
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.9))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, secStr)
            elseif si.active and si.id == "fogMap" then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.65))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "已用")
            elseif si.used then
                nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.5))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "已用")
            elseif si.usable then
                nvgFillColor(vg, nvgRGBAf(si.color.r, si.color.g, si.color.b, 0.7))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "使用")
            else
                nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.5))
                nvgText(vg, ix2 + itemW - 6, row3Y + itemH * 0.5, "×" .. si.count)
            end

            if si.usable then
                table.insert(self.itemButtons, {
                    id = si.id,
                    x = ix2, y = row3Y, w = itemW, h = itemH,
                })
            end
        end
    end
end

------------------------------------------------------------
-- 操作区
------------------------------------------------------------

function ES:renderControls(vg, logW, logH, t)
    local P = InkPalette

    VirtualJoystick.draw(vg, logW, logH)

    if self.interactType then
        local btnX = logW * 0.78
        local btnY = logH * 0.88
        local btnR = 32

        BrushStrokes.inkWash(vg, btnX, btnY, btnR * 0.15, btnR, P.jade, 0.18)

        nvgSave(vg)
        nvgLineCap(vg, NVG_ROUND)
        for seg = 1, 4 do
            local startA = (seg - 1) * math.pi * 0.5 + 0.12
            local sweep = math.pi * 0.5 - 0.35
            nvgBeginPath(vg)
            nvgArc(vg, btnX, btnY, btnR * 0.88, startA, startA + sweep, NVG_CW)
            local w = 1.2 + (seg % 3) * 0.4
            nvgStrokeWidth(vg, w)
            nvgStrokeColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.50 + seg * 0.04))
            nvgStroke(vg)
        end
        nvgRestore(vg)

        local labels = {
            investigate = "调查",
            collect = "采集",
            suppress = "压制",
            evacuate = "撤离",
        }
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.8))
        nvgText(vg, btnX + 1, btnY + 1, labels[self.interactType] or "")
    end

    if self.investigateTarget and self.investigateDuration > 0 then
        local prog = math.min(1, self.investigateTimer / self.investigateDuration)
        local barW = logW * 0.35
        local barH = 6
        local barX = (logW - barW) * 0.5
        local barY = logH * 0.65
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 3)
        nvgFillColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.35))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * prog, barH, 3)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.75))
        nvgFill(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.7))
        nvgText(vg, logW * 0.5, barY - 3, "调查中...")
    end

    if EvacuationSystem.evacuating then
        local prog = EvacuationSystem.getProgress()
        local ep = EvacuationSystem.currentPoint
        if ep then
            local sx, sy = Camera.toScreen(ep.x, ep.y)
            nvgBeginPath(vg)
            nvgArc(vg, sx, sy, 20, -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2 * prog, NVG_CW)
            nvgStrokeColor(vg, nvgRGBAf(P.gold.r, P.gold.g, P.gold.b, 0.8))
            nvgStrokeWidth(vg, 3)
            nvgStroke(vg)
        end
    end

    self.skillBtn = nil
    if SkillSystem.activeSkill then
        local skill = SkillSystem.SKILLS[SkillSystem.activeSkill]
        if skill then
            local skBtnX = logW * 0.60
            local skBtnY = logH * 0.88
            local skBtnR = 28
            local onCooldown = SkillSystem.cooldownTimer > 0
            local noUses = SkillSystem.usesLeft <= 0

            local bgColor = onCooldown and P.inkLight or (noUses and P.inkWash or P.azure)
            local bgAlpha = (onCooldown or noUses) and 0.10 or 0.18
            BrushStrokes.inkWash(vg, skBtnX, skBtnY, skBtnR * 0.15, skBtnR, bgColor, bgAlpha)

            nvgSave(vg)
            nvgLineCap(vg, NVG_ROUND)
            local arcColor = (onCooldown or noUses) and P.inkLight or P.azure
            local arcAlpha = (onCooldown or noUses) and 0.25 or 0.55
            for seg = 1, 4 do
                local startA = (seg - 1) * math.pi * 0.5 + 0.12
                local sweep = math.pi * 0.5 - 0.35
                nvgBeginPath(vg)
                nvgArc(vg, skBtnX, skBtnY, skBtnR * 0.88, startA, startA + sweep, NVG_CW)
                nvgStrokeWidth(vg, 1.0 + (seg % 3) * 0.3)
                nvgStrokeColor(vg, nvgRGBAf(arcColor.r, arcColor.g, arcColor.b, arcAlpha))
                nvgStroke(vg)
            end
            nvgRestore(vg)

            if onCooldown then
                local cdMax = 1.5
                local cdProg = math.min(1, SkillSystem.cooldownTimer / cdMax)
                nvgBeginPath(vg)
                nvgMoveTo(vg, skBtnX, skBtnY)
                nvgArc(vg, skBtnX, skBtnY, skBtnR * 0.85,
                    -math.pi * 0.5,
                    -math.pi * 0.5 + math.pi * 2 * cdProg, NVG_CW)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBAf(P.inkDark.r, P.inkDark.g, P.inkDark.b, 0.25))
                nvgFill(vg)
            end

            local iconSymbols = {
                lingfudan = "符", zhuijidan = "追", baoyanfu = "焰",
                fengyinzhen = "封", dingshenzou = "定", qusanfa = "散",
            }
            local sym = iconSymbols[SkillSystem.activeSkill] or "技"
            local textAlpha = (onCooldown or noUses) and 0.35 or 0.85
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, textAlpha))
            nvgText(vg, skBtnX, skBtnY - 2, sym)

            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local countColor = noUses and P.cinnabar or P.inkMedium
            local countAlpha = noUses and 0.70 or 0.75
            nvgFillColor(vg, nvgRGBAf(countColor.r, countColor.g, countColor.b, countAlpha))
            nvgText(vg, skBtnX + skBtnR * 0.55, skBtnY + skBtnR * 0.55,
                tostring(SkillSystem.usesLeft))

            self.skillBtn = { x = skBtnX, y = skBtnY, r = skBtnR }
        end
    end

    if self.emergencyEscapeAvailable then
        local ebW = 120
        local ebH = 36
        local ebX = (logW - ebW) * 0.5
        local ebY = logH * 0.58
        local pulse = 0.7 + math.sin(t * 4) * 0.2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, ebX, ebY, ebW, ebH, 6)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.20 * pulse))
        nvgFill(vg)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.65 * pulse))
        nvgStroke(vg)

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.90 * pulse))
        nvgText(vg, logW * 0.5, ebY + ebH * 0.5, "紧急逃脱")

        self.emergencyEscapeBtn = { x = ebX, y = ebY, w = ebW, h = ebH }
    else
        self.emergencyEscapeBtn = nil
    end
end

------------------------------------------------------------
-- Toast 消息
------------------------------------------------------------

function ES:renderToasts(vg, logW, logH, t)
    local P = InkPalette
    local baseY = logH * 0.35
    for i, toast in ipairs(self.toasts) do
        local alpha = math.min(1, toast.life / 0.5)
        local y = baseY + (i - 1) * 30
        InkRenderer.drawToast(vg, logW * 0.5, y, toast.text, alpha, logW)
    end
end

------------------------------------------------------------
-- 封灵器选择弹窗
------------------------------------------------------------

function ES:renderSealerSelect(vg, logW, logH, t)
    local P = InkPalette
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.5))
    nvgFill(vg)

    local list = self.sealerSelectList or {}
    local panelW = logW * 0.8
    local itemH = 52
    local panelH = #list * itemH + 80
    local panelX = (logW - panelW) * 0.5
    local panelY = (logH - panelH) * 0.5

    nvgBeginPath(vg)
    nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paper.r, P.paper.g, P.paper.b, 0.95))
    nvgFill(vg)
    BrushStrokes.inkRect(vg, panelX, panelY, panelW, panelH, P.inkMedium, 0.4, 99)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85))
    nvgText(vg, logW * 0.5, panelY + 24, "选择封灵器")

    self.sealerSelectButtons = {}
    local beast = self.sealerSelectBeast
    local ambush = beast and beast.ambushBonus
    for i, info in ipairs(list) do
        local iy = panelY + 48 + (i - 1) * itemH
        local rate = info.rate
        if ambush then rate = math.min(1.0, rate + 0.20) end

        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX + 10, iy, panelW - 20, itemH - 4, 4)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.06))
        nvgFill(vg)

        nvgFontSize(vg, 15)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.85))
        nvgText(vg, panelX + 24, iy + itemH * 0.35, info.name)

        nvgFontSize(vg, 11)
        nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.7))
        nvgText(vg, panelX + 24, iy + itemH * 0.7,
            string.format("成功率 %d%%  库存 %d", math.floor(rate * 100), info.count))

        table.insert(self.sealerSelectButtons, {
            x = panelX + 10, y = iy, w = panelW - 20, h = itemH - 4,
            info = info,
        })
    end

    local cancelY = panelY + panelH - 30
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.6))
    nvgText(vg, logW * 0.5, cancelY, "取消（异兽将逃跑）")
    table.insert(self.sealerSelectButtons, {
        x = panelX, y = cancelY - 12, w = panelW, h = 24,
        info = nil,
    })
end

------------------------------------------------------------
-- 灵境传说卡片
------------------------------------------------------------

function ES:renderRealmLegend(vg, logW, logH, t)
    local P = InkPalette
    local alpha = self.realmLegendAlpha
    local legend = self.realmLegend

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.55 * alpha))
    nvgFill(vg)

    local cardW = math.min(logW * 0.82, 320)
    local cardH = logH * 0.55
    local cardX = (logW - cardW) * 0.5
    local cardY = (logH - cardH) * 0.5

    nvgBeginPath(vg)
    nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 8)
    nvgFillColor(vg, nvgRGBAf(P.paperWarm.r, P.paperWarm.g, P.paperWarm.b, 0.95 * alpha))
    nvgFill(vg)

    BrushStrokes.inkRect(vg, cardX, cardY, cardW, cardH, P.inkMedium, 0.45 * alpha, 77)

    local cy = cardY + 32
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBAf(P.inkStrong.r, P.inkStrong.g, P.inkStrong.b, 0.90 * alpha))
    nvgText(vg, logW * 0.5, cy, legend.title or "灵境")

    cy = cy + 22
    BrushStrokes.inkLine(vg, cardX + 30, cy, cardX + cardW - 30, cy,
        1.0, P.inkWash, 0.35 * alpha, 33)

    cy = cy + 18
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.inkMedium.r, P.inkMedium.g, P.inkMedium.b, 0.80 * alpha))
    local textX = cardX + 24
    local textW = cardW - 48
    local bounds = {}
    nvgTextBoxBounds(vg, textX, cy, textW, legend.text or "", bounds)
    nvgTextBox(vg, textX, cy, textW, legend.text or "")

    local textBottom = bounds[4] or (cy + 60)
    local hintY = textBottom + 20
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBAf(P.jade.r, P.jade.g, P.jade.b, 0.65 * alpha))
    nvgTextBox(vg, cardX + 24, hintY, textW, legend.hint or "")

    local tipAlpha = (0.4 + math.sin(t * 2.5) * 0.15) * alpha
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBAf(P.inkLight.r, P.inkLight.g, P.inkLight.b, tipAlpha))
    nvgText(vg, logW * 0.5, cardY + cardH - 12, "点击任意处继续")
end

------------------------------------------------------------
-- HP 血条
------------------------------------------------------------

function ES:renderHPBar(vg, logW, logH, t)
    local P = InkPalette
    local hp = CombatSystem.hp
    local maxHP = CombatSystem.MAX_HP

    local startX = 12
    local startY = logH * 0.04 + 8
    local dropSpacing = 14
    local dropR = 5

    for i = 1, maxHP do
        local cx = startX + (i - 1) * dropSpacing
        local cy = startY

        if i <= hp then
            local alive = true
            if hp <= 3 then
                local blink = math.sin(t * 6 + i * 0.5)
                if blink < -0.3 then alive = false end
            end

            if alive then
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy + 1, dropR)
                nvgMoveTo(vg, cx - dropR * 0.5, cy - dropR * 0.3)
                nvgLineTo(vg, cx, cy - dropR * 1.4)
                nvgLineTo(vg, cx + dropR * 0.5, cy - dropR * 0.3)
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.85))
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgCircle(vg, cx, cy + 1, dropR)
                nvgFillColor(vg, nvgRGBAf(P.cinnabar.r, P.cinnabar.g, P.cinnabar.b, 0.25))
                nvgFill(vg)
            end
        else
            nvgBeginPath(vg)
            nvgCircle(vg, cx, cy + 1, dropR * 0.8)
            nvgStrokeWidth(vg, 1.0)
            nvgStrokeColor(vg, nvgRGBAf(P.inkWash.r, P.inkWash.g, P.inkWash.b, 0.35))
            nvgStroke(vg)
        end
    end
end

------------------------------------------------------------
-- 小地图
------------------------------------------------------------

function ES:renderMinimap(vg, logW, logH, t)
    local map = self.map
    if not map then return end

    local expanded = self.minimapExpanded
    local scale, mx, my, mw, mh

    if expanded then
        scale = math.min((logW * 0.65) / map.width, (logH * 0.60) / map.height)
        mw = map.width * scale
        mh = map.height * scale
        mx = (logW - mw) * 0.5
        my = (logH - mh) * 0.5
    else
        scale = math.min(2.5, (logW * 0.22) / map.width)
        mw = map.width * scale
        mh = map.height * scale
        mx = logW - mw - 10
        my = 55
    end

    self.minimapBounds = { x = mx, y = my, w = mw, h = mh }

    if expanded then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, logW, logH)
        nvgFillColor(vg, nvgRGBAf(0, 0, 0, 0.55))
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx - 2, my - 2, mw + 4, mh + 4, 3)
    nvgFillColor(vg, nvgRGBAf(0.06, 0.05, 0.04, 0.9))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBAf(0.3, 0.25, 0.2, 0.5))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    for ty = 1, map.height do
        for tx = 1, map.width do
            local tile = map.tiles[ty][tx]
            local fogState = FogOfWar.getState(tx - 1, ty - 1)
            if fogState ~= FogOfWar.DARK then
                local col = MINIMAP_COLORS[tile.type] or MINIMAP_COLORS.wall
                local alpha = fogState == FogOfWar.VISIBLE and 0.9 or 0.4
                nvgBeginPath(vg)
                local sy = my + (map.height - ty) * scale
                nvgRect(vg, mx + (tx - 1) * scale, sy, scale + 0.5, scale + 0.5)
                nvgFillColor(vg, nvgRGBAf(col[1], col[2], col[3], alpha))
                nvgFill(vg)
            end
        end
    end

    if expanded then
        for _, ep in ipairs(map.evacuationPoints) do
            local fs = FogOfWar.getState(ep.x, ep.y)
            if fs ~= FogOfWar.DARK then
                local ex = mx + ep.x * scale + scale * 0.5
                local ey = my + (map.height - 1 - ep.y) * scale + scale * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, ex, ey, scale * 1.2)
                nvgFillColor(vg, nvgRGBAf(0.2, 0.6, 0.9, 0.85))
                nvgFill(vg)
            end
        end
        for _, res in ipairs(map.resources) do
            if not res.collected then
                local fs = FogOfWar.getState(res.x, res.y)
                if fs ~= FogOfWar.DARK then
                    local rx = mx + res.x * scale + scale * 0.5
                    local ry = my + (map.height - 1 - res.y) * scale + scale * 0.5
                    nvgBeginPath(vg)
                    nvgCircle(vg, rx, ry, scale * 0.5)
                    nvgFillColor(vg, nvgRGBAf(0.3, 0.7, 0.3, fs == FogOfWar.VISIBLE and 0.8 or 0.4))
                    nvgFill(vg)
                end
            end
        end
        for _, beast in ipairs(self.beasts) do
            if beast.aiState ~= "captured" and FogOfWar.isEntityVisible(beast.x, beast.y) then
                local bx = mx + beast.x * scale + scale * 0.5
                local by = my + (map.height - 1 - beast.y) * scale + scale * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, bx, by, scale * 0.7)
                nvgFillColor(vg, nvgRGBAf(0.8, 0.2, 0.15, 0.85))
                nvgFill(vg)
            end
        end
    else
        for _, ep in ipairs(map.evacuationPoints) do
            local fs = FogOfWar.getState(ep.x, ep.y)
            if fs ~= FogOfWar.DARK then
                local ex = mx + ep.x * scale + scale * 0.5
                local ey = my + (map.height - 1 - ep.y) * scale + scale * 0.5
                nvgBeginPath(vg)
                nvgCircle(vg, ex, ey, 2.5)
                nvgFillColor(vg, nvgRGBAf(0.2, 0.6, 0.9, 0.9))
                nvgFill(vg)
            end
        end
    end

    local px = mx + self.playerX * scale + scale * 0.5
    local py = my + (map.height - 1 - self.playerY) * scale + scale * 0.5
    local dotR = expanded and 4.5 or 2.5
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, dotR + 2)
    nvgFillColor(vg, nvgRGBAf(1, 0.85, 0.3, 0.3 + math.sin(t * 4) * 0.15))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, px, py, dotR)
    nvgFillColor(vg, nvgRGBAf(1, 0.9, 0.35, 1))
    nvgFill(vg)

    if not expanded then
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 9)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBAf(0.6, 0.55, 0.5, 0.7))
        nvgText(vg, mx + mw * 0.5, my + mh + 3, "[ 点击展开 ]")
    end
end

end -- return function(ES)
