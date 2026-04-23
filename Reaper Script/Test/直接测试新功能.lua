-- 直接测试新功能
reaper.ShowConsoleMsg("=== 直接测试新功能 ===\n")

-- 检查当前选中的item数量
local item_count = reaper.CountSelectedMediaItems(0)
reaper.ShowConsoleMsg("当前选中的item数量: " .. item_count .. "\n")

if item_count == 0 then
    reaper.ShowConsoleMsg("提示：请先选中至少一个item（视频）\n")
    reaper.ShowMessageBox("请先选中至少一个item（视频）", "提示", 0)
    return
end

-- 测试获取文件名功能
reaper.ShowConsoleMsg("\n=== 测试获取文件名功能 ===\n")
for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
        local take = reaper.GetActiveTake(item)
        if take then
            local source = reaper.GetMediaItemTake_Source(take)
            if source then
                local filename = reaper.GetMediaSourceFileName(source, "")
                reaper.ShowConsoleMsg("Item " .. (i+1) .. " 文件路径: " .. (filename or "无") .. "\n")
                
                -- 提取文件名（不含路径和扩展名）
                if filename and filename ~= "" then
                    local name_with_ext = filename:match("[^\\/]+$") or filename
                    local name = name_with_ext:match("(.+)%..+$") or name_with_ext
                    reaper.ShowConsoleMsg("Item " .. (i+1) .. " 文件名: " .. name .. "\n")
                end
            else
                reaper.ShowConsoleMsg("Item " .. (i+1) .. ": 无法获取媒体源\n")
            end
        else
            reaper.ShowConsoleMsg("Item " .. (i+1) .. ": 无有效take\n")
        end
    end
end

-- 提供解决方案
reaper.ShowConsoleMsg("\n=== 如果主脚本看不到新功能按钮，请尝试： ===\n")
reaper.ShowConsoleMsg("1. 重启REAPER（重要！清除缓存）\n")
reaper.ShowConsoleMsg("2. 确认运行的是修改后的脚本\n")
reaper.ShowConsoleMsg("3. 检查脚本文件修改时间\n")
reaper.ShowConsoleMsg("4. 尝试重新保存脚本文件\n")

-- 检查文件修改时间
local function checkFileModTime()
    local file_path = "D:\\Pan&Audio\\AI\\Tools\\Reaper Script\\Arrange_track_sample_GUI.lua"
    local file = io.open(file_path, "r")
    if file then
        -- 简单的文件大小检查
        local size = file:seek("end")
        file:close()
        reaper.ShowConsoleMsg("\n脚本文件信息：\n")
        reaper.ShowConsoleMsg("  文件大小: " .. size .. " 字节\n")
        
        if size > 10000 then
            reaper.ShowConsoleMsg("  文件大小正常（应该是修改后的版本）\n")
        else
            reaper.ShowConsoleMsg("  警告：文件可能不是修改后的版本\n")
        end
    else
        reaper.ShowConsoleMsg("✗ 无法打开脚本文件\n")
    end
end

checkFileModTime()

reaper.ShowConsoleMsg("\n=== 测试完成 ===\n")