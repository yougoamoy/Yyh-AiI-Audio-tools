-- 诊断脚本 v2：穷举所有可能的Rank标记存储位置

local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then
  reaper.ShowMessageBox("请先选中一个Item！", "提示", 0)
  return
end

local full_report = ""

for i = 0, item_count - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  if item then
    full_report = full_report .. "===== Item " .. (i+1) .. " =====\n"

    -- 1. Notes
    local notes_ret = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    local notes = (type(notes_ret) == "string") and notes_ret or ""
    full_report = full_report .. "P_NOTES: \"" .. notes .. "\"\n"

    -- 2. Item 层面的数值属性（穷举常见键）
    local item_value_keys = {
      "B_MUTE", "B_LOOPSRC", "B_ALLTAKESPLAY", "B_UISEL",
      "C_BEATATTACHMODE", "C_LOCK", "D_VOL", "D_POSITION", "D_LENGTH",
      "D_SNAPOFFSET", "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO",
      "D_FADEOUTLEN_AUTO", "D_FADEINDIR", "D_FADEOUTDIR", "D_FADEINSHAPE",
      "D_FADEOUTSHAPE", "I_CUSTOMCOLOR", "I_GROUPID", "I_LASTTAKE",
      "I_LOCK", "I_PLAYRATE", "I_CHANMODE", "I_PITCHMODE",
      "I_USERDATA", "I_HEIGHTOVERRIDE", "I_POOL_GUID",
      -- SWS 扩展属性（可能存在的）
      "I_PASS", "B_SEETHROUGH", "I_SELECTED", "I_FREEMODE",
      "F_FREEMODE_X", "F_FREEMODE_Y", "F_FREEMODE_W", "F_FREEMODE_H",
      "IP_EXT_N", "I_LASTY", "I_LASTH"
    }

    full_report = full_report .. "\n--- Item 数值属性 ---\n"
    for _, key in ipairs(item_value_keys) do
      local ok, val = pcall(function()
        return reaper.GetMediaItemInfo_Value(item, key)
      end)
      if ok and val ~= 0 then
        full_report = full_report .. "  " .. key .. ": " .. tostring(val) .. "\n"
      end
    end

    -- 3. Item 扩展状态（GetItemExtState）
    full_report = full_report .. "\n--- Item Ext State ---\n"
    local item_ext_keys = {
      "rank", "pass_rank", "recording_rank", "take_rank",
      "quality", "rating", "pass", "recording_pass",
      "rank_level", "rank_value"
    }
    if reaper.GetItemExtState then
      local found = false
      for _, key in ipairs(item_ext_keys) do
        local val = reaper.GetItemExtState(item, key, "")
        if val and val ~= "" then
          full_report = full_report .. "  " .. key .. ": \"" .. tostring(val) .. "\"\n"
          found = true
        end
      end
      if not found then
        full_report = full_report .. "  (无值)\n"
      end
    else
      full_report = full_report .. "  GetItemExtState 不可用\n"
    end

    -- Take 信息
    local take = reaper.GetActiveTake(item)
    if take then
      local take_name = reaper.GetTakeName(take) or ""
      full_report = full_report .. "\nTake名称: \"" .. take_name .. "\"\n"

      -- 4. Take 数值属性（穷举）
      local take_value_keys = {
        "B_PPITCH", "B_PPITCH", "I_CHANMODE", "I_PITCHMODE",
        "I_PLAYRATE", "D_VOL", "D_PAN", "D_STARTOFFS",
        "D_STARTOFFS", "I_CUSTOMCOLOR", "IP_TAKENUMBER",
        "D_PANLAW", "I_STRETCHMODE", "I_FITMODE",
        "D_SEEKFUNCHORD", "I_RECARM", "I_RECMODE",
        -- SWS 扩展可能使用的
        "IP_EXT_N", "B_SEETHROUGH", "I_PASS"
      }

      full_report = full_report .. "\n--- Take 数值属性 ---\n"
      for _, key in ipairs(take_value_keys) do
        local ok, val = pcall(function()
          return reaper.GetMediaItemTakeInfo_Value(take, key)
        end)
        if ok and val ~= 0 then
          full_report = full_report .. "  " .. key .. ": " .. tostring(val) .. "\n"
        end
      end

      -- 5. GetTakeExtState
      full_report = full_report .. "\n--- Take Ext State ---\n"
      if reaper.GetTakeExtState then
        local found = false
        for _, key in ipairs(item_ext_keys) do
          local ok, retval, val = pcall(function()
            return reaper.GetTakeExtState(take, key)
          end)
          if ok and retval and val and val ~= "" then
            full_report = full_report .. "  " .. key .. ": \"" .. tostring(val) .. "\"\n"
            found = true
          end
        end
        if not found then
          full_report = full_report .. "  (无值)\n"
        end
      else
        full_report = full_report .. "  GetTakeExtState 不可用\n"
      end

      -- 6. P_EXT: 前缀（通过 GetSetMediaItemTakeInfo_String）
      full_report = full_report .. "\n--- Take P_EXT: 前缀 ---\n"
      local pext_keys = {
        "pass_rank", "rank", "recording_rank", "pass", "quality",
        "rating", "take_rank", "item_rank", "rank_level", "rank_value",
        "rank_marker"
      }
      local found_pext = false
      for _, key in ipairs(pext_keys) do
        local pext_key = "P_EXT:" .. key
        local ok, retval, val = pcall(function()
          return reaper.GetSetMediaItemTakeInfo_String(take, pext_key, "", false)
        end)
        if ok and retval and val and val ~= "" then
          full_report = full_report .. "  " .. pext_key .. ": \"" .. tostring(val) .. "\"\n"
          found_pext = true
        end
      end
      if not found_pext then
        full_report = full_report .. "  (无值)\n"
      end

      -- 7. Item P_EXT: 前缀
      full_report = full_report .. "\n--- Item P_EXT: 前缀 ---\n"
      local found_item_pext = false
      for _, key in ipairs(pext_keys) do
        local pext_key = "P_EXT:" .. key
        local ok, retval, val = pcall(function()
          return reaper.GetSetMediaItemInfo_String(item, pext_key, "", false)
        end)
        if ok and retval and val and val ~= "" then
          full_report = full_report .. "  " .. pext_key .. ": \"" .. tostring(val) .. "\"\n"
          found_item_pext = true
        end
      end
      if not found_item_pext then
        full_report = full_report .. "  (无值)\n"
      end

      -- 8. Take 源文件信息
      full_report = full_report .. "\n--- Take Source ---\n"
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        local ok, src_filename = pcall(function()
          return reaper.GetMediaSourceFileName(source)
        end)
        if ok and src_filename then
          full_report = full_report .. "  文件: " .. src_filename .. "\n"
        end
      end

    else
      full_report = full_report .. "(无Take)\n"
    end

    full_report = full_report .. "\n"
  end
end

reaper.ShowConsoleMsg(full_report)
reaper.ShowMessageBox("诊断完成 v2！\n\n请打开 REAPER 控制台 (View → Console) 查看结果。\n\n重要：请在运行此诊断前，先对选中的Item运行一次 SWS 的 Down-rank 脚本，然后再运行此诊断。", "诊断完成", 0)
