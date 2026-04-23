-- 定义该项目 Item Rank
-- 配置保存到当前工程文件中，随工程切换

local ext_name = "ItemRankDef"

-- 读取项目扩展状态
local function load_project_config()
  local config = {
    rank1_smile = "",
    rank2_smile = "",
    rank3_smile = "",
    rank1_frown = "",
    empty_rank = ""
  }
  
  local retval, v1 = reaper.GetProjExtState(0, ext_name, "rank1_smile")
  local retval2, v2 = reaper.GetProjExtState(0, ext_name, "rank2_smile")
  local retval3, v3 = reaper.GetProjExtState(0, ext_name, "rank3_smile")
  local retval4, v4 = reaper.GetProjExtState(0, ext_name, "rank1_frown")
  local retval5, v5 = reaper.GetProjExtState(0, ext_name, "empty_rank")
  
  if retval == 1 then config.rank1_smile = v1 end
  if retval2 == 1 then config.rank2_smile = v2 end
  if retval3 == 1 then config.rank3_smile = v3 end
  if retval4 == 1 then config.rank1_frown = v4 end
  if retval5 == 1 then config.empty_rank = v5 end
  
  return config
end

-- 保存配置到当前工程
local function save_project_config(config)
  reaper.SetProjExtState(0, ext_name, "rank1_smile", config.rank1_smile)
  reaper.SetProjExtState(0, ext_name, "rank2_smile", config.rank2_smile)
  reaper.SetProjExtState(0, ext_name, "rank3_smile", config.rank3_smile)
  reaper.SetProjExtState(0, ext_name, "rank1_frown", config.rank1_frown)
  reaper.SetProjExtState(0, ext_name, "empty_rank", config.empty_rank)
end

-- 检查是否有工程打开
local proj = reaper.EnumProjects(-1)
if not proj then
  reaper.ShowMessageBox("请先打开一个工程文件！", "提示", 0)
  return
end

-- 加载当前工程的配置
local config = load_project_config()

-- 构建带默认值的输入框初始值
local default_values = config.rank1_smile .. ","
default_values = default_values .. config.rank2_smile .. ","
default_values = default_values .. config.rank3_smile .. ","
default_values = default_values .. config.rank1_frown .. ","
default_values = default_values .. config.empty_rank

local retval, retvals_csv = reaper.GetUserInputs("定义该项目item rank", 5, 
  "笑脸1级:,笑脸2级:,笑脸3级:,哭脸1级:,空级（无标注）:", 
  default_values)

if not retval then return end

-- 解析返回值
local rank1_smile, rank2_smile, rank3_smile, rank1_frown, empty_rank
rank1_smile, rank2_smile, rank3_smile, rank1_frown, empty_rank = 
  retvals_csv:match("([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")

config.rank1_smile = rank1_smile or ""
config.rank2_smile = rank2_smile or ""
config.rank3_smile = rank3_smile or ""
config.rank1_frown = rank1_frown or ""
config.empty_rank = empty_rank or ""

-- 保存到当前工程
save_project_config(config)

-- 显示确认对话框
local msg = "定义已保存到此工程！\n\n"
msg = msg .. "笑脸1级: " .. (config.rank1_smile ~= "" and config.rank1_smile or "(未定义)") .. "\n"
msg = msg .. "笑脸2级: " .. (config.rank2_smile ~= "" and config.rank2_smile or "(未定义)") .. "\n"
msg = msg .. "笑脸3级: " .. (config.rank3_smile ~= "" and config.rank3_smile or "(未定义)") .. "\n"
msg = msg .. "哭脸1级: " .. (config.rank1_frown ~= "" and config.rank1_frown or "(未定义)") .. "\n"
msg = msg .. "空级: " .. (config.empty_rank ~= "" and config.empty_rank or "(未定义)")

reaper.ShowMessageBox(msg, "Item Rank 定义已保存", 0)
