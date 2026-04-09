--- 合成系统
local EventBus = require("systems.EventBus")

local CraftSystem = {}

CraftSystem.recipes = {
    { id = "sealer_t2", name = "青玉壶",   tier = "T2", category = "sealer", cost = { lingshi = 3 } },
    { id = "sealer_t3", name = "金缕珠",   tier = "T3", category = "sealer", cost = { lingshi = 5, shouhun = 1 } },
    { id = "sealer_t4", name = "天命盘",   tier = "T4", category = "sealer", cost = { lingshi = 15, shouhun = 5, tianjing = 2 } },
    { id = "sealer_t5", name = "混沌印",   tier = "T5", category = "sealer", cost = { lingshi = 30, shouhun = 12, tianjing = 5, lingyin = 2 } },
    { id = "rushWard",  name = "疾风符",   tier = nil,  category = "item",   cost = { lingshi = 8, traceAsh = 3 } },
    { id = "fogMap",    name = "迷雾残图", tier = nil,  category = "item",   cost = { shouhun = 2 } },
    { id = "sealEcho",  name = "封印回响", tier = nil,  category = "item",   cost = { shouhun = 3, tianjing = 1 } },
    -- 恢复类道具
    { id = "lingquanWan", name = "灵泉丸", tier = nil, category = "recovery", cost = { lingshi = 6 },                          yield = 2 },
    { id = "jianzhulu",   name = "绛珠露", tier = nil, category = "recovery", cost = { lingshi = 10, shouhun = 2 } },
    { id = "fusufu",      name = "复苏符", tier = nil, category = "recovery", cost = { lingshi = 8, shouhun = 3, traceAsh = 2 } },
}

function CraftSystem.canCraft(recipeId, inventory)
    local recipe = CraftSystem.getRecipe(recipeId)
    if not recipe then return false end
    -- T5混沌印使用后，本局禁止合成任何封灵器
    if recipe.category == "sealer" then
        local SessionState = require("systems.SessionState")
        if SessionState.t5Used then return false end
    end
    for res, amount in pairs(recipe.cost) do
        if (inventory[res] or 0) < amount then return false end
    end
    return true
end

function CraftSystem.craft(recipeId, inventory)
    if not CraftSystem.canCraft(recipeId, inventory) then return false end
    local recipe = CraftSystem.getRecipe(recipeId)
    for res, amount in pairs(recipe.cost) do
        inventory[res] = inventory[res] - amount
    end
    local yield = recipe.yield or 1
    inventory[recipeId] = (inventory[recipeId] or 0) + yield
    EventBus.emit("resource_changed", "craft", recipeId)
    return true
end

function CraftSystem.getRecipe(id)
    for _, r in ipairs(CraftSystem.recipes) do
        if r.id == id then return r end
    end
    return nil
end

return CraftSystem
