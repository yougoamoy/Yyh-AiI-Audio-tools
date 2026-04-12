-- Sound Design Search Expander v2.2 (Modular)
-- 输入设计需求关键词，输出多维度扩展搜索词
-- 架构：search_modes/ 目录下独立搜索模式，通过注册中心统一调度
--
-- 添加新模式：
--   1. search_modes/ 下新建 xxx.lua，实现 init() 和 expand() 接口
--   2. search_modes/init.lua 中注册
--   3. 主脚本无需修改

local ctx = reaper.ImGui_CreateContext("Search Expander")

-- ================================================================
-- 路径
-- ================================================================
local script_path = ({reaper.get_action_context()})[2]:match("(.*[/\\])")
local history_file = script_path .. "search_history.lua"
local favorites_file = script_path .. "search_favorites.lua"

-- ================================================================
-- 加载搜索模式
-- ================================================================
local modes = dofile(script_path .. "search_modes/init.lua")
modes.load_all(script_path)
local ucs_mode = modes.get("ucs")
local personal_mode = modes.get("personal")

-- ================================================================
-- 内置中文映射（短语级 + 词级）
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

-- 将 cn 表注册到 UCS 模块（用于翻译查询）
if ucs_mode then ucs_mode.register_cn(cn) end

-- ================================================================
-- 格式化工具
-- ================================================================
local function format_en(list)
  local seen = {}
  local unique = {}
  for _, w in ipairs(list) do if not seen[w] then seen[w] = true; table.insert(unique, w) end end
  return table.concat(unique, "\n")
end

local function format_cn(list, catpath)
  local seen = {}
  local unique = {}
  for _, w in ipairs(list) do
    if not seen[w] then
      seen[w] = true
      local c = ucs_mode and ucs_mode.get_cn(w, catpath) or ""
      table.insert(unique, c ~= "" and c or "无中文")
    end
  end
  return table.concat(unique, "\n")
end

-- ================================================================
-- 个人映射持久化
-- ================================================================
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
local search_cache = {}
local zh_candidates = {}
local selected_word = ""

-- 渲染双列词列表（左英右中，各自可点击）
local function draw_words(words, catpath, id_prefix)
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  local col_w = math.floor(avail_w / 2) - 4
  local cur_x = 0
  local need_sep = false
  for i, w in ipairs(words) do
    local zh = ucs_mode and ucs_mode.get_cn(w, catpath) or ""
    if need_sep then
      if cur_x + col_w * 2 + 8 <= avail_w then
        reaper.ImGui_SameLine(ctx, 0, 8)
        cur_x = cur_x + 8
      else
        cur_x = 0
      end
    end
    local en_w = reaper.ImGui_CalcTextSize(ctx, w) + 16
    if reaper.ImGui_Selectable(ctx, w .. "##e" .. id_prefix .. i, selected_word == w,
        reaper.ImGui_SelectableFlags_AllowDoubleClick(), en_w) then
      selected_word = w
      if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
        input_buf = w; prev_input = ""; zh_candidates = {}
      end
    end
    cur_x = cur_x + en_w
    if zh ~= "" then
      reaper.ImGui_SameLine(ctx, 0, 2)
      local cn_w = reaper.ImGui_CalcTextSize(ctx, zh) + 16
      if reaper.ImGui_Selectable(ctx, zh .. "##c" .. id_prefix .. i, selected_word == zh,
          reaper.ImGui_SelectableFlags_AllowDoubleClick(), cn_w) then
        selected_word = zh
        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          input_buf = zh; prev_input = ""; zh_candidates = {}
        end
      end
      cur_x = cur_x + cn_w + 2
    end
    need_sep = true
  end
end

-- 搜索历史导航
local nav_history = {}
local nav_pos = 0

local function nav_push(query)
  if query == "" then return end
  if nav_history[nav_pos] == query then return end
  while #nav_history > nav_pos do table.remove(nav_history) end
  table.insert(nav_history, query)
  nav_pos = #nav_history
end

local function do_search(query)
  input_buf = query
  prev_input = ""
  zh_candidates = {}
end

-- 结果文本缓冲
local buf_per_en = ""
local buf_per_cn = ""
local ucs_en_bufs = {}
local ucs_cn_bufs = {}

-- 条件构建器状态
local show_builder = false
local builder_conditions = {{text="", relation=0}}

-- ================================================================
-- 分词 + 短语优先匹配
-- ================================================================
local function is_chinese(s)
  return s:match("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function tokenize(input)
  local terms = {}
  local remaining = input

  for phrase, en in pairs(phrase_cn) do
    if remaining:find(phrase, 1, true) then
      table.insert(terms, en)
      remaining = remaining:gsub(phrase, " ")
    end
  end

  for segment in remaining:gmatch("[^,，/]+") do
    local seg = segment:lower():gsub("^%s+",""):gsub("%s+$","")
    if seg == "" then goto continue end

    if is_chinese(seg) then
      local found_en = {}
      local zh_to_en = ucs_mode and ucs_mode.get_zh_to_en() or {}
      -- 精确匹配
      if zh_to_en[seg] then
        for en in pairs(zh_to_en[seg]) do found_en[en] = true end
      end
      -- 分割后逐词精确匹配
      for zh_key, en_set in pairs(zh_to_en) do
        for part in zh_key:gmatch("[^、,%s/]+") do
          if part == seg then
            for en in pairs(en_set) do found_en[en] = true end
          end
        end
      end
      for en in pairs(found_en) do table.insert(terms, en) end
      if #terms == 0 then table.insert(terms, seg) end
    elseif ucs_mode and ucs_mode.is_ucs_phrase(seg) then
      table.insert(terms, seg)
    else
      for word in segment:gmatch("%S+") do
        local w = word:lower():gsub("^%s+",""):gsub("%s+$","")
        if w ~= "" then
          if ucs_mode and ucs_mode.is_ucs_phrase(w) then
            table.insert(terms, w)
          else
            table.insert(terms, cn[w] or w)
          end
        end
      end
    end
    ::continue::
  end
  return terms
end

-- ================================================================
-- 核心扩展（通过模式注册中心调用所有模式）
-- ================================================================
function expand(input)
  if search_cache[input] then return search_cache[input].result, search_cache[input].no_match end
  local terms = tokenize(input)
  local result = {personal={}, ucs={}}
  local seen = {}
  local no_match = {}

  local function add(list, w)
    if not seen[w] then seen[w] = true; table.insert(list, w) end
  end

  for _, term in ipairs(terms) do
    local found = false

    -- 个人经验模式
    if personal_mode then
      local pr = personal_mode.expand(term, input)
      if #pr.words > 0 then
        found = true
        for _, w in ipairs(pr.words) do
          for sub_w in w:gmatch("%S+") do add(result.personal, sub_w) end
        end
      end
    end

    -- UCS 分类模式
    if ucs_mode then
      local ur = ucs_mode.expand(term)
      local has_cats = false
      for catpath, cat_words in pairs(ur.categories) do
        has_cats = true
        if not result.ucs[catpath] then result.ucs[catpath] = {} end
        for _, w in ipairs(cat_words) do
          if not seen[w] then seen[w] = true; table.insert(result.ucs[catpath], w) end
        end
      end
      if has_cats then found = true end
    end

    -- 新模式在此继续调用:
    -- if xxx_mode then
    --   local xr = xxx_mode.expand(term, input)
    --   if xr and #xr.words > 0 then
    --     found = true
    --     for _, w in ipairs(xr.words) do add(result.xxx, w) end
    --   end
    -- end

    if not found then table.insert(no_match, term) end
  end

  search_cache[input] = {result=result, no_match=no_match}
  return result, no_match
end

local function expand_terms(terms)
  local result = {personal={}, ucs={}}
  local seen = {}
  local function add(list, w)
    if not seen[w] then seen[w] = true; table.insert(list, w) end
  end
  for _, term in ipairs(terms) do
    -- 个人经验
    if personal_mode then
      local pr = personal_mode.expand(term)
      for _, w in ipairs(pr.words) do
        for sub_w in w:gmatch("%S+") do add(result.personal, sub_w) end
      end
    end
    -- UCS 分类
    if ucs_mode then
      local ur = ucs_mode.expand(term)
      for catpath, cat_words in pairs(ur.categories) do
        if not result.ucs[catpath] then result.ucs[catpath] = {} end
        for _, w in ipairs(cat_words) do
          if not seen[w] then seen[w] = true; table.insert(result.ucs[catpath], w) end
        end
      end
    end
  end
  return result
end

-- ================================================================
-- 应用条件到基础结果
-- ================================================================
local function apply_conditions(base, conditions)
  if not base then return nil end
  local has_conditions = false
  for _, cond in ipairs(conditions) do
    if cond.text ~= "" then has_conditions = true; break end
  end
  if not has_conditions then return base end

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
        add_not(expanded.personal)
        for _, cw in pairs(expanded.ucs) do add_not(cw) end
      end
    end
  end

  local and_pass = {}
  if #and_list > 0 then
    local first = {}
    local function add_first(list) for _, w in ipairs(list) do first[w] = true end end
    add_first(and_list[1].personal)
    for _, cw in pairs(and_list[1].ucs) do add_first(cw) end
    for w in pairs(first) do and_pass[w] = true end
    for i = 2, #and_list do
      local cur = {}
      local function add_cur(list) for _, w in ipairs(list) do cur[w] = true end end
      add_cur(and_list[i].personal)
      for _, cw in pairs(and_list[i].ucs) do add_cur(cw) end
      for w in pairs(and_pass) do if not cur[w] then and_pass[w] = nil end end
    end
  end

  local final_personal = {}
  local final_ucs = {}
  local seen = {}

  local function add_base(list, w)
    if seen[w] then return end
    if #and_list > 0 and not and_pass[w] then return end
    if not_set[w] then return end
    seen[w] = true; table.insert(list, w)
  end
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

  local function add_or(list, w)
    if seen[w] then return end
    if not_set[w] then return end
    seen[w] = true; table.insert(list, w)
  end
  for _, expanded in ipairs(or_expanded_list) do
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

  return {personal=final_personal, ucs=final_ucs}
end

-- ================================================================
-- 更新结果缓冲
-- ================================================================
local function update_result_bufs()
  if not results then return end
  buf_per_en = format_en(results.personal)
  buf_per_cn = format_cn(results.personal)
  ucs_en_bufs = {}
  ucs_cn_bufs = {}
  for catpath, cat_words in pairs(results.ucs) do
    ucs_en_bufs[catpath] = format_en(cat_words)
    ucs_cn_bufs[catpath] = format_cn(cat_words, catpath)
  end
end

-- ================================================================
-- 主循环
-- ================================================================
function loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, 620, 700, reaper.ImGui_Cond_FirstUseEver())
    first_frame = false
  end

  local vis, open = reaper.ImGui_Begin(ctx, "Search Expander v2.2", true)
  if vis then
    if not ucs_mode then
      reaper.ImGui_TextColored(ctx, 0xFF00AAFF, "⚠ UCS 数据未载入，仅使用内置词库")
    end
    
    reaper.ImGui_Text(ctx, "输入关键词：")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, -170)
    local changed, new_val = reaper.ImGui_InputText(ctx, "##input", input_buf, 256)
    if changed and new_val ~= input_buf then input_buf = new_val end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "收藏", 40, 22) and input_buf ~= "" then
      favorites[input_buf] = true
      save_favorites_map(favorites_file, favorites)
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
      zh_candidates = {}
      nav_history = {}
      nav_pos = 0
      buf_per_en, buf_per_cn = "", ""
      ucs_en_bufs, ucs_cn_bufs = {}, {}
      suggestions = nil
      builder_conditions = {{text="", relation=0}}
      collapsed_cats = {}
      history_open = false
      favorites_open = false
    end
    if input_buf ~= prev_input then
      prev_input = input_buf
      if input_buf ~= "" then
        local input_clean = input_buf:gsub("^%s+",""):gsub("%s+$","")
        local is_cn_input = input_clean:match("[\228-\233][\128-\191][\128-\191]") ~= nil
        if is_cn_input then
          -- 中文输入：收集候选英文词
          local found_en = {}
          local zh_to_en = ucs_mode and ucs_mode.get_zh_to_en() or {}
          -- 直接精确匹配
          if zh_to_en[input_clean] then
            for en in pairs(zh_to_en[input_clean]) do found_en[en] = true end
          end
          -- 分割匹配 + 子串匹配
          for zh_key, en_set in pairs(zh_to_en) do
            for part in zh_key:gmatch("[^、,%s/]+") do
              if part == input_clean or part:find(input_clean, 1, true) then
                for en in pairs(en_set) do found_en[en] = true end
              end
            end
          end
          -- 兜底：直接扫描所有 ucs_zh 和 cn 表
          if not next(found_en) then
            local ucs_zh_data = ucs_mode and (function()
              -- 通过 get_zh_to_en 间接获取
              local z2e = ucs_mode.get_zh_to_en()
              for zh, en_set in pairs(z2e) do
                if zh == input_clean or zh:find(input_clean, 1, true) then
                  for en in pairs(en_set) do found_en[en] = true end
                end
              end
            end)() or nil
            for zh, en in pairs(cn) do
              if zh == input_clean or zh:find(input_clean, 1, true) then
                found_en[en] = true
              end
            end
          end
          -- 调试
          if not next(found_en) then
            local z2e = ucs_mode and ucs_mode.get_zh_to_en() or {}
            local zh_count = 0
            for _ in pairs(z2e) do zh_count = zh_count + 1 end
            reaper.ImGui_TextColored(ctx, 0xFFFF0000, "'"..input_clean.."' zh2en="..zh_count)
          end
          zh_candidates = {}
          for en in pairs(found_en) do table.insert(zh_candidates, en) end
          table.sort(zh_candidates)
          if #zh_candidates > 0 then
            base_results = expand_terms(zh_candidates)
            results = apply_conditions(base_results, builder_conditions)
            update_result_bufs()
            nav_push(input_buf)
          else
            base_results = nil; results = nil
            buf_per_en, buf_per_cn = "", ""
            ucs_en_bufs, ucs_cn_bufs = {}, {}
          end
          suggestions = nil
        else
          -- 英文输入：直接搜索
          zh_candidates = {}
          local no_match
          base_results, no_match = expand(input_buf)
          results = apply_conditions(base_results, builder_conditions)
          update_result_bufs()
          nav_push(input_buf)
          suggestions = {}
          for _, term in ipairs(no_match) do
            local matches = ucs_mode and ucs_mode.suggest(term) or {}
            if #matches > 0 then suggestions[term] = matches end
          end
        end
      else
        zh_candidates = {}
        results = nil
        buf_per_en, buf_per_cn = "", ""
        ucs_en_bufs, ucs_cn_bufs = {}, {}
        suggestions = nil
      end
    end

    -- 中文候选词显示
    if #zh_candidates > 0 then
      reaper.ImGui_TextColored(ctx, 0xFF88CC88, "匹配词汇（点击删除）：")
      local win_w = reaper.ImGui_GetContentRegionAvail(ctx)
      local line_h = 22
      local cur_x = 0
      local line_count = 1
      for i = 1, #zh_candidates do
        local w = zh_candidates[i]
        local zh = ucs_mode and ucs_mode.get_cn(w) or ""
        local label = zh ~= "" and (w .. " " .. zh) or w
        local item_w = reaper.ImGui_CalcTextSize(ctx, "X " .. label) + 24
        if cur_x + item_w > win_w and cur_x > 0 then
          line_count = line_count + 1
          cur_x = item_w
        else
          cur_x = cur_x + item_w
        end
      end
      local child_h = math.min(line_count * line_h, 120)
      reaper.ImGui_BeginChild(ctx, "##cands", 0, child_h)
      local changed_cands = false
      cur_x = 0
      for i = #zh_candidates, 1, -1 do
        local w = zh_candidates[i]
        local zh = ucs_mode and ucs_mode.get_cn(w) or ""
        local label = zh ~= "" and (w .. " " .. zh) or w
        local item_w = reaper.ImGui_CalcTextSize(ctx, "X " .. label) + 24
        if cur_x + item_w > win_w and cur_x > 0 then
          cur_x = 0
        elseif cur_x > 0 then
          reaper.ImGui_SameLine(ctx, 0, 4)
        end
        if reaper.ImGui_SmallButton(ctx, "X##c" .. i) then
          table.remove(zh_candidates, i)
          changed_cands = true
        end
        reaper.ImGui_SameLine(ctx, 0, 2)
        reaper.ImGui_Text(ctx, label)
        cur_x = cur_x + item_w
      end
      reaper.ImGui_EndChild(ctx)
      if changed_cands and #zh_candidates > 0 then
        base_results = expand_terms(zh_candidates)
        results = apply_conditions(base_results, builder_conditions)
        update_result_bufs()
      elseif changed_cands then
        base_results = nil; results = nil
        buf_per_en, buf_per_cn = "", ""
        ucs_en_bufs, ucs_cn_bufs = {}, {}
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

    -- 导航按钮行
    local can_back = nav_pos > 1
    local can_fwd = nav_pos < #nav_history
    if not can_back then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "<", 28, 22) then
      nav_pos = nav_pos - 1
      do_search(nav_history[nav_pos])
    end
    if not can_back then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)
    if not can_fwd then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, ">", 28, 22) then
      nav_pos = nav_pos + 1
      do_search(nav_history[nav_pos])
    end
    if not can_fwd then reaper.ImGui_EndDisabled(ctx) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "添加条件", 70, 22) then
      show_builder = not show_builder
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

    if show_builder then
      for i, cond in ipairs(builder_conditions) do
        reaper.ImGui_PushID(ctx, i)
        
        local rel_labels = {"[且]", "[或]", "[非]"}
        local rel_colors = {0xFF66CC66, 0xFF6666FF, 0xFFFF6666}
        reaper.ImGui_TextColored(ctx, rel_colors[cond.relation + 1], rel_labels[cond.relation + 1])
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_SmallButton(ctx, "切换") then
          builder_conditions[i].relation = (cond.relation + 1) % 3
          if base_results then results = apply_conditions(base_results, builder_conditions); update_result_bufs() end
        end
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 200)
        local txt_changed, txt_val = reaper.ImGui_InputText(ctx, "##txt", cond.text, 256)
        if txt_changed and txt_val ~= cond.text then
          builder_conditions[i].text = txt_val
          if base_results then results = apply_conditions(base_results, builder_conditions); update_result_bufs() end
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "✕") then
          table.remove(builder_conditions, i)
          if base_results then results = apply_conditions(base_results, builder_conditions); update_result_bufs() end
          reaper.ImGui_PopID(ctx)
          break
        end
        
        reaper.ImGui_PopID(ctx)
      end
      
      if reaper.ImGui_SmallButton(ctx, "+ 添加条件") then
        table.insert(builder_conditions, {text="", relation=0})
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
            update_result_bufs()
            suggestions = nil
            break
          end
          x = x + w
        end
      end
      reaper.ImGui_Separator(ctx)
    end

    if results then
      reaper.ImGui_BeginChild(ctx, "##results", 0, 0)
      if #results.personal > 0 then
        reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "个人经验 (" .. #results.personal .. ")")
        draw_words(results.personal, nil, "per")
        reaper.ImGui_Spacing(ctx)
      end

      local ucs_count = 0
      for _ in pairs(results.ucs) do ucs_count = ucs_count + 1 end
      if ucs_count > 0 then
        reaper.ImGui_TextColored(ctx, 0xFF8888CC, "UCS分类 (" .. ucs_count .. ")")

        for catpath, cat_words in pairs(results.ucs) do
          if #cat_words > 0 then
            if collapsed_cats[catpath] == nil then collapsed_cats[catpath] = true end
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
              draw_words(cat_words, catpath, catpath)
              reaper.ImGui_Unindent(ctx)
              reaper.ImGui_Spacing(ctx)
            end
          end
        end
      end

      -- 新模式结果在此显示:
      -- local xxx_count = 0
      -- for _ in pairs(results.xxx) do xxx_count = xxx_count + 1 end
      -- if xxx_count > 0 then
      --   reaper.ImGui_TextColored(ctx, 0xFFCC88FF, "XXX模式 (" .. xxx_count .. ")")
      --   ...
      -- end

      -- 复制选中词按钮
      if selected_word ~= "" then
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextColored(ctx, 0xFF888888, "已选中: " .. selected_word)
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "复制") then
          reaper.ImGui_SetClipboardText(ctx, selected_word)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "搜索此词") then
          input_buf = selected_word
          prev_input = ""
          zh_candidates = {}
        end
      end

      reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
