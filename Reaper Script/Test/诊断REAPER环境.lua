-- 快速诊断 REAPER 环境和扩展

local report = ""

-- REAPER 版本
local retval, version_str = reaper.GetAppVersion()
report = report .. "REAPER 版本: " .. tostring(version_str) .. "\n"

-- SWS 扩展检测
report = report .. "\n--- SWS 扩展 ---\n"
local sws_funcs = {
  "BR_GetMediaItemTakeInfo", "BR_SetMediaItemTakeInfo",
  "BR_GetMediaItemInfo_String", "BR_SetMediaItemInfo_String",
  "BR_GetTakeGUID", "BR_EnvGetProperties",
  "SNM_GetIntConfigVar", "SNM_SetIntConfigVar",
  "CF_GetClipboardBig", "CF_GetSWSVersion"
}
for _, fn in ipairs(sws_funcs) do
  if reaper[fn] then
    report = report .. "  reaper." .. fn .. ": 可用\n"
  end
end

-- js_ReaScriptAPI 检测
report = report .. "\n--- js_ReaScriptAPI ---\n"
if reaper.JS_ReaScriptAPI_Version then
  report = report .. "  版本: " .. tostring(reaper.JS_ReaScriptAPI_Version()) .. "\n"
else
  report = report .. "  未安装\n"
end

-- 核心 ExtState API
report = report .. "\n--- ExtState API ---\n"
report = report .. "  GetSetProjExtState: " .. (reaper.GetSetProjExtState and "可用" or "不可用") .. "\n"
report = report .. "  GetProjExtState: " .. (reaper.GetProjExtState and "可用" or "不可用") .. "\n"
report = report .. "  SetProjExtState: " .. (reaper.SetProjExtState and "可用" or "不可用") .. "\n"
report = report .. "  GetExtState: " .. (reaper.GetExtState and "可用" or "不可用") .. "\n"
report = report .. "  SetExtState: " .. (reaper.SetExtState and "可用" or "不可用") .. "\n"
report = report .. "  GetExtState (带section): " .. (reaper.HasExtState and "可用" or "不可用") .. "\n"
report = report .. "  GetItemExtState: " .. (reaper.GetItemExtState and "可用" or "不可用") .. "\n"
report = report .. "  SetItemExtState: " .. (reaper.SetItemExtState and "可用" or "不可用") .. "\n"
report = report .. "  GetTakeExtState: " .. (reaper.GetTakeExtState and "可用" or "不可用") .. "\n"
report = report .. "  SetTakeExtState: " .. (reaper.SetTakeExtState and "可用" or "不可用") .. "\n"
report = report .. "  GetItemExtState_Key: " .. (reaper.GetItemExtState_Key and "可用" or "不可用") .. "\n"
report = report .. "  GetTakeExtState_Key: " .. (reaper.GetTakeExtState_Key and "可用" or "不可用") .. "\n"

-- 测试全局 ExtState 写入和读取
report = report .. "\n--- 全局 ExtState 测试 ---\n"
reaper.SetExtState("TestDiag", "test_key", "test_value_123", false)
local val = reaper.GetExtState("TestDiag", "test_key")
report = report .. "  写入/读取测试: " .. (val == "test_value_123" and "成功" or "失败 (值=" .. tostring(val) .. ")") .. "\n"

-- 测试 Item ExtState 写入和读取
report = report .. "\n--- Item ExtState 测试 ---\n"
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
  if reaper.SetItemExtState then
    reaper.SetItemExtState(item, "test_rank_key", "rank1_smile", true)
    local read_val = reaper.GetItemExtState(item, "test_rank_key", "")
    report = report .. "  SetItemExtState 写入成功\n"
    report = report .. "  GetItemExtState 读取: \"" .. tostring(read_val) .. "\"\n"
  else
    report = report .. "  SetItemExtState 不可用，无法测试\n"
  end
else
  report = report .. "  没有选中的Item\n"
end

-- 列出已安装的扩展
report = report .. "\n--- 扩展检测 ---\n"
report = report .. "  ImGui: " .. (reaper.ImGui_CreateContext and "可用" or "不可用") .. "\n"

-- SWS 版本检测（如果可用）
if reaper.CF_GetSWSVersion then
  local sws_ver = reaper.CF_GetSWSVersion()
  report = report .. "  SWS 版本: " .. tostring(sws_ver) .. "\n"
end

reaper.ShowConsoleMsg(report)
reaper.ShowMessageBox("环境诊断完成！请查看控制台。", "完成", 0)
