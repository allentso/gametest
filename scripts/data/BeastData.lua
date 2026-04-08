--- 异兽数据表（10只）
local BeastData = {
    { id = "001", name = "玄狐", element = "火", bodySize = 0.42, baseSpeed = 2.0, fleeChance = 0.3, senseRange = 3 },
    { id = "002", name = "噬天", element = "暗", bodySize = 0.55, baseSpeed = 1.5, fleeChance = 0.2, senseRange = 4 },
    { id = "003", name = "雷翼", element = "雷", bodySize = 0.50, baseSpeed = 2.5, fleeChance = 0.4, senseRange = 4 },
    { id = "004", name = "白泽", element = "光", bodySize = 0.48, baseSpeed = 1.8, fleeChance = 0.3, senseRange = 5 },
    { id = "005", name = "石灵", element = "土", bodySize = 0.45, baseSpeed = 1.2, fleeChance = 0.1, senseRange = 3 },
    { id = "006", name = "水蛟", element = "水", bodySize = 0.50, baseSpeed = 2.2, fleeChance = 0.4, senseRange = 4 },
    { id = "007", name = "风鸣", element = "风", bodySize = 0.38, baseSpeed = 3.0, fleeChance = 0.5, senseRange = 4 },
    { id = "008", name = "土偶", element = "土", bodySize = 0.52, baseSpeed = 1.0, fleeChance = 0.1, senseRange = 3 },
    { id = "009", name = "冰蚕", element = "冰", bodySize = 0.35, baseSpeed = 1.5, fleeChance = 0.3, senseRange = 3 },
    { id = "010", name = "墨鸦", element = "火", bodySize = 0.40, baseSpeed = 2.8, fleeChance = 0.5, senseRange = 4 },
}

function BeastData.getById(id)
    for _, b in ipairs(BeastData) do
        if b.id == id then return b end
    end
    return nil
end

function BeastData.getByName(name)
    for _, b in ipairs(BeastData) do
        if b.name == name then return b end
    end
    return nil
end

function BeastData.getRandomForBiome(biomeName)
    -- 灵境→异兽映射
    local biomeBeasts = {
        ["翠谷灵境"] = { "005", "008", "007", "006", "009" },
        ["雷峰灵境"] = { "003", "004", "007" },
        ["焰渊灵境"] = { "001", "010", "005" },
        ["幽潭灵境"] = { "006", "009", "002" },
        ["虚空灵境"] = { "001", "002", "003", "004", "005", "006", "007", "008", "009", "010" },
    }
    local pool = biomeBeasts[biomeName] or biomeBeasts["翠谷灵境"]
    local id = pool[math.random(#pool)]
    return BeastData.getById(id)
end

function BeastData.getRandom()
    return BeastData[math.random(#BeastData)]
end

return BeastData
