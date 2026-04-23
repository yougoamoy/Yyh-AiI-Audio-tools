# Reaper Script

Reaper DAW 相关脚本工具集。

## Import_Video_With_Random_Samples.lua

### 功能描述
批量导入视频文件到Reaper,支持为每个视频生成多个随机样本副本。

### 主要特性
- ✅ 支持多文件选择(需要js_ReaScriptAPI扩展)
- ✅ 为每个视频询问并生成指定数量的随机样本
- ✅ 自动禁用视频音频轨道
- ✅ 可配置视频间隔时间(默认2秒)
- ✅ 智能接续已有视频,避免重叠

### 安装要求
1. Reaper DAW
2. [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174) 扩展

### 使用步骤
1. 打开Reaper
2. Actions → Show action list → Load ReaScript
3. 选择此lua文件
4. 执行脚本
5. 选择视频文件
6. 设置间隔时间
7. 为每个视频设置样本数量

### 更新日志
- 2026-02-09: 初始版本发布
