-- search_modes/ucs.lua
-- UCS 分类扩展模式
-- 输入一个词，找出它所属的 UCS 分类，返回这些分类下的所有词
--
-- 接口:
--   init(script_path)  加载数据
--   expand(term)       扩展搜索
--   get_cn(en, catpath) 英→中翻译
--   get_variants(w)    词干变体
--   suggest(prefix)    前缀匹配建议

local M = {}

local ucs_data = nil
local ucs_rev = {}
local ucs_rev_expl = {}
local ucs_entries = {}
local word_to_cats = {}
local all_ucs_words = {}
local all_ucs_phrases = {}
local ucs_zh = {}
local rev_cn = {}
local zh_to_en = {}

function M.init(script_path)
  local ok
  ok, ucs_data = pcall(dofile, script_path .. "ucs_data.lua")
  if not ok then return false end

  ucs_rev = ucs_data.rev or {}
  ucs_rev_expl = ucs_data.rev_expl or {}
  ucs_entries = ucs_data.entries or {}

  local zh_ok
  zh_ok, ucs_zh = pcall(dofile, script_path .. "ucszh_map.lua")
  if not zh_ok then ucs_zh = {} end

  -- word -> categories
  for catpath, words in pairs(ucs_entries) do
    for _, w in ipairs(words) do
      if not word_to_cats[w] then word_to_cats[w] = {} end
      table.insert(word_to_cats[w], catpath)
    end
  end

  -- unique sorted word list
  local set = {}
  for _, words in pairs(ucs_entries) do
    for _, w in ipairs(words) do
      if not set[w] then set[w] = true; table.insert(all_ucs_words, w) end
    end
  end
  table.sort(all_ucs_words)

  -- phrase lookup (lowercase)
  for phrase in pairs(ucs_rev) do all_ucs_phrases[phrase:lower()] = true end

  -- zh -> en reverse from ucs_zh
  for _, word_map in pairs(ucs_zh) do
    for en, zh in pairs(word_map) do
      if not zh_to_en[zh] then zh_to_en[zh] = {} end
      zh_to_en[zh][en] = true
    end
  end

  return true
end

-- 英→中翻译
function M.get_cn(w, catpath)
  if catpath and ucs_zh[catpath] and ucs_zh[catpath][w] then return ucs_zh[catpath][w] end
  if rev_cn[w] then return rev_cn[w] end
  for zh, en in pairs(zh_to_en) do
    for en_w in pairs(en) do
      if en_w == w then return zh end
    end
  end
  return ""
end

-- 注册中文词（由主脚本调用，合并 cn 表）
function M.register_cn(cn_table)
  for k, v in pairs(cn_table) do
    if not rev_cn[v] then rev_cn[v] = k end
    if not zh_to_en[k] then zh_to_en[k] = {} end
    zh_to_en[k][v] = true
  end
end

-- zh_to_en 查找（供主脚本中文输入使用）
function M.get_zh_to_en()
  return zh_to_en
end

-- 是否是 UCS 短语
function M.is_ucs_phrase(w)
  return all_ucs_phrases[w:lower()] == true
end

-- 所有 UCS 词
function M.get_all_words()
  return all_ucs_words
end

-- 前缀匹配
function M.suggest(prefix, limit)
  limit = limit or 8
  local matches = {}
  for _, word in ipairs(all_ucs_words) do
    if word:find("^" .. prefix) and word ~= prefix then
      table.insert(matches, word)
      if #matches >= limit then break end
    end
  end
  return matches
end

-- 词干变体
function M.get_variants(w)
  local set = {[w] = true}
  local list = {w}
  local function add(v)
    if not set[v] and #v >= 3 then set[v] = true; table.insert(list, v) end
  end
  if w:match("ing$") then
    local base = w:sub(1, -4)
    add(base); add(base .. "e"); add(base .. "ed"); add(base .. "s"); add(base .. "er")
    if #base >= 2 then add(base:sub(1, -2) .. "e") end
  end
  if w:match("ed$") then
    local base = w:sub(1, -3)
    add(base); add(base .. "e"); add(base .. "ing"); add(base .. "s"); add(base .. "er")
    add(w:sub(1, -2))
  end
  if w:match("er$") then
    local base = w:sub(1, -3)
    add(base); add(base .. "ing"); add(base .. "ed"); add(base .. "s")
  end
  if w:match("s$") and not w:match("ss$") then
    local base = w:sub(1, -2)
    add(base); add(base .. "ing"); add(base .. "ed"); add(base .. "er")
  end
  if w:match("tion$") then
    local base = w:sub(1, -4)
    add(base); add(base .. "te"); add(base .. "ted"); add(base .. "ting")
  end
  if w:match("ly$") then
    add(w:sub(1, -3))
  end
  if not w:match("e$") then add(w .. "ing") else add(w:sub(1,-2) .. "ing") end
  if not w:match("e$") then add(w .. "ed") else add(w:sub(1,-2) .. "ed") end
  add(w .. "s"); add(w .. "er"); add(w .. "tion")
  return list
end

-- 核心扩展
function M.expand(term)
  local categories = {}
  local seen = {}

  for _, variant in ipairs(M.get_variants(term)) do
    local cats_set = {}
    for _, src in ipairs({ucs_rev[variant], ucs_rev_expl[variant], word_to_cats[variant]}) do
      if src then for _, cp in ipairs(src) do cats_set[cp] = true end end
    end
    for catpath in pairs(cats_set) do
      if not categories[catpath] then
        categories[catpath] = {}
        if ucs_entries[catpath] then
          for _, w in ipairs(ucs_entries[catpath]) do
            if not seen[w] then seen[w] = true; table.insert(categories[catpath], w) end
          end
        end
      end
    end
  end

  return {
    source = "ucs",
    label = "UCS分类",
    categories = categories,
  }
end

return M
