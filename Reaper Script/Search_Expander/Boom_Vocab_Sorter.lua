-- Boom Vocab Sorter - 词汇分拣流水线
-- 从 word_pool.lua 加载词汇，逐个展示，用户归类
-- 快捷键: 1-9 归到已有类别, N 新建类别, S 跳过, ←→ 导航, Q 退出
-- 分类结果持久化到 boom_categories.lua

local ctx = reaper.ImGui_CreateContext("Boom Vocab Sorter")

-- ================================================================
-- 路径
-- ================================================================
local script_path = ({reaper.get_action_context()})[2]:match("(.*[/\\])")
local pool_file = script_path .. "boom_vocab/word_pool.lua"
local categories_file = script_path .. "boom_vocab/boom_categories.lua"

-- ================================================================
-- 加载词汇池
-- ================================================================
local word_pool = {}
local ok_pool, data = pcall(dofile, pool_file)
if ok_pool and type(data) == "table" then
  word_pool = data
end

-- ================================================================
-- 加载已有分类
-- ================================================================
local categories = {}  -- {cat_name = {word1=true, word2=true, ...}}
local word_category = {} -- word -> cat_name (快速查找)
local cat_order = {}   -- 保持插入顺序

local function save_categories()
  local f = io.open(categories_file, "w")
  if not f then return end
  f:write("-- boom_categories.lua\n")
  f:write("-- Boom 词汇分类结果，由 Vocab Sorter 自动生成\n\n")
  f:write("local M = {}\n\n")
  f:write("M.categories = {\n")
  for _, cat in ipairs(cat_order) do
    local words = categories[cat]
    if words and next(words) then
      f:write('  ["' .. cat .. '"] = {\n')
      -- 按字母排序写出
      local sorted = {}
      for w in pairs(words) do table.insert(sorted, w) end
      table.sort(sorted)
      for _, w in ipairs(sorted) do
        f:write('    "' .. w .. '",\n')
      end
      f:write("  },\n")
    end
  end
  f:write("}\n\n")
  f:write("M.cat_order = {\n")
  for _, cat in ipairs(cat_order) do
    f:write('  "' .. cat .. '",\n')
  end
  f:write("}\n\n")
  f:write("return M\n")
  f:close()
end

local function load_categories()
  local ok, data = pcall(dofile, categories_file)
  if ok and type(data) == "table" and data.categories then
    categories = data.categories
    cat_order = data.cat_order or {}
    -- 构建 word_category 反查表
    for cat, words in pairs(categories) do
      if type(words) == "table" then
        for _, w in ipairs(words) do
          word_category[w] = cat
        end
      end
    end
  end
end

load_categories()

-- ================================================================
-- 状态
-- ================================================================
local current_idx = 1  -- 当前词汇索引
local new_cat_buf = "" -- 新建类别输入
local new_cat_mode = false
local assign_mode = false  -- 数字键分配模式
local status_msg = ""
local status_timer = 0
local filter_cat = ""  -- 按类别筛选
local show_classified = false  -- 是否显示已分类词

-- 已跳过的词
local skipped = {}
-- 加载跳过记录
local skip_file = script_path .. "boom_vocab/skip_record.lua"
local function load_skip()
  local ok, data = pcall(dofile, skip_file)
  if ok and type(data) == "table" then
    for _, w in ipairs(data) do skipped[w] = true end
  end
end
local function save_skip()
  local f = io.open(skip_file, "w")
  if not f then return end
  f:write("return {\n")
  for w in pairs(skipped) do
    f:write('  "' .. w .. '",\n')
  end
  f:write("}\n")
  f:close()
end
load_skip()

-- ================================================================
-- 统计
-- ================================================================
local function get_stats()
  local total = #word_pool
  local classified = 0
  local skipped_count = 0
  for _, entry in ipairs(word_pool) do
    if word_category[entry.word] then classified = classified + 1 end
    if skipped[entry.word] then skipped_count = skipped_count + 1 end
  end
  return total, classified, skipped_count
end

-- 找下一个未分类、未跳过的词
local function find_next_unclassified(start_idx)
  for i = start_idx, #word_pool do
    local w = word_pool[i].word
    if not word_category[w] and not skipped[w] then
      return i
    end
  end
  -- 从头找
  for i = 1, start_idx - 1 do
    local w = word_pool[i].word
    if not word_category[w] and not skipped[w] then
      return i
    end
  end
  return nil  -- 全部完成
end

-- 初始化：定位到第一个未分类词
if #word_pool > 0 then
  local next_i = find_next_unclassified(1)
  if next_i then current_idx = next_i end
end

-- ================================================================
-- 归类操作
-- ================================================================
local function assign_word(word, cat)
  -- 如果已有分类，先从旧分类移除
  local old_cat = word_category[word]
  if old_cat and categories[old_cat] then
    categories[old_cat][word] = nil
  end
  -- 添加到新分类
  if not categories[cat] then
    categories[cat] = {}
    table.insert(cat_order, cat)
  end
  categories[cat][word] = true
  word_category[word] = cat
  save_categories()
  status_msg = word .. " -> [" .. cat .. "]"
  status_timer = 120
end

local function skip_word(word)
  skipped[word] = true
  save_skip()
  status_msg = "跳过: " .. word
  status_timer = 60
end

-- ================================================================
-- 主循环
-- ================================================================
local first_frame = true

function loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, 720, 620, reaper.ImGui_Cond_FirstUseEver())
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

  -- 确保索引有效
  if current_idx < 1 then current_idx = 1 end
  if current_idx > #word_pool then current_idx = #word_pool end

  local entry = word_pool[current_idx]

  -- ================================================================
  -- 顶部：进度条
  -- ================================================================
  local total, classified, skipped_count = get_stats()
  local remaining = total - classified - skipped_count
  local pct = total > 0 and (classified / total * 100) or 0

  reaper.ImGui_Text(ctx, string.format("进度: %d/%d 已分类 | %d 跳过 | %d 剩余 | %.1f%%",
    classified, total, skipped_count, remaining, pct))

  -- 进度条
  local bar_w = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGuiCol_PlotHistogram(), 0xFF66CC66)
  reaper.ImGui_ProgressBar(ctx, pct / 100, bar_w, 0, "")
  reaper.ImGui_PopStyleColor(ctx)

  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 当前词 + 上下文
  -- ================================================================
  local is_classified = word_category[entry.word] ~= nil
  local is_skipped = skipped[entry.word] ~= nil

  -- 词频信息行
  reaper.ImGui_TextColored(ctx, 0xFFCCCCFF, string.format("[%d/%d]", current_idx, #word_pool))
  reaper.ImGui_SameLine(ctx)

  -- 当前词（大号显示）
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGuiCol_Text(), is_classified and 0xFF66CC66 or (is_skipped and 0xFF888888 or 0xFFFFFFFF))
  reaper.ImGui_Text(ctx, entry.word)
  reaper.ImGui_PopStyleColor(ctx)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextColored(ctx, 0xFF888888, string.format("词频:%d  desc:%d  fn:%d  tier:%s  来源:%s",
    entry.count, entry.desc_count, entry.fn_count, entry.tier, entry.source))

  -- 已分类标记
  if is_classified then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF66CC66, "-> [" .. word_category[entry.word] .. "]")
  elseif is_skipped then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF888888, "[已跳过]")
  end

  -- 上下文示例
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextColored(ctx, 0xFFAAAAAA, "上下文示例:")
  reaper.ImGui_Indent(ctx)
  if entry.examples then
    for i = 1, #entry.examples do
      reaper.ImGui_TextWrapped(ctx, entry.examples[i])
      if i < #entry.examples then
        reaper.ImGui_Spacing(ctx)
      end
    end
  else
    reaper.ImGui_TextColored(ctx, 0xFF666666, "无示例")
  end
  reaper.ImGui_Unindent(ctx)

  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 分类操作区
  -- ================================================================

  -- 新建类别输入
  if new_cat_mode then
    reaper.ImGui_TextColored(ctx, 0xFFFFAA00, "新类别名称:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local changed, val = reaper.ImGui_InputText(ctx, "##newcat", new_cat_buf, 64,
      reaper.ImGui_InputTextFlags_EnterReturnsTrue())
    if changed then new_cat_buf = val end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "确认", 50, 22) and new_cat_buf ~= "" then
      assign_word(entry.word, new_cat_buf)
      new_cat_buf = ""
      new_cat_mode = false
      -- 自动跳到下一个
      local nxt = find_next_unclassified(current_idx + 1)
      if nxt then current_idx = nxt end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "取消", 50, 22) then
      new_cat_mode = false
      new_cat_buf = ""
    end
  else
    -- 已有类别按钮（每行最多6个）
    reaper.ImGui_TextColored(ctx, 0xFFCCCCFF, "归到已有类别:")
    if #cat_order == 0 then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextColored(ctx, 0xFF666666, "暂无类别，按 N 新建")
    end

    local btn_idx = 0
    for i, cat in ipairs(cat_order) do
      if i <= 9 then
        local count = 0
        for _ in pairs(categories[cat] or {}) do count = count + 1 end
        local label = string.format("%d.%s(%d)", i, cat, count)
        local btn_w = reaper.ImGui_CalcTextSize(ctx, label) + 20
        if btn_idx > 0 then reaper.ImGui_SameLine(ctx, 0, 4) end
        -- 当前词已归此类则高亮
        if word_category[entry.word] == cat then
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGuiCol_Button(), 0xFF446644)
        end
        if reaper.ImGui_Button(ctx, label, btn_w, 24) then
          assign_word(entry.word, cat)
          local nxt = find_next_unclassified(current_idx + 1)
          if nxt then current_idx = nxt end
        end
        if word_category[entry.word] == cat then
          reaper.ImGui_PopStyleColor(ctx)
        end
        btn_idx = btn_idx + 1
        if btn_idx >= 6 then btn_idx = 0 end
      end
    end

    -- 超过9个类别的，用下拉选择
    if #cat_order > 9 then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Text("更多类别:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, 200)
      local sel_idx = 0
      if reaper.ImGui_BeginCombo(ctx, "##morecats", "选择类别...") then
        for i, cat in ipairs(cat_order) do
          if i > 9 then
            local count = 0
            for _ in pairs(categories[cat] or {}) do count = count + 1 end
            if reaper.ImGui_Selectable(ctx, cat .. " (" .. count .. ")") then
              assign_word(entry.word, cat)
              local nxt = find_next_unclassified(current_idx + 1)
              if nxt then current_idx = nxt end
            end
          end
        end
        reaper.ImGui_EndCombo(ctx)
      end
    end
  end

  reaper.ImGui_Spacing(ctx)

  -- 操作按钮行
  if reaper.ImGui_Button(ctx, "N 新建类别", 90, 26) then
    new_cat_mode = true
    new_cat_buf = ""
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "S 跳过", 65, 26) then
    skip_word(entry.word)
    local nxt = find_next_unclassified(current_idx + 1)
    if nxt then current_idx = nxt end
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "U 取消分类", 85, 26) then
    if is_classified then
      local cat = word_category[entry.word]
      if categories[cat] then categories[cat][entry.word] = nil end
      word_category[entry.word] = nil
      save_categories()
      status_msg = "已取消: " .. entry.word
      status_timer = 60
    end
  end
  reaper.ImGui_SameLine(ctx, 0, 4)
  if reaper.ImGui_Button(ctx, "R 取消跳过", 85, 26) then
    if is_skipped then
      skipped[entry.word] = nil
      save_skip()
      status_msg = "取消跳过: " .. entry.word
      status_timer = 60
    end
  end

  reaper.ImGui_Separator(ctx)

  -- ================================================================
  -- 导航
  -- ================================================================
  reaper.ImGui_Text(ctx, "导航:")
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_Button(ctx, "|< 首个", 60, 22) then
    local nxt = find_next_unclassified(1)
    if nxt then current_idx = nxt end
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, "< 上一个", 65, 22) then
    -- 找前一个未分类词
    for i = current_idx - 1, 1, -1 do
      local w = word_pool[i].word
      if not word_category[w] and not skipped[w] then
        current_idx = i
        break
      end
    end
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, "> 下一个", 65, 22) then
    local nxt = find_next_unclassified(current_idx + 1)
    if nxt then current_idx = nxt end
  end
  reaper.ImGui_SameLine(ctx, 0, 2)
  if reaper.ImGui_Button(ctx, ">| 末个", 60, 22) then
    for i = #word_pool, 1, -1 do
      local w = word_pool[i].word
      if not word_category[w] and not skipped[w] then
        current_idx = i
        break
      end
    end
  end
  reaper.ImGui_SameLine(ctx, 0, 8)
  reaper.ImGui_TextColored(ctx, 0xFF888888, "或直接浏览:")
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
  -- 类别概览（折叠）
  -- ================================================================
  if reaper.ImGui_CollapsingHeader(ctx, "类别概览 (" .. #cat_order .. ")") then
    reaper.ImGui_Indent(ctx)
    for _, cat in ipairs(cat_order) do
      local words = categories[cat] or {}
      local count = 0
      for _ in pairs(words) do count = count + 1 end
      reaper.ImGui_TextColored(ctx, 0xFFCCCCFF, cat)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextColored(ctx, 0xFF888888, "(" .. count .. ")")
      reaper.ImGui_SameLine(ctx)
      -- 显示前5个词
      local shown = 0
      local word_list = {}
      for w in pairs(words) do table.insert(word_list, w) end
      table.sort(word_list, function(a, b)
        -- 按词频排序
        local ca = 0; local cb = 0
        for _, e in ipairs(word_pool) do
          if e.word == a then ca = e.count end
          if e.word == b then cb = e.count end
        end
        return ca > cb
      end)
      local preview = {}
      for _, w in ipairs(word_list) do
        if shown >= 8 then break end
        table.insert(preview, w)
        shown = shown + 1
      end
      reaper.ImGui_TextColored(ctx, 0xFFAAAAAA, table.concat(preview, ", ") .. (count > 8 and " ..." or ""))
    end
    reaper.ImGui_Unindent(ctx)
  end

  -- ================================================================
  -- 快捷键提示
  -- ================================================================
  if reaper.ImGui_CollapsingHeader(ctx, "快捷键") then
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_Text(ctx, "1-9     归到已有类别")
    reaper.ImGui_Text(ctx, "N       新建类别")
    reaper.ImGui_Text(ctx, "S       跳过当前词")
    reaper.ImGui_Text(ctx, "U       取消分类")
    reaper.ImGui_Text(ctx, "R       取消跳过")
    reaper.ImGui_Text(ctx, "←/→     前后导航（含已分类）")
    reaper.ImGui_Text(ctx, "Enter   新建类别时确认")
    reaper.ImGui_Text(ctx, "Esc     取消新建/退出输入")
    reaper.ImGui_Unindent(ctx)
  end

  -- ================================================================
  -- 键盘快捷键
  -- ================================================================
  if not new_cat_mode then
    -- 数字键 1-9 分配到类别
    for i = 1, math.min(9, #cat_order) do
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_0 + i) then
        assign_word(entry.word, cat_order[i])
        local nxt = find_next_unclassified(current_idx + 1)
        if nxt then current_idx = nxt end
      end
    end
    -- N = 新建类别
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_N) then
      new_cat_mode = true
      new_cat_buf = ""
    end
    -- S = 跳过
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S) then
      skip_word(entry.word)
      local nxt = find_next_unclassified(current_idx + 1)
      if nxt then current_idx = nxt end
    end
    -- U = 取消分类
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_U) then
      if is_classified then
        local cat = word_category[entry.word]
        if categories[cat] then categories[cat][entry.word] = nil end
        word_category[entry.word] = nil
        save_categories()
      end
    end
    -- R = 取消跳过
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_R) then
      if is_skipped then
        skipped[entry.word] = nil
        save_skip()
      end
    end
    -- 左右箭头浏览
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow) then
      current_idx = math.max(1, current_idx - 1)
    end
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow) then
      current_idx = math.min(#word_pool, current_idx + 1)
    end
  else
    -- 新建类别模式下，Esc取消
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape) then
      new_cat_mode = false
      new_cat_buf = ""
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
