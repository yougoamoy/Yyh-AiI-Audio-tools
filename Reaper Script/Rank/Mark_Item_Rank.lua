-- Marker Tool - 定义 + 标记合一面板
-- 动态数量的 marker，+/- 按钮增减
-- 使用 Take Marker API（REAPER 7.17+）

local ext_name = "MarkerTool"
local ctx = reaper.ImGui_CreateContext("Marker Tool")

-- 颜色池
local color_pool = {
  0xFF44BB44, 0xFF4488CC, 0xFFCC8844, 0xFFCC44CC, 0xFF44CCCC,
  0xFF88CC44, 0xFFCC4488, 0xFF8844CC, 0xFFCCCC44, 0xFF448888,
}

-- 读写 ProjExtState
local function load_markers()
  local markers = {}
  local rv, cnt_s = reaper.GetProjExtState(0, ext_name, "count")
  local cnt = (rv == 1 and cnt_s ~= "") and tonumber(cnt_s) or 0
  for i = 1, cnt do
    local r, v = reaper.GetProjExtState(0, ext_name, "m"..i)
    markers[i] = (r == 1) and v or ""
  end
  return markers
end

local function save_markers(markers)
  reaper.SetProjExtState(0, ext_name, "count", tostring(#markers))
  for i, v in ipairs(markers) do
    reaper.SetProjExtState(0, ext_name, "m"..i, v)
  end
end

-- Take Marker 读写
local function get_take_marker_name(take)
  if not take then return nil end
  for i = 0, reaper.GetNumTakeMarkers(take) - 1 do
    local _, name = reaper.GetTakeMarker(take, i)
    if name and name:find("^m%d+$") then return name end
  end
  return nil
end

local function set_take_marker(take, idx)
  if not take then return end
  for i = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
    local _, name = reaper.GetTakeMarker(take, i)
    if name and name:find("^m%d+$") then reaper.DeleteTakeMarker(take, i) end
  end
  if idx > 0 then reaper.SetTakeMarker(take, -1, "m"..idx, 0) end
end

local function count_markers(markers)
  local cnt = {}
  local unk = 0
  local tot = reaper.CountSelectedMediaItems(0)
  for i = 1, #markers do cnt[i] = 0 end
  for i = 0, tot - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      local r = get_take_marker_name(reaper.GetActiveTake(item))
      if r then
        local n = tonumber(r:sub(2))
        if n and n >= 1 and n <= #markers then cnt[n] = cnt[n] + 1 else unk = unk + 1 end
      else unk = unk + 1 end
    end
  end
  return cnt, unk, tot
end

-- UI state
local input_bufs = {}
local dirty = false
local first_frame = true

function loop()
  local markers = load_markers()
  local ic = reaper.CountSelectedMediaItems(0)

  -- 首帧设置窗口大小
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, 340, 400, reaper.ImGui_Cond_FirstUseEver())
    first_frame = false
  end

  local vis, open = reaper.ImGui_Begin(ctx, "Marker Tool", true)
  if vis then
    reaper.ImGui_PushItemWidth(ctx, 200)

    -- ===== 定义区 =====
    reaper.ImGui_Text(ctx, "Marker 定义")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+", 24, 20) then
      table.insert(markers, "")
      input_bufs[#markers] = ""
      save_markers(markers)
    end
    reaper.ImGui_SameLine(ctx)
    if #markers > 1 and reaper.ImGui_Button(ctx, "-", 24, 20) then
      table.remove(markers)
      table.remove(input_bufs)
      save_markers(markers)
    end

    reaper.ImGui_Separator(ctx)

    -- 输入框
    for i = 1, #markers do
      if input_bufs[i] == nil then input_bufs[i] = markers[i] end
      reaper.ImGui_SetNextItemWidth(ctx, 160)
      local changed, new_val = reaper.ImGui_InputText(ctx, "#"..i.."##mk"..i, input_bufs[i], 128)
      if changed then input_bufs[i] = new_val; dirty = true end
      if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        markers[i] = input_bufs[i]
        save_markers(markers)
        dirty = false
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "X##defdel"..i, 20, 20) then
        table.remove(markers, i)
        table.remove(input_bufs, i)
        save_markers(markers)
        break
      end
    end

    if dirty then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFFAA8800)
      if reaper.ImGui_Button(ctx, "保存修改", -1, 20) then
        for i = 1, #markers do markers[i] = input_bufs[i] end
        save_markers(markers)
        dirty = false
      end
      reaper.ImGui_PopStyleColor(ctx)
    end

    reaper.ImGui_Separator(ctx)

    -- ===== 标记区 =====
    if ic == 0 then
      reaper.ImGui_TextColored(ctx, 0xFF8888FF, "先选中 Item")
    else
      reaper.ImGui_Text(ctx, ic .. " 个 Item 已选中")
    end

    local counts, unranked, total = count_markers(markers)

    for i = 1, #markers do
      local name = markers[i]
      if name == "" then name = "(未命名)" end
      local col = color_pool[((i - 1) % #color_pool) + 1]
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col)
      local dis = (ic == 0 or markers[i] == "")
      if dis then reaper.ImGui_BeginDisabled(ctx) end
      reaper.ImGui_SetNextItemWidth(ctx, 200)
      if reaper.ImGui_Button(ctx, "#"..i.." "..name, 200, 26) then
        reaper.Undo_BeginBlock()
        for j = 0, ic - 1 do
          local item = reaper.GetSelectedMediaItem(0, j)
          if item then set_take_marker(reaper.GetActiveTake(item), i) end
        end
        reaper.Undo_EndBlock("Mark #"..i, -1)
        reaper.UpdateArrange()
      end
      if dis then reaper.ImGui_EndDisabled(ctx) end
      reaper.ImGui_PopStyleColor(ctx)
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "X##del"..i, 20, 26) then
        table.remove(markers, i)
        table.remove(input_bufs, i)
        save_markers(markers)
        break
      end
      if counts[i] and counts[i] > 0 then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0xFF66CC66, "("..counts[i]..")")
      end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF666699)
    if ic > 0 and reaper.ImGui_Button(ctx, "清除标记", -1, 26) then
      reaper.Undo_BeginBlock()
      for j = 0, ic - 1 do
        local item = reaper.GetSelectedMediaItem(0, j)
        if item then set_take_marker(reaper.GetActiveTake(item), 0) end
      end
      reaper.Undo_EndBlock("Clear markers", -1)
      reaper.UpdateArrange()
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF4444CC)
    if #markers > 0 and reaper.ImGui_Button(ctx, "删除全部 Marker", -1, 26) then
      markers = {}
      input_bufs = {}
      save_markers(markers)
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_Separator(ctx)
    local st = "未标记: "..unranked
    for i = 1, #markers do
      if counts[i] and counts[i] > 0 then st = st.." | #"..i..": "..counts[i] end
    end
    reaper.ImGui_TextColored(ctx, 0xFFAAAAAA, st)

    -- ===== 整理item区 =====
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "整理 Item")
    
    if ic == 0 then
      reaper.ImGui_BeginDisabled(ctx)
      reaper.ImGui_Button(ctx, "整理item", -1, 30)
      reaper.ImGui_EndDisabled(ctx)
      reaper.ImGui_TextDisabled(ctx, "请先选中需要整理的Item")
    else
      if reaper.ImGui_Button(ctx, "整理item", -1, 30) then
        reaper.Undo_BeginBlock()
        
        -- 收集marker种类和每个marker下的item
        local marker_types = {}
        local marker_items = {}  -- marker_idx -> {items}
        for j = 0, ic - 1 do
          local item = reaper.GetSelectedMediaItem(0, j)
          if item then
            local marker_name = get_take_marker_name(reaper.GetActiveTake(item))
            if marker_name then
              local marker_idx = tonumber(marker_name:sub(2))
              if marker_idx then
                if not marker_types[marker_idx] then
                  marker_types[marker_idx] = true
                end
                if not marker_items[marker_idx] then
                  marker_items[marker_idx] = {}
                end
                table.insert(marker_items[marker_idx], item)
              end
            end
          end
        end
        
        -- 排序marker种类
        local marker_type_order = {}
        for idx, _ in pairs(marker_types) do
          table.insert(marker_type_order, idx)
        end
        table.sort(marker_type_order)
        
        -- 查找已存在的Material Pool和Construction Kit文件夹
        local existing_mp_track = nil
        local existing_ck_track = nil
        local mp_children = {}  -- marker名称 -> track
        local track_count = reaper.CountTracks(0)
        
        for j = 0, track_count - 1 do
          local track = reaper.GetTrack(0, j)
          local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
          local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
          
          if name == "Material Pool" and folder_depth == 1 then
            existing_mp_track = track
            -- 收集Material Pool下的子轨道
            local child_idx = j + 1
            while child_idx < track_count do
              local child_track = reaper.GetTrack(0, child_idx)
              local _, child_name = reaper.GetSetMediaTrackInfo_String(child_track, "P_NAME", "", false)
              local child_depth = reaper.GetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH")
              mp_children[child_name] = child_track
              if child_depth == -1 then break end
              child_idx = child_idx + 1
            end
          end
          
          if name == "Construction Kit" then
            existing_ck_track = track
          end
        end
        
        -- 如果Material Pool不存在，创建完整结构
        if not existing_mp_track then
          -- 在轨道末尾创建Material Pool父轨道
          local mp_base_idx = reaper.CountTracks(0)
          reaper.InsertTrackAtIndex(mp_base_idx, false)
          local mp_track = reaper.GetTrack(0, mp_base_idx)
          reaper.GetSetMediaTrackInfo_String(mp_track, "P_NAME", "Material Pool", true)
          reaper.SetMediaTrackInfo_Value(mp_track, "I_FOLDERDEPTH", 1)
          existing_mp_track = mp_track
          
          -- 为Material Pool创建子轨道（根据marker种类命名）
          for j, marker_idx in ipairs(marker_type_order) do
            local child_idx = mp_base_idx + j
            reaper.InsertTrackAtIndex(child_idx, false)
            local child_track = reaper.GetTrack(0, child_idx)
            local mname = markers[marker_idx] or ("#" .. marker_idx)
            reaper.GetSetMediaTrackInfo_String(child_track, "P_NAME", mname, true)
            mp_children[mname] = child_track
          end
          
          -- 设置Material Pool最后一个子轨道的folder结束标记
          if #marker_type_order > 0 then
            local mp_last_idx = mp_base_idx + #marker_type_order
            local mp_last_track = reaper.GetTrack(0, mp_last_idx)
            if mp_last_track then
              reaper.SetMediaTrackInfo_Value(mp_last_track, "I_FOLDERDEPTH", -1)
            end
          else
            reaper.SetMediaTrackInfo_Value(mp_track, "I_FOLDERDEPTH", -1)
          end
          
          -- 创建Construction Kit父轨道（在Material Pool下方）
          local ck_base_idx = reaper.CountTracks(0)
          reaper.InsertTrackAtIndex(ck_base_idx, false)
          local ck_track = reaper.GetTrack(0, ck_base_idx)
          reaper.GetSetMediaTrackInfo_String(ck_track, "P_NAME", "Construction Kit", true)
          reaper.SetMediaTrackInfo_Value(ck_track, "I_FOLDERDEPTH", -1)
          existing_ck_track = ck_track
          
          -- 收集所有选中item所在的原始轨道（去重）
          local item_tracks_set = {}
          local item_tracks_list = {}
          for j = 0, ic - 1 do
            local item = reaper.GetSelectedMediaItem(0, j)
            if item then
              local track = reaper.GetMediaItem_Track(item)
              local track_idx = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
              if not item_tracks_set[track_idx] then
                item_tracks_set[track_idx] = true
                table.insert(item_tracks_list, track_idx)
              end
            end
          end
          table.sort(item_tracks_list)
          
          -- 将原始轨道移动到Construction Kit下方
          for j = #item_tracks_list, 1, -1 do
            local src_idx = item_tracks_list[j]
            local src_track = reaper.GetTrack(0, src_idx - 1)
            reaper.SetOnlyTrackSelected(src_track)
            reaper.ReorderSelectedTracks(ck_base_idx + 1, 0)
          end
          
          -- 设置Construction Kit子轨道的folder结束标记
          if #item_tracks_list > 0 then
            local ck_last_idx = ck_base_idx + #item_tracks_list
            local ck_last_track = reaper.GetTrack(0, ck_last_idx)
            if ck_last_track then
              reaper.SetMediaTrackInfo_Value(ck_last_track, "I_FOLDERDEPTH", -1)
            end
            reaper.SetMediaTrackInfo_Value(ck_track, "I_FOLDERDEPTH", 1)
          end
        else
          -- Material Pool已存在，为新marker创建子轨道
          -- 找到Material Pool的最后一个子轨道
          local mp_idx = math.floor(reaper.GetMediaTrackInfo_Value(existing_mp_track, "IP_TRACKNUMBER")) - 1
          local last_child_idx = mp_idx
          
          for j = mp_idx + 1, track_count - 1 do
            local track = reaper.GetTrack(0, j)
            local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            last_child_idx = j
            if depth == -1 then
              break
            end
          end
          
          -- 为新marker创建子轨道（插入到最后一个子轨道之前）
          local insert_idx = last_child_idx
          for _, marker_idx in ipairs(marker_type_order) do
            local mname = markers[marker_idx] or ("#" .. marker_idx)
            if not mp_children[mname] then
              -- 在最后一个子轨道位置插入新轨道
              reaper.InsertTrackAtIndex(insert_idx, false)
              local new_track = reaper.GetTrack(0, insert_idx)
              reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", mname, true)
              mp_children[mname] = new_track
              insert_idx = insert_idx + 1
              last_child_idx = last_child_idx + 1
            end
          end
          
          -- 重新设置所有Material Pool子轨道的folder标记
          -- 先清除所有子轨道的-1标记
          for j = mp_idx + 1, last_child_idx do
            local track = reaper.GetTrack(0, j)
            if track then
              local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
              if depth == -1 then
                reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
              end
            end
          end
          -- 设置最后一个子轨道的folder结束标记
          local new_last_child = reaper.GetTrack(0, last_child_idx)
          if new_last_child then
            reaper.SetMediaTrackInfo_Value(new_last_child, "I_FOLDERDEPTH", -1)
          end
        end
        
        -- 处理每个marker的item：移动到对应轨道并按轨道左对齐排列
        for marker_idx, items in pairs(marker_items) do
          local mname = markers[marker_idx] or ("#" .. marker_idx)
          local target_track = mp_children[mname]
          if target_track then
            -- 为同种marker的item设置相同颜色
            local color = color_pool[((marker_idx - 1) % #color_pool) + 1]
            
            -- 获取当前轨道最后一个item的位置
            local track_item_count = reaper.CountTrackMediaItems(target_track)
            local current_pos = 0
            if track_item_count > 0 then
              local last_item = reaper.GetTrackMediaItem(target_track, track_item_count - 1)
              local last_pos = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION")
              local last_len = reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
              current_pos = last_pos + last_len
            end
            
            -- 按轨道左对齐紧密排列
            for _, item in ipairs(items) do
              -- 移动item到目标轨道
              reaper.MoveMediaItemToTrack(item, target_track)
              
              -- 设置颜色
              reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
              
              -- 左对齐紧密排列
              local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
              reaper.SetMediaItemInfo_Value(item, "D_POSITION", current_pos)
              current_pos = current_pos + item_len
            end
          end
        end
        
        reaper.Undo_EndBlock("整理Item到Material Pool", -1)
        reaper.UpdateArrange()
      end
      reaper.ImGui_TextDisabled(ctx, "创建Material Pool/Construction Kit，同种Marker同色")
    end

    reaper.ImGui_PopItemWidth(ctx)
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
