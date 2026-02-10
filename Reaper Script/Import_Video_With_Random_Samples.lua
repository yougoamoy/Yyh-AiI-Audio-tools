-- Import Video With Random Samples Script for REAPER
-- 导入视频并创建随机音效样本
-- Author: Generated Script
-- Version: 1.0

-- 获取视频文件路径(支持多选)
function SelectVideoFiles()
    -- 使用JS_Dialog_BrowseForOpenFiles支持多选(需要安装js_ReaScriptAPI扩展)
    -- 如果未安装,则回退到单选模式
    if reaper.JS_Dialog_BrowseForOpenFiles then
        local ret, file_list = reaper.JS_Dialog_BrowseForOpenFiles(
            "选择要导入的视频文件",
            "",
            "",
            "视频文件\0*.mp4;*.avi;*.mov;*.mkv;*.wmv;*.flv;*.webm\0所有文件\0*.*\0",
            true -- 允许多选
        )
        
        if ret == 1 then
            return file_list
        else
            return nil
        end
    else
        -- 回退方案:使用标准对话框(单选)
        reaper.ShowMessageBox(
            "检测到未安装 js_ReaScriptAPI 扩展\n将使用单选模式\n\n建议安装 ReaPack 和 js_ReaScriptAPI 以支持多选功能",
            "提示",
            0
        )
        
        local files = {}
        while true do
            local ret, file_path = reaper.GetUserFileNameForRead("", "选择视频文件(选完后点取消)", "视频文件\0*.mp4;*.avi;*.mov;*.mkv;*.wmv;*.flv;*.webm\0所有文件\0*.*\0")
            
            if not ret then
                break
            end
            
            table.insert(files, file_path)
            
            local continue = reaper.ShowMessageBox(
                string.format("已选择 %d 个文件\n是否继续添加?", #files),
                "继续选择",
                4 -- Yes/No
            )
            
            if continue == 7 then -- No
                break
            end
        end
        
        if #files == 0 then
            return nil
        end
        
        -- 将文件列表转换为分隔符格式
        return table.concat(files, "\0")
    end
end

-- 解析多个文件
function ParseFileList(file_list)
    local files = {}
    
    -- 处理空字符分隔的文件列表
    local temp = {}
    for file in string.gmatch(file_list, "[^\0]+") do
        if file ~= "" and file ~= " " then
            table.insert(temp, file)
        end
    end
    
    -- JS_Dialog_BrowseForOpenFiles 返回格式: 目录\0文件1\0文件2\0...
    -- 第一个元素是目录路径
    if #temp > 1 then
        local directory = temp[1]
        -- 从第二个元素开始是文件名
        for i = 2, #temp do
            local full_path = directory .. "\\" .. temp[i]
            table.insert(files, full_path)
        end
    elseif #temp == 1 then
        -- 单个文件的情况
        table.insert(files, temp[1])
    end
    
    -- 如果仍然没有文件,尝试直接使用
    if #files == 0 and file_list ~= "" then
        table.insert(files, file_list)
    end
    
    return files
end

-- 询问用户需要创建多少个随机样本
function AskForSampleCount(video_name, video_index, total_videos)
    local ret, user_input = reaper.GetUserInputs(
        string.format("视频 %d/%d: %s", video_index, total_videos, video_name),
        1,
        "需要创建多少个随机音效样本? (输入数字,1表示不复制)",
        "1"
    )
    
    if not ret then
        return nil -- 用户取消
    end
    
    local count = tonumber(user_input)
    if not count or count < 1 then
        reaper.ShowMessageBox("请输入有效的数字(>=1)", "错误", 0)
        return AskForSampleCount(video_name, video_index, total_videos)
    end
    
    return math.floor(count)
end

-- 获取视频文件名(不含路径)
function GetFileName(path)
    return path:match("^.+[\\/](.+)$") or path
end

-- 在指定位置插入视频
function InsertVideoAtPosition(file_path, position, track)
    reaper.SetEditCurPos(position, false, false)
    reaper.InsertMedia(file_path, 0) -- 0 = 插入到光标位置
    
    local item = reaper.GetTrackMediaItem(track, reaper.CountTrackMediaItems(track) - 1)
    return item
end

-- 获取媒体项的长度
function GetItemLength(item)
    if item then
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        return item_len
    end
    return 0
end

-- 主函数
function Main()
    -- 获取视频文件
    local file_list = SelectVideoFiles()
    
    if not file_list then
        reaper.ShowMessageBox("未选择任何文件", "取消", 0)
        return
    end
    
    -- 解析文件列表
    local files = ParseFileList(file_list)
    
    if #files == 0 then
        reaper.ShowMessageBox("未找到有效的视频文件", "错误", 0)
        return
    end
    
    -- 收集每个视频需要的样本数量
    local sample_counts = {}
    for i, file in ipairs(files) do
        local file_name = GetFileName(file)
        local count = AskForSampleCount(file_name, i, #files)
        
        if not count then
            reaper.ShowMessageBox("操作已取消", "取消", 0)
            return
        end
        
        sample_counts[i] = count
    end
    
    -- 询问视频间隔时间
    local ret, user_input = reaper.GetUserInputs(
        "设置视频间隔",
        1,
        "视频间隔时间(秒):",
        "2.0"
    )
    
    if not ret then
        reaper.ShowMessageBox("操作已取消", "取消", 0)
        return
    end
    
    local gap_time = tonumber(user_input)
    if not gap_time or gap_time < 0 then
        reaper.ShowMessageBox("请输入有效的间隔时间(>=0)", "错误", 0)
        return
    end
    
    -- 开始导入
    reaper.Undo_BeginBlock()
    
    -- 获取或创建视频轨道
    local track_count = reaper.CountTracks(0)
    local video_track
    
    if track_count == 0 then
        reaper.InsertTrackAtIndex(0, true)
        video_track = reaper.GetTrack(0, 0)
        reaper.GetSetMediaTrackInfo_String(video_track, "P_NAME", "Video Track", true)
    else
        video_track = reaper.GetTrack(0, 0)
    end
    
    -- 检查轨道上是否已有媒体项,如果有则从最后一个项的结束位置开始
    local current_position = 0
    local existing_items = reaper.CountTrackMediaItems(video_track)
    
    if existing_items > 0 then
        -- 找到所有媒体项中结束位置最靠后的那个
        local max_end_position = 0
        for j = 0, existing_items - 1 do
            local item = reaper.GetTrackMediaItem(video_track, j)
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len
            
            if item_end > max_end_position then
                max_end_position = item_end
            end
        end
        
        -- 从最后一个项结束后的2秒位置开始
        current_position = max_end_position + gap_time
    end
    
    -- 取消所有选择
    reaper.SelectAllMediaItems(0, false)
    
    -- 遍历每个视频文件
    for i, file in ipairs(files) do
        local sample_count = sample_counts[i]
        local file_name = GetFileName(file)
        
        -- 为每个样本创建视频
        for sample_idx = 1, sample_count do
            -- 记录插入前的媒体项数量
            local items_before = reaper.CountTrackMediaItems(video_track)
            
            -- 设置光标到当前位置
            reaper.SetEditCurPos(current_position, false, false)
            reaper.SetOnlyTrackSelected(video_track)
            
            -- 插入视频
            reaper.InsertMedia(file, 0)
            
            -- 等待一下确保插入完成
            reaper.defer(function() end)
            
            -- 获取插入后的媒体项数量
            local items_after = reaper.CountTrackMediaItems(video_track)
            
            -- 找到刚插入的媒体项
            if items_after > items_before then
                local new_item = reaper.GetTrackMediaItem(video_track, items_after - 1)
                
                -- 获取媒体项的长度
                local item_length = GetItemLength(new_item)
                
                -- 强制设置位置(确保在正确的位置)
                reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", current_position)
                reaper.UpdateItemInProject(new_item)
                
                -- 禁用视频的音频
                local take = reaper.GetActiveTake(new_item)
                if take then
                    -- 在 Reaper 中,I_CHANMODE 的正确值:
                    -- 0 = Normal
                    -- 1 = Reverse stereo
                    -- 2 = Mono (downmix)
                    -- 3 = Mono (left)
                    -- 4 = Mono (right)
                    -- 5 = Disable audio (这是正确的值!)
                    reaper.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", 5)
                    
                    -- 强制更新
                    reaper.UpdateItemInProject(new_item)
                end
                
                -- 重命名媒体项
                if sample_count > 1 then
                    reaper.GetSetMediaItemInfo_String(new_item, "P_NOTES", 
                        string.format("%s - 样本 %d/%d", file_name, sample_idx, sample_count), true)
                end
                
                -- 更新下一个位置 = 当前位置 + 视频长度 + 2秒间隔
                current_position = current_position + item_length + gap_time
            else
                -- 如果没有插入成功,跳过这个样本
                reaper.ShowMessageBox(
                    string.format("警告: 视频 '%s' 样本 %d 插入失败", file_name, sample_idx),
                    "警告",
                    0
                )
            end
        end
    end
    
    reaper.Undo_EndBlock("导入视频并创建随机音效样本", -1)
    
    -- 显示完成消息
    local total_items = 0
    for _, count in ipairs(sample_counts) do
        total_items = total_items + count
    end
    
    reaper.ShowMessageBox(
        string.format("成功导入 %d 个视频文件,共创建 %d 个媒体项\n视频间隔: %.1f 秒", 
            #files, total_items, gap_time),
        "导入完成",
        0
    )
    
    -- 更新界面
    reaper.UpdateArrange()
end

-- 执行主函数
Main()
