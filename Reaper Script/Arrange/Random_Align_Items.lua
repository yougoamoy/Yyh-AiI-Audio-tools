-- 随机组合对齐选中的 Item
-- 支持两种排列方式：齐头排列 & 随机排列，可生成多种组合

local ext_name = "RandomAlign"

-- 获取选中的 item
local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then
  reaper.ShowMessageBox("请先框选 Item！", "提示", 0)
  return
end

-- 收集所有选中的 item
local selected_items = {}
for i = 0, item_count - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  if item then
    table.insert(selected_items, item)
  end
end

-- 界面状态变量
local selected_mode = 0  -- 0 = 未选择, 1 = 齐头排列, 2 = 随机排列, 3 = Marker排列
local combo_count = 1    -- 当前选中的组合数量
local concentration = 0.5 -- 集中度控制参数 (0.0 = 完全分散, 1.0 = 高度集中)
local show_rank_adjust = false  -- 是否显示权重调整界面
local rank_adjust_values = {}     -- marker权重值，动态键 "m1", "m2", ...
local rank_max_items_values = {}  -- marker最大item数量，动态键 "m1", "m2", ... (0表示不限制)
local rank_adjust_mode = 1        -- 调整模式: 1=出现频率, 2=数量限制
local rank_concentration_values = {} -- 单个marker的集中度，动态键 "m1", "m2", ... (0.0-1.0)

-- 查找Construction Kit文件夹
local function find_construction_kit_folder()
    local track_count = reaper.CountTracks(0)
    for j = 0, track_count - 1 do
        local track = reaper.GetTrack(0, j)
        local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if name == "Construction Kit" then
            local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if folder_depth == 1 then
                return track, j
            end
        end
    end
    return nil, -1
end

-- 获取Construction Kit文件夹的最后一个子轨道索引
local function get_ck_folder_end_index(ck_track, ck_idx)
    if not ck_track then return -1 end
    local track_count = reaper.CountTracks(0)
    local last_idx = ck_idx
    for j = ck_idx + 1, track_count - 1 do
        local track = reaper.GetTrack(0, j)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        last_idx = j
        if depth == -1 then
            break
        end
    end
    return last_idx
end

-- 在Construction Kit文件夹内创建新轨道
local function create_track_in_ck_folder(ck_track, ck_idx)
    if not ck_track then
        -- 如果没有Construction Kit文件夹，在末尾创建
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), false)
        return reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    end
    local last_idx = get_ck_folder_end_index(ck_track, ck_idx)
    reaper.InsertTrackAtIndex(last_idx, false)
    local new_track = reaper.GetTrack(0, last_idx)
    -- 更新folder结束标记
    local new_last_idx = get_ck_folder_end_index(ck_track, ck_idx)
    if new_last_idx > last_idx then
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
        local final_track = reaper.GetTrack(0, new_last_idx)
        if final_track then
            reaper.SetMediaTrackInfo_Value(final_track, "I_FOLDERDEPTH", -1)
        end
    end
    return new_track
end

if #selected_items == 0 then
  reaper.ShowMessageBox("未找到有效的 Item！", "错误", 0)
  return
end

-- ===== Rank标记复制函数 =====
-- 复制item的rank标记（notes、userdata、take名称）
local function copy_item_rank_markers(orig_item, new_item)
    -- 复制notes - 使用标准REAPER API
    local notes_ret = reaper.GetSetMediaItemInfo_String(orig_item, "P_NOTES", "", false)
    local orig_notes = (type(notes_ret) == "string") and notes_ret or ""
    if orig_notes ~= "" then
        reaper.GetSetMediaItemInfo_String(new_item, "P_NOTES", orig_notes, true)
    end
    
    -- 复制userdata
    local orig_userdata = reaper.GetMediaItemInfo_Value(orig_item, "I_USERDATA")
    reaper.SetMediaItemInfo_Value(new_item, "I_USERDATA", orig_userdata)
    
    -- 复制take名称和所有扩展状态（如果有take）
    local orig_take = reaper.GetActiveTake(orig_item)
    local new_take = reaper.GetActiveTake(new_item)
    if orig_take and new_take then
        -- 复制take名称
        local orig_take_name = reaper.GetTakeName(orig_take)
        if orig_take_name and orig_take_name ~= "" then
            reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", orig_take_name, true)
        end
        
        -- 复制take markers（包括marker标记）
        local num_markers = reaper.GetNumTakeMarkers(orig_take)
        for i = 0, num_markers - 1 do
            local retval, name, pos, color = reaper.GetTakeMarker(orig_take, i)
            if name then
                reaper.SetTakeMarker(new_take, -1, name, pos, color)
            end
        end

        -- 尝试复制take的所有扩展属性（如颜色等）
        if reaper.GetMediaItemTakeExtKey then
            for i = 0, reaper.GetMediaItemTakeInfo_Value(orig_take, "IP_EXT_N") do
                local key = reaper.GetMediaItemTakeExtKey(orig_take, i)
                local val = reaper.GetMediaItemTakeExtValue(orig_take, key)
                if key ~= "" then
                    reaper.SetMediaItemTakeExtValue(new_take, key, val)
                end
            end
        end
    end
    
    -- 复制item的扩展状态（SWS函数）
    if reaper.GetItemExtState_Key then
        for i = 0, reaper.GetMediaItemInfo_Value(orig_item, "IP_EXT_N") do
            local key = reaper.GetItemExtState_Key(orig_item, i)
            local val = reaper.GetItemExtState(orig_item, key, "")
            if key ~= "" then
                reaper.SetItemExtState(new_item, key, val, true)
            end
        end
    end
    
    -- 复制item颜色
    local color = reaper.GetMediaItemInfo_Value(orig_item, "I_CUSTOMCOLOR")
    if color > 0 then
        reaper.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", color)
    end
end

-- 完整复制item，包括rank标记
local function copy_item_with_rank(orig_item, target_track)
    local new_item = reaper.AddMediaItemToTrack(target_track)
    if not new_item then return nil end
    
    -- 复制source（如果有take）
    local orig_take = reaper.GetActiveTake(orig_item)
    if orig_take then
        local source = reaper.GetMediaItemTake_Source(orig_take)
        if source then
            local new_take = reaper.AddTakeToMediaItem(new_item)
            if new_take then
                reaper.SetMediaItemTake_Source(new_take, source)
            end
        end
    end
    
    -- 复制基本属性
    local len = reaper.GetMediaItemInfo_Value(orig_item, "D_LENGTH")
    reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", len)
    
    local mute = reaper.GetMediaItemInfo_Value(orig_item, "B_MUTE")
    reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", mute)
    
    local vol = reaper.GetMediaItemInfo_Value(orig_item, "D_VOL")
    reaper.SetMediaItemInfo_Value(new_item, "D_VOL", vol)
    
    -- 复制rank标记
    copy_item_rank_markers(orig_item, new_item)
    
    return new_item
end

-- 查找Construction Kit文件夹并获取其子轨道
local ck_folder_track, ck_folder_idx = find_construction_kit_folder()
local all_tracks = {}
local start_index = 0

if ck_folder_track then
    -- Construction Kit文件夹存在，获取其子轨道
    start_index = ck_folder_idx + 1
    local track_count = reaper.CountTracks(0)
    for i = start_index, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            table.insert(all_tracks, track)
            if depth == -1 then
                break  -- 到达文件夹末尾
            end
        end
    end
else
    -- Construction Kit文件夹不存在，使用原有逻辑
    local top_track_num = math.huge
    for _, item in ipairs(selected_items) do
        local track = reaper.GetMediaItem_Track(item)
        local track_num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        if track_num < top_track_num then
            top_track_num = track_num
        end
    end
    start_index = top_track_num - 1
    local track_count = reaper.CountTracks(0)
    for i = start_index, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            table.insert(all_tracks, track)
        end
    end
end

if #all_tracks == 0 then
    reaper.ShowMessageBox("没有可用的轨道！", "错误", 0)
    return
end

-- ===== Rank分布算法 =====
-- 计算单个marker的有效集中度（全局集中度与单个marker集中度的加权组合）
local function get_effective_concentration(rank, global_conc)
    local marker_conc = rank_concentration_values[rank] or 0.5
    -- 权重系数: 全局集中度占60%，单个marker集中度占40%
    return global_conc * 0.6 + marker_conc * 0.4
end

-- 随机分布：同rank的item可以随机混合，但尽可能均匀分布
local function distribute_random_by_rank(groups, group_start_pos, range_half, concentration, tracks)
    local all_items = {}
    local all_ranks = {}
    
    -- 收集所有item和它们的rank
    for rank, items in pairs(groups) do
        for _, item in ipairs(items) do
            table.insert(all_items, {item = item, rank = rank})
        end
        table.insert(all_ranks, rank)
    end
    
    -- 根据rank调整值应用权重
    local weighted_items = {}
    for _, data in ipairs(all_items) do
        local weight = rank_adjust_values[data.rank] or 1.0
        
        -- 根据权重添加多次（高权重的marker有更多副本）
        local copies = math.max(1, math.floor(weight))
        for i = 1, copies do
            table.insert(weighted_items, data)
        end
        
        -- 添加小数部分的机会
        local fractional_chance = weight - math.floor(weight)
        if fractional_chance > 0 and math.random() < fractional_chance then
            table.insert(weighted_items, data)
        end
    end
    
    -- 使用加权后的items
    all_items = weighted_items
    
    -- 随机打乱所有item
    math.randomseed(os.time() + os.clock() * 1000000)
    for i = #all_items, 2, -1 do
        local j = math.random(i)
        all_items[i], all_items[j] = all_items[j], all_items[i]
    end
    
    -- 分配位置
    local assigned_positions = {}
    local track_index = 1
    local used_tracks = {}  -- 跟踪已使用的轨道
    
    for idx, data in ipairs(all_items) do
        local target_track = nil
        
        -- 查找可用的轨道
        while not target_track do
            if track_index <= #tracks then
                local candidate_track = tracks[track_index]
                if not used_tracks[candidate_track] then
                    target_track = candidate_track
                    used_tracks[target_track] = true
                    track_index = track_index + 1  -- 找到轨道后增加索引
                else
                    track_index = track_index + 1
                end
            else
                -- 如果轨道不够用，在Construction Kit文件夹内创建新轨道
                local ck_track, ck_idx = find_construction_kit_folder()
                target_track = create_track_in_ck_folder(ck_track, ck_idx)
                table.insert(tracks, target_track)
                used_tracks[target_track] = true
            end
        end
        
        -- 只有在当前轨道和目标轨道不同时才移动
        local current_track = reaper.GetMediaItem_Track(data.item)
        if current_track ~= target_track then
            reaper.MoveMediaItemToTrack(data.item, target_track)
        end
        
        -- 计算该marker的有效集中度
        local effective_conc = get_effective_concentration(data.rank, concentration)
        
        -- 计算随机偏移
        local random_offset
        if effective_conc > 0.7 then
            local std_dev = range_half * (1.0 - effective_conc * 0.8)
            random_offset = (math.random() - 0.5) * 2 * std_dev
        else
            random_offset = (math.random() - 0.5) * 2 * range_half
        end
        
        local new_pos = group_start_pos + random_offset
        
        -- 避免重叠
        local min_overlap_distance = 0.05
        if effective_conc > 0.3 then
            local max_attempts = 10
            local attempts = 0
            
            while attempts < max_attempts do
                local too_close = false
                
                for _, pos in ipairs(assigned_positions) do
                    if math.abs(new_pos - pos) < min_overlap_distance then
                        too_close = true
                        break
                    end
                end
                
                if not too_close then break end
                
                local adjustment = (math.random() - 0.5) * min_overlap_distance * 2
                new_pos = new_pos + adjustment
                attempts = attempts + 1
            end
        end
        
        table.insert(assigned_positions, new_pos)
        if new_pos < 0 then new_pos = 0 end
        
        reaper.SetMediaItemInfo_Value(data.item, "D_POSITION", new_pos)
    end
end

-- 离散分布：同rank的item尽量分散，避免同一时间轴上有两个相同rank
local function distribute_discrete_by_rank(groups, group_start_pos, range_half, concentration, tracks)
    local all_ranks = {}
    local rank_weights = {}
    for rank, _ in pairs(groups) do
        table.insert(all_ranks, rank)
        rank_weights[rank] = rank_adjust_values[rank] or 1.0
    end
    
    -- 为每个rank创建时间槽
    local time_slots = {}
    local slot_count = math.max(#all_ranks, 3)  -- 至少3个时间槽
    local slot_width = range_half * 2 / slot_count
    
    for i = 1, slot_count do
        local slot_center = group_start_pos - range_half + (i - 0.5) * slot_width
        table.insert(time_slots, {
            center = slot_center,
            available = true,
            assigned_rank = nil
        })
    end
    
    -- 分配时间槽给不同的rank，根据权重分配不同数量的时间槽
    local rank_slots = {}
    local slot_index = 1
    
    -- 首先按权重排序rank，权重高的先分配
    table.sort(all_ranks, function(a, b)
        return rank_weights[a] > rank_weights[b]
    end)
    
    for _, rank in ipairs(all_ranks) do
        rank_slots[rank] = {}
        
        -- 根据权重计算应该分配的时间槽数量
        local weight = rank_weights[rank]
        local max_slots_per_rank = math.min(4, slot_count)  -- 每个rank最多4个时间槽
        local slot_count_for_rank = math.max(1, math.floor(weight))
        
        -- 如果权重有小数部分，增加一个槽的机会
        if weight - math.floor(weight) > 0 and math.random() < (weight - math.floor(weight)) then
            slot_count_for_rank = slot_count_for_rank + 1
        end
        
        slot_count_for_rank = math.min(slot_count_for_rank, max_slots_per_rank)
        
        -- 为每个rank分配时间槽，尽量分散
        for i = 1, slot_count_for_rank do
            while slot_index <= #time_slots and time_slots[slot_index].assigned_rank ~= nil do
                slot_index = slot_index + 1
            end
            
            if slot_index <= #time_slots then
                time_slots[slot_index].assigned_rank = rank
                table.insert(rank_slots[rank], time_slots[slot_index])
                slot_index = slot_index + math.ceil(slot_count / slot_count_for_rank)  -- 根据分配的槽数调整跳转
            end
        end
    end
    
    -- 分配item到时间槽
    local track_index = 1
    local assigned_positions = {}
    local used_tracks = {}  -- 跟踪已使用的轨道
    
    for rank, slots in pairs(rank_slots) do
        local items = groups[rank]
        if not items or #items == 0 then goto continue end
        
        -- 计算该marker的有效集中度
        local effective_conc = get_effective_concentration(rank, concentration)
        
        -- 打乱items
        for i = #items, 2, -1 do
            local j = math.random(i)
            items[i], items[j] = items[j], items[i]
        end
        
        -- 将items平均分配到该rank的时间槽
        for i, item in ipairs(items) do
            local target_track = nil
            
            -- 查找可用的轨道
            while not target_track do
                if track_index <= #tracks then
                    local candidate_track = tracks[track_index]
                    if not used_tracks[candidate_track] then
                        target_track = candidate_track
                        used_tracks[target_track] = true
                    end
                    track_index = track_index + 1  -- 无论是否找到，都检查下一个轨道
                else
                    -- 如果轨道不够用，在Construction Kit文件夹内创建新轨道
                    local ck_track, ck_idx = find_construction_kit_folder()
                    target_track = create_track_in_ck_folder(ck_track, ck_idx)
                    table.insert(tracks, target_track)
                    used_tracks[target_track] = true
                    track_index = track_index + 1
                end
            end
            
            -- 只有在当前轨道和目标轨道不同时才移动
            local current_track = reaper.GetMediaItem_Track(item)
            if current_track ~= target_track then
                reaper.MoveMediaItemToTrack(item, target_track)
            end
            
            -- 选择时间槽
            local slot_index = ((i - 1) % #slots) + 1
            local slot = slots[slot_index]
            
            -- 在时间槽内随机偏移（根据有效集中度调整变化范围）
            local variation_factor = 0.5 - effective_conc * 0.4  -- 集中度越高，变化越小
            local slot_variation = slot_width * math.max(0.1, variation_factor)
            local random_offset = (math.random() - 0.5) * slot_variation
            local new_pos = slot.center + random_offset
            
            -- 避免重叠
            local min_overlap_distance = 0.1  -- 离散分布需要更大的最小距离
            local max_attempts = 5
            local attempts = 0
            
            while attempts < max_attempts do
                local too_close = false
                
                for _, pos in ipairs(assigned_positions) do
                    if math.abs(new_pos - pos) < min_overlap_distance then
                        too_close = true
                        break
                    end
                end
                
                if not too_close then break end
                
                random_offset = (math.random() - 0.5) * slot_variation
                new_pos = slot.center + random_offset
                attempts = attempts + 1
            end
            
            table.insert(assigned_positions, new_pos)
            if new_pos < 0 then new_pos = 0 end
            
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
        end
        
        ::continue::
    end
end

-- 获取最左边的位置
local leftmost_pos = math.huge
-- 获取最长 item 的长度
local max_item_length = 0
-- 计算原样本最右侧item的尾部位置
local sample_rightmost_end = -math.huge
for _, item in ipairs(selected_items) do
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_len
  if item_pos < leftmost_pos then
    leftmost_pos = item_pos
  end
  if item_len > max_item_length then
    max_item_length = item_len
  end
  if item_end > sample_rightmost_end then
    sample_rightmost_end = item_end
  end
end

-- 收集所有 item 的长度
local item_lengths = {}
for _, item in ipairs(selected_items) do
  table.insert(item_lengths, reaper.GetMediaItemInfo_Value(item, "D_LENGTH"))
end

-- ===== 读取Marker配置 =====
local function load_rank_config()
    local config = {}
    local ext_name = "MarkerTool"
    local rv, cnt_s = reaper.GetProjExtState(0, ext_name, "count")
    local cnt = (rv == 1 and cnt_s ~= "") and tonumber(cnt_s) or 0
    for i = 1, cnt do
        local r, v = reaper.GetProjExtState(0, ext_name, "m"..i)
        config["m"..i] = (r == 1) and v or ""
    end
    config._count = cnt
    return config
end

-- 获取item的rank标记
-- 通过 Take Marker 读取 item 的 marker 标记
-- Mark_Item_Rank.lua 使用 SetTakeMarker(take, -1, "mN", 0) 写入
local function get_item_rank(item, config)
    local take = reaper.GetActiveTake(item)
    if not take then return "unranked" end

    for i = 0, reaper.GetNumTakeMarkers(take) - 1 do
        local _, name = reaper.GetTakeMarker(take, i)
        if name then
            local idx = name:match("^m(%d+)$")
            if idx then return "m" .. idx end
        end
    end

    return "unranked"
end

-- 按rank分组item
local function group_items_by_rank(selected_items, config)
    local groups = {}
    local unranked_items = {}
    
    for _, item in ipairs(selected_items) do
        local rank = get_item_rank(item, config)
        
        if rank == "unranked" then
            table.insert(unranked_items, item)
        else
            if not groups[rank] then
                groups[rank] = {}
            end
            table.insert(groups[rank], item)
        end
    end
    
    return groups, unranked_items
end

-- ===== ImGui GUI =====
local ctx = reaper.ImGui_CreateContext("随机组合排列")
local WINDOW_W = 520
local WINDOW_H = 450

-- 下拉选项
local combo_options = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "12", "15", "20"}
local combo_preview = 1

-- 齐头排列子选项
local align_options = {"左对齐", "居中对齐", "右对齐"}
local align_preview = 1  -- 默认左对齐

local function draw_button_with_style(ctx, label, pressed)
  if pressed then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x4080C0FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x5090D0FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x3060A0FF)
  end
  
  reaper.ImGui_Button(ctx, label, 120, 35)
  local clicked = reaper.ImGui_IsItemClicked(ctx, 0)
  
  if pressed then
    reaper.ImGui_PopStyleColor(ctx, 3)
  end
  
  return clicked
end

-- 绘制rank调整窗口
local function draw_rank_adjust_window(ctx, config)
    reaper.ImGui_SetNextWindowSize(ctx, 400, 350, reaper.ImGui_Cond_Once())
    reaper.ImGui_SetNextWindowPos(ctx, 100, 100, reaper.ImGui_Cond_Once())
    
    local visible, open = reaper.ImGui_Begin(ctx, "Rank种类调整", true, 
        reaper.ImGui_WindowFlags_NoResize() + reaper.ImGui_WindowFlags_NoCollapse())
    
    if visible then
        reaper.ImGui_Text(ctx, "调整各个marker的分布权重（1.0为默认值）")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- 动态显示marker权重滑块
        local cfg = load_rank_config()
        for i = 1, cfg._count do
            local key = "m"..i
            local name = cfg[key]
            if name == "" then name = "#"..i end
            if rank_adjust_values[key] == nil then rank_adjust_values[key] = 1.0 end
            reaper.ImGui_Text(ctx, "#"..i.." "..name..":")
            reaper.ImGui_SameLine(ctx, 180)
            reaper.ImGui_SetNextItemWidth(ctx, 100)
            local changed, new_value = reaper.ImGui_SliderDouble(ctx, "##adj"..i, rank_adjust_values[key], 0.1, 3.0, "%.1f")
            if changed then rank_adjust_values[key] = new_value end
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_TextDisabled(ctx, "权重说明:")
        reaper.ImGui_Indent(ctx)
        reaper.ImGui_TextDisabled(ctx, "• 0.1-0.5: 减少出现频率")
        reaper.ImGui_TextDisabled(ctx, "• 0.5-1.0: 正常频率")
        reaper.ImGui_TextDisabled(ctx, "• 1.0-2.0: 增加出现频率")
        reaper.ImGui_TextDisabled(ctx, "• 2.0-3.0: 显著增加频率")
        reaper.ImGui_Unindent(ctx)
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)
        
        if reaper.ImGui_Button(ctx, "确定", 100, 30) then
            show_rank_adjust = false
        end
        
        reaper.ImGui_SameLine(ctx, 120)
        
        if reaper.ImGui_Button(ctx, "重置为默认值", 150, 30) then
            for i = 1, cfg._count do rank_adjust_values["m"..i] = 1.0 end
        end
        
        reaper.ImGui_End(ctx)
    end
    
    return open
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, WINDOW_W, WINDOW_H, reaper.ImGui_Cond_Once())
  
  local visible, open = reaper.ImGui_Begin(ctx, "随机组合排列", true)
  
  if visible then
    reaper.ImGui_Text(ctx, "已选中 " .. #selected_items .. " 个 Item")
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_Text(ctx, "请选择排列方式：")
    reaper.ImGui_Spacing(ctx)
    
    -- 齐头排列行
    if draw_button_with_style(ctx, "齐头排列", selected_mode == 1) then
      selected_mode = 1
      show_rank_adjust = not show_rank_adjust
    end
    
    reaper.ImGui_SameLine(ctx, 130)
    
    -- 对齐方式下拉框
    if reaper.ImGui_BeginCombo(ctx, "##align", align_options[align_preview], 0) then
      for i, opt in ipairs(align_options) do
        local is_selected = (align_preview == i)
        if reaper.ImGui_Selectable(ctx, opt, is_selected, 0, 0) then
          align_preview = i
        end
      end
      reaper.ImGui_SetItemDefaultFocus(ctx)
      reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_TextDisabled(ctx, "随机打乱后，按选定方式对齐排列")
    reaper.ImGui_Unindent(ctx)
    
    reaper.ImGui_Spacing(ctx)
    
    -- 随机排列行
    if draw_button_with_style(ctx, "随机排列", selected_mode == 2) then
      selected_mode = 2
      show_rank_adjust = not show_rank_adjust
    end
    
    reaper.ImGui_SameLine(ctx, 130)
    reaper.ImGui_TextDisabled(ctx, "生成组合数：")
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_BeginCombo(ctx, "##combo2", combo_options[combo_preview], 0) then
      for i, opt in ipairs(combo_options) do
        local is_selected = (combo_preview == i)
        if reaper.ImGui_Selectable(ctx, opt, is_selected, 0, 0) then
          combo_preview = i
          combo_count = i
        end
      end
      reaper.ImGui_SetItemDefaultFocus(ctx)
      reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_TextDisabled(ctx, "位置随机，纵向可重叠")
    reaper.ImGui_Unindent(ctx)
    
    reaper.ImGui_Spacing(ctx)
    
    -- Marker排列行
    if draw_button_with_style(ctx, "Marker排列", selected_mode == 3) then
      selected_mode = 3
      -- 切换rank调整界面的显示状态
      show_rank_adjust = not show_rank_adjust
    end
    
    reaper.ImGui_SameLine(ctx, 130)
    reaper.ImGui_TextDisabled(ctx, "生成组合数：")
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_BeginCombo(ctx, "##combo3", combo_options[combo_preview], 0) then
      for i, opt in ipairs(combo_options) do
        local is_selected = (combo_preview == i)
        if reaper.ImGui_Selectable(ctx, opt, is_selected, 0, 0) then
          combo_preview = i
          combo_count = i
        end
      end
      reaper.ImGui_SetItemDefaultFocus(ctx)
      reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_TextDisabled(ctx, "按rank标记分层排列，支持生成多组组合")
    reaper.ImGui_Unindent(ctx)
    
    -- 集中度控制
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_Text(ctx, "集中度控制:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, " (0.0 = 完全分散, 1.0 = 高度集中)")
    reaper.ImGui_Unindent(ctx)
    
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    -- 获取所有返回值
    local ret1, ret2 = reaper.ImGui_SliderDouble(ctx, "##concentration", concentration, 0.0, 1.0, "%.2f")
    
    -- 判断返回值类型
    if type(ret1) == "boolean" then
        -- ret1是changed，ret2是value
        if ret1 then
            concentration = ret2
        end
    else
        -- ret1是value
        concentration = ret1
    end
    
    -- 集中度百分比显示
    reaper.ImGui_SameLine(ctx, 220)
    local concentration_percent = math.floor(concentration * 100 + 0.5)
    reaper.ImGui_Text(ctx, concentration_percent .. "%")
    
    -- 集中度效果描述
    reaper.ImGui_Indent(ctx)
    if concentration <= 0.25 then
        reaper.ImGui_TextDisabled(ctx, "效果: 松散分布")
    elseif concentration <= 0.5 then
        reaper.ImGui_TextDisabled(ctx, "效果: 中等集中")
    elseif concentration <= 0.75 then
        reaper.ImGui_TextDisabled(ctx, "效果: 紧密聚集")
    else
        reaper.ImGui_TextDisabled(ctx, "效果: 高度密集")
    end
    reaper.ImGui_Unindent(ctx)
    reaper.ImGui_Unindent(ctx)
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- 确认按钮
    if selected_mode == 0 then
      reaper.ImGui_BeginDisabled(ctx)
    end
    
    if reaper.ImGui_Button(ctx, "执行排列", -1, 40) then
      open = false  -- 关闭窗口
      
      local count = combo_count
      
      if selected_mode == 1 then
        -- ===== 齐头排列 =====
        -- 计算最大长度
        local group_max_length = 0
        for _, len in ipairs(item_lengths) do
          if len > group_max_length then
            group_max_length = len
          end
        end
        
        -- 生成排列的起始位置 = 原样本最右侧尾部 + 3秒间隔
        local group_start_pos = sample_rightmost_end + 3
        
        -- 复制原始 items（使用新的rank复制函数）
        local copied_items = {}
        for _, orig_item in ipairs(selected_items) do
          local new_item = copy_item_with_rank(orig_item, all_tracks[1])
          if new_item then
            local len = reaper.GetMediaItemInfo_Value(orig_item, "D_LENGTH")
            table.insert(copied_items, {item = new_item, length = len, orig = orig_item})
          end
        end
        
        -- 随机打乱顺序
        math.randomseed(os.time())
        for i = #copied_items, 2, -1 do
          local j = math.random(i)
          copied_items[i], copied_items[j] = copied_items[j], copied_items[i]
        end
        
        -- 根据对齐方式分配位置（统一最左边缘为 group_start_pos）
        -- 确保有足够的轨道，每个item分配到独立轨道
        local needed_tracks = #copied_items
        local current_track_count = reaper.CountTracks(0)
        local ck_track, ck_idx = find_construction_kit_folder()
        if needed_tracks > #all_tracks then
            for i = #all_tracks + 1, needed_tracks do
                create_track_in_ck_folder(ck_track, ck_idx)
            end
            
            -- 重新获取所有轨道
            all_tracks = {}
            for i = start_index, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                if track then
                    table.insert(all_tracks, track)
                end
            end
        end
        
        for idx, data in ipairs(copied_items) do
          local target_track = all_tracks[idx]  -- 每个item分配到不同的轨道（索引从1开始）
          if target_track then
            -- 只有当目标轨道不是原始创建轨道时才移动
            local current_track = reaper.GetMediaItem_Track(data.item)
            if current_track ~= target_track then
              reaper.MoveMediaItemToTrack(data.item, target_track)
            end
          else
            -- 如果没有足够的轨道，在Construction Kit文件夹内创建新轨道
            target_track = create_track_in_ck_folder(ck_track, ck_idx)
            table.insert(all_tracks, target_track)
            reaper.MoveMediaItemToTrack(data.item, target_track)
          end
          
          -- 统一最左边缘位置（与原样本最右侧间隔3秒）
          local pos = group_start_pos
          
          reaper.SetMediaItemInfo_Value(data.item, "D_POSITION", pos)
        end
        
        reaper.UpdateArrange()
        
        local align_name = align_options[align_preview]
        reaper.ShowMessageBox(
          "齐头排列完成！\n对齐方式：" .. align_name, 
          "完成", 0)
          
      elseif selected_mode == 2 then
        -- ===== 随机排列（可重叠版）=====
        -- 计算每组的最大长度
        local group_max_length = 0
        for _, len in ipairs(item_lengths) do
          if len > group_max_length then
            group_max_length = len
          end
        end
        
        -- 生成排列的起始位置 = 原样本最右侧尾部 + 3秒间隔
        local group_start_pos = sample_rightmost_end + 3
        
        for combo = 1, count do
          -- 复制原始 items（使用新的rank复制函数）
          local copied_items = {}
          for _, orig_item in ipairs(selected_items) do
            local new_item = copy_item_with_rank(orig_item, all_tracks[1])
            if new_item then
              table.insert(copied_items, new_item)
            end
          end
          
          -- 生成新的随机种子
          local seed = os.time() + os.clock() * 1000000 + combo * 1000
          math.randomseed(seed)
          
          -- 计算平均长度
          local total_len = 0
          for _, len in ipairs(item_lengths) do
            total_len = total_len + len
          end
          local avg_len = total_len / #selected_items
          -- 基于集中度计算随机范围
          -- concentration = 0.0: 完全分散 (范围 = max_item_length * 0.5)
          -- concentration = 0.5: 中等集中 (范围 = max_item_length * 0.3)
          -- concentration = 1.0: 高度集中 (范围 = max_item_length * 0.1)
          local base_range = 0.5
          local min_range = 0.1
          local range_factor = base_range - concentration * (base_range - min_range)
          local range_half = math.max(max_item_length * range_factor, 0.1)
          
          -- 确保有足够的轨道（如果item数量超过现有轨道，在Construction Kit文件夹内创建新轨道）
          local needed_tracks = #copied_items
          local current_track_count = reaper.CountTracks(0)
          local ck_track, ck_idx = find_construction_kit_folder()
          for i = current_track_count + 1, needed_tracks do
            create_track_in_ck_folder(ck_track, ck_idx)
          end
          
          -- 重新获取从起点轨道开始的所有轨道（包括新增的）
          local tracks_for_this_group = {}
          local new_track_count = reaper.CountTracks(0)
          for i = start_index, new_track_count - 1 do
            local track = reaper.GetTrack(0, i)
            if track then
              table.insert(tracks_for_this_group, track)
            end
          end
          
          -- 分配到轨道（每轨一个，轨道不够时自动新增）
          local assigned_positions = {}  -- 用于防止重叠
          local used_tracks = {}  -- 跟踪已使用的轨道
          for idx, item in ipairs(copied_items) do
            local target_track
            local track_found = false
            local attempt_count = 0
            
            -- 寻找一个未使用的轨道
            while not track_found and attempt_count < #tracks_for_this_group do
              local track_idx
              if idx <= #tracks_for_this_group then
                track_idx = idx
              else
                -- 如果item数量超过轨道数量，使用取模但确保不重复
                track_idx = ((idx - 1) % #tracks_for_this_group) + 1
              end
              
              target_track = tracks_for_this_group[track_idx]
              if not used_tracks[target_track] then
                used_tracks[target_track] = true
                track_found = true
              else
                attempt_count = attempt_count + 1
                track_idx = ((track_idx) % #tracks_for_this_group) + 1
              end
            end
            
            -- 如果没有找到未使用的轨道，在Construction Kit文件夹内创建新轨道
            if not target_track or not track_found then
              local ck_track, ck_idx = find_construction_kit_folder()
              target_track = create_track_in_ck_folder(ck_track, ck_idx)
              table.insert(tracks_for_this_group, target_track)
              used_tracks[target_track] = true
            end
            
            reaper.MoveMediaItemToTrack(item, target_track)
            
            -- 获取当前item长度
            local item_len = item_lengths[idx]
            
            -- 随机位置（在组起始位置附近）
            -- 使用改进的随机分布：随着集中度增加，item更倾向于聚集在中心
            local random_offset
            if concentration > 0.7 then
                -- 高集中度：使用正态分布，更集中在中心
                local std_dev = range_half * (1.0 - concentration * 0.8)
                random_offset = (math.random() - 0.5) * 2 * std_dev
            else
                -- 中低集中度：使用均匀分布
                random_offset = (math.random() - 0.5) * 2 * range_half
            end
            
            -- 确保位置不会太分散（可选约束）
            if concentration > 0.5 then
                -- 对于高集中度，限制最大偏移
                local max_offset = range_half * (1.0 - concentration * 0.5)
                if math.abs(random_offset) > max_offset then
                    random_offset = max_offset * (random_offset > 0 and 1 or -1)
                end
            end
            
            local new_pos = group_start_pos + random_offset
            
            -- 防止完全重叠：检查是否与其他已分配的item位置太接近
            local min_overlap_distance = 0.05  -- 最小重叠距离（0.05秒）
            if concentration > 0.3 then  -- 只有在较高集中度时才检查
                local max_attempts = 10
                local attempts = 0
                
                while attempts < max_attempts do
                    local too_close = false
                    
                    for _, pos in ipairs(assigned_positions) do
                        if math.abs(new_pos - pos) < min_overlap_distance then
                            too_close = true
                            break
                        end
                    end
                    
                    if not too_close then
                        break
                    end
                    
                    -- 如果太接近，微调位置
                    local adjustment = (math.random() - 0.5) * min_overlap_distance * 2
                    new_pos = new_pos + adjustment
                    attempts = attempts + 1
                end
            end
            
            table.insert(assigned_positions, new_pos)
            
            if new_pos < 0 then new_pos = 0 end
            
            reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
          end
          
          -- 下一组起始位置 = 当前组起始位置 + 当前组最大长度 + 3秒间隔
          group_start_pos = group_start_pos + group_max_length + 3
        end
        
        reaper.UpdateArrange()
        
        reaper.ShowMessageBox(
          "随机排列完成！\n已生成 " .. count .. " 种组合，每种间隔3秒。", 
          "完成", 0)
          
      elseif selected_mode == 3 then
        -- ===== Rank排列 =====
        -- 加载rank配置
        local config = load_rank_config()
        
        -- 调试：显示当前加载的rank配置
        local debug_info = "当前工程Rank配置：\n"
        for i = 1, config._count do
            local key = "m"..i
            local name = config[key]
            if name == "" then name = "#"..i end
            debug_info = debug_info .. "#"..i.." "..name..": " .. (config[key] ~= "" and config[key] or "(未定义)") .. "\n"
        end
        
        -- 按rank分组item
        local groups, unranked_items = group_items_by_rank(selected_items, config)
        
        -- 调试：显示检测到的rank标记
        debug_info = debug_info .. "\n检测到的Rank标记：\n"
        local total_ranked_items = 0
        for rank, items in pairs(groups) do
            if #items > 0 then
                debug_info = debug_info .. rank .. ": " .. #items .. " 个item\n"
                total_ranked_items = total_ranked_items + #items
            end
        end
        debug_info = debug_info .. "未标记的item: " .. #unranked_items .. " 个\n"
        debug_info = debug_info .. "总计rank标记的item: " .. total_ranked_items .. " 个"
        
        -- 调试：显示第一个未标记item的信息，帮助诊断问题
        if #unranked_items > 0 then
            local sample_item = unranked_items[1]
            debug_info = debug_info .. "\n\n第一个未标记item的详细信息：\n"
            
            -- notes信息 - 使用标准API
            local notes_val = reaper.GetSetMediaItemInfo_String(sample_item, "P_NOTES", "", false)
            local notes = (type(notes_val) == "string") and notes_val or ""
            debug_info = debug_info .. "Notes: \"" .. notes .. "\"\n"
            
            -- userdata信息
            local userdata = reaper.GetMediaItemInfo_Value(sample_item, "I_USERDATA")
            debug_info = debug_info .. "Userdata: " .. tostring(userdata) .. "\n"
            
            -- take名称信息
            local take = reaper.GetActiveTake(sample_item)
            if take then
                local take_name = reaper.GetTakeName(take) or ""
                debug_info = debug_info .. "Take名称: \"" .. take_name .. "\"\n"
                
                -- 检查take扩展属性（用于Down-rank/Up-rank脚本标记）
                debug_info = debug_info .. "Take扩展属性检查:\n"
                
                -- 检查常见的rank相关扩展属性键
                local ext_keys_to_check = {
                    "rank", "rank_level", "rank_marker", "rank_value",
                    "take_rank", "item_rank", "pass_rank", "recording_rank"
                }
                
                local found_ext_state = false
                -- 检查GetTakeExtState函数是否存在
                if reaper.GetTakeExtState then
                    for _, key in ipairs(ext_keys_to_check) do
                        -- 尝试两种调用方式，因为不同版本的API可能不同
                        local retval, ext_value
                        -- 方式1：两个参数（retval, value）
                        retval, ext_value = reaper.GetTakeExtState(take, key)
                        -- 如果方式1返回nil或错误，尝试方式2：三个参数
                        if not retval or retval == 0 then
                            ext_value = reaper.GetTakeExtState(take, key, "")
                            retval = (ext_value ~= nil and ext_value ~= "") and 1 or 0
                        end
                        
                        if retval > 0 and ext_value ~= "" then
                            debug_info = debug_info .. "  - " .. key .. ": " .. ext_value .. "\n"
                            found_ext_state = true
                        end
                    end
                else
                    debug_info = debug_info .. "  - GetTakeExtState函数不可用\n"
                    -- 尝试使用其他可能的方法获取take扩展状态
                    local item = reaper.GetMediaItemTake_Item(take)
                    if item and reaper.GetItemExtState then
                        debug_info = debug_info .. "  - 尝试使用GetItemExtState:\n"
                        for _, key in ipairs(ext_keys_to_check) do
                            local ext_value = reaper.GetItemExtState(item, key, "")
                            if ext_value ~= "" then
                                debug_info = debug_info .. "    - " .. key .. ": " .. ext_value .. "\n"
                                found_ext_state = true
                            end
                        end
                    end
                end
                
                -- 如果有SWS扩展函数，尝试获取所有扩展属性
                if reaper.GetMediaItemTakeExtKey then
                    for i = 0, reaper.GetMediaItemTakeInfo_Value(take, "IP_EXT_N") do
                        local key = reaper.GetMediaItemTakeExtKey(take, i)
                        if key ~= "" then
                            local val = reaper.GetMediaItemTakeExtValue(take, key)
                            debug_info = debug_info .. "  - " .. key .. ": " .. tostring(val) .. "\n"
                            found_ext_state = true
                        end
                    end
                end
                
                -- 检查take标记（已注释，因为相关函数可能不存在）
                -- debug_info = debug_info .. "Take标记检查:\n"
                -- if reaper.GetTakeMarker and reaper.GetTakeMarkerCount then
                --     local marker_count = reaper.GetTakeMarkerCount(take)
                --     if marker_count > 0 then
                --         for i = 0, marker_count - 1 do
                --             local retval, pos, name = reaper.GetTakeMarker(take, i)
                --             if retval and name ~= "" then
                --                 debug_info = debug_info .. "  - 标记" .. i .. ": " .. name .. " (位置: " .. pos .. ")\n"
                --             end
                --         end
                --     else
                --         debug_info = debug_info .. "  (无take标记)\n"
                --     end
                -- else
                --     debug_info = debug_info .. "  - GetTakeMarker或GetTakeMarkerCount函数不可用\n"
                -- end
                
                if not found_ext_state then
                    debug_info = debug_info .. "Take扩展属性: (无扩展属性)\n"
                end
            else
                debug_info = debug_info .. "Take名称: (无take)\n"
            end
            
            -- item位置信息
            local item_pos = reaper.GetMediaItemInfo_Value(sample_item, "D_POSITION")
            local item_len = reaper.GetMediaItemInfo_Value(sample_item, "D_LENGTH")
            debug_info = debug_info .. "位置: " .. string.format("%.2f", item_pos) .. " 秒\n"
            debug_info = debug_info .. "长度: " .. string.format("%.2f", item_len) .. " 秒\n"
            
            debug_info = debug_info .. "\n提示：请检查item的notes、userdata、take名称或take扩展属性中是否包含rank标记。"
        end
        
        -- 检查是否有rank标记的item
        local has_ranked_items = false
        for rank, items in pairs(groups) do
            if #items > 0 then
                has_ranked_items = true
                break
            end
        end
        
        if not has_ranked_items then
            reaper.ShowMessageBox(
                "未找到带有rank标记的Item！\n\n" .. debug_info .. "\n\n可能的原因和解决方案：\n\n" ..
                "1. 当前工程未定义Rank标记\n" ..
                "   → 运行Define_Item_Rank.lua脚本定义rank标记\n\n" ..
                "2. Item的标记方式与脚本预期不同\n" ..
                "   → 检查你是如何标记item的（notes/userdata/名称等）\n" ..
                "   → 在Define_Item_Rank.lua中使用相同的标记文本\n\n" ..
                "3. Rank标记定义与Item的实际标记不匹配\n" ..
                "   → 检查Define_Item_Rank.lua中定义的标记文本\n" ..
                "   → 确保item的标记包含这些文本（不区分大小写）\n\n" ..
                "4. 需要修改脚本以匹配你的标记方式\n" ..
                "   → 根据上面显示的item详细信息\n" ..
                "   → 告诉我你是如何标记item的，我可以修改脚本\n\n" ..
                "重要提示：脚本会检查item的notes、userdata和take名称来查找rank标记。",
                "提示", 0)
            return
        end
        
        -- 显示rank统计信息
        local rank_info = "Rank统计：\n"
        for rank, items in pairs(groups) do
            if #items > 0 then
                local rank_name = rank
                local idx = rank:match("^m(%d+)$")
                if idx then
                    local mname = config["m"..idx]
                    rank_name = (mname ~= "" and mname or "#"..idx)
                elseif rank:match("^custom:") then
                    rank_name = "自定义: " .. rank:sub(8)
                end
                
                rank_info = rank_info .. string.format("%s: %d 个item\n", rank_name, #items)
            end
        end
        
        if #unranked_items > 0 then
            rank_info = rank_info .. string.format("未标记: %d 个item\n", #unranked_items)
        end
        
        -- 计算每组最大长度
        local group_max_length = 0
        for _, len in ipairs(item_lengths) do
            if len > group_max_length then
                group_max_length = len
            end
        end
        
        -- 生成排列的起始位置
        local group_start_pos = sample_rightmost_end + 3
        
        for combo = 1, count do
            -- 复制原始items（使用新的rank复制函数）
            local copied_groups = {}
            for rank, items in pairs(groups) do
                copied_groups[rank] = {}
                for _, orig_item in ipairs(items) do
                    local new_item = copy_item_with_rank(orig_item, all_tracks[1])
                    if new_item then
                        table.insert(copied_groups[rank], new_item)
                    end
                end
                
                -- 根据max_items限制随机选取item
                local max_items = rank_max_items_values[rank] or 0
                if max_items > 0 and #copied_groups[rank] > max_items then
                    -- 随机打乱
                    local shuffled = copied_groups[rank]
                    for j = #shuffled, 2, -1 do
                        local k = math.random(j)
                        shuffled[j], shuffled[k] = shuffled[k], shuffled[j]
                    end
                    -- 只保留前max_items个
                    local limited = {}
                    for j = 1, max_items do
                        table.insert(limited, shuffled[j])
                    end
                    copied_groups[rank] = limited
                end
            end
            
            -- 复制未标记的items（使用新的rank复制函数）
            local copied_unranked = {}
            for _, orig_item in ipairs(unranked_items) do
                local new_item = copy_item_with_rank(orig_item, all_tracks[1])
                if new_item then
                    table.insert(copied_unranked, new_item)
                end
            end
            
            -- 生成新的随机种子
            local seed = os.time() + os.clock() * 1000000 + combo * 1000
            math.randomseed(seed)
            
            -- 基于集中度计算随机范围
            local base_range = 0.5
            local min_range = 0.1
            local range_factor = base_range - concentration * (base_range - min_range)
            local range_half = math.max(max_item_length * range_factor, 0.1)
            
            -- 确保有足够的轨道
            local total_items = 0
            for rank, items in pairs(copied_groups) do
                total_items = total_items + #items
            end
            total_items = total_items + #copied_unranked
            
            local needed_tracks = total_items
            local current_track_count = reaper.CountTracks(0)
            local ck_track, ck_idx = find_construction_kit_folder()
            for i = current_track_count + 1, needed_tracks do
                create_track_in_ck_folder(ck_track, ck_idx)
            end
            
            -- 重新获取所有轨道
            local tracks_for_this_group = {}
            local new_track_count = reaper.CountTracks(0)
            for i = start_index, new_track_count - 1 do
                local track = reaper.GetTrack(0, i)
                if track then
                    table.insert(tracks_for_this_group, track)
                end
            end
            
            -- 执行排列
            distribute_random_by_rank(copied_groups, group_start_pos, range_half, concentration, tracks_for_this_group)
            
            -- 处理未标记的items（放在最后）- 确保每个item在独立轨道上
            local used_tracks_for_unranked = {}
            for _, item in ipairs(copied_unranked) do
                local target_track = nil
                local track_index = 1
                
                -- 查找可用的轨道
                while track_index <= #tracks_for_this_group do
                    if not used_tracks_for_unranked[track_index] then
                        target_track = tracks_for_this_group[track_index]
                        used_tracks_for_unranked[track_index] = true
                        break
                    end
                    track_index = track_index + 1
                end
                
                -- 如果没有可用的轨道，在Construction Kit文件夹内创建新轨道
                if not target_track then
                    local ck_track, ck_idx = find_construction_kit_folder()
                    target_track = create_track_in_ck_folder(ck_track, ck_idx)
                    table.insert(tracks_for_this_group, target_track)
                    used_tracks_for_unranked[#tracks_for_this_group] = true
                end
                
                reaper.MoveMediaItemToTrack(item, target_track)
                
                -- 随机位置
                local random_offset = (math.random() - 0.5) * 2 * range_half
                local new_pos = group_start_pos + random_offset
                if new_pos < 0 then new_pos = 0 end
                
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
            end
            
            -- 下一组起始位置
            group_start_pos = group_start_pos + group_max_length + 3
        end
        
        reaper.UpdateArrange()
        
        -- 显示完成消息
        local complete_msg = string.format("Marker排列完成！\n\n%s\n已生成 %d 组排列，每组间隔3秒。", 
            rank_info, count)
        reaper.ShowMessageBox(complete_msg, "完成", 0)
      end
    end
    
    if selected_mode == 0 then
      reaper.ImGui_EndDisabled(ctx)
    end
    
    reaper.ImGui_End(ctx)
  end
  
  -- 如果选择了任意排列方式且显示调整界面，在下方展开调整界面
  if selected_mode > 0 and show_rank_adjust then
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- 根据模式显示不同标题
    local mode_names = {"齐头排列", "随机排列", "Marker排列"}
    reaper.ImGui_Text(ctx, mode_names[selected_mode] .. " - Marker种类调整")
    reaper.ImGui_Spacing(ctx)
    
    -- 模式选择（仅Marker排列显示两种模式）
    if selected_mode == 3 then
        reaper.ImGui_Text(ctx, "调整模式:")
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_RadioButton(ctx, "出现频率##mode", rank_adjust_mode == 1) then
            rank_adjust_mode = 1
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_RadioButton(ctx, "数量限制##mode", rank_adjust_mode == 2) then
            rank_adjust_mode = 2
        end
    else
        reaper.ImGui_Text(ctx, "调整模式: 出现频率")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    -- 动态显示marker控件
    local cfg = load_rank_config()
    for i = 1, cfg._count do
        local key = "m"..i
        local name = cfg[key]
        if name == "" then name = "#"..i end
        if rank_adjust_values[key] == nil then rank_adjust_values[key] = 1.0 end
        if rank_max_items_values[key] == nil then rank_max_items_values[key] = 0 end
        if rank_concentration_values[key] == nil then rank_concentration_values[key] = 0.5 end
        
        reaper.ImGui_Text(ctx, "#"..i.." "..name..":")
        
        -- 根据模式显示不同的控件
        if selected_mode == 3 and rank_adjust_mode == 2 then
            -- Marker排列的数量限制模式
            reaper.ImGui_SameLine(ctx, 180)
            reaper.ImGui_Text(ctx, "数量:")
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetNextItemWidth(ctx, 60)
            local max_changed, max_value = reaper.ImGui_InputInt(ctx, "##maxitems_"..i, rank_max_items_values[key], 0)
            if max_changed then
                rank_max_items_values[key] = math.max(0, max_value)
            end
        else
            -- 出现频率模式（所有排列方式都支持）
            reaper.ImGui_SameLine(ctx, 180)
            reaper.ImGui_SetNextItemWidth(ctx, 100)
            local changed, new_value = reaper.ImGui_SliderDouble(ctx, "##adj_"..i, rank_adjust_values[key], 0.1, 3.0, "%.1f")
            if changed then rank_adjust_values[key] = new_value end
        end
        
        -- 单个marker集中度（所有模式都显示）
        reaper.ImGui_SameLine(ctx, 310)
        reaper.ImGui_Text(ctx, "集中度:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 80)
        local conc_changed, conc_value = reaper.ImGui_SliderDouble(ctx, "##conc_"..i, rank_concentration_values[key], 0.0, 1.0, "%.2f")
        if conc_changed then rank_concentration_values[key] = conc_value end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- 模式说明（根据不同排列方式显示不同说明）
    if selected_mode == 1 then
        -- 齐头排列模式说明
        reaper.ImGui_TextDisabled(ctx, "齐头排列调整说明:")
        reaper.ImGui_Indent(ctx)
        reaper.ImGui_TextDisabled(ctx, "• 出现频率控制各类marker的排列权重")
        reaper.ImGui_TextDisabled(ctx, "• 频率越高，该类marker在排列中占比越大")
        reaper.ImGui_TextDisabled(ctx, "• 集中度影响同类marker的聚集程度")
        reaper.ImGui_Unindent(ctx)
    elseif selected_mode == 2 then
        -- 随机排列模式说明
        reaper.ImGui_TextDisabled(ctx, "随机排列调整说明:")
        reaper.ImGui_Indent(ctx)
        reaper.ImGui_TextDisabled(ctx, "• 出现频率控制各类marker的出现概率")
        reaper.ImGui_TextDisabled(ctx, "• 集中度影响item的分散程度")
        reaper.ImGui_TextDisabled(ctx, "• 可通过数量限制控制每类marker的最大数量")
        reaper.ImGui_Unindent(ctx)
    else
        -- Marker排列模式说明
        if rank_adjust_mode == 1 then
            reaper.ImGui_TextDisabled(ctx, "出现频率说明:")
            reaper.ImGui_Indent(ctx)
            reaper.ImGui_TextDisabled(ctx, "• 0.1-0.5: 减少该marker的出现频率")
            reaper.ImGui_TextDisabled(ctx, "• 0.5-1.0: 正常频率")
            reaper.ImGui_TextDisabled(ctx, "• 1.0-2.0: 增加该marker的出现频率")
            reaper.ImGui_TextDisabled(ctx, "• 2.0-3.0: 显著增加该marker的出现频率")
            reaper.ImGui_Unindent(ctx)
        else
            reaper.ImGui_TextDisabled(ctx, "数量限制说明:")
            reaper.ImGui_Indent(ctx)
            reaper.ImGui_TextDisabled(ctx, "• 0: 不限制，使用所有item")
            reaper.ImGui_TextDisabled(ctx, "• >0: 只随机选取指定数量的item参与排列")
            reaper.ImGui_Unindent(ctx)
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 集中度说明
    reaper.ImGui_TextDisabled(ctx, "集中度说明:")
    reaper.ImGui_Indent(ctx)
    reaper.ImGui_TextDisabled(ctx, "• 每个marker的集中度与总集中度共同影响")
    reaper.ImGui_TextDisabled(ctx, "• 0.0: 该marker的item分散分布")
    reaper.ImGui_TextDisabled(ctx, "• 1.0: 该marker的item紧密聚集")
    reaper.ImGui_Unindent(ctx)

    reaper.ImGui_Spacing(ctx)

    -- 重置按钮
    if reaper.ImGui_Button(ctx, "重置为默认值", 150, 30) then
        for i = 1, cfg._count do
            rank_adjust_values["m"..i] = 1.0
            rank_max_items_values["m"..i] = 0
            rank_concentration_values["m"..i] = 0.5
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
  end
  
  if open then
    reaper.defer(loop)
  end
end

loop()
