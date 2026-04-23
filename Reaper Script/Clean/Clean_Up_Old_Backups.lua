-- Clean Up Old Backups
-- 功能：清理工程旧备份文件，每个 backups 文件夹只保留最新的 .rpp-bak
-- 支持递归扫描子文件夹，自动处理含 & 和中文的路径

reaper.Undo_BeginBlock()

-- ================================================================
-- 工具函数
-- ================================================================

-- 将路径写入临时文件（UTF-8），供 PowerShell 读取
local tmp_file = os.getenv("TEMP") .. "\\reaper_cleanup_path.txt"

local function write_path_to_tmp(path)
  local f = io.open(tmp_file, "w")
  if not f then return false end
  f:write(path)
  f:close()
  return true
end

-- 调用 PowerShell 清理指定备份文件夹
local function clean_backup_dir(backup_dir)
  if not write_path_to_tmp(backup_dir) then return 0 end

  local ps_script = "$dir = Get-Content -LiteralPath $env:TEMP\\reaper_cleanup_path.txt -Encoding UTF8; "
    .. "$files = Get-ChildItem -LiteralPath $dir -Filter *.rpp-bak -ErrorAction SilentlyContinue | "
    .. "Sort-Object LastWriteTime -Descending; "
    .. "if ($files.Count -gt 1) { "
    .. "$files | Select-Object -Skip 1 | Remove-Item -Force; "
    .. "Write-Output ($files.Count - 1) "
    .. "} elseif ($files.Count -eq 0) { Write-Output 0 } else { Write-Output 0 }"

  local handle = io.popen(
    'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand '
    .. reaper.JS_StringToBase64(ps_script)
  )

  local count = 0
  if handle then
    local result = handle:read("*a")
    handle:close()
    count = tonumber(result:match("%d+")) or 0
  end
  return count
end

-- ================================================================
-- 主逻辑
-- ================================================================

local total_deleted = 0
local proj_file = reaper.GetProjectName(0, "")
local proj_dir = proj_file:match("(.+)[/\\]")

if not proj_dir or proj_dir == "" then
  reaper.ShowConsoleMsg("Error: Project file not found. Please save the project first.\n")
  reaper.Undo_EndBlock("Clean Up Old Backups", -1)
  return
end

-- 处理目录及其子目录
local function process_dir(dir)
  -- 检查 backups 子文件夹
  local i = 0
  while true do
    local subdir = reaper.EnumerateSubdirectories(dir, i)
    if not subdir then break end
    if subdir == "backups" or subdir == "Backup" then
      local backup_path = dir .. "\\" .. subdir
      local count = clean_backup_dir(backup_path)
      if count > 0 then
        total_deleted = total_deleted + count
        reaper.ShowConsoleMsg("[Deleted " .. count .. "] " .. backup_path .. "\n")
      end
    end
    i = i + 1
  end

  -- 递归子目录
  local j = 0
  while true do
    local subdir = reaper.EnumerateSubdirectories(dir, j)
    if not subdir then break end
    process_dir(dir .. "\\" .. subdir)
    j = j + 1
  end
end

process_dir(proj_dir)

-- 清理临时文件
os.remove(tmp_file)

reaper.Undo_EndBlock("Clean Up Old Backups: deleted " .. total_deleted .. " files", -1)

if total_deleted > 0 then
  reaper.ShowConsoleMsg("\nBackup cleanup complete: " .. total_deleted .. " old backup(s) deleted.\n")
else
  reaper.ShowConsoleMsg("No old backups to clean.\n")
end
