--[[
Random Layer Spreader (Selected Items -> Time Zones)

What it does:
- Only processes SELECTED media items
- Randomly groups selected items into time zones
- Places each zone as a tight vertical layer stack on N fixed "layer tracks"
  (no gaps between layers inside a zone; items go to tracks 1..k)
- Zones are separated in time by (max item length in that zone + gap seconds)
- NO markers (cleaner visual)
- Optionally colors items per zone for readability

Workflow:
1) Select scattered items anywhere in your project
2) Put edit cursor where you want Zone 1 to start
3) Run script, input: tracks-per-zone and gap seconds
4) Script creates a compact folder with N layer tracks, then moves items into zones

Note:
- This script MOVES selected items to new tracks.
- It does NOT delete original tracks.
--]]

local CONFIG = {
  default_tracks_per_zone = 3,
  default_gap_seconds = 2.0,
  color_items_by_zone = true,
}

local ZONE_COLORS = {
  {200, 100, 100},
  {100, 200, 100},
  {100, 100, 200},
  {200, 200, 100},
  {200, 100, 200},
  {100, 200, 200},
  {220, 150, 100},
  {150, 100, 220},
}

local EXT_SECTION = "Yyh_RandomLayerSpreader"
local KEY_TRACKS_PER_ZONE = "tracks_per_zone"
local KEY_GAP_SECONDS = "gap_seconds"

local function shuffle(t)
  math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000))
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

local function getSelectedItems()
  local items = {}
  local count = reaper.CountSelectedMediaItems(0)
  for i = 0, count - 1 do
    items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  return items
end

local function getItemLength(item)
  return reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
end

local function setItemPosition(item, pos)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
end

local function setItemColor(item, r, g, b)
  local c = reaper.ColorToNative(r, g, b) | 0x1000000
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", c)
end

local function getConfig(max_items)
  local saved_n = tonumber(reaper.GetExtState(EXT_SECTION, KEY_TRACKS_PER_ZONE))
  local saved_gap = tonumber(reaper.GetExtState(EXT_SECTION, KEY_GAP_SECONDS))

  local n = saved_n or CONFIG.default_tracks_per_zone
  local gap = saved_gap or CONFIG.default_gap_seconds

  local retval, input = reaper.GetUserInputs(
    "Random Layer Spreader",
    2,
    "Tracks per zone (1-" .. max_items .. "),Gap seconds",
    string.format("%d,%.1f", n, gap)
  )
  if not retval then return nil, nil end

  local n_str, gap_str = input:match("([^,]+),([^,]+)")
  n = tonumber(n_str)
  gap = tonumber(gap_str)

  if not n or n < 1 or n > max_items then
    reaper.ShowMessageBox("Invalid Tracks per zone.", "Error", 0)
    return nil, nil
  end
  if not gap or gap < 0 then gap = CONFIG.default_gap_seconds end

  reaper.SetExtState(EXT_SECTION, KEY_TRACKS_PER_ZONE, tostring(n), false)
  reaper.SetExtState(EXT_SECTION, KEY_GAP_SECONDS, tostring(gap), false)

  return n, gap
end

local function trackNameExists(name)
  local total = reaper.CountTracks(0)
  for i = 0, total - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tr_name = reaper.GetTrackName(tr)
    if tr_name == name then return true end
  end
  return false
end

local function makeUniqueName(base)
  if not trackNameExists(base) then return base end
  local i = 2
  while true do
    local candidate = string.format("%s (%d)", base, i)
    if not trackNameExists(candidate) then return candidate end
    i = i + 1
  end
end

local function createFolderWithLayerTracks(n)
  local total = reaper.CountTracks(0)

  -- parent folder track
  reaper.InsertTrackAtIndex(total, false)
  local parent = reaper.GetTrack(0, total)
  local parent_name = makeUniqueName("Layer Zones")
  reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", parent_name, true)
  reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)

  -- children
  local layer_tracks = {}
  for i = 1, n do
    reaper.InsertTrackAtIndex(total + i, false)
    local child = reaper.GetTrack(0, total + i)
    reaper.GetSetMediaTrackInfo_String(child, "P_NAME", string.format("L%02d", i), true)
    if i == n then
      reaper.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", -1)
    else
      reaper.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", 0)
    end
    layer_tracks[i] = child
  end

  return parent, layer_tracks
end

local function main()
  local items = getSelectedItems()
  local item_count = #items

  if item_count == 0 then
    reaper.ShowMessageBox("Select some media items first.", "Random Layer Spreader", 0)
    return
  end

  local n, gap = getConfig(item_count)
  if not n then return end

  -- randomize items
  shuffle(items)

  local zone_count = math.ceil(item_count / n)
  local start_pos = reaper.GetCursorPosition()

  reaper.Undo_BeginBlock()

  -- create compact layer area
  local _, layer_tracks = createFolderWithLayerTracks(n)

  local idx = 1
  local zone_start = start_pos

  for zone = 1, zone_count do
    -- collect this zone's items (up to n)
    local group = {}
    for layer = 1, n do
      if idx > item_count then break end
      group[#group + 1] = items[idx]
      idx = idx + 1
    end

    -- compute max length
    local max_len = 0
    for _, it in ipairs(group) do
      local len = getItemLength(it)
      if len > max_len then max_len = len end
    end

    -- assign to tracks 1..k (no gaps)
    local color = ZONE_COLORS[((zone - 1) % #ZONE_COLORS) + 1]
    for layer = 1, #group do
      local it = group[layer]
      reaper.MoveMediaItemToTrack(it, layer_tracks[layer])
      setItemPosition(it, zone_start)
      if CONFIG.color_items_by_zone then
        setItemColor(it, color[1], color[2], color[3])
      end
    end

    zone_start = zone_start + max_len + gap
  end

  reaper.Undo_EndBlock("Random Layer Spreader (selected items -> zones)", -1)
  reaper.UpdateArrange()

  reaper.ShowConsoleMsg(string.format(
    "Random Layer Spreader done. Selected=%d, TracksPerZone=%d, Zones=%d, Gap=%.1fs\n",
    item_count, n, zone_count, gap
  ))
end

main()
