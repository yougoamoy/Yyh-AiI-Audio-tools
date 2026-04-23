--[[
    Arrange Track Sample
    根据用户输入的音效名称批量创建父轨道和子轨道
    
    功能：
    - 弹出20个输入框，每个填写一个音效名称
    - 为每个名称创建一个父轨道
    - 每个父轨道下创建3个子轨道
    
    使用方法：
    - 每个输入框填写一个音效名称
    - 留空的输入框会被忽略
--]]

-- 默认子轨道数量
local DEFAULT_CHILD_COUNT = 3

-- 获取当前工程中的轨道总数
local function getTotalTracks()
    return reaper.CountTracks(0)
end

-- 创建轨道并设置名称
local function createTrack(name)
    local track_count = getTotalTracks()
    reaper.InsertTrackAtIndex(track_count, false)
    local track = reaper.GetTrack(0, track_count)
    if track and name then
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end
    return track
end

-- 设置轨道为文件夹（父轨道）
local function setAsFolderParent(track)
    reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)
end

-- 设置轨道为文件夹内最后一轨（子轨道）
local function setAsFolderChild(track, is_last_child)
    if is_last_child then
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", -1)
    else
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
    end
end

-- 设置轨道颜色
local function setTrackColor(track, r, g, b)
    local color = reaper.ColorToNative(r, g, b)
    reaper.SetTrackColor(track, color)
end

-- 主函数
local function main()
    -- 用户输入对话框 - 20个输入框
    local title = "Arrange Track Sample"
    local num_inputs = 20
    
    -- 构建 captions：20个编号的输入框
    local captions = ""
    for i = 1, num_inputs do
        if i > 1 then captions = captions .. "," end
        captions = captions .. string.format("%02d:", i)
    end
    
    -- 默认值：全部为空
    local default_input = ""
    for i = 1, num_inputs do
        if i > 1 then default_input = default_input .. "," end
        default_input = default_input .. ""
    end
    
    local retval, retvals_csv = reaper.GetUserInputs(title, num_inputs, captions, default_input)
    
    if not retval then
        return -- 用户取消
    end
    
    -- 解析返回值（逗号分隔）
    local names = {}
    local i = 1
    for name in string.gmatch(retvals_csv, "([^,]*)") do
        -- 去除首尾空格
        name = name:match("^%s*(.-)%s*$")
        if name and name ~= "" then
            table.insert(names, name)
        end
        i = i + 1
        if i > num_inputs then break end
    end
    
    if #names == 0 then
        reaper.ShowMessageBox("请输入至少一个音效名称", "错误", 0)
        return
    end
    
    -- 开始Undo块
    reaper.Undo_BeginBlock()
    
    -- 为每个名称创建轨道结构
    for i, name in ipairs(names) do
        -- 创建父轨道
        local parent = createTrack(name)
        setAsFolderParent(parent)
        -- 设置父轨道颜色
        setTrackColor(parent, 100, 150, 200)
        
        -- 创建子轨道
        for j = 1, DEFAULT_CHILD_COUNT do
            local child_name = string.format("%s_%02d", name, j)
            local child = createTrack(child_name)
            setAsFolderChild(child, j == DEFAULT_CHILD_COUNT)
            -- 设置子轨道颜色（稍浅）
            setTrackColor(child, 150, 180, 220)
        end
    end
    
    -- 结束Undo块
    reaper.Undo_EndBlock("Arrange Track Sample: Create tracks", -1)
    
    -- 提示完成
    reaper.ShowMessageBox(string.format("成功创建 %d 个父轨道，共 %d 个子轨道", #names, #names * DEFAULT_CHILD_COUNT), "完成", 0)
end

-- 执行主函数
main()
