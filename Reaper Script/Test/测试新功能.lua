-- 测试新功能是否存在的简单脚本
reaper.ShowConsoleMsg("=== 测试 Arrange_track_sample_GUI 新功能 ===\n")

-- 检查文件是否存在
local file_path = "D:\\Pan&Audio\\AI\\Tools\\Reaper Script\\Arrange_track_sample_GUI.lua"
local file = io.open(file_path, "r")
if file then
    reaper.ShowConsoleMsg("✓ 脚本文件存在\n")
    file:close()
    
    -- 检查文件内容
    local content = ""
    for line in io.lines(file_path) do
        content = content .. line .. "\n"
    end
    
    -- 检查新功能关键词
    if content:find("根据选中视频建立轨道") then
        reaper.ShowConsoleMsg("✓ 新功能代码存在\n")
        
        -- 统计出现次数
        local count = 0
        for _ in content:gmatch("根据选中视频建立轨道") do
            count = count + 1
        end
        reaper.ShowConsoleMsg("  关键词出现次数: " .. count .. "\n")
        
        -- 检查具体函数
        if content:find("createTracksFromSelectedVideos") then
            reaper.ShowConsoleMsg("✓ 新功能函数存在\n")
        else
            reaper.ShowConsoleMsg("✗ 新功能函数不存在\n")
        end
        
        if content:find("getItemFileName") then
            reaper.ShowConsoleMsg("✓ 文件名提取函数存在\n")
        else
            reaper.ShowConsoleMsg("✗ 文件名提取函数不存在\n")
        end
    else
        reaper.ShowConsoleMsg("✗ 新功能代码不存在\n")
    end
else
    reaper.ShowConsoleMsg("✗ 脚本文件不存在\n")
end

reaper.ShowConsoleMsg("=== 测试完成 ===\n")

-- 提供解决方案
reaper.ShowConsoleMsg("\n=== 如果看不到新功能按钮，请尝试： ===\n")
reaper.ShowConsoleMsg("1. 重启REAPER（清除缓存）\n")
reaper.ShowConsoleMsg("2. 重新加载脚本：\n")
reaper.ShowConsoleMsg("   - 关闭脚本窗口\n")
reaper.ShowConsoleMsg("   - 重新运行脚本\n")
reaper.ShowConsoleMsg("3. 检查脚本路径是否正确\n")
reaper.ShowConsoleMsg("4. 如果还是不行，请检查文件修改时间\n")

-- 显示文件信息
local function getFileInfo(path)
    local f = io.open(path, "r")
    if f then
        local size = f:seek("end")
        f:close()
        
        -- 获取修改时间（简化版）
        reaper.ShowConsoleMsg("\n文件信息：\n")
        reaper.ShowConsoleMsg("  路径: " .. path .. "\n")
        reaper.ShowConsoleMsg("  大小: " .. size .. " 字节\n")
        
        -- 读取前几行检查版本
        f = io.open(path, "r")
        local first_lines = ""
        for i = 1, 5 do
            local line = f:read("*l")
            if line then
                first_lines = first_lines .. line .. "\n"
            end
        end
        f:close()
        
        if first_lines:find("Arrange Track Sample GUI") then
            reaper.ShowConsoleMsg("  脚本标识: Arrange Track Sample GUI\n")
        end
    end
end

getFileInfo(file_path)