-- Go_To_First_Item_In_Folder.lua
-- 显示所有父文件夹轨道列表，点击选择后将 Edit Cursor 移动到该文件夹最早 item 的起始位置

local ctx = reaper.ImGui_CreateContext("选择父文件夹")
local WINDOW_W = 360
local WINDOW_H = 400
local selected_index = -1  -- -1 表示未选择
local folders = {}

-- ============ 获取所有父文件夹轨道 ============
local function get_folder_tracks()
  local result = {}
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth == 1 then
      local _, name = reaper.GetTrackName(track)
      table.insert(result, { name = name, track = track, index = i })
    end
  end
  return result
end

-- ============ 获取文件夹内所有 item 的时间范围、最顶/最底有 item 的轨道 ============
local function get_folder_item_range(folder_track_index)
  local track_count = reaper.CountTracks(0)
  local range_start  = nil
  local range_end    = nil
  local top_track    = nil   -- 最靠上（序号最小）的有 item 轨道
  local bottom_track = nil   -- 最靠下（序号最大）的有 item 轨道
  local depth_accum  = 0

  for i = folder_track_index, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

    local item_count = reaper.CountTrackMediaItems(track)
    local active_count = 0
    for j = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
      if muted ~= 1 then
        active_count = active_count + 1
      end
    end
    if active_count > 0 then
      -- 记录最顶和最底轨道
      if top_track == nil then top_track = track end
      bottom_track = track

      for j = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(track, j)
        local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
        if muted ~= 1 then
          local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          if range_start == nil or pos < range_start then range_start = pos end
          if range_end   == nil or pos + len > range_end then range_end = pos + len end
        end
      end
    end

    if i > folder_track_index then
      if depth == 1 then break end
      depth_accum = depth_accum + depth
      if depth_accum < 0 then break end
    end
  end

  return range_start, range_end, top_track, bottom_track
end

-- ============ 计算轨道在 arrange 视图中的 Y 偏移（只累加实际有高度的轨道）============
local function get_track_y_offset(target_track)
  local total_y = 0
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    if track == target_track then
      return total_y
    end
    -- I_WNDH 是轨道在 arrange 中实际占用的像素高度，折叠/隐藏时为 0
    local h = reaper.GetMediaTrackInfo_Value(track, "I_WNDH")
    if h > 0 then
      total_y = total_y + h
    end
  end
  return total_y
end

-- ============ 初始化 ============
folders = get_folder_tracks()

-- ============ ImGui 渲染循环 ============
local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, WINDOW_W, WINDOW_H, reaper.ImGui_Cond_Once())

  local visible, open = reaper.ImGui_Begin(ctx, "选择父文件夹", true)

  if visible then
    reaper.ImGui_Text(ctx, "请点击选择一个父文件夹：")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    if #folders == 0 then
      reaper.ImGui_TextDisabled(ctx, "当前工程中没有父文件夹轨道")
    else
      -- 列表区域（带滚动）
      reaper.ImGui_BeginChild(ctx, "folder_list", 0, WINDOW_H - 110)
      local do_jump = false
      for i, f in ipairs(folders) do
        local is_selected = (selected_index == i)
        local flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
        if reaper.ImGui_Selectable(ctx, f.name, is_selected, flags) then
          selected_index = i
          -- 双击直接触发跳转
          if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            do_jump = true
          end
        end
      end
      reaper.ImGui_EndChild(ctx)

      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)

      -- 确认按钮
      if selected_index == -1 then
        reaper.ImGui_BeginDisabled(ctx)
      end

      if reaper.ImGui_Button(ctx, "跳转到所选文件夹", -1, 0) or do_jump then
        local folder = folders[selected_index]
        local range_start, range_end, top_track, bottom_track = get_folder_item_range(folder.index)
        if range_start ~= nil then
          -- Edit Cursor 移动到所有 item 的时间中点
          local time_center = (range_start + range_end) / 2
          reaper.SetEditCurPos(time_center, false, false)

          -- 水平：视图显示所有 item 的完整范围，两侧各留 10% 空白
          local total_len  = range_end - range_start
          local padding    = total_len * 0.1
          local view_start = range_start - padding
          if view_start < 0 then view_start = 0 end
          local view_end   = range_end + padding
          reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)

          -- 垂直：让有 item 的轨道区域在视图中居中
          if top_track ~= nil and reaper.JS_Window_FindChildByID ~= nil then
            reaper.PreventUIRefresh(1)

            local arrange_wnd = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
            if arrange_wnd then
              local _, arrange_w, arrange_h = reaper.JS_Window_GetClientSize(arrange_wnd)
              local top_y = get_track_y_offset(top_track)
              local bot_y = get_track_y_offset(bottom_track)
                          + reaper.GetMediaTrackInfo_Value(bottom_track, "I_WNDH")
              local region_center = (top_y + bot_y) / 2
              local scroll_y = math.floor(region_center - arrange_h / 2)
              if scroll_y < 0 then scroll_y = 0 end

              reaper.JS_Window_SetScrollPos(arrange_wnd, "v", scroll_y)
            end

            reaper.PreventUIRefresh(-1)
          elseif top_track ~= nil then
            -- 兼容方案
            reaper.SetOnlyTrackSelected(top_track)
            reaper.Main_OnCommand(40913, 0)
          end

          reaper.UpdateArrange()
          open = false  -- 关闭窗口
        else
          reaper.ShowMessageBox(
            "文件夹「" .. folder.name .. "」中没有找到任何 item。",
            "提示", 0
          )
        end
      end

      if selected_index == -1 then
        reaper.ImGui_EndDisabled(ctx)
      end
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  end
end

loop()
