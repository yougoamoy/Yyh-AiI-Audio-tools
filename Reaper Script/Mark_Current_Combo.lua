--[[
    Mark Current Combo
    标记/收藏当前随机激活的轨道组合

    功能：
    - 读取 Random_Layer_Combo.lua 记录的当前激活轨道
    - 给这些轨道统一涂上高亮颜色
    - 在轨道名末尾追加 ★ 标记（可多次标记，颜色循环变化便于区分不同收藏批次）
    - 在 Reaper Console 输出收藏记录

    使用方法：
    1. 先运行 Random_Layer_Combo.lua 切换到你喜欢的组合
    2. 觉得当前组合不错时，按此脚本对应的快捷键（如 Alt+M）
    3. 当前激活的轨道会被高亮标记

    配合脚本：
    - Random_Layer_Combo.lua：随机切换组合主脚本
--]]

-- ============================================================
-- 配置区
-- ============================================================

-- 收藏颜色循环列表（每次收藏使用下一个颜色，便于区分不同轮次的好组合）
local MARK_COLORS = {
    {255, 220,  60},  -- 1. 金黄
    {255, 120,  60},  -- 2. 橙红
    {120, 220,  80},  -- 3. 草绿
    {80,  200, 220},  -- 4. 青蓝
    {200,  80, 220},  -- 5. 紫粉
    {255, 180, 180},  -- 6. 粉红
    {180, 255, 180},  -- 7. 浅绿
    {180, 180, 255},  -- 8. 淡蓝
}

local STAR_MARK    = "★"    -- 追加到轨道名的标记符号
local EXT_SECTION  = "Yyh_RandomLayerCombo"
local KEY_COMBO    = "current_combo"
local KEY_NAMES    = "current_names"
local KEY_COLOR_IDX = "mark_color_index"

-- ============================================================
-- 工具函数
-- ============================================================

-- 获取当前收藏颜色（循环）
local function getNextColor()
    local idx = tonumber(reaper.GetExtState(EXT_SECTION, KEY_COLOR_IDX)) or 0
    idx = (idx % #MARK_COLORS) + 1
    reaper.SetExtState(EXT_SECTION, KEY_COLOR_IDX, tostring(idx), false)
    return MARK_COLORS[idx], idx
end

-- 解析组合 key（"1,3,7" → {1,3,7}）
local function parseComboKey(key)
    local indices = {}
    for n in key:gmatch("(%d+)") do
        table.insert(indices, tonumber(n))
    end
    return indices
end

-- 轨道名末尾追加 ★（避免重复添加过多）
local function addStarToName(track)
    local _, name = reaper.GetTrackName(track)
    -- 已经有 ★ 就不重复添加
    if not name:find(STAR_MARK, 1, true) then
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name .. " " .. STAR_MARK, true)
    end
end

-- ============================================================
-- 主函数
-- ============================================================
local function main()
    -- 读取当前激活组合
    local combo_key = reaper.GetExtState(EXT_SECTION, KEY_COMBO)
    if not combo_key or combo_key == "" then
        reaper.ShowMessageBox(
            "尚未检测到激活的组合。\n请先运行 Random_Layer_Combo.lua 切换到一个组合。",
            "Mark Current Combo", 0
        )
        return
    end

    local indices = parseComboKey(combo_key)
    if #indices == 0 then
        reaper.ShowMessageBox("组合数据解析失败：" .. combo_key, "错误", 0)
        return
    end

    local track_count = reaper.CountTracks(0)

    -- 验证索引合法性
    for _, idx in ipairs(indices) do
        if idx < 1 or idx > track_count then
            reaper.ShowMessageBox(
                string.format("轨道索引 %d 超出范围（当前工程共 %d 条轨道）", idx, track_count),
                "错误", 0
            )
            return
        end
    end

    -- 获取颜色
    local color_rgb, color_idx = getNextColor()
    local native_color = reaper.ColorToNative(color_rgb[1], color_rgb[2], color_rgb[3])

    -- -------------------------------------------------------
    -- 应用标记
    -- -------------------------------------------------------
    reaper.Undo_BeginBlock()

    local marked_names = {}
    for _, idx in ipairs(indices) do
        local track = reaper.GetTrack(0, idx - 1)
        if track then
            -- 涂色
            reaper.SetTrackColor(track, native_color)
            -- 加星标
            addStarToName(track)
            local _, name = reaper.GetTrackName(track)
            table.insert(marked_names, string.format("[%d] %s", idx, name))
        end
    end

    reaper.Undo_EndBlock("Mark Current Combo: mark tracks", -1)
    reaper.UpdateArrange()

    -- -------------------------------------------------------
    -- Console 输出收藏记录
    -- -------------------------------------------------------
    local timestamp = os.date("%H:%M:%S")
    local color_name = string.format("颜色#%d (R%d G%d B%d)",
        color_idx, color_rgb[1], color_rgb[2], color_rgb[3])

    reaper.ShowConsoleMsg(string.format(
        "★ [%s] 收藏组合 | %s | 轨道：%s\n",
        timestamp,
        color_name,
        table.concat(marked_names, " + ")
    ))
end

-- 执行
main()
