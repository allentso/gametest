--- 合成系统
local EventBus = require("systems.EventBus")

local CraftSystem = {}

CraftSystem.recipes = {
    { id = "sealer_t2", name = "青玉壶",  tier = "T2", cost = { lingshi = 3 } },
    { id = "sealer_t3", name = "金缕珠",  tier = "T3", cost = { lingshi = 5, shouhun = 1 } },
    { id = "sealer_t4", name = "天命盘",  tier = "T4", cost = { lingshi = 15, shouhun = 5, tianjing = 2 } },
}

function CraftSystem.canCraft(recipeId, inventory)
    local recipe = CraftSystem.getRecipe(recipeId)
    if not recipe then return false end
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
    inventory[recipeId] = (inventory[recipeId] or 0) + 1
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
