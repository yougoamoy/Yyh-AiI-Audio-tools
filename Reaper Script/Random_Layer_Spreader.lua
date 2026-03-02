--[[
    Random Layer Spreader
    随机 Layer 分区展开工具

    功能：
    - 将多条轨道上的样本随机分组，并在时间轴上物理分离
    - 每组包含 N 条轨道的样本（layer 数量可自定义）
    - 组与组之间自动计算间隔（该组最长 item + 余量）
    - 不同组自动涂不同颜色，方便视觉区分
    - 在每组起点添加时间标记（Marker），方便导航

    使用场景：
    音效设计时，将多个候选样本放入轨道，运行脚本后：
    - 所有样本被随机分配到不同时间分区
    - 按一次播放键即可听到所有随机组合
    - 每个分区是一个独立的 layer 组合
    - 方便后续批量处理、导出、调整

    使用方法：
    1. 每条轨道放一个样本（可以多条轨道）
    2. 确保所有样本都在时间轴起点（或其他同一位置）
    3. 运行脚本，输入每组几条轨道
    4. 脚本自动随机分组、展开到时间轴

    配合脚本：
    - Mark_Current_Zone.lua：标记喜欢的分区（可选）
--]]

-- ============================================================
-- 配置区
-- ============================================================
local CONFIG = {
    gap_seconds     = 2.0,    -- 每组之间的额外空白时间（余量）
    default_layer   = 3,      -- 默认每组轨道数
}

-- 分区颜色（循环使用）
local ZONE_COLORS = {
    {200, 100, 100},  -- 红系
    {100, 200, 100},  -- 绿系
    {100, 100, 200},  -- 蓝系
    {200, 200, 100},  -- 黄系
    {200, 100, 200},  -- 紫系
    {100, 200, 200},  -- 青系
    {220, 150, 100},  -- 橙系
    {150, 100, 220},  -- 靛蓝
}

-- ExtState 存储 key
local EXT_SECTION   = "Yyh_RandomLayerSpreader"
local KEY_LAYER_N   = "layer_count"
local KEY_GAP       = "gap_seconds"

-- ============================================================
-- 工具函数
-- ============================================================

-- Fisher-Yates 随机打乱
local function shuffle(t)
    math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000))
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- 获取轨道上第一个 media item
local function getFirstItem(track)
    return reaper.GetTrackMediaItem(track, 0)
end

-- 获取 item 的起始位置和长度
local function getItemInfo(item)
    if not item then return nil, 0 end
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    return pos, len
end

-- 移动 item 到新位置
local function moveItem(item, new_pos)
    if item then
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
    end
end

-- 设置轨道颜色
local function setTrackColor(track, r, g, b)
    local color = reaper.ColorToNative(r, g, b)
    reaper.SetTrackColor(track, color)
end

-- 添加时间标记
local function addMarker(pos, name, color_rgb)
    local color = reaper.ColorToNative(color_rgb[1], color_rgb[2], color_rgb[3])
    local idx = reaper.AddProjectMarker2(0, false, pos, 0, name, -1, color)
    return idx
end

-- ============================================================
-- 获取配置参数
-- ============================================================
local function getConfig(track_count)
    -- 读取上次保存的 layer 数量
    local saved_layer = reaper.GetExtState(EXT_SECTION, KEY_LAYER_N)
    local saved_gap = reaper.GetExtState(EXT_SECTION, KEY_GAP)

    local default_layer = tonumber(saved_layer) or CONFIG.default_layer
    local default_gap = tonumber(saved_gap) or CONFIG.gap_seconds

    -- 弹窗询问参数
    local retval, input = reaper.GetUserInputs(
        "Random Layer Spreader - 设置",
        2,
        "每组轨道数 (1-" .. track_count .. "),组间空白时间(秒)",
        string.format("%d,%.1f", default_layer, default_gap)
    )

    if not retval then return nil, nil end

    -- 解析输入
    local layer_n, gap = input:match("([^,]+),([^,]+)")
    layer_n = tonumber(layer_n)
    gap = tonumber(gap)

    if not layer_n or layer_n < 1 or layer_n > track_count then
        reaper.ShowMessageBox(
            string.format("每组轨道数必须是 1 到 %d 之间的整数", track_count),
            "输入错误", 0
        )
        return nil, nil
    end

    if not gap or gap < 0 then
        gap = CONFIG.gap_seconds
    end

    -- 保存设置
    reaper.SetExtState(EXT_SECTION, KEY_LAYER_N, tostring(layer_n), false)
    reaper.SetExtState(EXT_SECTION, KEY_GAP, tostring(gap), false)

    return layer_n, gap
end

-- ============================================================
-- 主函数
-- ============================================================
local function main()
    -- 获取所有轨道
    local track_count = reaper.CountTracks(0)
    if track_count == 0 then
        reaper.ShowMessageBox("工程中没有轨道", "错误", 0)
        return
    end

    -- 收集有 item 的轨道
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
        reaper.ShowMessageBox("没有找到任何媒体 item", "错误", 0)
        return
    end

    -- 获取配置
    local layer_n, gap = getConfig(valid_count)
    if not layer_n then return end

    -- 随机打乱轨道顺序
    shuffle(tracks_with_items)

    -- 计算分区数量
    local zone_count = math.ceil(valid_count / layer_n)

    -- 获取原始起始位置（所有 item 的最小位置，作为第一个分区的起点）
    local base_position = nil
    for _, t in ipairs(tracks_with_items) do
        local pos, _ = getItemInfo(t.item)
        if base_position == nil or pos < base_position then
            base_position = pos
        end
    end
    if not base_position then base_position = 0 end

    -- -------------------------------------------------------
    -- 开始处理
    -- -------------------------------------------------------
    reaper.Undo_BeginBlock()

    local current_position = base_position
    local zone_info = {}

    for zone_idx = 1, zone_count do
        local start_idx = (zone_idx - 1) * layer_n + 1
        local end_idx = math.min(start_idx + layer_n - 1, valid_count)

        -- 获取该分区包含的轨道
        local zone_tracks = {}
        local max_len = 0

        for i = start_idx, end_idx do
            local t = tracks_with_items[i]
            table.insert(zone_tracks, t)
            local _, len = getItemInfo(t.item)
            if len > max_len then max_len = len end
        end

        -- 计算分区起始时间
        local zone_start = current_position
        local zone_end = zone_start + max_len

        -- 移动该分区所有 item
        for _, t in ipairs(zone_tracks) do
            local old_pos, _ = getItemInfo(t.item)
            local offset = old_pos - base_position  -- 保持相对位置
            moveItem(t.item, zone_start + offset)
        end

        -- 设置轨道颜色
        local color = ZONE_COLORS[((zone_idx - 1) % #ZONE_COLORS) + 1]
        for _, t in ipairs(zone_tracks) do
            setTrackColor(t.track, color[1], color[2], color[3])
        end

        -- 添加时间标记
        local marker_name = string.format("Zone %d (%d tracks)", zone_idx, #zone_tracks)
        addMarker(zone_start, marker_name, color)

        -- 记录分区信息
        table.insert(zone_info, {
            zone = zone_idx,
            start = zone_start,
            tracks = #zone_tracks,
            max_len = max_len
        })

        -- 更新下一个分区的起始位置
        current_position = zone_end + gap
    end

    reaper.Undo_EndBlock("Random Layer Spreader: spread tracks", -1)
    reaper.UpdateArrange()

    -- -------------------------------------------------------
    -- 输出结果
    -- -------------------------------------------------------
    local msg = string.format(
        "✅ Random Layer Spreader 完成\n\n" ..
        "总轨道数: %d\n" ..
        "每组轨道数: %d\n" ..
        "分区数量: %d\n" ..
        "组间空白: %.1f 秒\n\n" ..
        "分区详情:\n",
        valid_count, layer_n, zone_count, gap
    )

    for _, z in ipairs(zone_info) do
        msg = msg .. string.format(
            "  Zone %d: %.2f\" 起, %d 轨道, 最长 %.2f\"\n",
            z.zone, z.start, z.tracks, z.max_len
        )
    end

    msg = msg .. "\n按空格键播放，可听到所有随机组合！"

    reaper.ShowConsoleMsg(msg)
end

-- 执行
main()
