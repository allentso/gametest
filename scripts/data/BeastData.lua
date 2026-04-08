--- 异兽数据表（10只）—— desc: 图鉴短描述  lore: 百灵志
local BeastData = {
    {
        id = "001", name = "玄狐", element = "火",
        bodySize = 0.42, baseSpeed = 2.0, fleeChance = 0.3, senseRange = 3,
        desc = "三尾赤狐，夜行林间，尾焰如灯",
        lore = "《山海经·南山经》载：青丘之山有兽，其状如狐而九尾。此玄狐仅余三尾，乃千年灵气散逸之故。月圆之夜尾焰最盛，方圆数里草木不生，唯余焦土。然其性惧水，遇溪涧则遁。",
        captureTip = "玄狐惧水，利用竹林隐蔽接近，从背后压制成功率最高。",
    },
    {
        id = "002", name = "噬天", element = "暗",
        bodySize = 0.55, baseSpeed = 1.5, fleeChance = 0.2, senseRange = 4,
        desc = "吞光巨兽，行则天暗，止则地裂",
        lore = "古籍残卷记：太古有兽名噬天，身若丘陵，张口可吞日月之光。其行也，方圆十里如入永夜。封灵师代代相传，遇噬天而生还者十不存一，盖因此兽不惧灵符，唯畏天命盘之光。",
        captureTip = "噬天体型巨大但行动迟缓，需准备高阶封灵器，利用侧翼接近避免正面感知。",
    },
    {
        id = "003", name = "雷翼", element = "雷",
        bodySize = 0.50, baseSpeed = 2.5, fleeChance = 0.4, senseRange = 4,
        desc = "雷电鹰隼，振翅则雷鸣，敛翼则无声",
        lore = "雷峰灵境常见此鸟，双翼展开三丈余，翎羽间电光缭绕。飞行极速，鲜有封灵师能正面追及。古法云：欲擒雷翼，须于暴雨将至时伏于高处，趁其引雷蓄力之际出手，此时其双翼僵直，不可走避。",
        captureTip = "雷翼高速冲刺后会短暂停歇1.5秒，这是唯一的追击窗口。",
    },
    {
        id = "004", name = "白泽", element = "光",
        bodySize = 0.48, baseSpeed = 1.8, fleeChance = 0.3, senseRange = 5,
        desc = "通万物之情，知鬼神之事，角生白芒",
        lore = "《云笈七签》载白泽为瑞兽，能言语，通万物之情。此灵境之白泽虽不能言，然其角所发白芒可照破一切幻术。感知极为敏锐，察觉封灵师气息之距离远超常兽。据传集齐三品白泽，可窥天机一线。",
        captureTip = "白泽会凝视玩家，保持静止3秒可令其放下警戒，此时背刺压制效果极佳。",
    },
    {
        id = "005", name = "石灵", element = "土",
        bodySize = 0.45, baseSpeed = 1.2, fleeChance = 0.1, senseRange = 3,
        desc = "磐石所化，不动如山，动则山崩",
        lore = "石灵本非生灵，乃灵境之石吸纳千年地气而生灵智。其状如嶙峋怪石，不动时与山岩无异。性极温钝，少有主动攻击之举，然受惊则周身碎石飞射，杀伤甚巨。入手虽易，却常被封灵师误作普通岩石而错过。",
        captureTip = "石灵移速极慢且不会逃跑，但压制失败会石化5秒，注意把握QTE节奏。",
    },
    {
        id = "006", name = "水蛟", element = "水",
        bodySize = 0.50, baseSpeed = 2.2, fleeChance = 0.4, senseRange = 4,
        desc = "潜游深潭，鳞光如月，翻腾成雨",
        lore = "水蛟形似小龙而无角，通体覆青白鳞片，月下鳞光粼粼。常居深潭暗流，偶露水面换气。古法捕蛟需以镇灵砂撒于水面，令其灵力紊乱方可迫出。闪光品水蛟据传鳞片可入药，为炼丹上品之材。",
        captureTip = "水蛟常出没于水域地形，远离水域后速度降低，可在旱地拦截压制。",
    },
    {
        id = "007", name = "风鸣", element = "风",
        bodySize = 0.38, baseSpeed = 3.0, fleeChance = 0.5, senseRange = 4,
        desc = "无形之鸟，唯闻其声，不见其影",
        lore = "风鸣体型虽小，速度却冠绝灵境诸兽。行动时仅余一道清风，伴以空灵鸣啭。察觉危险即刻远遁，为封灵师公认最难捕获之灵兽。古来有言：三追风鸣不如一伏白泽。唯背后偷袭方有一线之机。",
        captureTip = "风鸣速度最快但耐力差，连续追逐后会短暂驻足喘息，利用竹林伏击效果最佳。",
    },
    {
        id = "008", name = "土偶", element = "土",
        bodySize = 0.52, baseSpeed = 1.0, fleeChance = 0.1, senseRange = 3,
        desc = "泥塑成形，笨拙忠厚，守望一方",
        lore = "土偶非天然灵兽，相传为上古封灵师以秘法造就之守护。灵境封印松动后，失去主人指令的土偶四处游荡，行动迟缓却力大无穷。封灵后可作看守之用，是初学封灵师最趁手的伙伴。然其灵智有限，指令不可超过三条。",
        captureTip = "土偶最慢且几乎不逃跑，适合新手练习。注意其受惊后碎石反击，保持正面按压即可。",
    },
    {
        id = "009", name = "冰蚕", element = "冰",
        bodySize = 0.35, baseSpeed = 1.5, fleeChance = 0.3, senseRange = 3,
        desc = "天蚕吐寒丝，结茧如冰晶，破茧则蝶",
        lore = "冰蚕体小如拇指，通体晶莹剔透。其丝入水成冰，可编织天蚕衣抵御灵境寒气。最珍者为闪光品冰蚕，破茧化为冰蝶，双翅可凝万年寒冰。据手记载，冰蚕群居于灵境最深处，需追迹灰方能寻踪。",
        captureTip = "冰蚕体型最小不易发现，使用追迹灰可显示其踪迹。封灵时注意寒气冻伤，快速完成QTE。",
    },
    {
        id = "010", name = "墨鸦", element = "火",
        bodySize = 0.40, baseSpeed = 2.8, fleeChance = 0.5, senseRange = 4,
        desc = "漆黑如墨，飞则流焰，落则成灰",
        lore = "墨鸦浑身漆黑，飞行时羽翼燃烧，拖出长长火尾。性极机警，群居而行，一只受惊则全群四散。单独封灵几无可能，须以追迹灰标记其巢穴，待夜深鸦群归巢时方可出手。坊间传闻墨鸦之墨可制灵墨，一滴千金。",
        captureTip = "墨鸦群居且极度警觉，惊扰一只全群逃散。用追迹灰定位巢穴后单独引出落单个体再压制。",
    },
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
