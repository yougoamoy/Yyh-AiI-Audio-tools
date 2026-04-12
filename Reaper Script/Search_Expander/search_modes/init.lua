-- search_modes/init.lua
-- 搜索模式注册中心
-- 管理所有搜索模式的加载、注册和调度
--
-- 添加新模式:
--   1. 在 search_modes/ 下新建 xxx.lua
--   2. 实现 init(script_path) 和 expand(term, input) 接口
--   3. 在 load_all() 中注册
--
-- 模式接口规范:
--   init(script_path) -> bool
--   expand(term, input) -> result
--
--   result 格式（二选一）:
--     分类模式: { source="xxx", label="显示名", categories={ ["catpath"]={"w1","w2"} } }
--     列表模式: { source="xxx", label="显示名", words={"w1","w2"} }

local M = {}

local modes = {}

-- 注册一个模式
function M.register(name, mode_module)
  modes[name] = mode_module
end

-- 获取一个模式
function M.get(name)
  return modes[name]
end

-- 获取所有模式名
function M.list()
  local names = {}
  for name in pairs(modes) do table.insert(names, name) end
  table.sort(names)
  return names
end

-- 依次执行所有已注册模式的 expand，合并结果
function M.expand_all(terms, input)
  local results = {}
  for _, mode in pairs(modes) do
    for _, term in ipairs(terms) do
      local r = mode.expand(term, input)
      if r then table.insert(results, r) end
    end
  end
  return results
end

-- 加载所有内置模式
function M.load_all(script_path)
  local ucs
  local ok, ucs_mod = pcall(dofile, script_path .. "search_modes/ucs.lua")
  if ok then
    ucs_mod.init(script_path)
    M.register("ucs", ucs_mod)
    ucs = ucs_mod
  end

  local ok2, personal = pcall(dofile, script_path .. "search_modes/personal.lua")
  if ok2 then
    personal.init(script_path)
    if ucs then personal.set_ucs_module(ucs) end
    M.register("personal", personal)
  end

  -- 新模式在此添加:
  -- local ok3, xxx = pcall(dofile, script_path .. "search_modes/xxx.lua")
  -- if ok3 then xxx.init(script_path); M.register("xxx", xxx) end
end

return M
