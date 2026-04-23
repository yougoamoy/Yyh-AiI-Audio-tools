-- Clean Up Project
-- 功能：清理 REAPER 工程
-- 1. 删除所有 Mute 状态的 Item
-- 2. 删除所有空轨道
-- 3. 按颜色分组排列（同颜色item放在同一轨，从左到右从上到下）
-- 备份清理请使用独立脚本：Clean_Up_Old_Backups.lua

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- ================================================================
-- 第一步：删除所有 Mute 状态的 Item（跳过第一条轨道）
-- ================================================================
local muted_count = 0
local num_items = reaper.CountMediaItems(0)
local first_track = reaper.GetTrack(0, 0)

for i = num_items - 1, 0, -1 do
  local item = reaper.GetMediaItem(0, i)
  local item_track = reaper.GetMediaItem_Track(item)
  if item_track ~= first_track then
    local is_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
    if is_muted == 1 then
      reaper.DeleteTrackMediaItem(item_track, item)
      muted_count = muted_count + 1
    end
  end
end

-- ================================================================
-- 第二步：删除所有空轨道（跳过第一条轨道）
-- ================================================================
local empty_count = 0
local num_tracks = reaper.CountTracks(0)

for i = num_tracks - 1, 1, -1 do
  local track = reaper.GetTrack(0, i)
  local num_track_items = reaper.CountTrackMediaItems(track)
  if num_track_items == 0 then
    reaper.DeleteTrack(track)
    empty_count = empty_count + 1
  end
end

-- ================================================================
-- 第三步：按颜色分组排列
-- ================================================================

local function get_item_color(item)
  local color = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
  if color == 0 then return "default" end
  -- REAPER 颜色格式: 0x01000000 + 0x00RRGGBB
  local r = math.floor(color / 65536) % 256
  local g = math.floor(color / 256) % 256
  local b = color % 256
  return string.format("#%02X%02X%02X", r, g, b)
end

local groups = {}
num_items = reaper.CountMediaItems(0)
first_track = reaper.GetTrack(0, 0)

for i = 0, num_items - 1 do
  local item = reaper.GetMediaItem(0, i)
  local item_track = reaper.GetMediaItem_Track(item)
  if item_track ~= first_track then
    local color_key = get_item_color(item)
    if not groups[color_key] then groups[color_key] = {} end
    table.insert(groups[color_key], item)
  end
end

-- 按组内最左侧item的位置排序
local group_order = {}
for color_key, items in pairs(groups) do
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  end)
  table.insert(group_order, {color_key = color_key, items = items, pos = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")})
end

table.sort(group_order, function(a, b) return a.pos < b.pos end)

-- 在第一条轨道之后创建新轨道并移动item
local track_count = 0
for i, group in ipairs(group_order) do
  reaper.InsertTrackAtIndex(i, false)
  local track = reaper.GetTrack(0, i)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", group.color_key, true)

  for _, item in ipairs(group.items) do
    reaper.MoveMediaItemToTrack(item, track)
  end
  track_count = track_count + 1
end

-- 删除第一条轨道之后的旧轨道
local total_tracks = reaper.CountTracks(0)
for i = total_tracks - 1, 1 + track_count, -1 do
  reaper.DeleteTrack(reaper.GetTrack(0, i))
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock("Clean Up Project: muted(" .. muted_count .. ") empty_tracks(" .. empty_count .. ") groups(" .. track_count .. ")", -1)

reaper.ShowConsoleMsg("Clean Up Complete:\n")
reaper.ShowConsoleMsg("  Muted items deleted: " .. muted_count .. "\n")
reaper.ShowConsoleMsg("  Empty tracks deleted: " .. empty_count .. "\n")
reaper.ShowConsoleMsg("  Tracks rearranged: " .. track_count .. "\n")
