import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import json
import math
import os
import random

class CurveGeneratorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("PhasePlant Curve Generator - Demo v0.1")
        self.root.geometry("800x600")
        
        # 默认输出路径
        self.output_dir = "D:/Pan&Audio/预设/phaseplant/Curve/Generated"
        
        # 创建主框架
        main_frame = ttk.Frame(root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # 标题
        title_label = ttk.Label(main_frame, text="PhasePlant 包络生成器", font=("Arial", 16, "bold"))
        title_label.grid(row=0, column=0, columnspan=2, pady=10)
        
        # === 选项区域 ===
        options_frame = ttk.LabelFrame(main_frame, text="参数设置", padding="10")
        options_frame.grid(row=1, column=0, sticky=(tk.W, tk.E, tk.N, tk.S), padx=5, pady=5)
        
        # 1. 类型选择
        ttk.Label(options_frame, text="1. 包络类型:").grid(row=0, column=0, sticky=tk.W, pady=5)
        self.type_var = tk.StringVar(value="one_shot")
        ttk.Radiobutton(options_frame, text="一次性 (One-shot)", variable=self.type_var, 
                       value="one_shot", command=self.update_preview).grid(row=0, column=1, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="循环 (Loop)", variable=self.type_var, 
                       value="loop", command=self.update_preview).grid(row=0, column=2, sticky=tk.W)
        
        # 2. 形状选择
        ttk.Label(options_frame, text="2. 曲线形状:").grid(row=1, column=0, sticky=tk.W, pady=5)
        self.shape_var = tk.StringVar(value="linear")
        ttk.Radiobutton(options_frame, text="线性", variable=self.shape_var, 
                       value="linear", command=self.update_preview).grid(row=1, column=1, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="指数", variable=self.shape_var, 
                       value="exponential", command=self.update_preview).grid(row=1, column=2, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="S曲线", variable=self.shape_var, 
                       value="scurve", command=self.update_preview).grid(row=1, column=3, sticky=tk.W)
        
        # 3. 方向选择
        ttk.Label(options_frame, text="3. 变化方向:").grid(row=2, column=0, sticky=tk.W, pady=5)
        self.direction_var = tk.StringVar(value="rise")
        ttk.Radiobutton(options_frame, text="上升", variable=self.direction_var, 
                       value="rise", command=self.update_preview).grid(row=2, column=1, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="下降", variable=self.direction_var, 
                       value="fall", command=self.update_preview).grid(row=2, column=2, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="起伏", variable=self.direction_var, 
                       value="wave", command=self.update_preview).grid(row=2, column=3, sticky=tk.W)
        
        # 4. 速度选择
        ttk.Label(options_frame, text="4. 变化速度:").grid(row=3, column=0, sticky=tk.W, pady=5)
        self.speed_var = tk.StringVar(value="medium")
        ttk.Radiobutton(options_frame, text="快", variable=self.speed_var, 
                       value="fast", command=self.update_preview).grid(row=3, column=1, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="中", variable=self.speed_var, 
                       value="medium", command=self.update_preview).grid(row=3, column=2, sticky=tk.W)
        ttk.Radiobutton(options_frame, text="慢", variable=self.speed_var, 
                       value="slow", command=self.update_preview).grid(row=3, column=3, sticky=tk.W)
        
        # 5. 循环次数(仅循环模式)
        ttk.Label(options_frame, text="5. 循环次数:").grid(row=4, column=0, sticky=tk.W, pady=5)
        self.cycles_var = tk.IntVar(value=4)
        self.cycles_spinbox = ttk.Spinbox(options_frame, from_=1, to=16, textvariable=self.cycles_var,
                                         width=10, command=self.update_preview)
        self.cycles_spinbox.grid(row=4, column=1, sticky=tk.W)
        ttk.Label(options_frame, text="(仅循环模式有效)").grid(row=4, column=2, columnspan=2, sticky=tk.W)
        
        # 6. 随机变化程度
        ttk.Label(options_frame, text="6. 随机变化:").grid(row=5, column=0, sticky=tk.W, pady=5)
        self.randomness_var = tk.DoubleVar(value=0.0)
        self.randomness_scale = ttk.Scale(options_frame, from_=0, to=0.3, variable=self.randomness_var,
                                         orient=tk.HORIZONTAL, length=150, command=self.update_preview)
        self.randomness_scale.grid(row=5, column=1, columnspan=2, sticky=tk.W)
        self.randomness_label = ttk.Label(options_frame, text="0%")
        self.randomness_label.grid(row=5, column=3, sticky=tk.W)
        
        # 7. 生成数量
        ttk.Label(options_frame, text="7. 生成数量:").grid(row=6, column=0, sticky=tk.W, pady=5)
        self.quantity_var = tk.IntVar(value=1)
        ttk.Spinbox(options_frame, from_=1, to=20, textvariable=self.quantity_var,
                   width=10).grid(row=6, column=1, sticky=tk.W)
        ttk.Label(options_frame, text="(批量生成多个变体)").grid(row=6, column=2, columnspan=2, sticky=tk.W)
        
        # === 预览区域 ===
        preview_frame = ttk.LabelFrame(main_frame, text="曲线预览", padding="10")
        preview_frame.grid(row=1, column=1, sticky=(tk.W, tk.E, tk.N, tk.S), padx=5, pady=5)
        
        self.canvas = tk.Canvas(preview_frame, width=400, height=300, bg="white", highlightthickness=1, highlightbackground="gray")
        self.canvas.pack()
        
        # === 文件名和导出 ===
        export_frame = ttk.Frame(main_frame, padding="10")
        export_frame.grid(row=2, column=0, columnspan=2, sticky=(tk.W, tk.E))
        
        ttk.Label(export_frame, text="文件名:").grid(row=0, column=0, sticky=tk.W, padx=5)
        self.filename_var = tk.StringVar(value="My_Curve")
        ttk.Entry(export_frame, textvariable=self.filename_var, width=30).grid(row=0, column=1, padx=5)
        
        ttk.Button(export_frame, text="选择输出目录", command=self.choose_directory).grid(row=0, column=2, padx=5)
        ttk.Button(export_frame, text="生成并导出", command=self.export_curve, 
                  style="Accent.TButton").grid(row=0, column=3, padx=5)
        
        # 输出路径显示
        self.path_label = ttk.Label(export_frame, text=f"输出目录: {self.output_dir}", foreground="gray")
        self.path_label.grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=5)
        
        # 初始预览
        self.update_preview()
    
    def choose_directory(self):
        """选择输出目录"""
        directory = filedialog.askdirectory(initialdir=self.output_dir)
        if directory:
            self.output_dir = directory
            self.path_label.config(text=f"输出目录: {self.output_dir}")
    
    def generate_curve_points(self):
        """根据选项生成曲线点"""
        curve_type = self.type_var.get()
        shape = self.shape_var.get()
        direction = self.direction_var.get()
        speed = self.speed_var.get()
        cycles = self.cycles_var.get()
        randomness = self.randomness_var.get()
        
        # 根据速度和类型确定关键点数(大幅减少)
        if curve_type == "loop":
            # 循环模式:每个循环4-8个点
            base_points = cycles * 6
        else:
            # 一次性模式:根据速度
            speed_map = {"fast": 8, "medium": 12, "slow": 16}
            base_points = speed_map[speed]
        
        segments = []
        
        for i in range(base_points):
            t = i / (base_points - 1)  # 0.0 到 1.0
            
            # 根据方向计算基础值
            if direction == "rise":
                base_value = t
            elif direction == "fall":
                base_value = 1.0 - t
            elif direction == "wave":
                if curve_type == "loop":
                    base_value = 0.5 + 0.5 * math.sin(2 * math.pi * cycles * t)
                else:
                    base_value = 0.5 + 0.5 * math.sin(math.pi * t)
            
            # 应用形状变换
            if shape == "exponential":
                if direction == "rise":
                    value = base_value ** 2
                elif direction == "fall":
                    value = math.sqrt(base_value) if base_value > 0 else 0
                else:
                    value = base_value
            elif shape == "scurve":
                # S曲线: 使用平滑步函数
                value = base_value * base_value * (3 - 2 * base_value)
            else:  # linear
                value = base_value
            
            # 添加随机变化
            if randomness > 0:
                random_offset = (random.random() - 0.5) * 2 * randomness
                value = max(0, min(1, value + random_offset))
            
            # 转换到-1到1的范围
            y_value = value * 2 - 1
            
            # 计算切线值(tangent) - 根据形状智能调整
            if shape == "exponential":
                st = 0.7
                et = 1.3
            elif shape == "scurve":
                # S曲线在两端缓和,中间陡峭
                progress = abs(0.5 - t) * 2  # 0(中心)到1(边缘)
                st = progress * 0.3
                et = progress * 0.3
            else:  # linear
                st = 1.0
                et = 1.0
            
            segments.append({
                "x": str(round(t, 6)),
                "y": str(round(y_value, 6)),
                "st": str(round(st, 4)),
                "et": str(round(et, 4))
            })
        
        return segments
    
    def update_preview(self, *args):
        """更新预览画布"""
        self.canvas.delete("all")
        
        # 更新随机变化百分比显示
        randomness_percent = int(self.randomness_var.get() * 100)
        self.randomness_label.config(text=f"{randomness_percent}%")
        
        segments = self.generate_curve_points()
        
        # 画布尺寸
        width = 400
        height = 300
        margin = 20
        
        # 绘制网格
        for i in range(5):
            y = margin + i * (height - 2 * margin) / 4
            self.canvas.create_line(margin, y, width - margin, y, fill="lightgray", dash=(2, 2))
        
        for i in range(5):
            x = margin + i * (width - 2 * margin) / 4
            self.canvas.create_line(x, margin, x, height - margin, fill="lightgray", dash=(2, 2))
        
        # 绘制边框和中心线
        self.canvas.create_rectangle(margin, margin, width - margin, height - margin, outline="black")
        center_y = margin + (height - 2 * margin) / 2
        self.canvas.create_line(margin, center_y, width - margin, center_y, fill="gray", dash=(5, 3))
        
        # 在左下角显示点数
        point_count = len(segments)
        self.canvas.create_text(margin + 5, height - margin - 5, anchor=tk.SW, 
                               text=f"点数: {point_count}", fill="gray", font=("Arial", 9))
        
        # 绘制曲线
        if len(segments) > 1:
            coords = []
            for segment in segments:
                x_val = float(segment["x"])
                y_val = float(segment["y"])
                
                # x: 0-1 映射到画布宽度
                x = margin + x_val * (width - 2 * margin)
                # y: -1到1 映射到画布高度 (注意反转,因为画布y轴向下)
                y = margin + (1 - (y_val + 1) / 2) * (height - 2 * margin)
                coords.extend([x, y])
            
            self.canvas.create_line(coords, fill="blue", width=2, smooth=True)
            
            # 绘制关键点(仅在点数较少时显示)
            if len(segments) <= 20:
                for i, segment in enumerate(segments):
                    x_val = float(segment["x"])
                    y_val = float(segment["y"])
                    x = margin + x_val * (width - 2 * margin)
                    y = margin + (1 - (y_val + 1) / 2) * (height - 2 * margin)
                    
                    if i == 0:
                        self.canvas.create_oval(x-3, y-3, x+3, y+3, fill="green", outline="darkgreen")
                    elif i == len(segments) - 1:
                        self.canvas.create_oval(x-3, y-3, x+3, y+3, fill="red", outline="darkred")
                    else:
                        self.canvas.create_oval(x-2, y-2, x+2, y+2, fill="blue", outline="blue")
    
    def export_curve(self):
        """导出曲线文件"""
        filename = self.filename_var.get().strip()
        if not filename:
            messagebox.showerror("错误", "请输入文件名")
            return
        
        # 确保输出目录存在
        os.makedirs(self.output_dir, exist_ok=True)
        
        quantity = self.quantity_var.get()
        exported_files = []
        
        # 批量生成
        for i in range(quantity):
            # 如果生成多个,添加编号后缀
            if quantity > 1:
                file_path = os.path.join(self.output_dir, f"{filename}_{i+1:02d}.curve")
            else:
                file_path = os.path.join(self.output_dir, f"{filename}.curve")
            
            # 每次生成时如果有随机性,会产生不同的结果
            segments = self.generate_curve_points()
            
            # 构建符合PhasePlant格式的JSON结构
            curve_data = {
                "$type": "curve_data",
                "start": "0",
                "length": "1",
                "mode": "off",
                "curve": {
                    "$type": "segmented_curve",
                    "segments": segments
                }
            }
            
            # 写入文件
            try:
                with open(file_path, 'w') as f:
                    json.dump(curve_data, f, indent=2)
                exported_files.append(file_path)
            except Exception as e:
                messagebox.showerror("错误", f"生成文件失败:\n{str(e)}")
                return
        
        # 显示成功消息
        if len(exported_files) == 1:
            messagebox.showinfo("成功", f"曲线文件已生成:\n{exported_files[0]}")
        else:
            messagebox.showinfo("成功", f"成功生成 {len(exported_files)} 个曲线文件:\n{self.output_dir}")

def main():
    root = tk.Tk()
    app = CurveGeneratorGUI(root)
    root.mainloop()

if __name__ == "__main__":
    main()
