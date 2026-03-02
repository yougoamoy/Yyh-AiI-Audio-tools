--[[
    Random Layer Spreader
    随机 Layer 分区展开工具

    功能：
    - 将多条轨道上的样本随机分组，并在时间轴上物理分离
    - 每组包含 N 条轨道的样本（layer 数量可自定义）
    - 组与组之间自动计算间隔（该组最长 item + 余量）
    - 不同组自动涂不同颜色，方便视觉区分
    - 在每组起点添加时间标记（Marker），方便导航
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

local function getFirstItem(track)
    return reaper.GetTrackMediaItem(track, 0)
end

local function getItemInfo(item)
    if not item then return nil, 0 end
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    return pos, len
end

local function moveItem(item, new_pos)
    if item then
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
    end
end

local function setTrackColor(track, r, g, b)
    local color = reaper.ColorToNative(r, g, b)
    reaper.SetTrackColor(track, color)
end

local function addMarker(pos, name, color_rgb)
    local color = reaper.ColorToNative(color_rgb[1], color_rgb[2], color_rgb[3])
    local idx = reaper.AddProjectMarker2(0, false, pos, 0, name, -1, color)
    return idx
end

local function getConfig(track_count)
    local saved_layer = reaper.GetExtState(EXT_SECTION, KEY_LAYER_N)
    local saved_gap = reaper.GetExtState(EXT_SECTION, KEY_GAP)

    local default_layer = tonumber(saved_layer) or CONFIG.default_layer
    local default_gap = tonumber(saved_gap) or CONFIG.gap_seconds

    local retval, input = reaper.GetUserInputs(
        "Random Layer Spreader",
        2,
        "Tracks per zone (1-" .. track_count .. "),Gap seconds",
        string.format("%d,%.1f", default_layer, default_gap)
    )

    if not retval then return nil, nil end

    local layer_n, gap = input:match("([^,]+),([^,]+)")
    layer_n = tonumber(layer_n)
    gap = tonumber(gap)

    if not layer_n or layer_n < 1 or layer_n > track_count then
        reaper.ShowMessageBox(
            string.format("Tracks per zone must be 1 to %d", track_count),
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

local function main()
    local track_count = reaper.CountTracks(0)
    if track_count == 0 then
        reaper.ShowMessageBox("No tracks in project", "Error", 0)
        return
    end

    local tracks_with_items = {}
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local item = getFirstItem(track)
        if item then
            table.insert(tracks_with_items, {
                track = track,
                item = item,
                index = i + 1
            })
        end
    end

    local valid_count = #tracks_with_items
    if valid_count == 0 then
        reaper.ShowMessageBox("No media items found", "Error", 0)
        return
    end

    local layer_n, gap = getConfig(valid_count)
    if not layer_n then return end

    shuffle(tracks_with_items)

    local zone_count = math.ceil(valid_count / layer_n)

    local base_position = nil
    for _, t in ipairs(tracks_with_items) do
        local pos, _ = getItemInfo(t.item)
        if base_position == nil or pos < base_position then
            base_position = pos
        end
    end
    if not base_position then base_position = 0 end

    reaper.Undo_BeginBlock()

    local current_position = base_position
    local zone_info = {}

    for zone_idx = 1, zone_count do
        local start_idx = (zone_idx - 1) * layer_n + 1
        local end_idx = math.min(start_idx + layer_n - 1, valid_count)

        local zone_tracks = {}
        local max_len = 0

        for i = start_idx, end_idx do
            local t = tracks_with_items[i]
            table.insert(zone_tracks, t)
            local _, len = getItemInfo(t.item)
            if len > max_len then max_len = len end
        end

        local zone_start = current_position
        local zone_end = zone_start + max_len

        for _, t in ipairs(zone_tracks) do
            local old_pos, _ = getItemInfo(t.item)
            local offset = old_pos - base_position
            moveItem(t.item, zone_start + offset)
        end

        local color = ZONE_COLORS[((zone_idx - 1) % #ZONE_COLORS) + 1]
        for _, t in ipairs(zone_tracks) do
            setTrackColor(t.track, color[1], color[2], color[3])
        end

        local marker_name = string.format("Zone %d (%d tracks)", zone_idx, #zone_tracks)
        addMarker(zone_start, marker_name, color)

        table.insert(zone_info, {
            zone = zone_idx,
            start = zone_start,
            tracks = #zone_tracks,
            max_len = max_len
        })

        current_position = zone_end + gap
    end

    reaper.Undo_EndBlock("Random Layer Spreader", -1)
    reaper.UpdateArrange()

    local msg = string.format(
        "Random Layer Spreader Complete\n\n" ..
        "Total tracks: %d\n" ..
        "Tracks per zone: %d\n" ..
        "Zones created: %d\n" ..
        "Gap: %.1f sec\n\n",
        valid_count, layer_n, zone_count, gap
    )

    for _, z in ipairs(zone_info) do
        msg = msg .. string.format(
            "Zone %d: %.2fs, %d tracks, max %.2fs\n",
            z.zone, z.start, z.tracks, z.max_len
        )
    end

    reaper.ShowConsoleMsg(msg)
end

main()
