--[[
    Random Layer Combo
    随机组合轨道 Layer 探索工具 - 主脚本

    功能：
    - 读取工程中所有轨道
    - 随机选取 N 条轨道 unmute，其余全部 mute
    - 每次调用脚本切换到一个新的随机组合
    - 自动避免短期内重复同一组合
    - 在 Reaper 状态栏显示当前激活的是哪些轨道

    使用方法：
    1. 将所有样本各放一条轨道（建议全部取消 mute 初始状态）
    2. 将此脚本绑定到一个快捷键（如 Alt+R）
    3. 每次按快捷键随机切换到新的 layer 组合
    4. 听到好的组合按 Mark_Current_Combo.lua 对应快捷键保存

    配合脚本：
    - Mark_Current_Combo.lua：标记/收藏当前组合
--]]

-- ============================================================
-- 配置区（可根据需要修改）
-- ============================================================
local CONFIG = {
    layer_count       = 3,      -- 默认 layer 数量（首次运行会弹窗询问）
    avoid_repeat      = true,   -- 是否避免短期重复组合
    history_size      = 10,     -- 记忆最近几个组合（避免重复）
    show_track_names  = true,   -- 状态栏显示轨道名
    first_run_ask     = true,   -- 首次运行时弹窗询问 layer 数量
}

-- ============================================================
-- 持久化存储 key（利用 Reaper ExtState 跨调用保存状态）
-- ============================================================
local EXT_SECTION   = "Yyh_RandomLayerCombo"
local KEY_LAYER_N   = "layer_count"
local KEY_HISTORY   = "combo_history"

-- ============================================================
-- 工具函数
-- ============================================================

-- 获取工程所有轨道（返回 track 对象列表）
local function getAllTracks()
    local tracks = {}
    local count = reaper.CountTracks(0)
    for i = 0, count - 1 do
        table.insert(tracks, reaper.GetTrack(0, i))
    end
    return tracks
end

-- 获取轨道名称
local function getTrackName(track)
    local _, name = reaper.GetTrackName(track)
    return name
end

-- Fisher-Yates 随机打乱
local function shuffle(t)
    math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000))
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- 将组合转换为字符串 key（用于去重）
local function comboToKey(indices)
    local sorted = {}
    for _, v in ipairs(indices) do table.insert(sorted, v) end
    table.sort(sorted)
    return table.concat(sorted, ",")
end

-- 从 ExtState 读取历史记录
local function loadHistory()
    local raw = reaper.GetExtState(EXT_SECTION, KEY_HISTORY)
    local history = {}
    if raw and raw ~= "" then
        for entry in raw:gmatch("[^|]+") do
            table.insert(history, entry)
        end
    end
    return history
end

-- 保存历史记录到 ExtState
local function saveHistory(history)
    -- 只保留最近 N 条
    while #history > CONFIG.history_size do
        table.remove(history, 1)
    end
    reaper.SetExtState(EXT_SECTION, KEY_HISTORY, table.concat(history, "|"), false)
end

-- 检查 key 是否在历史中
local function inHistory(history, key)
    for _, v in ipairs(history) do
        if v == key then return true end
    end
    return false
end

-- ============================================================
-- 获取/设置 layer 数量
-- ============================================================
local function getLayerCount(track_count)
    -- 读取上次保存的值
    local saved = reaper.GetExtState(EXT_SECTION, KEY_LAYER_N)
    local n = tonumber(saved)

    -- 首次运行或无效值时弹窗询问
    if not n or n < 1 or n > track_count then
        local retval, input = reaper.GetUserInputs(
            "Random Layer Combo - 设置",
            1,
            string.format("同时激活几条轨道？(1-%d)", track_count),
            tostring(CONFIG.layer_count)
        )
        if not retval then return nil end
        n = tonumber(input)
        if not n or n < 1 or n > track_count then
            reaper.ShowMessageBox(
                string.format("请输入 1 到 %d 之间的整数", track_count),
                "输入错误", 0
            )
            return nil
        end
        reaper.SetExtState(EXT_SECTION, KEY_LAYER_N, tostring(n), false)
    end
    return n
end

-- ============================================================
-- 主函数
-- ============================================================
local function main()
    local tracks = getAllTracks()
    local track_count = #tracks

    if track_count == 0 then
        reaper.ShowMessageBox("工程中没有轨道", "错误", 0)
        return
    end

    -- 获取 layer 数量
    local n = getLayerCount(track_count)
    if not n then return end

    if n >= track_count then
        reaper.ShowMessageBox(
            string.format("layer 数量(%d)必须小于总轨道数(%d)", n, track_count),
            "错误", 0
        )
        return
    end

    -- 读取历史，尝试生成不重复的组合
    local history = loadHistory()
    local indices = {}
    local chosen_key = ""
    local max_attempts = 30  -- 最多尝试次数（防止所有组合都被记录时死循环）

    for attempt = 1, max_attempts do
        -- 生成候选索引列表并打乱
        local pool = {}
        for i = 1, track_count do table.insert(pool, i) end
        shuffle(pool)

        -- 取前 n 个
        indices = {}
        for i = 1, n do table.insert(indices, pool[i]) end

        chosen_key = comboToKey(indices)

        -- 检查是否重复，或已超过尝试次数
        if not CONFIG.avoid_repeat or not inHistory(history, chosen_key) then
            break
        end

        -- 最后一次尝试时不管是否重复都直接用
        if attempt == max_attempts then break end
    end

    -- 构建激活集合（用于快速查找）
    local active_set = {}
    for _, idx in ipairs(indices) do
        active_set[idx] = true
    end

    -- -------------------------------------------------------
    -- 应用 mute/unmute
    -- -------------------------------------------------------
    reaper.Undo_BeginBlock()

    local active_names = {}
    for i, track in ipairs(tracks) do
        if active_set[i] then
            reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
            table.insert(active_names, string.format("[%d] %s", i, getTrackName(track)))
        else
            reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
        end
    end

    reaper.Undo_EndBlock("Random Layer Combo: switch", -1)

    -- -------------------------------------------------------
    -- 保存当前组合到历史
    -- -------------------------------------------------------
    table.insert(history, chosen_key)
    saveHistory(history)

    -- -------------------------------------------------------
    -- 保存当前激活轨道 index（供 Mark 脚本读取）
    -- -------------------------------------------------------
    reaper.SetExtState(EXT_SECTION, "current_combo", chosen_key, false)

    -- -------------------------------------------------------
    -- 状态栏提示
    -- -------------------------------------------------------
    local status = string.format(
        "🎲 Random Layer Combo | %d/%d 轨道激活 | %s",
        n, track_count,
        table.concat(active_names, "  +  ")
    )
    reaper.SetExtState(EXT_SECTION, "current_names", table.concat(active_names, " + "), false)
    reaper.ShowConsoleMsg(status .. "\n")

    -- 更新工程标题栏提示（可选）
    reaper.UpdateArrange()
end

-- 执行
main()
