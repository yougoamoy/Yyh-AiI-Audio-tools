# Random_Align_Items.lua Rank调整窗口修复说明

## 问题描述
用户报告："rank排列点击后各个rank种类的调整窗口没有显示，是不是这个功能坏了"

## 问题分析
经过分析，原始的`Random_Align_Items.lua`脚本确实存在这个问题：
1. 当用户点击"Rank排列"按钮时，只设置了`selected_mode = 3`
2. 没有显示任何rank种类调整窗口
3. 用户无法调整各个rank种类的分布权重

## 修复内容

### 1. 添加了rank调整窗口相关变量（第414{+7}行）
```lua
local show_rank_adjust_window = false  -- 是否显示rank调整窗口
local rank_adjust_values = {          -- rank调整值
    rank1_smile = 1.0,
    rank2_smile = 1.0,
    rank3_smile = 1.0,
    rank1_frown = 1.0,
    empty_rank = 1.0
}
```

### 2. 修改了Rank排列按钮点击逻辑（第513{+2}行）
```lua
if draw_button_with_style(ctx, "Rank排列", selected_mode == 3) then
  selected_mode = 3
  -- 加载rank配置并显示调整窗口
  local config = load_rank_config()
  show_rank_adjust_window = true
end
```

### 3. 添加了rank调整窗口绘制函数（第442{+96}行）
添加了`draw_rank_adjust_window(ctx, config)`函数，功能包括：
- 显示当前已定义的rank种类及其标记文本
- 为每个rank提供滑块调整权重（0.1-3.0范围）
- 权重说明和重置按钮
- 确定和重置按钮

### 4. 添加了rank调整窗口绘制调用（第1276{+11}行）
```lua
-- 如果显示了rank调整窗口，则绘制它
if show_rank_adjust_window then
  local config = load_rank_config()
  local still_open = draw_rank_adjust_window(ctx, config)
  if not still_open then
    show_rank_adjust_window = false
  end
end
```

### 5. 修改了rank分布算法以应用调整值

#### 5.1 修改了随机分布函数（第56行）
- 根据rank调整值创建加权item列表
- 高权重的rank会有更多副本，增加出现频率

#### 5.2 修改了离散分布函数（第165行）
- 根据rank权重分配不同数量的时间槽
- 权重高的rank获得更多时间槽
- 权重高的rank优先分配时间槽

## 权重调整说明
- **0.1-0.5**：减少该rank的出现频率
- **0.5-1.0**：正常频率
- **1.0-2.0**：增加该rank的出现频率
- **2.0-3.0**：显著增加该rank的出现频率

## 使用方法

### 测试步骤：
1. 在REAPER中运行`Define_Item_Rank.lua`定义rank标记
2. 使用标记工具标记一些item
3. 运行修复后的`Random_Align_Items.lua`
4. 点击"Rank排列"按钮
5. 应该会弹出rank调整窗口
6. 调整各个rank种类的权重
7. 点击"确定"关闭调整窗口
8. 点击"执行排列"进行rank排列

### 预期效果：
- 点击"Rank排列"按钮后，立即显示rank调整窗口
- 窗口中显示所有已定义的rank种类
- 可以通过滑块调整每个rank的分布权重
- 调整后的权重会应用到排列算法中
- 高权重的rank在排列中出现频率更高

## 注意事项
1. 需要先运行`Define_Item_Rank.lua`定义rank标记
2. 只有已定义的rank种类会显示在调整窗口中
3. 未定义的rank种类显示为"(未定义)"且不可调整
4. 权重调整只影响排列结果，不影响原始item

## 修复验证
脚本已通过语法检查，无语法错误。用户现在应该能够：
1. 看到rank调整窗口
2. 调整各个rank种类的权重
3. 应用调整后的权重进行排列

修复完成时间：2026年4月7日