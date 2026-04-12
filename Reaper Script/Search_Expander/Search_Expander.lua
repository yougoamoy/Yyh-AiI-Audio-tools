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
local debug_file = script_path .. "debug_notes.lua"

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

-- ================================================================
-- UI state
-- ================================================================
local input_buf = ""
local prev_input = ""
local base_results = nil
local results = nil
local first_frame = true
local suggestions = nil
local history = load_list(history_file)
local debug_notes = load_list(debug_file)
local collapsed_cats = {}
local history_open = false
local debug_open = false
local debug_input_buf = ""
local search_cache = {}
local zh_candidates = {}
local selected_word = ""

-- 分类选择器状态
local picker_open = false
local picker_source = ""
local picker_top_cats = {}
local picker_selected_top = ""
local picker_sub_cats = {}
local picker_selected = {} -- {[catpath]=true}

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
local per_en_bufs = {}
local per_cn_bufs = {}
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
  local result = {ucs={}, personal_categories={}}
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
      local has_cats = false
      for catpath, cat_words in pairs(pr.categories) do
        has_cats = true
        if not result.personal_categories[catpath] then result.personal_categories[catpath] = {} end
        for _, w in ipairs(cat_words) do
          if not seen[w] then seen[w] = true; table.insert(result.personal_categories[catpath], w) end
        end
      end
      if has_cats then found = true end
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
  local result = {ucs={}, personal_categories={}}
  local seen = {}
  local function add(list, w)
    if not seen[w] then seen[w] = true; table.insert(list, w) end
  end
  for _, term in ipairs(terms) do
    -- 个人映射
    if personal_mode then
      local pr = personal_mode.expand(term)
      for catpath, cat_words in pairs(pr.categories) do
        if not result.personal_categories[catpath] then result.personal_categories[catpath] = {} end
        for _, w in ipairs(cat_words) do
          if not seen[w] then seen[w] = true; table.insert(result.personal_categories[catpath], w) end
        end
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
local function flatten_categories(cats)
  local list = {}
  local seen = {}
  for _, words in pairs(cats or {}) do
    for _, w in ipairs(words) do
      if not seen[w] then seen[w] = true; table.insert(list, w) end
    end
  end
  return list
end

local function get_all_words(result)
  local list = {}
  local seen = {}
  local function add(w) if not seen[w] then seen[w] = true; table.insert(list, w) end end
  for _, w in ipairs(flatten_categories(result.personal_categories)) do add(w) end
  for _, w in ipairs(flatten_categories(result.ucs)) do add(w) end
  return list
end

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
        for _, w in ipairs(get_all_words(expanded)) do not_set[w] = true end
      end
    end
  end

  local and_pass = {}
  if #and_list > 0 then
    local first = {}
    for _, w in ipairs(get_all_words(and_list[1])) do first[w] = true end
    for w in pairs(first) do and_pass[w] = true end
    for i = 2, #and_list do
      local cur = {}
      for _, w in ipairs(get_all_words(and_list[i])) do cur[w] = true end
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
  for cat, cw in pairs(base.personal_categories or {}) do
    if not final_personal[cat] then final_personal[cat] = {} end
    for _, w in ipairs(cw) do add_base(final_personal[cat], w) end
  end
  for cat, cw in pairs(base.ucs) do
    for _, w in ipairs(cw) do
      if not seen[w] and (#and_list == 0 or and_pass[w]) and not not_set[w] then
        seen[w] = true
        if not final_ucs[cat] then final_ucs[cat] = {} end
        table.insert(final_ucs[cat], w)
      end
    end
  end

  for _, expanded in ipairs(or_expanded_list) do
    for cat, cw in pairs(expanded.personal_categories or {}) do
      if not final_personal[cat] then final_personal[cat] = {} end
      for _, w in ipairs(cw) do add_base(final_personal[cat], w) end
    end
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

  return {personal_categories=final_personal, ucs=final_ucs}
end

-- ================================================================
-- 更新结果缓冲
-- ================================================================
local function update_result_bufs()
  if not results then return end
  per_en_bufs = {}
  per_cn_bufs = {}
  ucs_en_bufs = {}
  ucs_cn_bufs = {}
  for catpath, cat_words in pairs(results.personal_categories or {}) do
    per_en_bufs[catpath] = format_en(cat_words)
    per_cn_bufs[catpath] = format_cn(cat_words, catpath)
  end
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
    if reaper.ImGui_Button(ctx, "历史", 40, 22) then history_open = not history_open; debug_open = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Debug", 50, 22) then debug_open = not debug_open; history_open = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "清除", 40, 22) then
      input_buf = ""
      prev_input = ""
      base_results = nil
      results = nil
      zh_candidates = {}
      nav_history = {}
      nav_pos = 0
      per_en_bufs, per_cn_bufs = {}, {}
      ucs_en_bufs, ucs_cn_bufs = {}, {}
      suggestions = nil
      builder_conditions = {{text="", relation=0}}
      collapsed_cats = {}
      history_open = false
      debug_open = false
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
            per_en_bufs, per_cn_bufs = {}, {}
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
        per_en_bufs, per_cn_bufs = {}, {}
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
        per_en_bufs, per_cn_bufs = {}, {}
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
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "映射", 40, 22) then
      if input_buf ~= "" and ucs_mode then
        picker_source = input_buf
        picker_top_cats = ucs_mode.get_top_categories()
        picker_selected_top = ""
        picker_sub_cats = {}
        picker_selected = {}
        picker_open = true
      end
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

    if debug_open then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_TextColored(ctx, 0xFFFF8888, "Debug 清单：")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextColored(ctx, 0xFF888888, "(输入后点添加)")

      -- 输入框
      reaper.ImGui_SetNextItemWidth(ctx, -60)
      local dbg_changed, dbg_val = reaper.ImGui_InputText(ctx, "##dbginput", debug_input_buf, 256)
      if dbg_changed then debug_input_buf = dbg_val end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "添加", 46, 22) and debug_input_buf ~= "" then
        table.insert(debug_notes, debug_input_buf)
        save_list(debug_file, debug_notes)
        debug_input_buf = ""
      end

      -- 列表
      if #debug_notes > 0 then
        reaper.ImGui_BeginChild(ctx, "##dbglist", 0, math.min(#debug_notes * 24, 300))
        for i = #debug_notes, 1, -1 do
          reaper.ImGui_PushID(ctx, i)
          if reaper.ImGui_SmallButton(ctx, "X") then
            table.remove(debug_notes, i)
            save_list(debug_file, debug_notes)
            reaper.ImGui_PopID(ctx)
            break
          end
          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_TextWrapped(ctx, debug_notes[i])
          reaper.ImGui_PopID(ctx)
        end
        reaper.ImGui_EndChild(ctx)
      else
        reaper.ImGui_TextColored(ctx, 0xFF888888, "暂无记录")
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

      -- 个人映射（按分类显示，与 UCS 同格式）
      local per_count = 0
      for _ in pairs(results.personal_categories or {}) do per_count = per_count + 1 end
      if per_count > 0 then
        reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "个人映射分类 (" .. per_count .. ")")
        for catpath, cat_words in pairs(results.personal_categories) do
          if #cat_words > 0 then
            local key = "per_" .. catpath
            if collapsed_cats[key] == nil then collapsed_cats[key] = true end
            local collapsed = collapsed_cats[key]
            local arrow = collapsed and ">" or "v"
            if reaper.ImGui_SmallButton(ctx, arrow .. "##" .. key) then
              collapsed_cats[key] = not collapsed
              collapsed = collapsed_cats[key]
            end
            local label = catpath == "direct" and "直接映射" or catpath
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0xFFAAAA88, label .. " (" .. #cat_words .. ")")
            if not collapsed then
              reaper.ImGui_Indent(ctx)
              draw_words(cat_words, catpath ~= "direct" and catpath or nil, key)
              reaper.ImGui_Unindent(ctx)
              reaper.ImGui_Spacing(ctx)
            end
          end
        end
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

    -- 新增个人映射：分类选择弹窗
    if picker_open then
      reaper.ImGui_OpenPopup(ctx, "新增映射")
      picker_open = false
    end

    if reaper.ImGui_BeginPopupModal(ctx, "新增映射", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
      reaper.ImGui_Text(ctx, "将 \"" .. picker_source .. "\" 映射到 UCS 分类：")
      reaper.ImGui_Separator(ctx)

      -- 左右两栏
      reaper.ImGui_BeginGroup(ctx)

      -- 左栏：顶级分类
      reaper.ImGui_TextColored(ctx, 0xFF88CC88, "大类")
      reaper.ImGui_BeginChild(ctx, "##topcat", 160, 300)
      for _, top in ipairs(picker_top_cats) do
        local is_sel = (top == picker_selected_top)
        if reaper.ImGui_Selectable(ctx, top .. "##top", is_sel) then
          picker_selected_top = top
          picker_sub_cats = ucs_mode.get_sub_categories(top)
        end
      end
      reaper.ImGui_EndChild(ctx)

      reaper.ImGui_SameLine(ctx)

      -- 右栏：子分类（可多选）
      reaper.ImGui_TextColored(ctx, 0xFF8888CC, "子分类")
      reaper.ImGui_BeginChild(ctx, "##subcat", 260, 300)
      if picker_selected_top ~= "" then
        for _, catpath in ipairs(picker_sub_cats) do
          local sub = catpath:match("[^/]+/(.+)") or catpath
          local checked = picker_selected[catpath] or false
          local changed, new_val = reaper.ImGui_Checkbox(ctx, sub .. "##sub", checked)
          if changed then picker_selected[catpath] = new_val or nil end
        end
      else
        reaper.ImGui_TextColored(ctx, 0xFF888888, "← 选择大类")
      end
      reaper.ImGui_EndChild(ctx)

      reaper.ImGui_EndGroup(ctx)

      reaper.ImGui_Separator(ctx)

      -- 已选分类展示
      local sel_count = 0
      for _ in pairs(picker_selected) do sel_count = sel_count + 1 end
      if sel_count > 0 then
        reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "已选 (" .. sel_count .. ")：")
        for cp in pairs(picker_selected) do
          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_Text(ctx, cp)
        end
      end

      -- 按钮
      if sel_count > 0 then
        if reaper.ImGui_Button(ctx, "确认", 80, 24) then
          local catpaths = {}
          for cp in pairs(picker_selected) do table.insert(catpaths, cp) end
          personal_mode.add_categories(picker_source, catpaths)
          search_cache = {}
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
      end
      if reaper.ImGui_Button(ctx, "取消", 80, 24) then
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
