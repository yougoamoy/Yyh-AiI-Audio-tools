-- search_modes/personal.lua
-- 个人经验映射模式
-- 基于用户自定义的映射关系扩展搜索词
-- 用于记录"X 可以用 Y 来替代"这类跨分类的经验关联
--
-- 接口:
--   init(script_path)  加载数据
--   expand(term, input) 扩展搜索
--   load()             重新加载映射
--   save()             保存映射
--   add(key, targets)  添加映射
--   get()              获取映射表

local M = {}

local personal_file = ""
local personal_mappings = {}

function M.init(script_path)
  personal_file = script_path .. "personal_mappings.lua"
  M.load()
  return true
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

function M.get()
  return personal_mappings
end

-- 核心扩展
-- term: 当前处理的单个词
-- input: 原始完整输入（用于兜底匹配）
function M.expand(term, input)
  local words = {}
  local seen = {}
  local function add(w)
    if not seen[w] then seen[w] = true; table.insert(words, w) end
  end

  local pm = personal_mappings[term] or (input and personal_mappings[input])
  if pm then
    for _, w in ipairs(pm) do
      for sub_w in w:gmatch("%S+") do add(sub_w) end
    end
  end

  return {
    source = "personal",
    label = "个人经验",
    words = words,
  }
end

return M
