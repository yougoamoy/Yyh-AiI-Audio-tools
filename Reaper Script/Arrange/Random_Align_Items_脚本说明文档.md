# Random_Align_Items.lua 脚本说明文档

## 概述

`Random_Align_Items.lua`是一个REAPER DAW脚本，用于对选中的音频Item进行智能排列和分布。脚本提供了三种主要的排列模式，并支持基于自定义Rank标记的分层排列。

## 脚本功能

### 1. 核心功能
- **齐头排列**：将所有Item对齐到同一时间点
- **随机排列**：在时间轴上随机分布Item
- **Rank排列**：基于Item的Rank标记进行分层排列（新增功能）

### 2. 主要参数
1. **组合数量**：控制Item的重复组合数量
2. **集中度控制**：控制Item在时间轴上的集中程度
3. **分布类型**（仅Rank排列）：
   - 随机分布：尽可能随机分布所有Item
   - 离散分布：确保同Rank的Item在时间轴上分散

## 技术架构

### 1. 文件结构
```
Random_Align_Items.lua          # 主脚本文件
Define_Item_Rank.lua            # Rank标记定义脚本（外部依赖）
Define_Item_Rank_config.txt     # Rank配置（外部依赖）
```

### 2. GUI界面
- 使用ImGui库创建图形界面
- 窗口高度：`WINDOW_H = 300`
- 主要控件：
  - 排列模式选择（齐头/随机/Rank）
  - 组合数量滑块
  - 集中度控制滑块
  - 分布类型下拉菜单（仅Rank模式）
  - 执行排列按钮

### 3. 全局变量
```lua
selected_mode = 3               # 当前选择的排列模式（1:齐头, 2:随机, 3:Rank）
rank_distribution_type = 1      # Rank分布类型（1:随机分布, 2:离散分布）
WINDOW_H = 300                  # 窗口高度
```

## Rank排列功能详解

### 1. Rank概念
- **定义**：Rank是用户为音效Item定义的自定义分层标记
- **特点**：
  - 含义不确定，因项目而异
  - 用于音效分层（如科幻音效：glitch, click sci, sci imp, sci tonal）
  - 枪声音效：mech层, snap层, body层等
- **存储**：通过Item的notes属性存储Rank标记

### 2. Rank标记系统
#### 2.1 标记来源
1. **预定义Rank**：来自`Define_Item_Rank.lua`的配置（如rank1_smile, rank2_neutral等）
2. **自定义Rank**：Item notes中任意文本（格式：`custom:自定义文本`）
3. **未标记Item**：标记为"unranked"

#### 2.2 标记读取流程
```lua
function get_item_rank(item, config)
    -- 1. 从Item notes读取标记
    -- 2. 匹配预定义Rank配置
    -- 3. 识别自定义Rank标记
    -- 4. 返回Rank值或"unranked"
end
```

### 3. Rank排列算法

#### 3.1 分组阶段
```lua
function group_items_by_rank(selected_items, config)
    -- 按Rank将Item分组
    -- 统计每个Rank的Item数量
    -- 记录未标记Item
end
```

#### 3.2 分布算法

##### 3.2.1 随机分布
```lua
function distribute_random_by_rank(rank_groups, ...)
    -- 尽可能随机分布所有Item
    -- 同Rank Item可混合但避免重叠
    -- 使用随机偏移保证分布随机性
end
```

##### 3.2.2 离散分布
```lua
function distribute_discrete_by_rank(rank_groups, ...)
    -- 为每个Rank创建独立的时间槽
    -- 确保同Rank Item在时间轴上分散
    -- 避免同一时间点出现两个相同Rank的Item
    -- 特别适用于低频音效等需要时间隔离的场景
end
```

### 4. 执行流程
1. **加载配置**：从项目扩展状态读取Rank定义
2. **分组Item**：按Rank分组选中的Item
3. **检查验证**：确认有已标记Rank的Item
4. **显示统计**：显示各Rank的Item数量
5. **复制Item**：为每个组合复制Item
6. **分布排列**：根据选择的分布类型调用对应算法
7. **处理未标记**：单独处理未标记Rank的Item
8. **完成报告**：显示包含详细统计的完成消息

## 与其他脚本的集成

### 1. Define_Item_Rank.lua
- **作用**：为Item标记Rank
- **集成方式**：通过项目扩展状态（ProjExtState）共享配置
- **数据流**：Define_Item_Rank → ProjExtState → Random_Align_Items

### 2. 配置系统
- **配置文件**：`Define_Item_Rank_config.txt`
- **存储格式**：键值对（如`rank1_smile=Glitch`）
- **读取逻辑**：通过`load_rank_config()`函数加载

## 关键函数说明

### 1. 核心函数
```lua
-- 加载Rank配置
function load_rank_config()

-- 获取Item的Rank标记
function get_item_rank(item, config)

-- 按Rank分组Item
function group_items_by_rank(selected_items, config)

-- Rank随机分布算法
function distribute_random_by_rank(rank_groups, combo_count, density_control, 
                                   track_start_time, track_end_time, track)

-- Rank离散分布算法
function distribute_discrete_by_rank(rank_groups, combo_count, density_control,
                                     track_start_time, track_end_time, track)
```

### 2. GUI相关函数
```lua
-- 绘制GUI界面
function draw_gui()

-- 处理GUI事件
function loop()
```

### 3. 辅助函数
```lua
-- 创建新轨道
function create_new_track(track_name)

-- 复制Item到轨道
function copy_item_to_track(item, track, start_time)
```

## 使用工作流程

### 完整流程
1. **准备阶段**：
   - 使用`Define_Item_Rank.lua`为音效Item标记Rank
   - 保存配置到项目

2. **排列阶段**：
   - 运行`Random_Align_Items.lua`
   - 选择"Rank排列"模式
   - 选择分布类型（随机/离散）
   - 设置组合数量和集中度
   - 点击"执行排列"

3. **结果验证**：
   - 检查各Rank的Item分布情况
   - 验证离散分布效果（如低频音效的时间隔离）

### 示例场景
#### 场景1：科幻音效排列
- **Rank定义**：glitch, click sci, sci imp, sci tonal
- **分布类型**：随机分布
- **目标**：创造丰富的科幻音效层次

#### 场景2：枪声音效排列
- **Rank定义**：mech层, snap层, body层
- **分布类型**：离散分布
- **目标**：确保低频body层在时间轴上分散

## 故障排除

### 常见问题
1. **无Rank标记Item**：
   - 原因：未使用Define_Item_Rank标记Item
   - 解决：先运行Define_Item_Rank.lua进行标记

2. **配置未加载**：
   - 原因：项目扩展状态未保存
   - 解决：确保Define_Item_Rank已保存配置

3. **分布效果不理想**：
   - 调整集中度控制参数
   - 尝试不同的分布类型

### 调试信息
- Rank排列执行时会显示详细的统计信息
- 包括各Rank的Item数量、未标记Item数量等
- 完成消息包含排列结果的摘要

## 扩展与维护

### 1. 添加新的排列模式
1. 在`selected_mode`中添加新模式编号
2. 在`draw_gui()`中添加对应的UI控件
3. 在核心执行逻辑中添加新的处理分支
4. 实现对应的排列算法

### 2. 修改Rank系统
1. 更新`get_item_rank()`函数以支持新的标记格式
2. 修改配置加载逻辑以适应新的配置结构
3. 更新分组算法以处理新的Rank类型

### 3. 优化性能
1. 对于大量Item，考虑分批处理
2. 优化时间槽分配算法
3. 减少不必要的Item复制操作

## 设计原则

### 1. 模块化设计
- 每个功能模块独立
- 清晰的函数边界
- 可重用的算法组件

### 2. 用户友好
- 直观的GUI界面
- 清晰的错误提示
- 详细的结果反馈

### 3. 可扩展性
- 易于添加新的排列模式
- 支持自定义Rank标记
- 灵活的分布算法

## 版本历史

### v1.0 - 基础版本
- 齐头排列
- 随机排列

### v2.0 - Rank排列版本（当前）
- 新增Rank排列模式
- 支持随机分布和离散分布
- 集成Define_Item_Rank标记系统
- 完整的Rank分组和分布算法

## 未来改进方向

### 1. 功能增强
- 支持更多分布算法
- 添加可视化预览
- 支持批量处理

### 2. 用户体验
- 更详细的帮助文档
- 预设配置管理
- 快捷键支持

### 3. 性能优化
- 多线程处理
- 内存使用优化
- 缓存机制

---

## 快速参考

### 关键变量
- `selected_mode`：排列模式（1=齐头, 2=随机, 3=Rank）
- `rank_distribution_type`：分布类型（1=随机, 2=离散）
- `WINDOW_H`：窗口高度

### 核心函数调用链
```
loop()
  → draw_gui()
    → 用户点击"执行排列"
      → 根据selected_mode选择分支
        → selected_mode == 3: Rank排列
          → load_rank_config()
          → group_items_by_rank()
          → distribute_*_by_rank()
```

### 配置文件示例
```
rank1_smile=Glitch
rank2_neutral=Click Sci
rank3_sad=Sci Imp
rank4_angry=Sci Tonal
```

---

**最后更新**：2026年4月2日  
**版本**：v2.0  
**维护者**：AI助手  
**适用环境**：REAPER DAW + Lua脚本