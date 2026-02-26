#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
PhasePlant 包络曲线生成器
用于生成各种类型的包络曲线模板
"""

import json
import math
import os
from typing import List, Dict, Tuple

class PhasePlantCurveGenerator:
    """PhasePlant 曲线生成器"""
    
    def __init__(self):
        self.curve_template = {
            "$type": "curve_data",
            "start": "0",
            "length": "1",
            "mode": "off",
            "curve": {
                "$type": "segmented_curve",
                "segments": []
            }
        }
    
    def create_segment(self, x: float, y: float, et: float = 1.0, st: float = 1.0) -> Dict:
        """创建一个曲线段"""
        return {
            "x": str(x),
            "et": str(et),
            "y": str(y),
            "st": str(st)
        }
    
    def generate_linear_curve(self, start_y: float = -1.0, end_y: float = 1.0, 
                            points: int = 20, name: str = "Linear") -> Dict:
        """生成线性包络"""
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        for i in range(points):
            x = i / (points - 1)
            y = start_y + (end_y - start_y) * x
            segment = self.create_segment(x, y)
            curve["curve"]["segments"].append(segment)
        
        return curve
    
    def generate_exponential_curve(self, start_y: float = -1.0, end_y: float = 1.0,
                                  exponent: float = 2.0, points: int = 30, 
                                  name: str = "Exponential") -> Dict:
        """生成指数包络"""
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        for i in range(points):
            x = i / (points - 1)
            # 指数曲线
            progress = math.pow(x, exponent)
            y = start_y + (end_y - start_y) * progress
            segment = self.create_segment(x, y)
            curve["curve"]["segments"].append(segment)
        
        return curve
    
    def generate_sine_curve(self, cycles: float = 1.0, amplitude: float = 1.0,
                          offset: float = 0.0, points: int = 50,
                          name: str = "Sine") -> Dict:
        """生成正弦包络"""
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        for i in range(points):
            x = i / (points - 1)
            y = offset + amplitude * math.sin(2 * math.pi * cycles * x)
            # 限制在 -1 到 1 之间
            y = max(-1.0, min(1.0, y))
            segment = self.create_segment(x, y)
            curve["curve"]["segments"].append(segment)
        
        return curve
    
    def generate_adsr_curve(self, attack: float = 0.1, decay: float = 0.2,
                          sustain_level: float = 0.7, sustain_time: float = 0.4,
                          release: float = 0.3, name: str = "ADSR") -> Dict:
        """生成 ADSR 包络"""
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        # Attack 阶段
        attack_points = max(5, int(attack * 30))
        for i in range(attack_points):
            x = (i / attack_points) * attack
            y = -1.0 + (1.0 + 1.0) * (i / attack_points)
            et = 1.5 if i < attack_points - 1 else 1.0  # 曲线张力
            segment = self.create_segment(x, y, et=et)
            curve["curve"]["segments"].append(segment)
        
        # Decay 阶段
        decay_points = max(5, int(decay * 30))
        for i in range(decay_points):
            x = attack + (i / decay_points) * decay
            y = 1.0 - (1.0 - sustain_level * 2 + 1.0) * (i / decay_points)
            segment = self.create_segment(x, y)
            curve["curve"]["segments"].append(segment)
        
        # Sustain 阶段
        sustain_y = sustain_level * 2 - 1.0
        sustain_points = max(5, int(sustain_time * 30))
        for i in range(sustain_points):
            x = attack + decay + (i / sustain_points) * sustain_time
            segment = self.create_segment(x, sustain_y, et=0)
            curve["curve"]["segments"].append(segment)
        
        # Release 阶段
        release_points = max(5, int(release * 30))
        for i in range(release_points + 1):
            x = attack + decay + sustain_time + (i / release_points) * release
            x = min(x, 1.0)
            y = sustain_y - (sustain_y + 1.0) * (i / release_points)
            segment = self.create_segment(x, y)
            curve["curve"]["segments"].append(segment)
        
        return curve
    
    def generate_random_curve(self, points: int = 30, smoothness: float = 0.5,
                            name: str = "Random") -> Dict:
        """生成随机包络"""
        import random
        
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        # 生成随机控制点
        control_points = []
        num_control_points = max(5, int(points * 0.3))
        
        for i in range(num_control_points):
            x = i / (num_control_points - 1)
            y = random.uniform(-1.0, 1.0)
            control_points.append((x, y))
        
        # 在控制点之间插值
        for i in range(points):
            x = i / (points - 1)
            
            # 找到最近的两个控制点
            y = self._interpolate_point(x, control_points)
            
            et = random.uniform(0.5, 1.5) if smoothness > 0.5 else random.uniform(0, 2.0)
            segment = self.create_segment(x, y, et=et)
            curve["curve"]["segments"].append(segment)
        
        return curve
    
    def _interpolate_point(self, x: float, control_points: List[Tuple[float, float]]) -> float:
        """在控制点之间插值"""
        if x <= control_points[0][0]:
            return control_points[0][1]
        if x >= control_points[-1][0]:
            return control_points[-1][1]
        
        for i in range(len(control_points) - 1):
            x1, y1 = control_points[i]
            x2, y2 = control_points[i + 1]
            
            if x1 <= x <= x2:
                # 线性插值
                t = (x - x1) / (x2 - x1)
                return y1 + (y2 - y1) * t
        
        return 0.0
    
    def generate_bounce_curve(self, bounces: int = 3, decay: float = 0.7,
                            name: str = "Bounce") -> Dict:
        """生成弹跳包络"""
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        points_per_bounce = 20
        current_amplitude = 1.0
        
        for bounce in range(bounces):
            # 上升
            for i in range(points_per_bounce // 2):
                x = (bounce * points_per_bounce + i) / (bounces * points_per_bounce)
                progress = i / (points_per_bounce // 2)
                y = -1.0 + current_amplitude * progress
                et = 2.0  # 快速上升
                segment = self.create_segment(x, y, et=et)
                curve["curve"]["segments"].append(segment)
            
            # 下降
            for i in range(points_per_bounce // 2):
                x = (bounce * points_per_bounce + points_per_bounce // 2 + i) / (bounces * points_per_bounce)
                progress = i / (points_per_bounce // 2)
                y = -1.0 + current_amplitude * (1.0 - progress)
                et = 0.5  # 快速下降
                segment = self.create_segment(x, y, et=et)
                curve["curve"]["segments"].append(segment)
            
            current_amplitude *= decay
        
        # 最后稳定在底部
        segment = self.create_segment(1.0, -1.0, et=0)
        curve["curve"]["segments"].append(segment)
        
        return curve
    
    def generate_step_curve(self, steps: int = 5, name: str = "Step") -> Dict:
        """生成阶梯包络"""
        curve = self.curve_template.copy()
        curve["curve"] = {"$type": "segmented_curve", "segments": []}
        
        for step in range(steps):
            x_start = step / steps
            x_end = (step + 1) / steps
            y = -1.0 + (2.0 * step / (steps - 1))
            
            # 每个阶梯的起点
            segment = self.create_segment(x_start, y, et=0)
            curve["curve"]["segments"].append(segment)
            
            # 每个阶梯的终点
            segment = self.create_segment(x_end, y, et=0)
            curve["curve"]["segments"].append(segment)
        
        return curve
    
    def save_curve(self, curve: Dict, filepath: str):
        """保存曲线到文件"""
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(curve, f, indent='\t')
        print(f"已生成: {filepath}")


def main():
    """主函数 - 生成各种类型的包络"""
    
    # 创建输出目录
    output_dir = "D:/Pan&Audio/预设/phaseplant/Curve/Generated"
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    generator = PhasePlantCurveGenerator()
    
    # 1. 线性包络系列
    print("\n生成线性包络...")
    curves = [
        (generator.generate_linear_curve(-1.0, 1.0, 20), "Linear_Rise.curve"),
        (generator.generate_linear_curve(1.0, -1.0, 20), "Linear_Fall.curve"),
        (generator.generate_linear_curve(0.0, 1.0, 20), "Linear_Rise_Half.curve"),
    ]
    
    # 2. 指数包络系列
    print("生成指数包络...")
    curves.extend([
        (generator.generate_exponential_curve(-1.0, 1.0, 2.0, 30), "Exponential_Smooth.curve"),
        (generator.generate_exponential_curve(-1.0, 1.0, 3.0, 30), "Exponential_Sharp.curve"),
        (generator.generate_exponential_curve(-1.0, 1.0, 0.5, 30), "Exponential_Inverse.curve"),
    ])
    
    # 3. 正弦波包络系列
    print("生成正弦波包络...")
    curves.extend([
        (generator.generate_sine_curve(1.0, 1.0, 0.0, 50), "Sine_1Cycle.curve"),
        (generator.generate_sine_curve(2.0, 1.0, 0.0, 50), "Sine_2Cycles.curve"),
        (generator.generate_sine_curve(3.0, 1.0, 0.0, 50), "Sine_3Cycles.curve"),
        (generator.generate_sine_curve(0.5, 0.8, -0.2, 50), "Sine_Slow_Offset.curve"),
    ])
    
    # 4. ADSR 包络系列
    print("生成 ADSR 包络...")
    curves.extend([
        (generator.generate_adsr_curve(0.1, 0.2, 0.7, 0.4, 0.3), "ADSR_Standard.curve"),
        (generator.generate_adsr_curve(0.05, 0.15, 0.8, 0.5, 0.3), "ADSR_Fast_Attack.curve"),
        (generator.generate_adsr_curve(0.2, 0.3, 0.6, 0.3, 0.2), "ADSR_Slow_Attack.curve"),
        (generator.generate_adsr_curve(0.1, 0.1, 0.5, 0.2, 0.6), "ADSR_Long_Release.curve"),
    ])
    
    # 5. 随机包络系列
    print("生成随机包络...")
    for i in range(5):
        curve = generator.generate_random_curve(30, 0.5)
        curves.append((curve, f"Random_{i+1:02d}.curve"))
    
    # 6. 弹跳包络系列
    print("生成弹跳包络...")
    curves.extend([
        (generator.generate_bounce_curve(3, 0.7), "Bounce_3Times.curve"),
        (generator.generate_bounce_curve(5, 0.6), "Bounce_5Times.curve"),
        (generator.generate_bounce_curve(2, 0.8), "Bounce_2Times_Slow.curve"),
    ])
    
    # 7. 阶梯包络系列
    print("生成阶梯包络...")
    curves.extend([
        (generator.generate_step_curve(4), "Step_4Levels.curve"),
        (generator.generate_step_curve(8), "Step_8Levels.curve"),
        (generator.generate_step_curve(16), "Step_16Levels.curve"),
    ])
    
    # 保存所有曲线
    print("\n开始保存文件...")
    for curve, filename in curves:
        filepath = os.path.join(output_dir, filename)
        generator.save_curve(curve, filepath)
    
    print(f"\n✅ 完成! 共生成 {len(curves)} 个包络文件")
    print(f"输出目录: {output_dir}")


if __name__ == "__main__":
    main()
