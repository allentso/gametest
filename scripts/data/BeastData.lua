--- 异兽数据表（24只）—— v3.0 基于《山海经》原典重构
--- SSR 001-006（六灵）/ SR 007-016（十异）/ R 017-024（八兆）
local BeastData = {
    ----------------------------------------------------------------
    -- SSR · 六灵
    ----------------------------------------------------------------
    {
        id = "001", name = "烛龙", quality = "SSR",
        element = {"暗","光"}, combatType = "territorial",
        bodySize = 0.70, baseSpeed = 1.5, fleeChance = 0, senseRange = 5,
        territoryRadius = 8, hp = 10,
        qteType = "daynight",
        desc = "人面蛇身而赤，直目正乘，其瞑乃晦，其视乃明",
        lore = "《山海经·大荒北经》：有神，人面蛇身而赤，直目正乘，其瞑乃晦，其视乃明，不食不寝不息，风雨是谒，是烛九阴，是谓烛龙。",
        captureTip = "在烛龙眼开（白昼）的最后1秒绕至背后，眼合瞬间发动压制——此时烛龙进入眼合准备状态，反应延迟1秒，是最安全的背刺窗口。",
    },
    {
        id = "002", name = "应龙", quality = "SSR",
        element = {"雷","风"}, combatType = "aggressive",
        bodySize = 0.75, baseSpeed = 2.8, fleeChance = 0, senseRange = 5,
        hp = 12,
        qteType = "dragonwing",
        desc = "有翼神龙，鳞甲金褐，双翼展开遮蔽半屏",
        lore = "《山海经·大荒东经》：应龙处南极，杀蚩尤与夸父，不得复上，故下数旱。旱而为应龙之状，乃得大雨。",
        captureTip = "触发雷霆怒吼后的2秒硬直是最佳背刺时机；竹林内风压横扫范围缩减为1.5格。",
    },
    {
        id = "003", name = "凤凰", quality = "SSR",
        element = {"炎","光"}, combatType = "passive",
        bodySize = 0.60, baseSpeed = 2.0, fleeChance = 0.4, senseRange = 4,
        hp = 8,
        qteType = "fiverhythm",
        fleeSpeed = 3.5,
        desc = "五采而文，自歌自舞，见则天下安宁",
        lore = "《山海经·南山经》：有鸟焉，其状如鸡，五采而文，名曰凤皇。首文曰德，翼文曰义，背文曰礼，膺文曰仁，腹文曰信。是鸟也，饮食自然，自歌自舞，见则天下安宁。",
        captureTip = "等待歌舞状态是最低风险的捕获时机；若错过歌舞窗口，凤凰会飞向地图边缘逃离，速度极快。",
    },
    {
        id = "004", name = "白泽", quality = "SSR",
        element = "光", combatType = "passive",
        bodySize = 0.48, baseSpeed = 1.8, fleeChance = 0, senseRange = 6,
        hp = 8,
        qteType = "bagua",
        desc = "通万物之情，知鬼神之事，角生白芒",
        lore = "《云笈七签》引《轩辕本纪》：黄帝巡于东海，登桓山，于海滨得白泽神兽，能言，达于万物之情。因问天下鬼神之事。",
        captureTip = "使用疾风符让自己移速大幅提升后立刻停止，利用惯性停止的瞬间作为进入静止状态的起点，比正常走近更快进入凝视流程。",
    },
    {
        id = "005", name = "白虎", quality = "SSR",
        element = {"风","金"}, combatType = "aggressive",
        bodySize = 0.65, baseSpeed = 3.0, fleeChance = 0, senseRange = 5,
        hp = 12,
        qteType = "goldclaw",
        desc = "纯白大虎，额头王字纹，四爪赤金印记",
        lore = "《宋书·符瑞志》引《瑞应图》：王者不暴虐，则白虎仁兽见。",
        captureTip = "使用封印阵——白虎进入法阵范围后attack状态暂停，可直接从法阵内背刺。",
    },
    {
        id = "006", name = "麒麟", quality = "SSR",
        element = {"土","光"}, combatType = "passive",
        bodySize = 0.58, baseSpeed = 2.0, fleeChance = 0, senseRange = 4,
        hp = 10,
        qteType = "fourspirits",
        desc = "鹿身牛尾马蹄，头生独角，通体柔和金光",
        lore = "《礼记·礼运》：麟、凤、龟、龙，谓之四灵。",
        captureTip = "麒麟感知回避依赖视野判断——利用黑夜状态接近时感知范围降至1格。",
    },
    ----------------------------------------------------------------
    -- SR · 十异
    ----------------------------------------------------------------
    {
        id = "007", name = "饕餮", quality = "SR",
        element = "暗", combatType = "aggressive",
        bodySize = 0.55, baseSpeed = 2.0, fleeChance = 0.15, senseRange = 4,
        hp = 6,
        qteType = "devour",
        desc = "羊身人面，目在腋下，虎齿人爪，音如婴儿",
        lore = "《山海经·北山经》：有兽焉，其状如羊身人面，其目在腋下，虎齿人爪，其音如婴儿，名曰狍鸮，是食人。",
        captureTip = "饕餮追击越久越快，不要拉锯——使用灵符弹眩晕后立即绕背。",
    },
    {
        id = "008", name = "穷奇", quality = "SR",
        element = {"暗","风"}, combatType = "aggressive",
        bodySize = 0.58, baseSpeed = 2.3, fleeChance = 0.20, senseRange = 4,
        hp = 6,
        qteType = "spinearmor",
        skillImmune = true,
        desc = "其状如牛，猬毛，音如嗥狗，是食人",
        lore = "《山海经·西山经》：有兽焉，其状如牛，猬毛，名曰穷奇，音如嗥狗，是食人。",
        captureTip = "穷奇对控制技能免疫但技能伤害仍有效；嚎狗乱吠触发时立刻脱离当前区域。",
    },
    {
        id = "009", name = "梼杌", quality = "SR",
        element = "暗", combatType = "territorial",
        bodySize = 0.62, baseSpeed = 1.8, fleeChance = 0, senseRange = 4,
        territoryRadius = 9, hp = 7,
        qteType = "rocksmash",
        ccImmune = true,
        desc = "似虎似犬，长毛蓬乱，面目模糊，不可教训",
        lore = "《左传·文公十八年》：颛顼有不才子，不可教训，不知话言，天下谓之梼杌。",
        captureTip = "梼杌免疫控制技能且不跨出领地——在领地边界绕后进入背刺最安全。",
    },
    {
        id = "010", name = "混沌", quality = "SR",
        element = "混沌", combatType = "passive",
        bodySize = 0.50, baseSpeed = 1.5, fleeChance = 0, senseRange = 1.5,
        hp = 4,
        qteType = "facelessdance",
        desc = "如黄囊，赤如丹火，六足四翼，浑敦无面目，是识歌舞",
        lore = "《山海经·西山经》：有神焉，其状如黄囊，赤如丹火，六足四翼，浑敦无面目，是识歌舞，实惟帝江也。",
        captureTip = "混沌是唯一值得等待而非追击的SR——歌舞模式提供的接近机会远比强行追击安全。",
    },
    {
        id = "011", name = "九婴", quality = "SR",
        element = {"水","炎"}, combatType = "aggressive",
        bodySize = 0.60, baseSpeed = 1.8, fleeChance = 0.25, senseRange = 4,
        hp = 6,
        qteType = "nineheads",
        desc = "九头蛇龙，四水头四火头一金色主头",
        lore = "王逸注《楚辞》：九婴，大水火之怪，为人害，之地有凶水。",
        captureTip = "触发九首齐鸣后在2秒窗口内背刺主头；或使用驱散法清除地面障碍从侧面绕背。",
    },
    {
        id = "012", name = "猰貐", quality = "SR",
        element = "暗", combatType = "territorial",
        bodySize = 0.52, baseSpeed = 2.0, fleeChance = 0, senseRange = 3,
        territoryRadius = 5, hp = 6,
        qteType = "snakebody",
        revivable = true,
        desc = "蛇身人面，死而复生，化为食人怪",
        lore = "《淮南子》：猰貐，死而复生，化为食人怪。《山海经》：蛇身人面，贰负臣所杀也。",
        captureTip = "假死状态可直接发动压制（无需重新触发warn）；封灵回响道具可封灵失败后直接二次压制。",
    },
    {
        id = "013", name = "毕方", quality = "SR",
        element = "炎", combatType = "ambush",
        bodySize = 0.48, baseSpeed = 2.5, fleeChance = 0.35, senseRange = 3,
        hp = 5,
        qteType = "singlefoot",
        desc = "鹤形一足，赤文青质白喙，见则其邑有讹火",
        lore = "《山海经·西山经》：有鸟焉，其状如鹤，一足，赤文青质而白喙，名曰毕方，其鸣自叫也，见则其邑有讹火。",
        captureTip = "驱散法可清除毕方制造的火焰地格；竹林中毕方不会主动追击。",
    },
    {
        id = "014", name = "乘黄", quality = "SR",
        element = {"光","金"}, combatType = "passive",
        bodySize = 0.45, baseSpeed = 2.8, fleeChance = 0.45, senseRange = 4,
        hp = 4,
        qteType = "gallop",
        sprintSpeed = 4.5, sprintDuration = 3.0,
        desc = "狐形，背上有角，乘之寿二千岁",
        lore = "《山海经·海外西经》：有乘黄，其状如狐，其背上有角，乘之寿二千岁。",
        captureTip = "使用追迹弹后乘黄无法触发角力冲刺；迷雾残图道具可提前获知地图走廊便于堵截。",
    },
    {
        id = "015", name = "文鳐鱼", quality = "SR",
        element = {"水","风"}, combatType = "passive",
        bodySize = 0.45, baseSpeed = 2.0, fleeChance = 0, senseRange = 3,
        hp = 4,
        qteType = "wingflight",
        flying = true,
        desc = "鱼身鸟翼，苍文白首赤喙，以夜飞",
        lore = "《山海经·西山经》：是多文鳐鱼，状如鲤鱼，鱼身而鸟翼，苍文而白首，赤喙，常行西海，游于东海，以夜飞。其音如鸾鸡，见则天下大穰。",
        captureTip = "记录降落时间规律，提前到达预计降落位置；携带迷雾残图可提前定位其游荡区域。",
    },
    {
        id = "016", name = "九尾狐", quality = "SR",
        element = {"炎","暗"}, combatType = "ambush",
        bodySize = 0.50, baseSpeed = 2.8, fleeChance = 0.50, senseRange = 4,
        hp = 6,
        qteType = "shapeshift",
        ambushRange = 1.5,
        desc = "狐而九尾，音如婴儿，能食人；食者不蛊",
        lore = "《山海经·南山经》：有兽焉，其状如狐而九尾，其音如婴儿，能食人；食者不蛊。",
        captureTip = "无论九尾狐伪装何种外形，叫声始终为婴儿笑声——靠音效识破伪装；兽目珠可穿透幻化。",
    },
    ----------------------------------------------------------------
    -- R · 八兆
    ----------------------------------------------------------------
    {
        id = "017", name = "帝江", quality = "R",
        element = "混沌", combatType = "passive",
        bodySize = 0.38, baseSpeed = 1.5, fleeChance = 0.30, senseRange = 1.5,
        hp = 4,
        qteType = "timing",
        desc = "如黄囊，赤如丹火，六足四翼，浑敦无面目（幼体）",
        lore = "帝江为混沌之幼态，形如小黄囊，歌舞旋转间飘忽不定。",
        captureTip = "帝江感知差，追上即压制，无需背刺。",
    },
    {
        id = "018", name = "当康", quality = "R",
        element = "土", combatType = "passive",
        bodySize = 0.35, baseSpeed = 0.8, fleeChance = 0.20, senseRange = 2,
        hp = 3,
        qteType = "timing",
        desc = "如豚而有牙，鸣自叫，见则天下大穰",
        lore = "《山海经·东山经》：有兽焉，其状如豚而有牙，其名曰当康，其鸣自叫，见则天下大穰。",
        captureTip = "找到资源密集区，等待当康进食窗口，是最省时省力的方法。",
    },
    {
        id = "019", name = "狸力", quality = "R",
        element = "土", combatType = "territorial",
        bodySize = 0.38, baseSpeed = 1.5, fleeChance = 0, senseRange = 3,
        territoryRadius = 4, hp = 4,
        qteType = "timing",
        desc = "如豚有距，音如狗吠，见则其县多土功",
        lore = "《山海经·南山经》：有兽焉，其状如豚，有距，其音如狗吠，其名曰狸力，见则其县多土功。",
        captureTip = "领地型教学对象——在warn期间绕到背后，等警告结束前0.3秒发动压制即可触发背刺。",
    },
    {
        id = "020", name = "旋龟", quality = "R",
        element = {"水","土"}, combatType = "territorial",
        bodySize = 0.42, baseSpeed = 0.6, fleeChance = 0, senseRange = 3,
        territoryRadius = 3.5, hp = 5,
        qteType = "charge",
        shellDefense = 0.4,
        desc = "如龟而鸟首虺尾，音如判木，佩之不聋",
        lore = "《山海经·南山经》：有神焉，其状如龟而鸟首虺尾，其名曰旋龟，其音如判木，佩之不聋，可以为底。",
        captureTip = "旋龟蛇尾攻击朝后，从正面接近反而安全——warn期间直接正面压制。",
    },
    {
        id = "021", name = "并封", quality = "R",
        element = "暗", combatType = "territorial",
        bodySize = 0.42, baseSpeed = 1.3, fleeChance = 0, senseRange = 3,
        territoryRadius = 4, hp = 4,
        qteType = "dualhead",
        dualHead = true,
        desc = "如彘，前后皆有首，黑",
        lore = "《山海经·海外西经》：并封在巫咸东，其状如彘，前后皆有首，黑。",
        captureTip = "封印阵是捕并封的核心道具；没有封印阵时可用灵符弹眩晕一个头再发动压制。",
    },
    {
        id = "022", name = "何罗鱼", quality = "R",
        element = "水", combatType = "passive",
        bodySize = 0.40, baseSpeed = 1.0, fleeChance = 0.25, senseRange = 2,
        hp = 3,
        qteType = "rapidtap",
        desc = "一首而十身，音如吠犬，食之已痈",
        lore = "《山海经·北山经》：有鱼焉，一首而十身，其音如吠犬，名曰何罗鱼，食之已痈。",
        captureTip = "何罗鱼移速慢且逃跑时十身分散降低速度。追击时靠近叫声最响方向。",
    },
    {
        id = "023", name = "化蛇", quality = "R",
        element = "水", combatType = "ambush",
        bodySize = 0.40, baseSpeed = 2.2, fleeChance = 0, senseRange = 2,
        hp = 3,
        qteType = "soundwave",
        ambushRange = 1.0, ambushStun = 0.8,
        desc = "人面豺身，鸟翼蛇行，音如叱呼，见则大水",
        lore = "《山海经·中山经》：有兽焉，名曰化蛇，其状如人面而豺身，鸟翼而蛇行，其音如叱呼，见则其邑大水。",
        captureTip = "化蛇是R级中最快的伏击型但硬直最长。现身时后退1格，等硬直结束后绕背。",
    },
    {
        id = "024", name = "蜚", quality = "R",
        element = "毒", combatType = "territorial",
        bodySize = 0.45, baseSpeed = 1.0, fleeChance = 0, senseRange = 3,
        territoryRadius = 4, hp = 4,
        qteType = "charge",
        poisonTrail = true,
        desc = "如牛白首一目蛇尾，行水则竭行草则死，见则大疫",
        lore = "《山海经·东山经》：有兽焉，其状如牛而白首，一目而蛇尾，其名曰蜚。行水则竭，行草则死，见则天下大疫。",
        captureTip = "优先使用驱散法清出接近路径再背刺；或穿越竹林绕背（竹林隔绝毒性传播）。",
    },
}

----------------------------------------------------------------
-- 查询接口
----------------------------------------------------------------

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

----------------------------------------------------------------
-- 灵境→异兽分布
----------------------------------------------------------------
local BIOME_POOLS = {
    ["翠谷灵境"] = {
        R   = { "017", "019", "020", "022", "018" },
        SR  = { "014", "015", "010", "016" },
        SSR = { "006", "004" },
    },
    ["雷峰灵境"] = {
        R   = { "023", "021", "024", "019" },
        SR  = { "013", "008", "011" },
        SSR = { "002", "005" },
    },
    ["焰渊灵境"] = {
        R   = { "018", "023", "024" },
        SR  = { "007", "016", "013" },
        SSR = { "003", "001" },
    },
    ["幽潭灵境"] = {
        R   = { "020", "022", "021", "017" },
        SR  = { "012", "011", "010" },
        SSR = { "001", "004" },
    },
    ["虚空灵境"] = {
        R   = { "017","018","019","020","021","022","023","024" },
        SR  = { "007","008","009","010","011","012","013","014","015","016" },
        SSR = { "001","002","003","004","005","006" },
    },
}

function BeastData.getRandomForBiome(biomeName, quality)
    local pool = BIOME_POOLS[biomeName] or BIOME_POOLS["翠谷灵境"]
    local tier = quality or "R"
    local ids = pool[tier]
    if not ids or #ids == 0 then
        ids = pool["R"]
    end
    local id = ids[math.random(#ids)]
    return BeastData.getById(id)
end

function BeastData.getBiomePool(biomeName, quality)
    local pool = BIOME_POOLS[biomeName] or BIOME_POOLS["翠谷灵境"]
    return pool[quality or "R"] or {}
end

function BeastData.getRandom()
    return BeastData[math.random(#BeastData)]
end

return BeastData
