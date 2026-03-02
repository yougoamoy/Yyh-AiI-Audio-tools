--[[
    Random Layer Spreader
    随机 Layer 分区展开工具

    功能：
    - 只处理用户选中的 media items
    - 随机分组并在时间轴上物理分离
    - 同组轨道纵向连续排列（重新排序轨道）
    - 不同组自动涂不同颜色
    - 每组起点添加 Marker
--]]

local CONFIG = {
    gap_seconds = 2.0,
    default_layer = 3,
}

local ZONE_COLORS = {
    {200, 100, 100},
    {100, 200, 100},
    {100, 100, 200},
    {200, 200, 100},
    {200, 100, 200},
    {100, 200, 200},
    {220, 150, 100},
    {150, 100, 220},
}

local EXT_SECTION = "Yyh_RandomLayerSpreader"
local KEY_LAYER_N = "layer_count"
local KEY_GAP = "gap_seconds"

local function shuffle(t)
    math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000))
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local function getItemInfo(item)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    return pos, len
end

local function moveItem(item, new_pos)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
end

local function setTrackColor(track, r, g, b)
    local color = reaper.ColorToNative(r, g, b)
    reaper.SetTrackColor(track, color)
end

local function addMarker(pos, name, color_rgb)
    local color = reaper.ColorToNative(color_rgb[1], color_rgb[2], color_rgb[3])
    reaper.AddProjectMarker2(0, false, pos, 0, name, -1, color)
end

local function getConfig(item_count)
    local saved_layer = reaper.GetExtState(EXT_SECTION, KEY_LAYER_N)
    local saved_gap = reaper.GetExtState(EXT_SECTION, KEY_GAP)

    local default_layer = tonumber(saved_layer) or CONFIG.default_layer
    local default_gap = tonumber(saved_gap) or CONFIG.gap_seconds

    local retval, input = reaper.GetUserInputs(
        "Random Layer Spreader",
        2,
        "Tracks per zone (1-" .. item_count .. "),Gap seconds",
        string.format("%d,%.1f", default_layer, default_gap)
    )

    if not retval then return nil, nil end

    local layer_n, gap = input:match("([^,]+),([^,]+)")
    layer_n = tonumber(layer_n)
    gap = tonumber(gap)

    if not layer_n or layer_n < 1 or layer_n > item_count then
        reaper.ShowMessageBox(
            string.format("Tracks per zone must be 1 to %d", item_count),
            "Error", 0
        )
        return nil, nil
    end

    if not gap or gap < 0 then
        gap = CONFIG.gap_seconds
    end

    reaper.SetExtState(EXT_SECTION, KEY_LAYER_N, tostring(layer_n), false)
    reaper.SetExtState(EXT_SECTION, KEY_GAP, tostring(gap), false)

    return layer_n, gap
end

-- 获取选中的 items，返回 {item, track, original_track_idx} 列表
local function getSelectedItems()
    local items = {}
    local count = reaper.CountSelectedMediaItems(0)
    
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        
        table.insert(items, {
            item = item,
            track = track,
            original_track_idx = track_idx
        })
    end
    
    return items
end

-- 移动轨道到指定位置（通过 SetOnlyTrackSelected + ReorderSelectedTracks）
local function moveTrackToPosition(track, new_idx)
    -- 先选中目标轨道
    reaper.SetOnlyTrackSelected(track)
    -- 获取当前轨道索引
    local current_idx = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1)
    
    if current_idx == new_idx then return end
    
    -- 使用 ReorderSelectedTracks
    -- 参数是一个表，表示选中轨道的新位置映射
    -- 但这个 API 比较复杂，用另一种方式：MoveMediaItemToTrack
    
    -- 更简单的方法：创建新轨道，移动 item，删除旧轨道
    -- 但这会丢失轨道设置
    
    -- 最佳方法：使用 SWS 的 BR_MoveTrack 但可能不可用
    -- 让我们用 reaper.SetMediaTrackInfo_Value 设置 I_FOLDERDEPTH 配合手动重排
end

-- 简化方案：直接在时间轴上对齐，轨道顺序通过颜色区分
-- 但用户要求纵向连续，需要真正重排轨道

local function reorderTracks(item_groups)
    -- 收集所有涉及的轨道（去重）
    local all_tracks = {}
    local track_seen = {}
    
    for _, group in ipairs(item_groups) do
        for _, entry in ipairs(group) do
            if not track_seen[entry.track] then
                track_seen[entry.track] = true
                table.insert(all_tracks, entry.track)
            end
        end
    end
    
    -- 构建新轨道顺序（按分组顺序）
    local new_track_order = {}
    for _, group in ipairs(item_groups) do
        for _, entry in ipairs(group) do
            table.insert(new_track_order, entry.track)
        end
    end
    
    -- 使用 reorderselectedtracks 需要先选中所有要重排的轨道
    reaper.SelectAllTracks(false)
    for _, track in ipairs(new_track_order) do
        reaper.SetTrackSelected(track, true)
    end
    
    -- 构建重排映射表
    local selected_count = reaper.CountSelectedTracks(0)
    local track_to_order = {}
    for i = 0, selected_count - 1 do
        local t = reaper.GetSelectedTrack(0, i)
        track_to_order[t] = i
    end
    
    -- 新顺序索引列表
    local new_order = {}
    for _, track in ipairs(new_track_order) do
        table.insert(new_order, track_to_order[track])
    end
    
    -- 执行重排
    reaper.ReorderSelectedTracks(new_order, -1)
end

local function main()
    -- 获取选中的 items
    local selected_items = getSelectedItems()
    
    if #selected_items == 0 then
        reaper.ShowMessageBox("Please select some media items first", "Error", 0)
        return
    end
    
    local layer_n, gap = getConfig(#selected_items)
    if not layer_n then return end
    
    -- 随机打乱
    shuffle(selected_items)
    
    -- 分组
    local zone_count = math.ceil(#selected_items / layer_n)
    local item_groups = {}
    
    for zone_idx = 1, zone_count do
        local start_idx = (zone_idx - 1) * layer_n + 1
        local end_idx = math.min(start_idx + layer_n - 1, #selected_items)
        
        local group = {}
        for i = start_idx, end_idx do
            table.insert(group, selected_items[i])
        end
        table.insert(item_groups, group)
    end
    
    -- 获取基准位置（第一个选中 item 的位置）
    local base_position
    do
        local pos, _ = getItemInfo(selected_items[1].item)
        base_position = pos
    end
    
    reaper.Undo_BeginBlock()
    
    local current_position = base_position
    local zone_info = {}
    
    for zone_idx, group in ipairs(item_groups) do
        -- 计算该组最长 item
        local max_len = 0
        for _, entry in ipairs(group) do
            local _, len = getItemInfo(entry.item)
            if len > max_len then max_len = len end
        end
        
        local zone_start = current_position
        local zone_end = zone_start + max_len
        
        -- 移动该组所有 items
        for _, entry in ipairs(group) do
            local old_pos, _ = getItemInfo(entry.item)
            local offset = old_pos - base_position
            moveItem(entry.item, zone_start + offset)
        end
        
        -- 设置轨道颜色
        local color = ZONE_COLORS[((zone_idx - 1) % #ZONE_COLORS) + 1]
        for _, entry in ipairs(group) do
            setTrackColor(entry.track, color[1], color[2], color[3])
        end
        
        -- 添加标记
        local marker_name = string.format("Zone %d (%d tracks)", zone_idx, #group)
        addMarker(zone_start, marker_name, color)
        
        table.insert(zone_info, {
            zone = zone_idx,
            start = zone_start,
            tracks = #group,
            max_len = max_len
        })
        
        current_position = zone_end + gap
    end
    
    -- 重排轨道顺序（同组连续）
    reorderTracks(item_groups)
    
    reaper.Undo_EndBlock("Random Layer Spreader", -1)
    reaper.UpdateArrange()
    
    -- 输出结果
    local msg = string.format(
        "Random Layer Spreader Complete\n\n" ..
        "Selected items: %d\n" ..
        "Tracks per zone: %d\n" ..
        "Zones created: %d\n" ..
        "Gap: %.1f sec\n\n",
        #selected_items, layer_n, zone_count, gap
    )
    
    for _, z in ipairs(zone_info) do
        msg = msg .. string.format(
            "Zone %d: %.2fs, %d tracks\n",
            z.zone, z.start, z.tracks
        )
    end
    
    reaper.ShowConsoleMsg(msg)
end

main()
