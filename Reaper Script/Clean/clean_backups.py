"""
Clean Up REAPER Backups
功能：清理工程旧备份文件，每个 backups 文件夹只保留最新的 .rpp-bak
用法：
  python clean_backups.py <目录路径>          # 扫描指定目录及其子目录
  python clean_backups.py                    # 扫描当前工作目录及其子目录
"""

import os
import sys


def clean_backup_dir(backup_dir):
    """清理指定备份文件夹，只保留最新的 .rpp-bak"""
    bak_files = []
    for name in os.listdir(backup_dir):
        if name.endswith(".rpp-bak"):
            full_path = os.path.join(backup_dir, name)
            try:
                mtime = os.path.getmtime(full_path)
                bak_files.append((full_path, mtime))
            except OSError:
                continue

    if len(bak_files) <= 1:
        return 0

    # 按修改时间倒序排列，最新的在前
    bak_files.sort(key=lambda x: x[1], reverse=True)

    deleted = 0
    for path, _ in bak_files[1:]:
        try:
            os.remove(path)
            print(f"  Deleted: {path}")
            deleted += 1
        except OSError as e:
            print(f"  Failed to delete: {path} ({e})")

    return deleted


def process_directory(root_dir):
    """递归扫描目录，清理每个 backups 子文件夹"""
    total_deleted = 0

    for dirpath, dirnames, _ in os.walk(root_dir):
        for dirname in dirnames:
            if dirname.lower() in ("backups", "backup"):
                backup_path = os.path.join(dirpath, dirname)
                deleted = clean_backup_dir(backup_path)
                if deleted > 0:
                    print(f"\n[Deleted {deleted}] {backup_path}")
                    total_deleted += deleted

    return total_deleted


if __name__ == "__main__":
    if len(sys.argv) > 1:
        target = sys.argv[1]
    else:
        print("Enter the project directory path (or press Enter to scan current directory):")
        target = input("> ").strip()
        if not target:
            target = os.getcwd()

    if not os.path.isdir(target):
        print(f"Error: Invalid directory: {target}")
        input("Press Enter to exit...")
        sys.exit(1)

    print(f"Scanning: {target}\n")
    total = process_directory(target)

    if total == 0:
        print("No backups folder found or no old backups to clean.")

    print(f"\nDone. Total old backups deleted: {total}")
    input("\nPress Enter to exit...")
