-- Sound Design Search Expander v2.1
-- 输入设计需求关键词，输出多维度扩展搜索词
-- 功能：同义词扩展 + UCS分类发现 + 个人经验映射 + 布尔搜索导出
-- 支持中文短语输入，按维度分类输出英文搜索词

local ctx = reaper.ImGui_CreateContext("Search Expander")

-- ================================================================
-- 路径
-- ================================================================
local script_path = ({reaper.get_action_context()})[2]:match("(.*[/\\])")
local personal_file = script_path .. "personal_mappings.lua"
local history_file = script_path .. "search_history.lua"
local favorites_file = script_path .. "search_favorites.lua"

-- ================================================================
-- 加载 UCS 数据
-- ================================================================
local ucs_ok, ucs_data = pcall(dofile, script_path .. "ucs_data.lua")
local ucs_rev = ucs_ok and ucs_data.rev or {}
local ucs_entries = ucs_ok and ucs_data.entries or {}

local word_to_cats = {}
local all_ucs_words = {}
if ucs_ok then
  for catpath, words in pairs(ucs_entries) do
    for _, w in ipairs(words) do
      if not word_to_cats[w] then word_to_cats[w] = {} end
      table.insert(word_to_cats[w], catpath)
    end
  end
  local set = {}
  for _, words in pairs(ucs_entries) do
    for _, w in ipairs(words) do
      if not set[w] then set[w] = true; table.insert(all_ucs_words, w) end
    end
  end
  table.sort(all_ucs_words)
end

-- ================================================================
-- 中文短语（优先匹配）
-- ================================================================
local phrase_cn = {
  ["脚步声"]="footstep", ["雷声"]="thunder", ["玻璃碎裂"]="glass shatter",
  ["枪声"]="gunshot", ["爆炸声"]="explosion", ["引擎声"]="engine",
  ["水滴声"]="water drip", ["风声"]="wind", ["雨声"]="rain",
  ["心跳声"]="heartbeat", ["呼吸声"]="breath", ["尖叫声"]="scream",
  ["笑声"]="laugh", ["哭声"]="cry", ["耳语声"]="whisper",
  ["金属碰撞"]="metal impact", ["木头断裂"]="wood break",
  ["门打开"]="door open", ["门关闭"]="door close",
  ["电火花"]="electric spark", ["机器运转"]="mechanical",
  ["虫鸣声"]="insect", ["鸟叫声"]="bird",
  ["电磁炮充能"]="sci_fi energy riser", ["激光射击"]="laser shot",
  ["飞船引擎"]="aircraft engine", ["汽车刹车"]="car brake",
}

-- ================================================================
-- 中文单字/词映射
-- ================================================================
local cn = {
  ["电"]="electric", ["电流"]="electric", ["电磁"]="electric", ["火花"]="spark",
  ["能量"]="energy", ["充能"]="energy", ["雷"]="lightning", ["雷电"]="lightning",
  ["冲击"]="impact", ["碰撞"]="impact", ["撞击"]="impact", ["打击"]="impact",
  ["爆炸"]="explosion", ["爆"]="explosion", ["炸"]="explosion", ["砰"]="impact",
  ["金属"]="metal", ["铁"]="metal", ["钢"]="metal", ["铜"]="metal", ["铝"]="metal",
  ["玻璃"]="glass", ["碎"]="glass", ["水晶"]="glass",
  ["木"]="wood", ["木头"]="wood", ["木质"]="wood", ["门"]="door",
  ["石"]="stone", ["石头"]="stone", ["岩"]="stone",
  ["陶瓷"]="ceramic", ["瓷"]="ceramic", ["塑料"]="plastic",
  ["橡胶"]="rubber", ["弹力"]="rubber",
  ["嗖"]="whoosh", ["呼啸"]="whoosh", ["飞"]="whoosh", ["风"]="wind",
  ["上升"]="riser", ["渐强"]="riser", ["升起"]="riser",
  ["下降"]="downer", ["落"]="fall", ["坠"]="fall",
  ["过渡"]="transition",
  ["水"]="water", ["滴"]="water", ["流"]="water", ["火"]="fire", ["燃"]="fire",
  ["虫"]="insect", ["昆虫"]="insect", ["蝉"]="insect", ["鸟"]="bird",
  ["动物"]="animal", ["雨"]="rain", ["雪"]="snow",
  ["噪"]="noise", ["噪音"]="noise", ["失真"]="distortion",
  ["干净"]="clean", ["清"]="clean", ["混响"]="reverb", ["滤波"]="filter",
  ["节奏"]="rhythm", ["鼓"]="percussion", ["打击乐"]="percussion",
  ["机械"]="mechanical", ["齿轮"]="mechanical", ["引擎"]="mechanical",
  ["恐怖"]="horror", ["暗"]="horror", ["科幻"]="sci_fi", ["太空"]="sci_fi",
  ["电影"]="cinematic", ["史诗"]="cinematic", ["故障"]="glitch",
  ["梦幻"]="dreamy", ["梦"]="dreamy",
  ["枪"]="gun", ["枪声"]="gunshot", ["手枪"]="pistol", ["步枪"]="rifle",
  ["霰弹"]="shotgun", ["子弹"]="bullet", ["武器"]="gun",
  ["车"]="car", ["汽车"]="car", ["卡车"]="truck", ["摩托"]="motorcycle",
  ["飞机"]="aircraft", ["火车"]="train", ["船"]="boat",
  ["人声"]="voice", ["尖叫"]="scream", ["笑"]="laugh", ["哭"]="cry",
  ["呼吸"]="breath", ["耳语"]="whisper",
  ["脚步"]="footstep", ["走路"]="footstep",
  ["点击"]="click", ["鼠标"]="click",
  ["声"]="sound",
}

-- ================================================================
-- 同义词表（分层：sound/material/object）
-- ================================================================
local synonyms = {
  gun = {sound={"shot","bang","report","discharge","fire","blast"}, material={"firearm","weapon","steel","lead","brass"}, object={"pistol","rifle","shotgun","revolver","handgun","trigger","hammer","cylinder","magazine"}},
  gunshot = {sound={"shot","bang","report","crack","thunder","pop","boom","blast"}, material={"ammunition","cartridge","bullet","slug","pellet","charge","ball","lead","brass"}, object={"missile","projectile","shell","cannonball","dumdum","cap","round"}},
  explosion = {sound={"blast","boom","bang","detonation","burst","eruption","blowout","pop","discharge"}, material={"fire","smoke","debris","shockwave","frag","ash"}, object={"bomb","dynamite","tnt","charge","mine","grenade","c4","torpedo"}},
  impact = {sound={"hit","strike","crash","smash","slam","thump","blow","bang","knock","punch","wallop"}, material={"collision","shock","concussion","jolt","bump","pounding","buffet"}, object={"force","power","energy","damage","dent","mark","scar"}},
  metal = {sound={"clang","ring","clank","clink","jangle","tinkle","chime","ping","resonance"}, material={"steel","iron","brass","aluminum","tin","copper","bronze","chrome","gold","silver"}, object={"anvil","chain","pipe","bell","cymbal","hammer","wrench","bolt","screw"}},
  glass = {sound={"shatter","crack","tinkle","ping","chime","crunch","splinter","fracture"}, material={"crystal","shard","fragment","silica"}, object={"bottle","window","cup","vase","mirror","wine","jar"}},
  wood = {sound={"knock","tap","creak","crack","snap","thump","rap","bang","hollow","resonance"}, material={"bamboo","oak","pine","maple","cedar","plywood","timber","lumber"}, object={"door","drum","block","table","chair","floor","cabinet","box"}},
  stone = {sound={"grind","crack","scrape","drag","tumble","crunch","gravel"}, material={"rock","granite","marble","slate","pebble","boulder","concrete"}, object={"wall","column","statue","monument","cave","mountain"}},
  water = {sound={"drip","splash","bubble","gurgle","trickle","drizzle","spray","pour","flow"}, material={"liquid","fluid","mist","foam","spray","rain","ice"}, object={"creek","river","ocean","lake","waterfall","fountain","pool","wave"}},
  fire = {sound={"crackle","snap","hiss","sizzle","fizzle","roar","pop","flicker"}, material={"flame","blaze","ember","ash","coal","wood","gas","fuel"}, object={"torch","campfire","bonfire","furnace","stove","candle","match","lighter"}},
  wind = {sound={"howl","whistle","moan","sigh","rush","gust","blast","whisper","breeze"}, material={"air","draft","current","gust","breeze","gale","storm"}, object={"tornado","hurricane","cyclone","fan","vent","window"}},
  whoosh = {sound={"swoosh","swish","whistle","zip","whiz","whish","buzz","hum","whir"}, material={"air","wind","breeze","draft"}, object={"fly","pass","fling","throw","sweep","rush"}},
  riser = {sound={"swell","crescendo","build","climb","rise","ascend","grow"}, material={"tension","energy","power","force","surge"}, object={"swell","wave","bloom","expand","inflate"}},
  footstep = {sound={"walk","run","step","stomp","creep","sneak","scuff","shuffle","tramp","tread"}, material={"ground","floor","stair","path","road","trail","grass","gravel"}, object={"boot","shoe","sandal","heel","toe","barefoot"}},
  door = {sound={"open","close","slam","creak","squeak","knock","lock","unlock","latch","hinge"}, material={"wood","metal","glass","plastic"}, object={"entrance","exit","gate","portal","cabinet","cupboard","drawer"}},
  mechanical = {sound={"tick","click","clack","whir","grind","grate","squeak","rattle","hum","buzz"}, material={"gear","motor","engine","piston","valve","servo","pump"}, object={"clock","machine","robot","factory","engine","turbine","generator"}},
  click = {sound={"tap","knock","snap","clack","tick","clink","pop"}, material={"button","switch","trigger","latch"}, object={"mouse","keyboard","switch","lock","camera","remote"}},
  voice = {sound={"vocal","speech","talk","whisper","shout","scream","cry","laugh","moan","groan","sigh","breath"}, material={"breath","air","vocal cord"}, object={"person","human","speaker","singer","actor"}},
  scream = {sound={"shriek","yell","cry","wail","howl","screech","shout","squeal","yelp"}, material={"fear","pain","horror","panic","terror"}, object={"victim","person","child","woman","man"}},
  bird = {sound={"tweet","chirp","song","call","caw","coo","hoot","warble","squawk"}, material={"feather","wing"}, object={"eagle","hawk","owl","raven","crow","sparrow","robin","pigeon"}},
  insect = {sound={"buzz","chirp","cricket","cicada","fly","swarm"}, material={"wing","antenna"}, object={"mosquito","bee","wasp","locust","beetle","moth","butterfly"}},
  car = {sound={"engine","motor","rev","brake","skid","exhaust","horn","beep"}, material={"metal","rubber","glass","plastic"}, object={"tire","door","trunk","hood","bumper","exhaust pipe","steering wheel"}},
  train = {sound={"rail","track","wheel","brake","whistle","horn","coupling"}, material={"steel","iron"}, object={"engine","carriage","platform","station","tunnel","bridge"}},
  aircraft = {sound={"jet","engine","turbine","propeller","flyby","pass","roar"}, material={"aluminum","titanium","composite"}, object={"wing","flap","landing gear","cabin","cockpit","runway"}},
  rain = {sound={"drizzle","pour","storm","drip","patter","thunder","rumble"}, material={"water","droplet","mist"}, object={"umbrella","roof","puddle","flood","storm"}},
  horror = {sound={"screech","scream","dread","doom","whisper","moan","stab","slash"}, material={"blood","dark","shadow"}, object={"ghost","demon","monster","knife","chain","coffin","grave"}},
  sci_fi = {sound={"laser","beam","warp","synth","digital","phaser","hum","buzz"}, material={"energy","plasma","electric"}, object={"robot","computer","screen","hologram","spaceship","portal"}},
  cinematic = {sound={"boom","hit","riser","stinger","drone","pad","texture","atmosphere"}, material={"epic","massive","dramatic"}, object={"trailer","movie","film","scene","act","drama"}},
  glitch = {sound={"error","stutter","skip","repeat","buffer","lag","freeze","crash"}, material={"digital","corrupt","broken"}, object={"computer","screen","signal","data","pixel"}},
  noise = {sound={"white","pink","brown","static","hiss","rumble","grain","grit"}, material={"texture","sand","snow","radio"}, object={"interference","static","background"}},
  distortion = {sound={"crush","fuzz","overdrive","saturate","clip","warp"}, material={"electric","analog","digital"}, object={"guitar","amp","pedal","speaker","signal"}},
  reverb = {sound={"echo","delay","plate","spring","ambient","shimmer"}, material={"space","room","cave","hall","cathedral"}, object={"chamber","tank","plate","algorithm"}},
}

-- ================================================================
-- 个人映射
-- ================================================================
local function load_personal() local ok, data = pcall(dofile, personal_file); return (ok and type(data) == "table") and data or {} end
local function save_personal(data) local f = io.open(personal_file, "w"); if f then f:write("return {\n"); for src, targets in pairs(data) do f:write(string.format("  [%q] = {", src)); for i, t in ipairs(targets) do if i > 1 then f:write(",") end; f:write(string.format("%q", t)) end; f:write("},\n") end; f:write("}\n"); f:close() end end
local function load_list(file) local ok, data = pcall(dofile, file); return (ok and type(data) == "table") and data or {} end
local function save_list(file, data) local f = io.open(file, "w"); if f then f:write("return {\n"); for _, v in ipairs(data) do f:write(string.format("  %q,\n", v)) end; f:write("}\n"); f:close() end end
local function load_favorites_map(file) local ok, data = pcall(dofile, file); return (ok and type(data) == "table") and data or {} end
local function save_favorites_map(file, data) local f = io.open(file, "w"); if f then f:write("return {\n"); for k, v in pairs(data) do f:write(string.format("  [%q] = true,\n", k)) end; f:write("}\n"); f:close() end end

-- ================================================================
-- UI state
-- ================================================================
local input_buf = ""
local prev_input = ""
local base_results = nil
local results = nil
local suggestions = nil
local first_frame = true
local history = load_list(history_file)
local favorites = load_favorites_map(favorites_file)
local collapsed_cats = {}
local history_open = false
local favorites_open = false
local personal_mappings = load_personal()
local show_add_mapping = false
local mapping_source = ""
local mapping_target = ""
local mapping_bidir = true
local search_cache = {}

-- 条件构建器状态
local show_builder = false
local builder_conditions = {{text="", relation=0}}  -- {text, relation: 0=且,1=或,2=非}
local builder_and_groups = {}
local builder_or_groups = {}
local builder_not_terms = {}
local builder_query = ""

-- ================================================================
-- 分词 + 短语优先匹配
-- ================================================================
local function tokenize(input)
  local terms = {}
  local remaining = input
  for phrase, en in pairs(phrase_cn) do
    if remaining:find(phrase, 1, true) then
      table.insert(terms, en)
      remaining = remaining:gsub(phrase, " ")
    end
  end
  for word in remaining:gmatch("[^,，%s/]+") do
    local w = word:lower():gsub("^%s+",""):gsub("%s+$","")
    if w ~= "" then table.insert(terms, cn[w] or w) end
  end
  return terms
end

-- ================================================================
-- 前缀匹配
-- ================================================================
local function find_prefix_matches(prefix)
  local matches = {}
  for _, word in ipairs(all_ucs_words) do
    if word:find("^" .. prefix) and word ~= prefix then
      table.insert(matches, word)
      if #matches >= 8 then break end
    end
  end
  return matches
end

-- ================================================================
-- 核心扩展
-- ================================================================
local function expand(input)
  if search_cache[input] then return search_cache[input].result, search_cache[input].no_match end
  local terms = tokenize(input)
  local result = {syn={}, mat={}, obj={}, personal={}, ucs={}}
  local seen = {}
  local no_match = {}

  local function add(list, w)
    if not seen[w] then seen[w] = true; table.insert(list, w) end
  end

  for _, term in ipairs(terms) do
    local found = false
    if synonyms[term] then
      found = true
      for _, w in ipairs(synonyms[term].sound or {}) do add(result.syn, w) end
      for _, w in ipairs(synonyms[term].material or {}) do add(result.mat, w) end
      for _, w in ipairs(synonyms[term].object or {}) do add(result.obj, w) end
    end
    local pm = personal_mappings[term] or personal_mappings[input]
    if pm then
      found = true
      for _, w in ipairs(pm) do
        for sub_w in w:gmatch("%S+") do add(result.personal, sub_w) end
      end
    end
    local cats = ucs_rev[term] or word_to_cats[term]
    if cats then
      found = true
      for _, catpath in ipairs(cats) do
        if not result.ucs[catpath] then
          result.ucs[catpath] = {}
          if ucs_entries[catpath] then
            for _, w in ipairs(ucs_entries[catpath]) do
              if not seen[w] then seen[w] = true; table.insert(result.ucs[catpath], w) end
            end
          end
        end
      end
    end
    if not found then table.insert(no_match, term) end
  end

  search_cache[input] = {result=result, no_match=no_match}
  return result, no_match
end

-- ================================================================
-- 应用条件到基础结果
-- ================================================================
local function apply_conditions(base, conditions)
  if not base then return nil end
  -- 检查是否有有效条件
  local has_conditions = false
  for _, cond in ipairs(conditions) do
    if cond.text ~= "" then has_conditions = true; break end
  end
  if not has_conditions then return base end

  -- 收集条件扩展（按关系分组，保留分类信息）
  local and_list, or_expanded_list, not_set = {}, {}, {}
  for _, cond in ipairs(conditions) do
    if cond.text ~= "" then
      local expanded = expand(cond.text)
      if cond.relation == 0 then
        table.insert(and_list, expanded)
      elseif cond.relation == 1 then
        table.insert(or_expanded_list, expanded)
      else
        local function add_not(list) for _, w in ipairs(list) do not_set[w] = true end end
        add_not(expanded.syn); add_not(expanded.mat); add_not(expanded.obj); add_not(expanded.personal)
        for _, cw in pairs(expanded.ucs) do add_not(cw) end
      end
    end
  end

  -- AND 过滤：取所有 AND 条件扩展词的交集
  local and_pass = {}
  if #and_list > 0 then
    local first = {}
    local function add_first(list) for _, w in ipairs(list) do first[w] = true end end
    add_first(and_list[1].syn); add_first(and_list[1].mat); add_first(and_list[1].obj); add_first(and_list[1].personal)
    for _, cw in pairs(and_list[1].ucs) do add_first(cw) end
    for w in pairs(first) do and_pass[w] = true end
    for i = 2, #and_list do
      local cur = {}
      local function add_cur(list) for _, w in ipairs(list) do cur[w] = true end end
      add_cur(and_list[i].syn); add_cur(and_list[i].mat); add_cur(and_list[i].obj); add_cur(and_list[i].personal)
      for _, cw in pairs(and_list[i].ucs) do add_cur(cw) end
      for w in pairs(and_pass) do if not cur[w] then and_pass[w] = nil end end
    end
  end

  -- 构建最终结果
  local final_syn, final_mat, final_obj, final_personal = {}, {}, {}, {}
  local final_ucs = {}
  local seen = {}

  -- 基础结果过滤（AND + NOT）
  local function add_base(list, w)
    if seen[w] then return end
    if #and_list > 0 and not and_pass[w] then return end
    if not_set[w] then return end
    seen[w] = true; table.insert(list, w)
  end
  for _, w in ipairs(base.syn) do add_base(final_syn, w) end
  for _, w in ipairs(base.mat) do add_base(final_mat, w) end
  for _, w in ipairs(base.obj) do add_base(final_obj, w) end
  for _, w in ipairs(base.personal) do add_base(final_personal, w) end
  for cat, cw in pairs(base.ucs) do
    for _, w in ipairs(cw) do
      if not seen[w] and (#and_list == 0 or and_pass[w]) and not not_set[w] then
        seen[w] = true
        if not final_ucs[cat] then final_ucs[cat] = {} end
        table.insert(final_ucs[cat], w)
      end
    end
  end

  -- OR 追加（仅 NOT 过滤，不走 AND）
  local function add_or(list, w)
    if seen[w] then return end
    if not_set[w] then return end
    seen[w] = true; table.insert(list, w)
  end
  for _, expanded in ipairs(or_expanded_list) do
    for _, w in ipairs(expanded.syn) do add_or(final_syn, w) end
    for _, w in ipairs(expanded.mat) do add_or(final_mat, w) end
    for _, w in ipairs(expanded.obj) do add_or(final_obj, w) end
    for _, w in ipairs(expanded.personal) do add_or(final_personal, w) end
    for cat, cw in pairs(expanded.ucs) do
      for _, w in ipairs(cw) do
        if not seen[w] and not not_set[w] then
          seen[w] = true
          if not final_ucs[cat] then final_ucs[cat] = {} end
          table.insert(final_ucs[cat], w)
        end
      end
    end
  end

  return {syn=final_syn, mat=final_mat, obj=final_obj, personal=final_personal, ucs=final_ucs}
end

-- ================================================================
-- 主循环
-- ================================================================
function loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, 620, 700, reaper.ImGui_Cond_FirstUseEver())
    first_frame = false
  end

  local vis, open = reaper.ImGui_Begin(ctx, "Search Expander v2.1", true)
  if vis then
    if not ucs_ok then
      reaper.ImGui_TextColored(ctx, 0xFF00AAFF, "⚠ UCS 数据未载入，仅使用内置词库")
    end
    
    reaper.ImGui_Text(ctx, "输入关键词：")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, -230)
    local changed, new_val = reaper.ImGui_InputText(ctx, "##input", input_buf, 256)
    if changed and new_val ~= input_buf then input_buf = new_val end
    if input_buf ~= prev_input then
      prev_input = input_buf
      if input_buf ~= "" then
        local no_match
        base_results, no_match = expand(input_buf)
        results = apply_conditions(base_results, builder_conditions)
        suggestions = {}
        for _, term in ipairs(no_match) do
          local matches = find_prefix_matches(term)
          if #matches > 0 then suggestions[term] = matches end
        end
      else
        results = nil
        suggestions = nil
      end
    end

    if #input_buf > 0 and not reaper.ImGui_IsItemActive(ctx) then
      local suggestions_list = {}
      local il = input_buf:lower()
      for phrase, _ in pairs(phrase_cn) do
        if phrase:find(il, 1, true) then
          table.insert(suggestions_list, phrase)
          if #suggestions_list >= 5 then break end
        end
      end
      if #suggestions_list > 0 then
        reaper.ImGui_TextColored(ctx, 0xFF888888, "建议：" .. table.concat(suggestions_list, " | "))
      end
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "收藏", 40, 22) and input_buf ~= "" then
      favorites[input_buf] = true
      save_favorites_map(favorites_file, favorites)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "添加", 40, 22) then
      show_add_mapping = not show_add_mapping
      mapping_source = input_buf
      mapping_target = ""
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "历史", 40, 22) then history_open = not history_open; favorites_open = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "收藏夹", 50, 22) then favorites_open = not favorites_open; history_open = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "清除", 40, 22) then
      input_buf = ""
      prev_input = ""
      base_results = nil
      results = nil
      suggestions = nil
      builder_conditions = {{text="", relation=0}}
      builder_query = ""
      collapsed_cats = {}
      history_open = false
      favorites_open = false
      show_add_mapping = false
    end

    if show_add_mapping then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "添加个人映射（支持词组）：")
      reaper.ImGui_Text(ctx, "源词：")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 150)
      local s_changed, s_val = reaper.ImGui_InputText(ctx, "##src", mapping_source, 128)
      if s_changed then mapping_source = s_val end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, "→ 目标词组：")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 200)
      local t_changed, t_val = reaper.ImGui_InputText(ctx, "##tgt", mapping_target, 256)
      if t_changed then mapping_target = t_val end
      reaper.ImGui_SameLine(ctx)
      local bidir_changed, bidir_val = reaper.ImGui_Checkbox(ctx, "双向映射##bidir", mapping_bidir)
      if bidir_changed then mapping_bidir = bidir_val end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "保存") and mapping_source ~= "" and mapping_target ~= "" then
        if not personal_mappings[mapping_source] then personal_mappings[mapping_source] = {} end
        table.insert(personal_mappings[mapping_source], mapping_target)
        if mapping_bidir then
          if not personal_mappings[mapping_target] then personal_mappings[mapping_target] = {} end
          table.insert(personal_mappings[mapping_target], mapping_source)
        end
        save_personal(personal_mappings)
        show_add_mapping = false
      end
      reaper.ImGui_TextColored(ctx, 0xFF888888, "例：电磁炮充能 → sci_fi energy riser")
    end

    if history_open and #history > 0 then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_TextColored(ctx, 0xFF88CC88, "搜索历史：")
      reaper.ImGui_BeginChild(ctx, "##hist", 0, math.min(#history * 22, 150))
      for i = #history, 1, -1 do
        if reaper.ImGui_Selectable(ctx, history[i] .. "##h" .. i) then input_buf = history[i]; prev_input = history[i]; history_open = false end
      end
      reaper.ImGui_EndChild(ctx)
    end

    if favorites_open then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_TextColored(ctx, 0xFFCC8888, "收藏夹：")
      local fav_list = {}
      for k, _ in pairs(favorites) do table.insert(fav_list, k) end
      if #fav_list > 0 then
        reaper.ImGui_BeginChild(ctx, "##fav", 0, math.min(#fav_list * 22, 150))
        for i, fav in ipairs(fav_list) do
          if reaper.ImGui_Selectable(ctx, fav .. "##f" .. i) then input_buf = fav; prev_input = fav; favorites_open = false end
        end
        reaper.ImGui_EndChild(ctx)
      else
        reaper.ImGui_Text(ctx, "收藏夹为空")
      end
    end

    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_Button(ctx, "添加条件", 80, 22) then
      show_builder = not show_builder
    end

    if show_builder then
      for i, cond in ipairs(builder_conditions) do
        reaper.ImGui_PushID(ctx, i)
        
        local rel_labels = {"[且]", "[或]", "[非]"}
        local rel_colors = {0xFF66CC66, 0xFF6666FF, 0xFFFF6666}
        reaper.ImGui_TextColored(ctx, rel_colors[cond.relation + 1], rel_labels[cond.relation + 1])
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_SmallButton(ctx, "切换") then
          builder_conditions[i].relation = (cond.relation + 1) % 3
          if base_results then results = apply_conditions(base_results, builder_conditions) end
        end
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 200)
        local txt_changed, txt_val = reaper.ImGui_InputText(ctx, "##txt", cond.text, 256)
        if txt_changed then
          if base_results then results = apply_conditions(base_results, builder_conditions) end
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "✕") then
          table.remove(builder_conditions, i)
          if base_results then results = apply_conditions(base_results, builder_conditions) end
          reaper.ImGui_PopID(ctx)
          break
        end
        
        reaper.ImGui_PopID(ctx)
      end
      
      if reaper.ImGui_SmallButton(ctx, "+ 添加条件") then
        table.insert(builder_conditions, {text="", relation=0})
      end
      
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "生成查询串") then
        builder_and_groups = {}
        builder_or_groups = {}
        builder_not_terms = {}
        
        for _, cond in ipairs(builder_conditions) do
          if cond.text ~= "" then
            local expanded = expand(cond.text)
            local all_expanded = {}
            for _, w in ipairs(expanded.syn) do table.insert(all_expanded, w) end
            for _, w in ipairs(expanded.mat) do table.insert(all_expanded, w) end
            for _, w in ipairs(expanded.obj) do table.insert(all_expanded, w) end
            for _, w in ipairs(expanded.personal) do table.insert(all_expanded, w) end
            for _, cat_words in pairs(expanded.ucs) do
              for _, w in ipairs(cat_words) do table.insert(all_expanded, w) end
            end
            
            if cond.relation == 0 then
              table.insert(builder_and_groups, all_expanded)
            elseif cond.relation == 1 then
              table.insert(builder_or_groups, all_expanded)
            else
              for _, w in ipairs(all_expanded) do
                table.insert(builder_not_terms, w)
              end
            end
          end
        end
        
        local parts = {}
        for _, group in ipairs(builder_and_groups) do
          if #group > 0 then
            if #group == 1 then table.insert(parts, group[1])
            else table.insert(parts, "(" .. table.concat(group, ", ") .. ")") end
          end
        end
        
        if #builder_or_groups > 0 then
          local or_parts = {}
          for _, group in ipairs(builder_or_groups) do
            if #group > 0 then
              if #group == 1 then table.insert(or_parts, group[1])
              else table.insert(or_parts, "(" .. table.concat(group, ", ") .. ")") end
            end
          end
          if #or_parts > 0 then
            if #parts > 0 then table.insert(parts, ", " .. table.concat(or_parts, ", "))
            else table.insert(parts, table.concat(or_parts, ", ")) end
          end
        end
        
        for _, w in ipairs(builder_not_terms) do
          table.insert(parts, "-" .. w)
        end
        
        builder_query = table.concat(parts, " ")
      end
      
      if builder_query ~= "" then
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "Soundminer 查询串：")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制查询串") then
          reaper.ImGui_SetClipboardText(ctx, builder_query)
        end
        reaper.ImGui_TextWrapped(ctx, builder_query)
      end
    end

    if suggestions and next(suggestions) then
      reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "你是不是要找：")
      reaper.ImGui_SameLine(ctx)
      local x = 0
      for term, matches in pairs(suggestions) do
        for i, word in ipairs(matches) do
          local w = reaper.ImGui_CalcTextSize(ctx, word) + 16
          if x + w > 560 then break end
          if i > 1 or x > 0 then reaper.ImGui_SameLine(ctx) end
          if reaper.ImGui_Button(ctx, word .. "##s" .. term .. i) then
            input_buf = word
            prev_input = word
            local no_match
            base_results, no_match = expand(input_buf)
            results = apply_conditions(base_results, builder_conditions)
            suggestions = nil
            break
          end
          x = x + w
        end
      end
      reaper.ImGui_Separator(ctx)
    end

    if results then
      local all_words = {}
      for _, w in ipairs(results.syn) do table.insert(all_words, w) end
      for _, w in ipairs(results.mat) do table.insert(all_words, w) end
      for _, w in ipairs(results.obj) do table.insert(all_words, w) end
      for _, w in ipairs(results.personal) do table.insert(all_words, w) end
      for _, cw in pairs(results.ucs) do
        for _, w in ipairs(cw) do table.insert(all_words, w) end
      end

      if #all_words > 0 then
        reaper.ImGui_TextColored(ctx, 0xFF8888CC, "结果 (" .. #all_words .. " 词)")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制全部") then
          reaper.ImGui_SetClipboardText(ctx, table.concat(all_words, ", "))
        end
      end

      reaper.ImGui_BeginChild(ctx, "##results", 0, 0)
      
      if #results.syn > 0 then
        reaper.ImGui_TextColored(ctx, 0xFF66CC66, "声音描述 (" .. #results.syn .. ")")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制##syn") then reaper.ImGui_SetClipboardText(ctx, table.concat(results.syn, ", ")) end
        reaper.ImGui_TextWrapped(ctx, table.concat(results.syn, ", "))
        reaper.ImGui_Spacing(ctx)
      end

      if #results.mat > 0 then
        reaper.ImGui_TextColored(ctx, 0xFF66CCCC, "材质属性 (" .. #results.mat .. ")")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制##mat") then reaper.ImGui_SetClipboardText(ctx, table.concat(results.mat, ", ")) end
        reaper.ImGui_TextWrapped(ctx, table.concat(results.mat, ", "))
        reaper.ImGui_Spacing(ctx)
      end

      if #results.obj > 0 then
        reaper.ImGui_TextColored(ctx, 0xFFCC66CC, "发声物体 (" .. #results.obj .. ")")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制##obj") then reaper.ImGui_SetClipboardText(ctx, table.concat(results.obj, ", ")) end
        reaper.ImGui_TextWrapped(ctx, table.concat(results.obj, ", "))
        reaper.ImGui_Spacing(ctx)
      end

      if #results.personal > 0 then
        reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "个人经验 (" .. #results.personal .. ")")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制##per") then reaper.ImGui_SetClipboardText(ctx, table.concat(results.personal, ", ")) end
        reaper.ImGui_TextWrapped(ctx, table.concat(results.personal, ", "))
        reaper.ImGui_Spacing(ctx)
      end

      local ucs_count = 0
      for _ in pairs(results.ucs) do ucs_count = ucs_count + 1 end
      if ucs_count > 0 then
        reaper.ImGui_TextColored(ctx, 0xFF8888CC, "UCS分类 (" .. ucs_count .. ")")
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制##ucs") then
          local ucs_words = {}
          for _, cw in pairs(results.ucs) do
            for _, w in ipairs(cw) do table.insert(ucs_words, w) end
          end
          reaper.ImGui_SetClipboardText(ctx, table.concat(ucs_words, ", "))
        end
        
        for catpath, cat_words in pairs(results.ucs) do
          if #cat_words > 0 then
            local collapsed = collapsed_cats[catpath]
            local arrow = collapsed and ">" or "v"
            if reaper.ImGui_SmallButton(ctx, arrow .. "##u" .. catpath) then
              collapsed_cats[catpath] = not collapsed
              collapsed = collapsed_cats[catpath]
            end
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0xFFAAAA88, catpath .. " (" .. #cat_words .. ")")
            if not collapsed then
              reaper.ImGui_Indent(ctx)
              reaper.ImGui_TextWrapped(ctx, table.concat(cat_words, ", "))
              reaper.ImGui_Unindent(ctx)
              reaper.ImGui_Spacing(ctx)
            end
          end
        end
      end

      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
