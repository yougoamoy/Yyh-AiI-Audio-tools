# 音频工具集合

个人音频制作工具集,包含Reaper脚本和PhasePlant包络生成器。

## 项目结构

```
├── Reaper Script/
│   └── Import_Video_With_Random_Samples.lua  # Reaper视频导入脚本
├── PhasePlant Tool/
│   ├── PhasePlant_Curve_Generator_GUI.py     # PhasePlant包络生成器(GUI版本)
│   └── Generate_PhasePlant_Curves.py         # PhasePlant包络生成器(旧版脚本)
└── README.md
```

## 1. Reaper视频导入脚本

### 功能
- 批量导入视频文件(支持多选)
- 为每个视频生成指定数量的随机样本
- 自动禁用视频音频
- 可配置视频间隔时间
- 智能接续已有视频,避免重叠

### 使用要求
- 需要安装 [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174) 扩展

### 使用方法
1. 在Reaper中: Actions → Show action list → Load ReaScript
2. 选择 `Reaper Script/Import_Video_With_Random_Samples.lua`
3. 执行脚本并按提示操作

## 2. PhasePlant包络生成器

### 功能
- 图形界面生成PhasePlant curve文件
- 多种包络类型:一次性/循环
- 多种曲线形状:线性/指数/S曲线
- 可调节随机变化(0-30%)
- 批量生成多个变体
- 性能优化:智能减少关键点数量

### 使用方法
```bash
python "PhasePlant Tool/PhasePlant_Curve_Generator_GUI.py"
```

### 参数说明
1. **包络类型**: 一次性(ADSR类) / 循环(LFO类)
2. **曲线形状**: 线性 / 指数 / S曲线
3. **变化方向**: 上升 / 下降 / 起伏
4. **变化速度**: 快(8点) / 中(12点) / 慢(16点)
5. **循环次数**: 1-16次(仅循环模式)
6. **随机变化**: 0-30%的随机偏移
7. **生成数量**: 批量生成1-20个变体

### 输出
默认输出到: `D:/Pan&Audio/预设/phaseplant/Curve/Generated/`

## 环境要求

- Python 3.6+
- tkinter (Python标准库)
- Reaper (用于lua脚本)

## 开发日志

- 2026-02-09: 初始版本
  - 完成Reaper视频导入脚本
  - 完成PhasePlant包络生成器GUI版本
  - 添加随机变化和批量生成功能
  - 优化性能,减少75-90%的点数
