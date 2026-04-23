-- 测试轨道创建逻辑
reaper.ShowConsoleMsg("=== 测试轨道结构逻辑 ===\n")

-- 模拟创建3个item的轨道组
reaper.ShowConsoleMsg("\n预期结构：\n")
reaper.ShowConsoleMsg("video1 (一级轨道，I_FOLDERDEPTH=1)\n")
reaper.ShowConsoleMsg("  video1_子轨道01 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video1_子轨道02 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video1_子轨道03 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video1_子轨道04 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video1_子轨道05 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("video2 (一级轨道，I_FOLDERDEPTH=1)\n")
reaper.ShowConsoleMsg("  video2_子轨道01 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video2_子轨道02 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video2_子轨道03 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video2_子轨道04 (次级轨道，I_FOLDERDEPTH=0)\n")
reaper.ShowConsoleMsg("  video2_子轨道05 (次级轨道，I_FOLDERDEPTH=0)\n")

reaper.ShowConsoleMsg("\n问题分析：\n")
reaper.ShowConsoleMsg("当前代码会让video1的次级轨道和video2的一级轨道在同一个文件夹中\n")
reaper.ShowConsoleMsg("需要在video1的最后一个次级轨道后结束文件夹\n")

reaper.ShowConsoleMsg("\n修正方案：\n")
reaper.ShowConsoleMsg("1. video1的一级轨道: I_FOLDERDEPTH=1 (开始文件夹)\n")
reaper.ShowConsoleMsg("2. video1的前4个次级轨道: I_FOLDERDEPTH=0 (在文件夹中)\n")
reaper.ShowConsoleMsg("3. video1的第5个次级轨道: I_FOLDERDEPTH=-1 (结束文件夹)\n")
reaper.ShowConsoleMsg("4. video2的一级轨道: I_FOLDERDEPTH=1 (开始新文件夹)\n")
reaper.ShowConsoleMsg("5. 以此类推...\n")

reaper.ShowConsoleMsg("\n=== 测试完成 ===\n")