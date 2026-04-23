--[[
    Arrange Track Sample GUI
    动态创建父/子/更次级轨道结构（支持多层级）
    依赖：ReaImGui
--]]

if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox(
        "此脚本需要 ReaImGui 扩展。\n\n请通过 ReaPack 安装 ReaImGui。",
        "缺少依赖",
        0
    )
    return
end

local ctx = reaper.ImGui_CreateContext("Arrange Track Sample GUI")

local function flag(fn)
    if fn then return fn() end
    return 0
end

local WINDOW_FLAGS = flag(reaper.ImGui_WindowFlags_NoCollapse)
local TREE_FLAGS = flag(reaper.ImGui_TreeNodeFlags_DefaultOpen)
local HSCROLL_WINDOW_FLAG = flag(reaper.ImGui_WindowFlags_HorizontalScrollbar)
local LEVEL_INDENT_PX = 40


local function BeginChildCompat(id, w, h)
    local attempts = {
        function() return reaper.ImGui_BeginChild(ctx, id, w, h, 0, HSCROLL_WINDOW_FLAG) end,
        function() return reaper.ImGui_BeginChild(ctx, id, w, h, 0, 0) end,
        function() return reaper.ImGui_BeginChild(ctx, id, w, h, 0) end,
        function() return reaper.ImGui_BeginChild(ctx, id, w, h, true, HSCROLL_WINDOW_FLAG) end,
        function() return reaper.ImGui_BeginChild(ctx, id, w, h, true, 0) end,
        function() return reaper.ImGui_BeginChild(ctx, id, w, h, true) end,
        function() return reaper.ImGui_BeginChild(ctx, id, w, h) end,
    }

    for _, fn in ipairs(attempts) do
        local ok = pcall(fn)
        if ok then return true end
    end

    return false
end

local function SliderNumberCompat(label, value, minv, maxv)
    if reaper.ImGui_SliderDouble then
        local ok, changed, newv = pcall(reaper.ImGui_SliderDouble, ctx, label, value, minv, maxv)
        if ok then return changed, newv end
    end
    if reaper.ImGui_SliderInt then
        local ok, changed, newv = pcall(reaper.ImGui_SliderInt, ctx, label, math.floor(value), math.floor(minv), math.floor(maxv))
        if ok then return changed, newv end
    end
    return false, value
end

local DEFAULT_CHILD_COUNT = 3

-- 数据结构：children = { {name="xx", level=1}, {name="yy", level=2}, ... }
local parent_tracks = {
    {
        name = "Track_01",
        children = {
            { name = "sub_01", level = 1 },
            { name = "sub_02", level = 1 },
            { name = "sub_03", level = 1 },
        }
    }
}

local function getTotalTracks()
    return reaper.CountTracks(0)
end

local function createTrack(name)
    local idx = getTotalTracks()
    reaper.InsertTrackAtIndex(idx, false)
    local tr = reaper.GetTrack(0, idx)
    if tr then
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name or "", true)
    end
    return tr
end

local function setTrackColor(track, r, g, b)
    local color = reaper.ColorToNative(r, g, b)
    reaper.SetTrackColor(track, color)
end

local function generateColor(index)
    local hue = (index * 47) % 360
    local s, l = 0.6, 0.5
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs((hue / 60) % 2 - 1))
    local m = l - c / 2

    local r, g, b = 0, 0, 0
    if hue < 60 then r, g, b = c, x, 0
    elseif hue < 120 then r, g, b = x, c, 0
    elseif hue < 180 then r, g, b = 0, c, x
    elseif hue < 240 then r, g, b = 0, x, c
    elseif hue < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end

    return math.floor((r + m) * 255), math.floor((g + m) * 255), math.floor((b + m) * 255)
end

local function generateLightColor(index)
    local r, g, b = generateColor(index)
    return math.min(255, r + 50), math.min(255, g + 50), math.min(255, b + 50)
end

local function normalizeParent(parent)
    if type(parent.children) ~= "table" then parent.children = {} end

    local out = {}
    local prev_level = 1

    for i, item in ipairs(parent.children) do
        local name, level

        if type(item) == "table" then
            name = tostring(item.name or "")
            level = tonumber(item.level) or 1
        else
            name = tostring(item or "")
            level = 1
        end

        level = math.floor(level)
        if level < 1 then level = 1 end
        if i == 1 then
            level = 1
        elseif level > prev_level + 1 then
            level = prev_level + 1
        end

        out[#out + 1] = { name = name, level = level }
        prev_level = level
    end

    parent.children = out
end

local function createAllTracks()
    local total_children = 0

    reaper.Undo_BeginBlock()

    for i, parent in ipairs(parent_tracks) do
        normalizeParent(parent)

        local parent_name = (parent.name and parent.name ~= "") and parent.name or string.format("Track_%02d", i)
        local parent_track = createTrack(parent_name)
        local r, g, b = generateColor(i)
        setTrackColor(parent_track, r, g, b)

        if #parent.children > 0 then
            -- 父轨道打开一层文件夹
            reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)

            for j, child in ipairs(parent.children) do
                local child_name = (child.name and child.name ~= "") and child.name or string.format("%s_%02d", parent_name, j)
                local child_track = createTrack(child_name)
                local lr, lg, lb = generateLightColor(i)
                setTrackColor(child_track, lr, lg, lb)

                local cur_level = child.level or 1
                local next_level
                if j < #parent.children then
                    next_level = parent.children[j + 1].level or 1
                else
                    next_level = 0 -- 最后一条：收回到父级外
                end

                local folder_delta = next_level - cur_level
                reaper.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", folder_delta)

                total_children = total_children + 1
            end
        end
    end

    reaper.Undo_EndBlock("Arrange Track Sample GUI: Create tracks", -1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    return #parent_tracks, total_children
end

local function drawGUI()
    reaper.ImGui_Text(ctx, "轨道结构编辑器（支持多层级）")
    reaper.ImGui_Separator(ctx)

    local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local child_h = math.max(180, avail_h - 45)
    BeginChildCompat("track_list", 0, child_h)


    for i = #parent_tracks, 1, -1 do
        local parent = parent_tracks[i]
        normalizeParent(parent)

        local open = reaper.ImGui_TreeNodeEx(ctx, string.format("L0 · ##parent_node_%d", i), TREE_FLAGS)
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 200)
        local p_changed, p_new = reaper.ImGui_InputText(ctx, string.format("##parent_name_%d", i), parent.name or "")
        if p_changed then parent.name = p_new end

        if open then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_SmallButton(ctx, "+##add_child_" .. i) then
                local idx = #parent.children + 1
                parent.children[idx] = { name = string.format("%s_%02d", parent.name ~= "" and parent.name or "sub", idx), level = 1 }
            end



            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_SmallButton(ctx, "-##del_parent_" .. i) then
                table.remove(parent_tracks, i)
                reaper.ImGui_TreePop(ctx)
                goto continue_parent
            end

            local add_after, del_idx = nil, nil

            for j = 1, #parent.children do
                local child = parent.children[j]
                local level = child.level or 1
                local indent = LEVEL_INDENT_PX * math.max(0, level - 1)

                reaper.ImGui_Indent(ctx, indent)

                reaper.ImGui_Text(ctx, string.format("L%d ·", level))
                
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                local c_changed, c_new = reaper.ImGui_InputText(ctx, string.format("##child_name_%d_%d", i, j), child.name or "")
                if c_changed then child.name = c_new end

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_SmallButton(ctx, string.format("+##add_sub_%d_%d", i, j)) then
                    add_after = j
                end

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_SmallButton(ctx, string.format("-##del_child_%d_%d", i, j)) then
                    del_idx = j
                end

                reaper.ImGui_Unindent(ctx, indent)
            end

            if add_after then
                local base = parent.children[add_after]
                local next_name = string.format("%s_sub", (base and base.name ~= "") and base.name or (parent.name ~= "" and parent.name or "sub"))
                table.insert(parent.children, add_after + 1, {
                    name = next_name,
                    level = (base.level or 1) + 1,
                })
            end

            if del_idx then
                table.remove(parent.children, del_idx)
                normalizeParent(parent)
            end

            reaper.ImGui_TreePop(ctx)
        end

        ::continue_parent::
    end

    local sx = reaper.ImGui_GetScrollX and reaper.ImGui_GetScrollX(ctx) or 0
    local sy = reaper.ImGui_GetScrollY and reaper.ImGui_GetScrollY(ctx) or 0
    local maxx = reaper.ImGui_GetScrollMaxX and reaper.ImGui_GetScrollMaxX(ctx) or 0
    local maxy = reaper.ImGui_GetScrollMaxY and reaper.ImGui_GetScrollMaxY(ctx) or 0

    if maxx > 0 then
        local changed_x, new_x = SliderNumberCompat("横向滑动##scroll_x", sx, 0, maxx)
        if changed_x and reaper.ImGui_SetScrollX then reaper.ImGui_SetScrollX(ctx, new_x) end
    end
    if maxy > 0 then
        local changed_y, new_y = SliderNumberCompat("纵向滑动##scroll_y", sy, 0, maxy)
        if changed_y and reaper.ImGui_SetScrollY then reaper.ImGui_SetScrollY(ctx, new_y) end
    end

    reaper.ImGui_EndChild(ctx)
    reaper.ImGui_Separator(ctx)


    if reaper.ImGui_Button(ctx, "添加父轨道", 120, 0) then
        local n = #parent_tracks + 1
        local p = { name = string.format("Track_%02d", n), children = {} }
        for k = 1, DEFAULT_CHILD_COUNT do
            p.children[k] = { name = string.format("%s_%02d", p.name, k), level = 1 }
        end
        parent_tracks[n] = p
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "确认创建轨道", 140, 0) then
        local pc, cc = createAllTracks()
        reaper.ShowMessageBox(string.format("成功创建 %d 个父轨道，共 %d 个子轨道", pc, cc), "完成", 0)
        return true
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "清空所有", 90, 0) then
        parent_tracks = {}
    end

    local total_children = 0
    for _, p in ipairs(parent_tracks) do
        total_children = total_children + #p.children
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, string.format("总计: %d 父轨道, %d 子轨道", #parent_tracks, total_children))

    return false
end

local function main()
    local keep_open = true

    local function loop()
        if not keep_open then return end

        local visible, open = reaper.ImGui_Begin(ctx, "轨道结构编辑器", true, WINDOW_FLAGS)
        if visible then
            local close_now = drawGUI()
            if close_now then
                keep_open = false
            end
            reaper.ImGui_End(ctx)
        end

        if open and keep_open then
            reaper.defer(loop)
        end
    end

    reaper.defer(loop)
end

main()
