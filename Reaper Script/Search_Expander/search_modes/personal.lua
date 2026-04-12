-- search_modes/personal.lua
-- 个人经验映射模式
-- 基于用户自定义的映射关系扩展搜索词
-- 支持两种映射格式：
--   直接词映射: "insect" -> 直接作为搜索结果
--   UCS分类映射: "CAT:CREATURE/INSECTOID" -> 展开该分类下的所有词
--
-- 接口:
--   init(script_path)          加载数据
--   set_ucs_module(ucs_mod)    设置 UCS 模块引用（用于解析分类路径）
--   expand(term, input)        扩展搜索
--   add(key, targets)          添加映射
--   add_categories(key, catpaths) 添加 UCS 分类映射
--   get()                      获取映射表
--   load()                     重新加载
--   save()                     保存

local M = {}

local personal_file = ""
local personal_mappings = {}
local ucs_module = nil

function M.init(script_path)
  personal_file = script_path .. "personal_mappings.lua"
  M.load()
  return true
end

function M.set_ucs_module(ucs_mod)
  ucs_module = ucs_mod
end

function M.load()
  local ok, data = pcall(dofile, personal_file)
  personal_mappings = (ok and type(data) == "table") and data or {}
end

function M.save()
  local f = io.open(personal_file, "w")
  if f then
    f:write("return {\n")
    for src, targets in pairs(personal_mappings) do
      f:write(string.format("  [%q] = {", src))
      for i, t in ipairs(targets) do
        if i > 1 then f:write(",") end
        f:write(string.format("%q", t))
      end
      f:write("},\n")
    end
    f:write("}\n")
    f:close()
  end
end

function M.add(key, targets)
  personal_mappings[key] = targets
  M.save()
end

-- 添加 UCS 分类映射（catpaths: {"CREATURE/INSECTOID", "METAL/CLANG"}）
function M.add_categories(key, catpaths)
  local targets = {}
  for _, cp in ipairs(catpaths) do
    table.insert(targets, "CAT:" .. cp)
  end
  -- 合并已有映射（保留直接词映射）
  if personal_mappings[key] then
    for _, v in ipairs(personal_mappings[key]) do
      if not v:find("^CAT:") then
        table.insert(targets, v)
      end
    end
  end
  personal_mappings[key] = targets
  M.save()
end

function M.get()
  return personal_mappings
end

-- 核心扩展
-- term: 当前处理的单个词
-- input: 原始完整输入（用于兜底匹配）
function M.expand(term, input)
  local categories = {}
  local seen = {}

  local pm = personal_mappings[term] or (input and personal_mappings[input])
  if pm then
    for _, entry in ipairs(pm) do
      local cat_key
      local words_source
      if entry:find("^CAT:") and ucs_module then
        -- UCS 分类路径 -> 按分类分组
        cat_key = entry:sub(5)
        words_source = ucs_module.get_words_by_category(cat_key)
      else
        -- 直接词映射 -> 归入"直接映射"组
        cat_key = "direct"
        words_source = {}
        for sub_w in entry:gmatch("%S+") do table.insert(words_source, sub_w) end
      end
      if not categories[cat_key] then categories[cat_key] = {} end
      for _, w in ipairs(words_source) do
        if not seen[w] then
          seen[w] = true
          table.insert(categories[cat_key], w)
        end
      end
    end
  end

  return {
    source = "personal",
    label = "个人映射",
    categories = categories,
  }
end

return M
