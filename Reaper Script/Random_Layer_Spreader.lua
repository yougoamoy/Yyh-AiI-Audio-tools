--[[
    Random Layer Spreader
    随机 Layer 分区展开工具

    功能：
    - 只处理用户选中的 media items
    - 随机分组并在时间轴上物理分离
    - 同组轨道纵向连续排列（创建新轨道）
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

-- 获取选中的 items
local function getSelectedItems()
    local items = {}
    local count = reaper.CountSelectedMediaItems(0)
    
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        table.insert(items, item)
    end
    
    return items
end

-- 创建新轨道并返回
local function createTrackAtEnd(name)
    local track_count = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(track_count, false)
    local track = reaper.GetTrack(0, track_count)
    if name then
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end
    return track
end

-- 移动 item 到目标轨道
local function moveItemToTrack(item, target_track)
    reaper.MoveMediaItemToTrack(item, target_track)
end

-- 删除空轨道
local function removeEmptyTracks()
    local i = reaper.CountTracks(0) - 1
    while i >= 0 do
        local track = reaper.GetTrack(0, i)
        local item_count = reaper.CountTrackMediaItems(track)
        if item_count == 0 then
            reaper.DeleteTrack(track)
        end
        i = i - 1
    end
end

-- 获取 item 的源文件名（用于轨道命名）
local function getItemName(item)
    local take = reaper.GetActiveTake(item)
    if take then
        local src = reaper.GetMediaItemTake_Source(take)
        if src then
            local fn = reaper.GetMediaSourceFileName(src, "")
            -- 提取文件名（不含扩展名）
            local name = fn:match("([^/\\]+)%.[^.]*$") or fn
            return name
        end
    end
    return "Sample"
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
    
    -- 获取基准位置
    local base_position = reaper.GetMediaItemInfo_Value(selected_items[1], "D_POSITION")
    
    reaper.Undo_BeginBlock()
    
    local current_position = base_position
    local zone_info = {}
    local all_new_tracks = {}
    
    for zone_idx, group in ipairs(item_groups) do
        -- 计算该组最长 item
        local max_len = 0
        for _, item in ipairs(group) do
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if len > max_len then max_len = len end
        end
        
        local zone_start = current_position
        local zone_end = zone_start + max_len
        local color = ZONE_COLORS[((zone_idx - 1) % #ZONE_COLORS) + 1]
        
        -- 为每个 item 创建新轨道并移动
        for item_idx, item in ipairs(group) do
            -- 创建新轨道
            local item_name = getItemName(item)
            local track_name = string.format("Z%d-%d %s", zone_idx, item_idx, item_name)
            local new_track = createTrackAtEnd(track_name)
            
            -- 设置颜色
            setTrackColor(new_track, color[1], color[2], color[3])
            
            -- 移动 item 到新轨道
            moveItemToTrack(item, new_track)
            
            -- 计算新的时间位置
            local old_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local offset = old_pos - base_position
            moveItem(item, zone_start + offset)
            
            table.insert(all_new_tracks, new_track)
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
    
    -- 删除空轨道
    removeEmptyTracks()
    
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
