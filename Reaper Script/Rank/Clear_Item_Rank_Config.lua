-- 一键删除当前工程的所有 Item Rank 定义
-- 仅清除当前打开工程的配置

local ext_name = "ItemRankDef"

-- 检查是否有工程打开
local proj = reaper.EnumProjects(-1)
if not proj then
  reaper.ShowMessageBox("请先打开一个工程文件！", "提示", 0)
  return
end

local retval = reaper.ShowMessageBox(
  "确定要删除当前工程的所有 Item Rank 定义吗？\n此操作不可撤销。", 
  "确认删除", 
  1)

if retval == 1 then
  reaper.SetProjExtState(0, ext_name, "rank1_smile", "")
  reaper.SetProjExtState(0, ext_name, "rank2_smile", "")
  reaper.SetProjExtState(0, ext_name, "rank3_smile", "")
  reaper.SetProjExtState(0, ext_name, "rank1_frown", "")
  reaper.SetProjExtState(0, ext_name, "empty_rank", "")
  reaper.ShowMessageBox("当前工程的定义已清空！", "删除成功", 0)
end
