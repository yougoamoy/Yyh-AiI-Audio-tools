-- Add Marker At Time Script for REAPER
-- 在选中的视频item上根据输入的时间添加标记
-- Author: Generated Script
-- Version: 1.0

-- 解析时间字符串，转换为秒数
-- 支持格式: "90" (90秒), "1.5m" (1.5分钟), "2h" (2小时), "1:30" (1分30秒)
function ParseTimeString(time_str)
    if time_str == nil or time_str == "" then
        return nil
    end
    
    -- 移除空格
    time_str = time_str:gsub("%s+", "")
    
    -- 检查是否有单位后缀 (h/m/s)
    local unit = time_str:sub(-1):lower()
    local number_str = time_str
    
    if unit == "h" or unit == "m" or unit == "s" then
        number_str = time_str:sub(1, -2)
    else
        unit = nil  -- 没有单位后缀
    end
    
    -- 尝试解析为数字
    local number = tonumber(number_str)
    if not number then
        -- 尝试解析为冒号格式 (HH:MM:SS 或 MM:SS)
        if time_str:match(":") then
            local parts = {}
            for part in time_str:gmatch("[^:]+") do
                table.insert(parts, tonumber(part))
            end
            
            local hours = 0
            local minutes = 0
            local seconds = 0
            
            if #parts == 3 then
                hours = parts[1] or 0
                minutes = parts[2] or 0
                seconds = parts[3] or 0
            elseif #parts == 2 then
                minutes = parts[1] or 0
                seconds = parts[2] or 0
            elseif #parts == 1 then
                seconds = parts[1] or 0
            end
            
            local total_seconds = hours * 3600 + minutes * 60 + seconds
            if total_seconds > 0 then
                return total_seconds
            else
                return nil
            end
        else
            return nil
        end
    end
    
    -- 根据单位计算秒数
    if unit == "h" then
        return number * 3600  -- 小时转秒
    elseif unit == "m" then
        return number * 60    -- 分钟转秒
    elseif unit == "s" then
        return number         -- 秒
    else
        -- 没有单位，默认为秒
        return number
    end
end

-- 主函数
function Main()
    -- 检查是否有选中的媒体项
    local selected_item = reaper.GetSelectedMediaItem(0, 0)
    if not selected_item then
        reaper.ShowMessageBox("请先选择一个视频item", "提示", 0)
        return
    end
    
    -- 获取item的开始位置和长度
    local item_start = reaper.GetMediaItemInfo_Value(selected_item, "D_POSITION")
    local item_length = reaper.GetMediaItemInfo_Value(selected_item, "D_LENGTH")
    local item_end = item_start + item_length
    
    -- 询问用户输入时间
    local ret, user_input = reaper.GetUserInputs(
        "添加标记",
        1,
        "请输入时间 (例如: 90, 1.5m, 2h, 1:30):",
        ""
    )
    
    if not ret then
        return -- 用户取消
    end
    
    -- 解析时间字符串
    local offset_seconds = ParseTimeString(user_input)
    if not offset_seconds then
        reaper.ShowMessageBox("时间格式无效，请使用如 '90', '1.5m', '2h', '1:30' 等格式", "错误", 0)
        return
    end
    
    -- 计算标记位置
    local marker_position = item_start + offset_seconds
    
    -- 检查标记位置是否在item范围内（可选，给出警告）
    if marker_position > item_end then
        local response = reaper.ShowMessageBox(
            string.format("标记位置 (%.2f秒) 超出了选中item的结束位置 (%.2f秒)。\n是否仍然添加标记？", 
                offset_seconds, item_length),
            "警告",
            4 -- Yes/No
        )
        if response == 7 then -- No
            return
        end
    end
    
    -- 添加标记
    reaper.Undo_BeginBlock()
    
    local marker_index = reaper.AddProjectMarker2(0, false, marker_position, 0, "", -1, 0)
    
    reaper.Undo_EndBlock("在时间点添加标记", -1)
    
    -- 显示成功消息
    reaper.ShowMessageBox(
        string.format("已在位置 %.2f 秒处添加标记", offset_seconds),
        "成功",
        0
    )
    
    -- 更新界面
    reaper.UpdateArrange()
end

-- 执行主函数
Main()