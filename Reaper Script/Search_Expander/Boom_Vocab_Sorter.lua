-- Boom Vocab Sorter - 词汇分拣流水线
-- 从 word_pool.lua 加载词汇，逐个展示，用户归类
-- 支持：多类别归属、类别重命名、类别删除、剔除词库
-- 快捷键: 1-9 归到已有类别, N 新建类别, S 跳过, X 剔除, ←→ 导航, Esc 退出

local ctx = reaper.ImGui_CreateContext("Boom Vocab Sorter")

-- ================================================================
-- 路径配置
-- ================================================================
local script_path = ({reaper.get_action_context()})[2]:match("(.*[/\\])")
local pool_file = script_path .. "boom_vocab/word_pool.lua"
local categories_file = script_path .. "boom_vocab/boom_categories.lua"
local skip_file = script_path .. "boom_vocab/skip_record.lua"
local removed_file = script_path .. "boom_vocab/removed_record.lua"

-- ================================================================
-- 数据存储
-- ================================================================
local word_pool = {}      -- 词汇池 {word, count, desc_count, fn_count, tier, source, examples}
local categories = {}     -- 类别 {cat_name = {word1=true, word2=true}}
local word_category = {}  -- 词 -> {cat1=true, cat2=true} 多类别支持
local cat_order = {}      -- 类别顺序
local skipped = {}        -- 跳过的词 {word=true}
local removed = {}        -- 剔除的词 {word=true}

-- ================================================================
-- 文件读写工具函数
-- ================================================================
local function safe_dofile(path)
  local ok, data = pcall(dofile, path)
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

local function save_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

-- ================================================================
-- 加载词汇池
-- ================================================================
local function load_word_pool()
  local data = safe_dofile(pool_file)
  if data then word_pool = data end
end

-- ================================================================
-- 加载分类
-- ================================================================
local function load_categories()
  local data = safe_dofile(categories_file)
  if not data or not data.categories then return end

  categories = {}
  word_category = {}
  cat_order = data.cat_order or {}

  -- 加载类别 -> 词的映射
  for cat, words in pairs(data.categories) do
    if type(words) == "table" then
      categories[cat] = {}
      for k, v in pairs(words) do
        local w = type(v) == "string" and v or (type(v) == "boolean" and k or nil)
        if w and type(w) == "string" then
          categories[cat][w] = true
          -- 构建 词 -> 多类别 映射
          if not word_category[w] then word_category[w] = {} end
          word_category[w][cat] = true
        end
      end
    end
  end

  -- 确保 cat_order 包含所有类别
  local cat_set = {}
  for _, c in ipairs(cat_order) do cat_set[c] = true end
  for cat in pairs(categories) do
    if not cat_set[cat] then table.insert(cat_order, cat) end
  end
end

-- ================================================================
-- 保存分类
-- ================================================================
local function save_categories()
  local lines = {
    "-- boom_categories.lua\n",
    "-- Boom 词汇分类结果，由 Vocab Sorter 自动生成\n\n",
    "local M = {}\n\n",
    "M.categories = {\n"
  }

  for _, cat in ipairs(cat_order) do
    local words = categories[cat]
    if words and next(words) then
      table.insert(lines, '  ["' .. cat .. '"] = {\n')
      local sorted = {}
      for w in pairs(words) do table.insert(sorted, w) end
      table.sort(sorted)
      for _, w in ipairs(sorted) do
        table.insert(lines, '    "' .. w .. '",\n')
      end
      table.insert(lines, "  },\n")
    end
  end

  table.insert(lines, "}\n\n")
  table.insert(lines, "M.cat_order = {\n")
  for _, cat in ipairs(cat_order) do
    table.insert(lines, '  "' .. cat .. '",\n')
  end
  table.insert(lines, "}\n\nreturn M\n")

  save_file(categories_file, table.concat(lines))
end

-- ================================================================
-- 加载/保存跳过记录
-- ================================================================
local function load_skip()
  local data = safe_dofile(skip_file)
  if data then
    skipped = {}
    for _, w in ipairs(data) do
      if type(w) == "string" then skipped[w] = true end
    end
  end
end

local function save_skip()
  local lines = {"return {\n"}
  for w in pairs(skipped) do table.insert(lines, '  "' .. w .. '",\n') end
  table.insert(lines, "}\n")
  save_file(skip_file, table.concat(lines))
end

-- ================================================================
-- 加载/保存剔除记录
-- ================================================================
local function load_removed()
  local data = safe_dofile(removed_file)
  if data then
    removed = {}
    for _, w in ipairs(data) do
      if type(w) == "string" then removed[w] = true end
    end
  end
end

local function save_removed()
  local lines = {"return {\n"}
  for w in pairs(removed) do table.insert(lines, '  "' .. w .. '",\n') end
  table.insert(lines, "}\n")
  save_file(removed_file, table.concat(lines))
end

-- ================================================================
-- 初始化数据
-- ================================================================
load_word_pool()
load_categories()
load_skip()
load_removed()

-- ================================================================
-- 界面状态
-- ================================================================
local current_idx = 1
local new_cat_buf = ""
local new_cat_mode = false
local edit_cat_mode = false      -- 编辑类别模式
local edit_cat_target = ""       -- 要编辑的类别名
local edit_cat_buf = ""          -- 编辑类别输入缓冲区
local status_msg = ""
local status_timer = 0
local show_cat_manager = false   -- 显示类别管理器
local expanded_cats = {}         -- 记录展开的类别 {cat_name = true}
local removed_panel_open = false -- 剔除词汇面板是否展开

-- ================================================================
-- 统计函数
-- ================================================================
local function get_stats()
  local total = #word_pool
  local classified = 0
  local skipped_count = 0
  local removed_count = 0
  for _, entry in ipairs(word_pool) do
    if word_category[entry.word] and next(word_category[entry.word]) then
      classified = classified + 1
    end
    if skipped[entry.word] then skipped_count = skipped_count + 1 end
    if removed[entry.word] then removed_count = removed_count + 1 end
  end
  return total, classified, skipped_count, removed_count, total - classified - skipped_count - removed_count
end

-- ================================================================
-- 导航函数
-- ================================================================
local function is_word_classified(w)
  return word_category[w] and next(word_category[w]) ~= nil
end

local function is_word_pending(w)
  return not is_word_classified(w) and not skipped[w] and not removed[w]
end

local function find_next_unclassified(start_idx)
  for i = start_idx, #word_pool do
    if is_word_pending(word_pool[i].word) then return i end
  end
  for i = 1, start_idx - 1 do
    if is_word_pending(word_pool[i].word) then return i end
  end
  return nil
end

local function find_prev_unclassified(start_idx)
  for i = start_idx - 1, 1, -1 do
    if is_word_pending(word_pool[i].word) then return i end
  end
  for i = #word_pool, start_idx, -1 do
    if is_word_pending(word_pool[i].word) then return i end
  end
  return nil
end

local function find_last_unclassified()
  for i = #word_pool, 1, -1 do
    if is_word_pending(word_pool[i].word) then return i end
  end
  return nil
end

local function find_next_classified(start_idx)
  for i = start_idx, #word_pool do
    if is_word_classified(word_pool[i].word) then return i end
  end
  for i = 1, start_idx - 1 do
    if is_word_classified(word_pool[i].word) then return i end
  end
  return nil
end

local function find_prev_classified(start_idx)
  for i = start_idx - 1, 1, -1 do
    if is_word_classified(word_pool[i].word) then return i end
  end
  for i = #word_pool, start_idx, -1 do
    if is_word_classified(word_pool[i].word) then return i end
  end
  return nil
end

local function goto_next()
  local nxt = find_next_unclassified(current_idx + 1)
  if nxt then current_idx = nxt end
end

-- ================================================================
-- 操作函数
-- ================================================================
local function add_word_to_cat(word, cat)
  -- 添加到类别
  if not categories[cat] then
    categories[cat] = {}
    table.insert(cat_order, cat)
  end
  categories[cat][word] = true
  -- 添加到词的类别集合
  if not word_category[word] then word_category[word] = {} end
  word_category[word][cat] = true
  save_categories()
  status_msg = word .. " + [" .. cat .. "]"
  status_timer = 120
end

local function remove_word_from_cat(word, cat)
  if categories[cat] then
    categories[cat][word] = nil
  end
  if word_category[word] then
    word_category[word][cat] = nil
  end
  save_categories()
  status_msg = word .. " - [" .. cat .. "]"
  status_timer = 120
end

local function toggle_word_cat(word, cat)
  if word_category[word] and word_category[word][cat] then
    remove_word_from_cat(word, cat)
  else
    add_word_to_cat(word, cat)
  end
end

local function clear_word_categories(word)
  if word_category[word] then
    for cat in pairs(word_category[word]) do
      if categories[cat] then categories[cat][word] = nil end
    end
  end
  word_category[word] = nil
  save_categories()
  status_msg = "已清除: " .. word .. " 的所有分类"
  status_timer = 60
end

local function skip_word(word)
  skipped[word] = true
  save_skip()
  status_msg = "跳过: " .. word
  status_timer = 60
end

local function unskip_word(word)
  skipped[word] = nil
  save_skip()
  status_msg = "取消跳过: " .. word
  status_timer = 60
end

local function remove_word(word)
  -- 先清除分类
  if word_category[word] then
    for cat in pairs(word_category[word]) do
      if categories[cat] then categories[cat][word] = nil end
    end
    word_category[word] = nil
    save_categories()
  end
  -- 剔除词库
  removed[word] = true
  save_removed()
  status_msg = "已剔除: " .. word
  status_timer = 60
end

local function unremove_word(word)
  removed[word] = nil
  save_removed()
  status_msg = "已恢复: " .. word
  status_timer = 60
end

-- 类别管理：重命名
local function rename_category(old_name, new_name)
  if new_name == "" or new_name == old_name then return end
  if categories[new_name] then
    status_msg = "错误: 类别 [" .. new_name .. "] 已存在"
    status_timer = 120
    return
  end

  -- 移动类别数据
  categories[new_name] = categories[old_name]
  categories[old_name] = nil

  -- 更新 cat_order
  for i, cat in ipairs(cat_order) do
    if cat == old_name then
      cat_order[i] = new_name
      break
    end
  end

  -- 更新 word_category
  for word, cats in pairs(word_category) do
    if cats[old_name] then
      cats[old_name] = nil
      cats[new_name] = true
    end
  end

  save_categories()
  status_msg = "已重命名: [" .. old_name .. "] -> [" .. new_name .. "]"
  status_timer = 120
end

-- 类别管理：删除
local function delete_category(cat)
  -- 从所有词的类别中移除
  if categories[cat] then
    for word in pairs(categories[cat]) do
      if word_category[word] then
        word_category[word][cat] = nil
      end
    end
  end
  categories[cat] = nil

  -- 从 cat_order 中移除
  for i, c in ipairs(cat_order) do
    if c == cat then
      table.remove(cat_order, i)
      break
    end
  end

  save_categories()
  status_msg = "已删除类别: [" .. cat .. "]"
  status_timer = 120
end

-- 获取词的类别列表字符串
local function get_word_cats_str(word)
  if not word_category[word] or not next(word_category[word]) then return "" end
  local cats = {}
  for cat in pairs(word_category[word]) do table.insert(cats, cat) end
  table.sort(cats)
  return table.concat(cats, ", ")
end

-- 获取类别词数
local function get_cat_word_count(cat)
  local count = 0
  for _ in pairs(categories[cat] or {}) do count = count + 1 end
  return count
end

-- ================================================================
-- 初始化索引
-- ================================================================
if #word_pool > 0 then
  local next_i = find_next_unclassified(1)
  if next_i then current_idx = next_i end
end

-- ================================================================
-- 主循环
-- ================================================================
local first_frame = true

function loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, 720, 680, reaper.ImGui_Cond_FirstUseEver())
    first_frame = false
  end

  local vis, open = reaper.ImGui_Begin(ctx, "Boom Vocab Sorter", true)
  if not vis then
    if open then reaper.defer(loop) end
    return
  end

  if #word_pool == 0 then
    reaper.ImGui_TextColored(ctx, 0xFFFF0000, "词汇池为空！请先运行 build_word_pool.py")
    reaper.ImGui_End(ctx)
    if open then reaper.defer(loop) end
    return
  end

  current_idx = math.max(1, math.min(current_idx, #word_pool))
  local entry = word_pool[current_idx]
  local word_cats = word_category[entry.word] or {}
  local is_classified = next(word_cats) ~= nil
  local is_skipped = skipped[entry.word] ~= nil
  local is_removed = removed[entry.word] ~= nil

  -- ================================================================
  -- 顶部进度
  -- ================================================================
  local total, classified, skipped_count, removed_count, remaining = get_stats()
  local pct = total > 0 and (classified / total * 100) or 0

  reaper.ImGui_Text(ctx, string.format("进度: %d/%d 已分类 | %d 跳过 | %d 剔除 | %d 剩余 | %.1f%%",
    classified, total, skipped_count, removed_count, remaining, pct))
  local bar_w = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_ProgressBar(ctx, pct / 100, bar_w, 0, "")
  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 当前词信息
  -- ================================================================
  reaper.ImGui_TextColored(ctx, 0xFFCCCCFF, string.format("[%d/%d]", current_idx, #word_pool))
  reaper.ImGui_SameLine(ctx)

  local word_color = is_removed and 0xFFFF4444 or (is_classified and 0xFF66CC66 or (is_skipped and 0xFF888888 or 0xFFFFFFFF))
  reaper.ImGui_TextColored(ctx, word_color, entry.word)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextColored(ctx, 0xFF888888, string.format("词频:%d  desc:%d  fn:%d  tier:%s  来源:%s",
    entry.count or 0, entry.desc_count or 0, entry.fn_count or 0, entry.tier or "?", entry.source or "?"))

  -- 显示当前词的所有类别
  if is_removed then
    reaper.ImGui_TextColored(ctx, 0xFFFF4444, "[已剔除]  按 R 恢复到词库")
  elseif is_classified then
    local cats_str = get_word_cats_str(entry.word)
    reaper.ImGui_TextColored(ctx, 0xFF66CC66, "分类: [" .. cats_str .. "]  (点击类别可切换)")
  elseif is_skipped then
    reaper.ImGui_TextColored(ctx, 0xFF888888, "[已跳过]")
  else
    reaper.ImGui_TextColored(ctx, 0xFFAAAAAA, "未分类")
  end

  -- 上下文示例
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextColored(ctx, 0xFFAAAAAA, "上下文示例:")
  reaper.ImGui_Indent(ctx)
  if entry.examples and #entry.examples > 0 then
    for i, ex in ipairs(entry.examples) do
      reaper.ImGui_TextWrapped(ctx, ex)
      if i < #entry.examples then reaper.ImGui_Spacing(ctx) end
    end
  else
    reaper.ImGui_TextColored(ctx, 0xFF666666, "无示例")
  end
  reaper.ImGui_Unindent(ctx)
  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 分类操作区
  -- ================================================================
  if new_cat_mode then
    -- 新建类别输入模式
    reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "新类别名称:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local _, buf = reaper.ImGui_InputText(ctx, "##newcat_input", new_cat_buf, 256)
    new_cat_buf = buf

    local should_confirm = false
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "确认", 50, 22) then should_confirm = true end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "取消", 50, 22) then
      new_cat_mode = false
      new_cat_buf = ""
    end

    if should_confirm and new_cat_buf ~= "" then
      add_word_to_cat(entry.word, new_cat_buf)
      new_cat_buf = ""
      new_cat_mode = false
      goto_next()
    end
  else
    -- 已有类别按钮（点击切换）
    reaper.ImGui_TextColored(ctx, 0xFFCCCCFF, "选择类别 (点击切换):")
    if #cat_order == 0 then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextColored(ctx, 0xFF666666, "暂无类别，按 N 新建")
    end

    local btn_idx = 0
    for i, cat in ipairs(cat_order) do
      local count = get_cat_word_count(cat)
      local label = string.format("%d.%s(%d)", i, cat, count)
      local btn_w = reaper.ImGui_CalcTextSize(ctx, label) + 20
      if btn_idx > 0 then reaper.ImGui_SameLine(ctx, 0, 4) end

      -- 当前词在此类别中则高亮
      local in_cat = word_cats[cat] == true
      if in_cat then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF448844)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF559955)
      end

      if reaper.ImGui_Button(ctx, label, btn_w, 24) then
        toggle_word_cat(entry.word, cat)
      end

      if in_cat then
        reaper.ImGui_PopStyleColor(ctx, 2)
      end

      btn_idx = btn_idx + 1
      if btn_idx >= 6 then btn_idx = 0 end
    end
  end

  reaper.ImGui_Spacing(ctx)

  -- ================================================================
  -- 操作按钮
  -- ================================================================
  if reaper.ImGui_Button(ctx, "N 新建类别", 90, 26) then
    new_cat_mode = true
    new_cat_buf = ""
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "S 跳过", 65, 26) then
    skip_word(entry.word)
    goto_next()
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "C 清除分类", 85, 26) then
    clear_word_categories(entry.word)
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  -- 剔除/恢复按钮
  if is_removed then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF444488)
    if reaper.ImGui_Button(ctx, "R 恢复词库", 85, 26) then
      unremove_word(entry.word)
    end
    reaper.ImGui_PopStyleColor(ctx)
  else
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF4444AA)
    if reaper.ImGui_Button(ctx, "X 剔除词库", 85, 26) then
      remove_word(entry.word)
      goto_next()
    end
    reaper.ImGui_PopStyleColor(ctx)
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "U 取消跳过", 85, 26) then
    if is_skipped then unskip_word(entry.word) end
  end

  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 导航按钮
  -- ================================================================
  -- 未分类导航
  reaper.ImGui_TextColored(ctx, 0xFFCCCCFF, "未分类:")
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_Button(ctx, "|< 首个", 60, 22) then
    local nxt = find_next_unclassified(1)
    if nxt then current_idx = nxt end
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, "< 上一个", 65, 22) then
    local prev = find_prev_unclassified(current_idx)
    if prev then current_idx = prev end
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, "> 下一个", 65, 22) then
    goto_next()
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, ">| 末个", 60, 22) then
    local last = find_last_unclassified()
    if last then current_idx = last end
  end

  -- 已分类导航
  reaper.ImGui_TextColored(ctx, 0xFF66CC66, "已分类:")
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_Button(ctx, "< 上个已分类", 85, 22) then
    local prev = find_prev_classified(current_idx)
    if prev then current_idx = prev end
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, "下个已分类 >", 85, 22) then
    local nxt = find_next_classified(current_idx + 1)
    if nxt then current_idx = nxt end
  end

  -- 直接浏览
  reaper.ImGui_SameLine(ctx, 0, 8)
  reaper.ImGui_TextColored(ctx, 0xFF888888, "浏览:")
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "<<", 30, 22) then
    current_idx = math.max(1, current_idx - 1)
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, ">>", 30, 22) then
    current_idx = math.min(#word_pool, current_idx + 1)
  end

  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 类别管理器（折叠）
  -- ================================================================
  if reaper.ImGui_CollapsingHeader(ctx, "类别管理器 (" .. #cat_order .. " 个类别)") then
    reaper.ImGui_Indent(ctx)

    for _, cat in ipairs(cat_order) do
      local count = get_cat_word_count(cat)
      local word_list = {}
      for w in pairs(categories[cat] or {}) do table.insert(word_list, w) end
      table.sort(word_list)

      -- 设置展开状态
      local is_expanded = expanded_cats[cat] == true
      reaper.ImGui_SetNextItemOpen(ctx, is_expanded)
      
      -- 使用TreeNode创建可展开的类别
      local tree_open = reaper.ImGui_TreeNode(ctx, cat .. " (" .. count .. ")##tree_" .. cat)
      
      -- 更新展开状态
      if tree_open then
        expanded_cats[cat] = true
      else
        expanded_cats[cat] = nil
      end
      
      -- 在同一行放置按钮
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "重命名##" .. cat, 50, 18) then
        edit_cat_mode = true
        edit_cat_target = cat
        edit_cat_buf = cat
      end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF444488)
      if reaper.ImGui_Button(ctx, "删除##" .. cat, 40, 18) then
        delete_category(cat)
        expanded_cats[cat] = nil
      end
      reaper.ImGui_PopStyleColor(ctx)

      if tree_open then
        -- 显示所有词汇，每个词汇带移除按钮
        for _, w in ipairs(word_list) do
          reaper.ImGui_TextColored(ctx, 0xFFAAAAAA, "  • " .. w)
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "移除##" .. cat .. "_" .. w, 40, 16) then
            remove_word_from_cat(w, cat)
          end
        end
        reaper.ImGui_TreePop(ctx)
      end
    end

    reaper.ImGui_Unindent(ctx)
  end

  -- ================================================================
  -- 剔除词汇管理器（折叠）
  -- ================================================================
  local removed_count = 0
  for _ in pairs(removed) do removed_count = removed_count + 1 end
  
  reaper.ImGui_SetNextItemOpen(ctx, removed_panel_open)
  local removed_header_open = reaper.ImGui_CollapsingHeader(ctx, "已剔除词汇 (" .. removed_count .. " 个)")
  removed_panel_open = removed_header_open
  
  if removed_header_open then
    reaper.ImGui_Indent(ctx)
    
    if removed_count == 0 then
      reaper.ImGui_TextColored(ctx, 0xFF888888, "暂无剔除词汇")
    else
      -- 收集并排序剔除的词汇
      local removed_list = {}
      for w in pairs(removed) do table.insert(removed_list, w) end
      table.sort(removed_list)
      
      -- 显示所有剔除的词汇，每个带恢复按钮
      for _, w in ipairs(removed_list) do
        reaper.ImGui_TextColored(ctx, 0xFFFF6666, "  • " .. w)
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "恢复##removed_" .. w, 40, 16) then
          unremove_word(w)
        end
      end
    end
    
    reaper.ImGui_Unindent(ctx)
  end

  -- ================================================================
  -- 重命名类别弹窗
  -- ================================================================
  if edit_cat_mode then
    reaper.ImGui_OpenPopup(ctx, "重命名类别")
    if reaper.ImGui_BeginPopupModal(ctx, "重命名类别", true) then
      reaper.ImGui_Text(ctx, "类别: " .. edit_cat_target)
      reaper.ImGui_Text(ctx, "新名称:")
      local _, buf = reaper.ImGui_InputText(ctx, "##rename_input", edit_cat_buf, 256)
      edit_cat_buf = buf

      if reaper.ImGui_Button(ctx, "确认", 60, 24) then
        if edit_cat_buf ~= "" and edit_cat_buf ~= edit_cat_target then
          rename_category(edit_cat_target, edit_cat_buf)
        end
        edit_cat_mode = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "取消", 60, 24) then
        edit_cat_mode = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    end
  end

  -- ================================================================
  -- 快捷键提示（折叠）
  -- ================================================================
  if reaper.ImGui_CollapsingHeader(ctx, "快捷键") then
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_Text(ctx, "1-9     切换类别归属")
    reaper.ImGui_Text(ctx, "N       新建类别")
    reaper.ImGui_Text(ctx, "S       跳过当前词")
    reaper.ImGui_Text(ctx, "C       清除所有分类")
    reaper.ImGui_Text(ctx, "X       剔除词库")
    reaper.ImGui_Text(ctx, "R       恢复/取消跳过")
    reaper.ImGui_Text(ctx, "←/→     浏览所有词")
    reaper.ImGui_Text(ctx, "↑/↓     跳转未分类词")
    reaper.ImGui_Text(ctx, "Esc     取消新建/退出")
    reaper.ImGui_Unindent(ctx)
  end

  -- ================================================================
  -- 键盘快捷键
  -- ================================================================
  if not new_cat_mode and not edit_cat_mode then
    -- 数字键 1-9 切换类别
    local digit_keys = {
      reaper.ImGui_Key_1(), reaper.ImGui_Key_2(), reaper.ImGui_Key_3(),
      reaper.ImGui_Key_4(), reaper.ImGui_Key_5(), reaper.ImGui_Key_6(),
      reaper.ImGui_Key_7(), reaper.ImGui_Key_8(), reaper.ImGui_Key_9()
    }
    for i = 1, math.min(9, #cat_order) do
      if reaper.ImGui_IsKeyPressed(ctx, digit_keys[i]) then
        toggle_word_cat(entry.word, cat_order[i])
      end
    end

    -- N = 新建类别
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_N()) then
      new_cat_mode = true
      new_cat_buf = ""
    end

    -- S = 跳过
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) then
      skip_word(entry.word)
      goto_next()
    end

    -- C = 清除分类
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_C()) then
      clear_word_categories(entry.word)
    end

    -- X = 剔除词库
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_X()) then
      if not is_removed then
        remove_word(entry.word)
        goto_next()
      end
    end

    -- R = 恢复/取消跳过
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_R()) then
      if is_removed then
        unremove_word(entry.word)
      elseif is_skipped then
        unskip_word(entry.word)
      end
    end

    -- 左右箭头浏览
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then
      current_idx = math.max(1, current_idx - 1)
    end
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then
      current_idx = math.min(#word_pool, current_idx + 1)
    end

    -- 上下箭头跳转未分类
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then
      local prev = find_prev_unclassified(current_idx)
      if prev then current_idx = prev end
    end
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
      goto_next()
    end
  else
    -- Esc 取消
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      new_cat_mode = false
      new_cat_buf = ""
      edit_cat_mode = false
    end
  end

  -- ================================================================
  -- 状态消息
  -- ================================================================
  if status_timer > 0 then
    status_timer = status_timer - 1
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF66CC66, status_msg)
  end

  reaper.ImGui_End(ctx)
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
