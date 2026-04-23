--[[
Random Layer Spreader (Selected Items -> Time Zones)

Core:
- Processes SELECTED media items
- Randomly groups into time zones
- Each zone is a tight vertical layer stack on N fixed layer tracks (L01..L0N)
- Zones separated by (max item length in that zone + gap seconds)
- No markers
- Optional item coloring by zone

New in this version:
- "Re-randomize" mode: keep existing zone start times, but RANDOMIZE ACROSS ZONES and reassign

How to use:
- Create/Spread:
  1) Select scattered items anywhere
  2) Put edit cursor where Zone 1 should start
  3) Run script -> choose mode 1

- Re-randomize:
  1) After you already created zones with this script
  2) Run script -> choose mode 2
  3) It will reshuffle assignments inside each zone (no time shift)

Notes:
- This script MOVES items to layer tracks.
- It does NOT delete your original tracks.
--]]

local CONFIG = {
  default_tracks_per_zone = 3,
  default_gap_seconds = 2.0,
  color_items_by_zone = true,

  parent_name_base = "Layer Zones",
  child_name_fmt = "L%02d",
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
local KEY_STATE = "state" -- serialized zones state

-- ============================================================
-- Helpers
-- ============================================================

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

local function getItemGUID(item)
  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid
end

local function setItemColor(item, r, g, b)
  -- 0x1000000 enables custom color flag
  local c = (reaper.ColorToNative(r, g, b) | 0x1000000)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", c)
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
  local parent_name = makeUniqueName(CONFIG.parent_name_base)
  reaper.GetSetMediaTrackInfo_String(parent, "P_NAME", parent_name, true)
  reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)

  -- children
  local layer_tracks = {}
  for i = 1, n do
    reaper.InsertTrackAtIndex(total + i, false)
    local child = reaper.GetTrack(0, total + i)
    reaper.GetSetMediaTrackInfo_String(child, "P_NAME", string.format(CONFIG.child_name_fmt, i), true)
    if i == n then
      reaper.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", -1)
    else
      reaper.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", 0)
    end
    layer_tracks[i] = child
  end

  return parent, layer_tracks
end

local function findLatestLayerFolderAndChildren()
  -- Finds the last parent track whose name starts with CONFIG.parent_name_base
  -- and then reads the immediate next tracks as L01..L0N based on saved N.
  local n = tonumber(reaper.GetExtState(EXT_SECTION, KEY_TRACKS_PER_ZONE))
  if not n or n < 1 then return nil, nil, nil end

  local total = reaper.CountTracks(0)
  local parent_idx = nil
  local parent = nil

  for i = total - 1, 0, -1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name and name:sub(1, #CONFIG.parent_name_base) == CONFIG.parent_name_base then
      parent_idx = i
      parent = tr
      break
    end
  end

  if not parent then return nil, nil, nil end

  local children = {}
  for i = 1, n do
    local tr = reaper.GetTrack(0, parent_idx + i)
    if not tr then return nil, nil, nil end
    children[i] = tr
  end

  return parent, children, n
end

local function buildItemMapByGUID()
  local map = {}
  local item_count = reaper.CountMediaItems(0)
  for i = 0, item_count - 1 do
    local it = reaper.GetMediaItem(0, i)
    local guid = getItemGUID(it)
    if guid and guid ~= "" then
      map[guid] = it
    end
  end
  return map
end

-- ============================================================
-- State serialization
-- Format:
--   n=<N>;gap=<gap>;zones=<Z>|z:<zone>:<start>:<guid>,<guid>,...
-- Example:
--   n=3;gap=2.0;zones=4|z:1:10.0:{GUID},{GUID},{GUID}|z:2:15.2:{GUID},...
-- ============================================================

local function serializeState(n, gap, zones)
  local header = string.format("n=%d;gap=%.6f;zones=%d", n, gap, #zones)
  local parts = {header}
  for _, z in ipairs(zones) do
    local guids = table.concat(z.guids, ",")
    parts[#parts + 1] = string.format("z:%d:%.6f:%s", z.zone, z.start, guids)
  end
  return table.concat(parts, "|")
end

local function parseState(raw)
  if not raw or raw == "" then return nil end

  local parts = {}
  for token in raw:gmatch("[^|]+") do
    parts[#parts + 1] = token
  end
  if #parts == 0 then return nil end

  local header = parts[1]
  local n_str = header:match("n=(%d+)")
  local gap_str = header:match("gap=([%d%.%-]+)")
  local zones_str = header:match("zones=(%d+)")

  local n = tonumber(n_str)
  local gap = tonumber(gap_str)
  local zc = tonumber(zones_str)
  if not n or not gap or not zc then return nil end

  local zones = {}
  for i = 2, #parts do
    local zone, start, guids_csv = parts[i]:match("z:(%d+):([%d%.%-]+):(.+)")
    zone = tonumber(zone)
    start = tonumber(start)
    if zone and start and guids_csv then
      local guids = {}
      for g in guids_csv:gmatch("[^,]+") do
        guids[#guids + 1] = g
      end
      zones[#zones + 1] = {zone = zone, start = start, guids = guids}
    end
  end

  -- if zones list is empty, treat as invalid
  if #zones == 0 then return nil end

  return {n = n, gap = gap, zones = zones}
end

-- ============================================================
-- UI
-- ============================================================

local function getModeAndConfig(max_items)
  local saved_n = tonumber(reaper.GetExtState(EXT_SECTION, KEY_TRACKS_PER_ZONE))
  local saved_gap = tonumber(reaper.GetExtState(EXT_SECTION, KEY_GAP_SECONDS))

  local n = saved_n or CONFIG.default_tracks_per_zone
  local gap = saved_gap or CONFIG.default_gap_seconds

  local retval, input = reaper.GetUserInputs(
    "Random Layer Spreader",
    3,
    "Mode (1=Create,2=Re-randomize),Tracks per zone (1-" .. max_items .. "),Gap seconds",
    string.format("1,%d,%.1f", n, gap)
  )
  if not retval then return nil end

  local mode_str, n_str, gap_str = input:match("([^,]+),([^,]+),([^,]+)")
  local mode = tonumber(mode_str)
  n = tonumber(n_str)
  gap = tonumber(gap_str)

  if mode ~= 1 and mode ~= 2 then
    reaper.ShowMessageBox("Mode must be 1 or 2", "Error", 0)
    return nil
  end

  if not n or n < 1 or n > max_items then
    reaper.ShowMessageBox("Invalid Tracks per zone", "Error", 0)
    return nil
  end

  if not gap or gap < 0 then gap = CONFIG.default_gap_seconds end

  reaper.SetExtState(EXT_SECTION, KEY_TRACKS_PER_ZONE, tostring(n), false)
  reaper.SetExtState(EXT_SECTION, KEY_GAP_SECONDS, tostring(gap), false)

  return {mode = mode, n = n, gap = gap}
end

-- ============================================================
-- Actions
-- ============================================================

local function actionCreate(items, n, gap)
  shuffle(items)

  local zone_count = math.ceil(#items / n)
  local start_pos = reaper.GetCursorPosition()

  local _, layer_tracks = createFolderWithLayerTracks(n)

  local zones = {}

  local idx = 1
  local zone_start = start_pos

  for zone = 1, zone_count do
    local group = {}
    for layer = 1, n do
      if idx > #items then break end
      group[#group + 1] = items[idx]
      idx = idx + 1
    end

    local max_len = 0
    for _, it in ipairs(group) do
      local len = getItemLength(it)
      if len > max_len then max_len = len end
    end

    local color = ZONE_COLORS[((zone - 1) % #ZONE_COLORS) + 1]

    local zone_guids = {}
    for layer = 1, #group do
      local it = group[layer]
      reaper.MoveMediaItemToTrack(it, layer_tracks[layer])
      setItemPosition(it, zone_start)
      if CONFIG.color_items_by_zone then
        setItemColor(it, color[1], color[2], color[3])
      end
      zone_guids[#zone_guids + 1] = getItemGUID(it)
    end

    zones[#zones + 1] = {zone = zone, start = zone_start, guids = zone_guids}

    zone_start = zone_start + max_len + gap
  end

  local raw = serializeState(n, gap, zones)
  reaper.SetExtState(EXT_SECTION, KEY_STATE, raw, false)

  reaper.ShowConsoleMsg(string.format(
    "Create done. Selected=%d, TracksPerZone=%d, Zones=%d, Gap=%.1fs\n",
    #items, n, #zones, gap
  ))
end

local function actionRerandomize(n)
  local raw = reaper.GetExtState(EXT_SECTION, KEY_STATE)
  local state = parseState(raw)

  if not state then
    reaper.ShowMessageBox("No previous state found. Run in Mode 1 first.", "Random Layer Spreader", 0)
    return
  end

  -- Use saved n from state if mismatch
  if state.n ~= n then
    n = state.n
  end

  local _, layer_tracks = findLatestLayerFolderAndChildren()
  if not layer_tracks then
    reaper.ShowMessageBox("Cannot find existing Layer Zones tracks. Run Mode 1 again.", "Random Layer Spreader", 0)
    return
  end

  local guid_map = buildItemMapByGUID()

  -- Collect all items across all zones, then shuffle globally.
  local all_items = {}
  local missing = 0

  for _, z in ipairs(state.zones) do
    for _, guid in ipairs(z.guids) do
      local it = guid_map[guid]
      if it then
        all_items[#all_items + 1] = it
      else
        missing = missing + 1
      end
    end
  end

  if #all_items == 0 then
    reaper.ShowMessageBox("No items found for re-randomize. Did you delete/move them?", "Random Layer Spreader", 0)
    return
  end

  shuffle(all_items)

  local cursor = 1

  for _, z in ipairs(state.zones) do
    local desired = #z.guids
    local items = {}

    for i = 1, desired do
      if cursor > #all_items then break end
      items[#items + 1] = all_items[cursor]
      cursor = cursor + 1
    end

    local color = ZONE_COLORS[((z.zone - 1) % #ZONE_COLORS) + 1]

    for layer = 1, #items do
      local it = items[layer]
      reaper.MoveMediaItemToTrack(it, layer_tracks[layer])
      setItemPosition(it, z.start)
      if CONFIG.color_items_by_zone then
        setItemColor(it, color[1], color[2], color[3])
      end
    end

    local new_guids = {}
    for i = 1, #items do
      new_guids[#new_guids + 1] = getItemGUID(items[i])
    end
    z.guids = new_guids
  end

  reaper.SetExtState(EXT_SECTION, KEY_STATE, serializeState(state.n, state.gap, state.zones), false)

  if missing > 0 then
    reaper.ShowConsoleMsg(string.format("Re-randomize done (global). Missing items: %d\n", missing))
  else
    reaper.ShowConsoleMsg("Re-randomize done (global).\n")
  end
end

-- ============================================================
-- Main
-- ============================================================

local function main()
  local items = getSelectedItems()
  local item_count = #items

  -- Allow re-randomize even without selection
  local max_items_for_ui = math.max(item_count, tonumber(reaper.GetExtState(EXT_SECTION, KEY_TRACKS_PER_ZONE)) or CONFIG.default_tracks_per_zone)

  local cfg = getModeAndConfig(max_items_for_ui)
  if not cfg then return end

  reaper.Undo_BeginBlock()

  if cfg.mode == 1 then
    if item_count == 0 then
      reaper.ShowMessageBox("Select some media items first (Mode 1).", "Random Layer Spreader", 0)
      reaper.Undo_EndBlock("Random Layer Spreader", -1)
      return
    end
    actionCreate(items, cfg.n, cfg.gap)
  else
    actionRerandomize(cfg.n)
  end

  reaper.Undo_EndBlock("Random Layer Spreader", -1)
  reaper.UpdateArrange()
end

main()
