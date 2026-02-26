import os
import cv2
import dashscope
from dashscope import MultiModalConversation
import tempfile
import shutil
import tkinter as tk
from tkinter import filedialog, messagebox
from datetime import datetime
import sys
import json

# ================= 配置区域 =================
DASHSCOPE_API_KEY = "sk-c253b9138a1e49a4a8e86506f401a757"  # ⚠️ 请用新 Key 替换泄露的旧 Key
MODEL_NAME = "qwen-vl-max" 
MAX_FRAMES = 10
FRAME_INTERVAL_SEC = 2

# 💰 模型价格配置（元/千 tokens）
MODEL_PRICES = {
    "qwen-vl-max": {"input": 0.020, "output": 0.060},
    "qwen-vl-plus": {"input": 0.008, "output": 0.012},
    "qwen-vl-chat": {"input": 0.008, "output": 0.012},
}

# 📊 你的套餐信息（请修改为实际值）
PACKAGE_TOTAL_YUAN = 500
PACKAGE_START_DATE = "2025-01-01"
PACKAGE_END_DATE = "2025-04-01"

# 📁 固定输出路径 🔧 修改点
OUTPUT_FOLDER = r"D:\Pan&Audio\AI\Qwen\视频理解工具\输出"

# 费用历史记录文件（放在脚本同目录）
COST_LOG_FILE = "cost_history.json"
# ===========================================

def log(message, log_path=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{timestamp}] {message}"
    print(log_line)
    if log_path:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(log_line + "\n")

def load_cost_history():
    if os.path.exists(COST_LOG_FILE):
        try:
            with open(COST_LOG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except:
            return {"total_cost": 0, "call_count": 0, "calls": []}
    return {"total_cost": 0, "call_count": 0, "calls": []}

def save_cost_history(history):
    with open(COST_LOG_FILE, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, indent=2)

def calculate_cost(usage, model_name):
    if model_name not in MODEL_PRICES:
        return 0, "未知模型"
    
    price = MODEL_PRICES[model_name]
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    
    input_cost = (input_tokens / 1000) * price["input"]
    output_cost = (output_tokens / 1000) * price["output"]
    total_cost = input_cost + output_cost
    
    return total_cost, {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + output_tokens,
        "input_cost": input_cost,
        "output_cost": output_cost,
        "total_cost": total_cost
    }

def estimate_remaining(total_cost, package_total, start_date, end_date):
    used_yuan = total_cost
    remaining_yuan = package_total - used_yuan
    
    start = datetime.strptime(start_date, "%Y-%m-%d")
    end = datetime.strptime(end_date, "%Y-%m-%d")
    total_days = (end - start).days
    elapsed_days = (datetime.now() - start).days
    remaining_days = (end - datetime.now()).days
    
    if elapsed_days > 0 and used_yuan > 0:
        daily_avg = used_yuan / elapsed_days
        if daily_avg > 0:
            estimated_runout_days = remaining_yuan / daily_avg
        else:
            estimated_runout_days = remaining_days
    else:
        estimated_runout_days = remaining_days
    
    history = load_cost_history()
    avg_cost_per_call = total_cost / history["call_count"] if history["call_count"] > 0 else 0
    remaining_calls = remaining_yuan / avg_cost_per_call if avg_cost_per_call > 0 else 0
    
    return {
        "package_total": package_total,
        "used_yuan": used_yuan,
        "remaining_yuan": remaining_yuan,
        "usage_percent": (used_yuan / package_total * 100) if package_total > 0 else 0,
        "total_days": total_days,
        "elapsed_days": elapsed_days,
        "remaining_days": remaining_days,
        "estimated_runout_days": min(estimated_runout_days, remaining_days),
        "avg_cost_per_call": avg_cost_per_call,
        "remaining_calls": int(remaining_calls)
    }

def select_video_file():
    """选择视频文件"""
    root = tk.Tk()
    root.withdraw()
    root.attributes('-topmost', True)
    
    file_path = filedialog.askopenfilename(
        title="请选择要描述的视频文件",
        filetypes=[
            ("视频文件", "*.mp4 *.avi *.mov *.mkv *.wmv *.flv"),
            ("所有文件", "*.*")
        ]
    )
    
    root.destroy()
    return file_path

def get_output_file_paths(video_path, output_folder):
    """
    根据视频文件名生成输出文件路径 🔧 新增功能
    例如：D:\Videos\test.mp4 → D:\Output\test_description.txt
    """
    # 获取视频文件名（不含路径）
    video_filename = os.path.basename(video_path)
    # 获取文件名（不含扩展名）
    video_name_no_ext = os.path.splitext(video_filename)[0]
    
    # 生成输出文件名
    result_filename = f"{video_name_no_ext}_description.txt"
    log_filename = f"{video_name_no_ext}_log.txt"
    
    # 生成完整路径
    result_path = os.path.join(output_folder, result_filename)
    log_path = os.path.join(output_folder, log_filename)
    
    return result_path, log_path, video_name_no_ext

def extract_frames(video_path, output_folder, max_frames=10):
    log(f"正在处理视频：{video_path}")
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        raise Exception("无法打开视频文件，请检查路径是否正确")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps
    
    log(f"视频时长：{duration:.2f} 秒，总帧数：{total_frames}, FPS: {fps}")
    
    frame_interval = int(fps * FRAME_INTERVAL_SEC)
    if total_frames / frame_interval > max_frames:
        frame_interval = int(total_frames / max_frames)
    
    expected_frames = total_frames // frame_interval
    log(f"设定抽帧间隔：每 {frame_interval} 帧提取一张，预计提取 {expected_frames} 张")
    
    saved_images = []
    count = 0
    frame_index = 0
    
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        
        if frame_index % frame_interval == 0:
            if count >= max_frames:
                break
            img_path = os.path.join(output_folder, f"frame_{count:04d}.jpg")
            cv2.imwrite(img_path, frame)
            saved_images.append(img_path)
            count += 1
        
        frame_index += 1
    
    cap.release()
    log(f"✅ 成功提取 {len(saved_images)} 张图片")
    return saved_images

def describe_video(image_paths, prompt="请详细描述这个视频里发生了什么内容，包括人物、动作和场景。"):
    dashscope.api_key = DASHSCOPE_API_KEY
    
    log(f"正在准备调用模型：{MODEL_NAME}")
    log(f"待发送图片数量：{len(image_paths)}")
    
    content_list = []
    for img_path in image_paths:
        content_list.append({"image": img_path})
        log(f"  - 添加图片：{os.path.basename(img_path)}")
    content_list.append({"text": prompt})
    
    messages = [
        {
            "role": "user",
            "content": content_list
        }
    ]
    
    log("📡 正在发送请求给百炼模型...")
    try:
        response = MultiModalConversation.call(model=MODEL_NAME, messages=messages)
        
        log(f"📥 收到响应，状态码：{response.status_code}")
        
        if response.status_code == 200:
            raw_content = response.output.choices[0].message.content
            
            if isinstance(raw_content, list):
                description = " ".join([str(item) for item in raw_content])
            elif isinstance(raw_content, dict):
                description = str(raw_content)
            elif raw_content is None:
                description = "无内容返回"
            else:
                description = str(raw_content)
            
            usage_info = None
            cost_info = None
            try:
                usage = response.usage
                log(f"📊 Token 使用情况：{usage}")
                
                cost, cost_detail = calculate_cost(usage, MODEL_NAME)
                usage_info = usage
                cost_info = cost_detail
                log(f"💰 本次调用费用：¥{cost:.4f} 元")
            except Exception as e:
                log(f"⚠️ 无法获取 Token 使用信息：{e}")
            
            return description, usage_info, cost_info
        else:
            log(f"❌ 请求失败：错误码={response.code}, 消息={response.message}")
            return f"请求失败：{response.code}, {response.message}", None, None
            
    except Exception as e:
        log(f"❌ 发生异常：{type(e).__name__}: {str(e)}")
        import traceback
        log(f"详细堆栈：{traceback.format_exc()}")
        return f"发生错误：{str(e)}", None, None

def main():
    print("=" * 60)
    print("       视频描述工具 - 基于阿里云百炼 Qwen-VL")
    print("=" * 60)
    
    # 🔧 检查并确保输出文件夹存在
    if not os.path.exists(OUTPUT_FOLDER):
        try:
            os.makedirs(OUTPUT_FOLDER)
            print(f"✅ 已创建输出文件夹：{OUTPUT_FOLDER}")
        except Exception as e:
            print(f"❌ 无法创建输出文件夹：{e}")
            print("请检查路径权限或手动创建文件夹")
            input("按回车键退出...")
            return
    else:
        print(f"✅ 输出文件夹：{OUTPUT_FOLDER}")
    
    # 1. 选择视频文件
    video_path = select_video_file()
    
    if not video_path:
        print("\n❌ 您取消了文件选择，程序退出。")
        input("按回车键退出...")
        return
    
    print(f"✅ 已选择视频：{video_path}")
    
    # 2. 生成输出文件路径 🔧 新增
    result_path, log_path, video_name = get_output_file_paths(video_path, OUTPUT_FOLDER)
    print(f"📁 结果将保存到：{result_path}")
    print(f"📋 日志将保存到：{log_path}")
    
    # 清空日志文件
    with open(log_path, "w", encoding="utf-8") as f:
        f.write("")
    
    # 3. 初始化日志
    log("程序启动", log_path)
    log(f"模型：{MODEL_NAME}", log_path)
    log(f"API Key 前缀：{DASHSCOPE_API_KEY[:10]}...", log_path)
    log(f"视频文件：{os.path.basename(video_path)}", log_path)
    log(f"输出路径：{result_path}", log_path)
    
    # 4. 加载历史费用
    history = load_cost_history()
    log(f"历史调用次数：{history['call_count']}", log_path)
    log(f"历史总费用：¥{history['total_cost']:.2f} 元", log_path)
    
    # 5. 创建临时文件夹
    temp_dir = tempfile.mkdtemp()
    log(f"创建临时文件夹：{temp_dir}", log_path)
    
    this_call_cost = 0
    
    try:
        # 6. 提取帧
        image_paths = extract_frames(video_path, temp_dir, max_frames=MAX_FRAMES)
        
        if not image_paths:
            log("❌ 未能提取到任何图片", log_path)
            print("未能提取到任何图片。")
            input("按回车键退出...")
            return

        # 7. 调用模型
        result, usage_info, cost_info = describe_video(image_paths)
        
        # 8. 确保 result 是字符串
        if not isinstance(result, str):
            log(f"⚠️ result 类型异常：{type(result)}，强制转换为字符串", log_path)
            result = str(result)
        
        # 9. 更新费用历史
        if cost_info:
            this_call_cost = cost_info["total_cost"]
            history["total_cost"] += this_call_cost
            history["call_count"] += 1
            history["calls"].append({
                "timestamp": datetime.now().isoformat(),
                "video": os.path.basename(video_path),
                "cost": this_call_cost,
                "tokens": cost_info["total_tokens"]
            })
            if len(history["calls"]) > 100:
                history["calls"] = history["calls"][-100:]
            save_cost_history(history)
        
        # 10. 估算剩余额度
        estimate = estimate_remaining(
            history["total_cost"], 
            PACKAGE_TOTAL_YUAN, 
            PACKAGE_START_DATE, 
            PACKAGE_END_DATE
        )
        
        # 11. 输出结果
        log("=" * 40, log_path)
        log("📝 视频描述结果：", log_path)
        log("=" * 40, log_path)
        log(result, log_path)
        log("=" * 40, log_path)
        
        print("\n" + "=" * 40)
        print("📝 视频描述结果：")
        print("=" * 40)
        print(result)
        print("=" * 40)
        
        # 12. 保存到文件 🔧 使用视频名命名
        with open(result_path, "w", encoding="utf-8") as f:
            f.write(f"视频路径：{video_path}\n")
            f.write(f"视频名称：{video_name}\n")
            f.write(f"处理时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"模型：{MODEL_NAME}\n")
            f.write(f"输出文件夹：{OUTPUT_FOLDER}\n")
            if cost_info:
                f.write(f"本次费用：¥{this_call_cost:.4f} 元\n")
                f.write(f"Token 消耗：{cost_info['total_tokens']}\n")
            f.write("=" * 40 + "\n")
            f.write(result)
        
        log(f"💾 结果已保存到 {result_path}", log_path)
        log(f"📋 详细日志已保存到 {log_path}", log_path)
        print(f"\n💾 结果已保存到：{result_path}")
        print(f"📋 详细日志已保存到：{log_path}")
        
        # 13. 费用统计
        print("\n" + "=" * 40)
        print("💰 费用统计")
        print("=" * 40)
        if cost_info:
            print(f"本次调用费用：¥{this_call_cost:.4f} 元")
            print(f"  - 输入 tokens: {cost_info['input_tokens']}")
            print(f"  - 输出 tokens: {cost_info['output_tokens']}")
        print(f"历史总调用次数：{history['call_count']} 次")
        print(f"历史总费用：¥{history['total_cost']:.2f} 元")
        print("=" * 40)
        
        # 14. 套餐额度估算
        print("\n" + "=" * 40)
        print("📊 套餐额度估算")
        print("=" * 40)
        print(f"套餐总额：¥{estimate['package_total']:.2f} 元")
        print(f"已用金额：¥{estimate['used_yuan']:.2f} 元 ({estimate['usage_percent']:.1f}%)")
        print(f"剩余金额：¥{estimate['remaining_yuan']:.2f} 元")
        print(f"套餐剩余天数：{estimate['remaining_days']} 天")
        print(f"平均每次调用成本：¥{estimate['avg_cost_per_call']:.4f} 元")
        print(f"预计还能调用：{estimate['remaining_calls']} 次")
        
        if estimate['remaining_days'] > 0 and estimate['estimated_runout_days'] < estimate['remaining_days']:
            print(f"⚠️ 按当前使用速度，预计 {estimate['estimated_runout_days']:.0f} 天后额度用完")
        else:
            print(f"✅ 按当前使用速度，额度足够用到套餐结束")
        print("=" * 40)
        
        log(f"💰 历史总费用：¥{history['total_cost']:.2f} 元", log_path)
        log(f"📊 剩余额度：¥{estimate['remaining_yuan']:.2f} 元，预计还能调用 {estimate['remaining_calls']} 次", log_path)
        
        # 15. 弹窗提示
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        
        preview = result[:150] + "..." if len(result) > 150 else result
        msg = f"✅ 视频描述已完成！\n\n"
        msg += f"📹 视频：{os.path.basename(video_path)}\n"
        msg += f"📁 保存位置：{OUTPUT_FOLDER}\n"
        msg += f"📄 文件名：{video_name}_description.txt\n"
        if cost_info:
            msg += f"💰 本次费用：¥{this_call_cost:.4f} 元\n"
        msg += f"📊 剩余额度：¥{estimate['remaining_yuan']:.2f} 元\n"
        msg += f"🔢 预计还能调用：{estimate['remaining_calls']} 次\n\n"
        msg += f"预览：{preview}"
        
        messagebox.showinfo("✅ 完成", msg)
        root.destroy()
        
    except Exception as e:
        log(f"❌ 程序发生严重错误：{type(e).__name__}: {str(e)}", log_path)
        import traceback
        log(f"详细堆栈：{traceback.format_exc()}", log_path)
        print(f"\n❌ 程序出错：{str(e)}")
        
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        messagebox.showerror("❌ 错误", f"程序运行出错：{str(e)}")
        root.destroy()
        
    finally:
        try:
            shutil.rmtree(temp_dir)
            log("🗑️ 临时文件已清理", log_path)
        except:
            pass
    
    print("\n" + "=" * 60)
    print("程序运行完成！")
    print("=" * 60)
    input("按回车键退出程序...")

if __name__ == "__main__":
    main()
