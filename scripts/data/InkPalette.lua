--- 水墨调色板 - 唯一色彩定义源
local InkPalette = {
    -- 宣纸
    paper     = { r = 0.96, g = 0.93, b = 0.87 },
    paperWarm = { r = 0.94, g = 0.90, b = 0.82 },
    -- 墨色五阶
    inkDark   = { r = 0.08, g = 0.06, b = 0.05 },
    inkStrong = { r = 0.18, g = 0.15, b = 0.13 },
    inkMedium = { r = 0.35, g = 0.32, b = 0.28 },
    inkLight  = { r = 0.55, g = 0.52, b = 0.47 },
    inkWash   = { r = 0.78, g = 0.75, b = 0.70 },
    -- 点缀色
    cinnabar  = { r = 0.76, g = 0.23, b = 0.18 },
    gold      = { r = 0.80, g = 0.68, b = 0.20 },
    jade      = { r = 0.30, g = 0.58, b = 0.45 },
    indigo    = { r = 0.22, g = 0.30, b = 0.48 },
    azure     = { r = 0.35, g = 0.55, b = 0.72 },
    -- 品质色
    qualR     = { r = 0.55, g = 0.52, b = 0.47 },
    qualSR    = { r = 0.35, g = 0.55, b = 0.72 },
    qualSSR   = { r = 0.80, g = 0.68, b = 0.20 },
    -- 灾变/迷雾
    miasmaLight = { r = 0.45, g = 0.15, b = 0.12 },
    miasmaDark  = { r = 0.30, g = 0.05, b = 0.05 },
}

--- 获取品质对应色
---@param quality string "R"|"SR"|"SSR"
---@return table
function InkPalette.qualColor(quality)
    if quality == "SSR" then return InkPalette.qualSSR
    elseif quality == "SR" then return InkPalette.qualSR
    else return InkPalette.qualR end
end

return InkPalette
