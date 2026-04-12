-- search_modes/boom.lua
-- Boom Library 描述搜索模式
-- 从 descriptions.csv 构建倒排索引，支持全文关键词搜索
-- 返回专业音效描述文本，每个词可点击触发新搜索
--
-- 接口:
--   init(script_path)  加载 CSV 并构建索引
--   expand(term)       搜索匹配的描述
--   ready()            是否已加载成功

local M = {}

local index = {}        -- word -> {row_indices}
local descriptions = {} -- row_index -> description text
local row_tier = {}     -- row_index -> tier weight (new=3, mid=1, old=0)
local loaded = false

-- ================================================================
-- 停用词过滤
-- ================================================================
local stop_words = {
  ["the"]=true, ["a"]=true, ["an"]=true, ["and"]=true, ["or"]=true,
  ["of"]=true, ["in"]=true, ["on"]=true, ["at"]=true, ["to"]=true,
  ["for"]=true, ["with"]=true, ["by"]=true, ["from"]=true, ["is"]=true,
  ["it"]=true, ["its"]=true, ["as"]=true, ["are"]=true, ["was"]=true,
  ["be"]=true, ["been"]=true, ["being"]=true, ["have"]=true, ["has"]=true,
  ["had"]=true, ["do"]=true, ["does"]=true, ["did"]=true, ["will"]=true,
  ["would"]=true, ["could"]=true, ["should"]=true, ["may"]=true,
  ["might"]=true, ["shall"]=true, ["can"]=true, ["not"]=true, ["no"]=true,
  ["but"]=true, ["if"]=true, ["so"]=true, ["than"]=true, ["that"]=true,
  ["this"]=true, ["these"]=true, ["those"]=true, ["which"]=true,
  ["what"]=true, ["who"]=true, ["whom"]=true, ["when"]=true, ["where"]=true,
  ["how"]=true, ["all"]=true, ["each"]=true, ["every"]=true, ["both"]=true,
  ["few"]=true, ["more"]=true, ["most"]=true, ["other"]=true, ["some"]=true,
  ["such"]=true, ["only"]=true, ["own"]=true, ["same"]=true, ["also"]=true,
  ["very"]=true, ["just"]=true, ["because"]=true, ["about"]=true,
  ["between"]=true, ["through"]=true, ["during"]=true, ["before"]=true,
  ["after"]=true, ["above"]=true, ["below"]=true, ["up"]=true, ["down"]=true,
  ["out"]=true, ["off"]=true, ["over"]=true, ["under"]=true, ["again"]=true,
  ["further"]=true, ["then"]=true, ["once"]=true, ["here"]=true,
  ["there"]=true, ["into"]=true, ["onto"]=true, ["upon"]=true,
  ["via"]=true, ["per"]=true, ["s"]=true, ["t"]=true, ["ll"]=true,
  ["re"]=true, ["ve"]=true, ["d"]=true, ["m"]=true,
  ["mono"]=true, ["stereo"]=true, ["wav"]=true,
}

-- ================================================================
-- CSV 解析（处理引号内逗号）
-- ================================================================
local function parse_csv_line(line)
  local fields = {}
  local i = 1
  local len = #line
  while i <= len do
    if line:sub(i, i) == '"' then
      -- 引号字段
      i = i + 1
      local buf = {}
      while i <= len do
        if line:sub(i, i) == '"' then
          if i + 1 <= len and line:sub(i + 1, i + 1) == '"' then
            table.insert(buf, '"')
            i = i + 2
          else
            i = i + 1
            break
          end
        else
          table.insert(buf, line:sub(i, i))
          i = i + 1
        end
      end
      table.insert(fields, table.concat(buf))
      if i <= len and line:sub(i, i) == ',' then
        i = i + 1
      end
    else
      -- 无引号字段
      local j = line:find(",", i, true)
      if j then
        table.insert(fields, line:sub(i, j - 1))
        i = j + 1
      else
        table.insert(fields, line:sub(i))
        i = len + 1
      end
    end
  end
  return fields
end

-- ================================================================
-- 提取描述中的可索引词
-- ================================================================
local function extract_words(text)
  local words = {}
  local seen = {}
  -- 小写化，提取纯字母词
  local lower = text:lower()
  for w in lower:gmatch("[%a][%a']*[%a]+") do
    if not seen[w] and #w >= 2 and not stop_words[w] then
      seen[w] = true
      table.insert(words, w)
    end
  end
  return words
end

-- ================================================================
-- tier 权重
-- ================================================================
local tier_weight = {new = 3, mid = 1, old = 0}

-- ================================================================
-- 加载 CSV
-- ================================================================
function M.init(script_path)
  local csv_path = script_path .. "boom_vocab/descriptions.csv"
  local f = io.open(csv_path, "r")
  if not f then
    return false
  end

  -- 读取全部内容
  local content = f:read("*a")
  f:close()
  if not content or #content == 0 then return false end

  -- 按行分割（处理 \r\n）
  local lines = {}
  for line in content:gmatch("[^\r\n]+") do
    if #line > 0 then
      table.insert(lines, line)
    end
  end

  if #lines < 2 then return false end

  -- 解析表头，找列索引
  local header = parse_csv_line(lines[1])
  local col_desc = nil
  local col_tier = nil
  for idx, name in ipairs(header) do
    local n = name:lower():gsub("%s+", "")
    if n == "description" then col_desc = idx end
    if n == "tier" then col_tier = idx end
  end
  if not col_desc then return false end

  -- 解析数据行，构建索引
  for row = 2, #lines do
    local fields = parse_csv_line(lines[row])
    local desc = fields[col_desc]
    if desc and #desc > 0 then
      local row_idx = #descriptions + 1
      descriptions[row_idx] = desc

      -- tier 权重
      local tier = col_tier and fields[col_tier] or ""
      row_tier[row_idx] = tier_weight[tier] or 1

      -- 倒排索引
      local words = extract_words(desc)
      for _, w in ipairs(words) do
        if not index[w] then index[w] = {} end
        table.insert(index[w], row_idx)
      end
    end
  end

  loaded = true
  return true
end

function M.ready()
  return loaded
end

-- ================================================================
-- 搜索
-- ================================================================
function M.expand(term)
  if not loaded then
    return { source="boom", label="Boom 描述", descriptions={} }
  end

  local key = term:lower():gsub("%s+", "")

  -- 单词直接查索引
  if index[key] then
    local rows = index[key]
    -- 按权重排序（新库优先）
    local sorted = {}
    for _, ri in ipairs(rows) do
      table.insert(sorted, {idx=ri, w=row_tier[ri] or 1})
    end
    table.sort(sorted, function(a, b) return a.w > b.w end)

    local result = {}
    local limit = math.min(#sorted, 50)
    for i = 1, limit do
      table.insert(result, descriptions[sorted[i].idx])
    end

    return { source="boom", label="Boom 描述", descriptions=result }
  end

  return { source="boom", label="Boom 描述", descriptions={} }
end

-- 多词搜索（取交集），从主脚本调用
function M.expand_multi(terms)
  if not loaded or #terms == 0 then
    return { source="boom", label="Boom 描述", descriptions={} }
  end

  -- 收集每个词的匹配行号
  local sets = {}
  for _, term in ipairs(terms) do
    local key = term:lower():gsub("%s+", "")
    local s = {}
    if index[key] then
      for _, ri in ipairs(index[key]) do s[ri] = true end
    end
    table.insert(sets, s)
  end

  -- 取交集
  local intersection = {}
  for ri in pairs(sets[1]) do
    local all_match = true
    for i = 2, #sets do
      if not sets[i][ri] then all_match = false; break end
    end
    if all_match then
      table.insert(intersection, {idx=ri, w=row_tier[ri] or 1})
    end
  end

  -- 如果交集为空，回退到第一个词的结果
  if #intersection == 0 then
    local has_any = false
    for _ in pairs(sets[1]) do has_any = true; break end
    if has_any then
      for ri in pairs(sets[1]) do
        table.insert(intersection, {idx=ri, w=row_tier[ri] or 1})
      end
    end
  end

  -- 按权重排序
  table.sort(intersection, function(a, b) return a.w > b.w end)

  local result = {}
  local limit = math.min(#intersection, 50)
  for i = 1, limit do
    table.insert(result, descriptions[intersection[i].idx])
  end

  return { source="boom", label="Boom 描述", descriptions=result }
end

return M
