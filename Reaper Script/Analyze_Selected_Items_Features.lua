--[[
Analyze Selected Items Features (prototype)

Goal:
- Analyze selected audio items and auto-tag simple sound features
- Use lightweight heuristics (no FFT) so it runs fast in Reaper

What it detects (rough):
- Transient-ish vs Sustained-ish
- Bright-ish vs Dark-ish

How it works:
- Reads audio samples from each selected item's active take
- Computes:
  - RMS, Peak, Crest(dB)
  - Attack ratio: RMS(first attack_ms) / RMS(total window)
  - ZCR: zero crossing rate
  - Diff ratio: RMS(1st difference) / RMS(signal)

Output:
- Prefix take name with tags like: [TRN][BRI]
- Color items by classification
- Print per-item features to console

Notes:
- This is a heuristic prototype. Thresholds may need tuning for your library.
- Skips MIDI takes.
--]]

local CONFIG = {
  analyze_seconds = 1.0,      -- max seconds analyzed per item (from item start)
  attack_ms = 50,            -- attack window in ms
  sample_rate = 44100,       -- analysis sample rate
  channels = 1,              -- request mono

  -- thresholds
  crest_db_transient = 12.0,
  attack_ratio_transient = 0.35,

  diff_ratio_bright = 0.70,
  zcr_bright = 0.12,

  rename_take = true,
  color_item = true,
}

local COLORS = {
  transient = {255, 170, 60},
  sustained = {120, 220, 120},
  bright = {120, 180, 255},
  dark = {180, 180, 180},
}

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function db(x)
  if x <= 0 then return -150 end
  return 20.0 * math.log(x, 10)
end

local function setItemColor(item, r, g, b)
  local c = (reaper.ColorToNative(r, g, b) | 0x1000000)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", c)
end

local function getTakeName(take)
  local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  return name or ""
end

local function setTakeName(take, name)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
end

local function stripExistingTags(name)
  -- remove leading [XXX] tags repeatedly
  local changed = true
  while changed do
    changed = false
    local new = name:gsub("^%b[]%s*", "")
    if new ~= name then
      name = new
      changed = true
    end
  end
  return name
end

local function analyzeTakeSegment(item, take)
  if not take or reaper.TakeIsMIDI(take) then return nil end

  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local dur = math.min(item_len, CONFIG.analyze_seconds)
  if dur <= 0 then return nil end

  local accessor = reaper.CreateTakeAudioAccessor(take)
  if not accessor then return nil end

  local sr = CONFIG.sample_rate
  local ch = CONFIG.channels
  local samples_per_ch = math.max(1, math.floor(dur * sr))

  -- Reaper API wants a pre-allocated array.
  local buf = reaper.new_array(samples_per_ch * ch)
  buf.clear()

  local ok = reaper.GetAudioAccessorSamples(accessor, sr, ch, item_pos, samples_per_ch, buf)
  reaper.DestroyAudioAccessor(accessor)

  if not ok then return nil end

  local data = buf.table()

  local sum_sq = 0.0
  local peak = 0.0
  local zc = 0
  local last = nil

  local diff_sum_sq = 0.0
  local last_s = nil

  for i = 1, #data do
    local s = data[i]
    local a = math.abs(s)
    if a > peak then peak = a end
    sum_sq = sum_sq + (s * s)

    if last ~= nil then
      if (last >= 0 and s < 0) or (last < 0 and s >= 0) then
        zc = zc + 1
      end
    end
    last = s

    if last_s ~= nil then
      local d = s - last_s
      diff_sum_sq = diff_sum_sq + (d * d)
    end
    last_s = s
  end

  local n = math.max(1, #data)
  local rms = math.sqrt(sum_sq / n)
  local diff_rms = math.sqrt(diff_sum_sq / math.max(1, n - 1))

  local crest_db = db(peak / math.max(1e-9, rms))
  local zcr = zc / n
  local diff_ratio = diff_rms / math.max(1e-9, rms)

  -- attack ratio: first attack_ms window rms / total rms
  local attack_samps = math.floor((CONFIG.attack_ms / 1000.0) * sr)
  attack_samps = clamp(attack_samps, 1, n)

  local a_sum_sq = 0.0
  for i = 1, attack_samps do
    local s = data[i]
    a_sum_sq = a_sum_sq + (s * s)
  end
  local a_rms = math.sqrt(a_sum_sq / attack_samps)
  local attack_ratio = a_rms / math.max(1e-9, rms)

  return {
    peak = peak,
    rms = rms,
    crest_db = crest_db,
    zcr = zcr,
    diff_ratio = diff_ratio,
    attack_ratio = attack_ratio,
  }
end

local function classify(f)
  local is_transient = (f.crest_db >= CONFIG.crest_db_transient) and (f.attack_ratio >= CONFIG.attack_ratio_transient)
  local is_bright = (f.diff_ratio >= CONFIG.diff_ratio_bright) or (f.zcr >= CONFIG.zcr_bright)

  local tags = {}
  tags[#tags + 1] = is_transient and "TRN" or "SUS"
  tags[#tags + 1] = is_bright and "BRI" or "DRK"

  return {
    transient = is_transient,
    bright = is_bright,
    tags = tags,
  }
end

local function colorFor(c)
  -- combine transient/sustained + bright/dark into a single color
  if c.transient and c.bright then return {255, 140, 60} end
  if c.transient and (not c.bright) then return {255, 200, 120} end
  if (not c.transient) and c.bright then return {120, 190, 255} end
  return {170, 170, 170}
end

local function main()
  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then
    reaper.ShowMessageBox("Select some media items first.", "Analyze Selected Items Features", 0)
    return
  end

  local retval, input = reaper.GetUserInputs(
    "Analyze Selected Items Features",
    6,
    "Analyze seconds,Attack ms,Crest dB(TRN),Attack ratio(TRN),Diff ratio(BRI),ZCR(BRI)",
    string.format("%.1f,%d,%.1f,%.2f,%.2f,%.2f",
      CONFIG.analyze_seconds,
      CONFIG.attack_ms,
      CONFIG.crest_db_transient,
      CONFIG.attack_ratio_transient,
      CONFIG.diff_ratio_bright,
      CONFIG.zcr_bright
    )
  )

  if not retval then return end

  local a_s, atk_ms, crest_db, atk_ratio, diff_ratio, zcr = input:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
  CONFIG.analyze_seconds = tonumber(a_s) or CONFIG.analyze_seconds
  CONFIG.attack_ms = tonumber(atk_ms) or CONFIG.attack_ms
  CONFIG.crest_db_transient = tonumber(crest_db) or CONFIG.crest_db_transient
  CONFIG.attack_ratio_transient = tonumber(atk_ratio) or CONFIG.attack_ratio_transient
  CONFIG.diff_ratio_bright = tonumber(diff_ratio) or CONFIG.diff_ratio_bright
  CONFIG.zcr_bright = tonumber(zcr) or CONFIG.zcr_bright

  reaper.Undo_BeginBlock()

  reaper.ShowConsoleMsg("\n--- Analyze Selected Items Features ---\n")
  reaper.ShowConsoleMsg(string.format("Items: %d\n", count))

  local processed = 0
  local skipped = 0

  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)

    local f = analyzeTakeSegment(item, take)
    if not f then
      skipped = skipped + 1
    else
      local c = classify(f)

      if CONFIG.rename_take and take and (not reaper.TakeIsMIDI(take)) then
        local name = getTakeName(take)
        name = stripExistingTags(name)
        local prefix = string.format("[%s][%s] ", c.tags[1], c.tags[2])
        setTakeName(take, prefix .. name)
      end

      if CONFIG.color_item then
        local col = colorFor(c)
        setItemColor(item, col[1], col[2], col[3])
      end

      processed = processed + 1

      reaper.ShowConsoleMsg(string.format(
        "%03d crest=%.1fdB attack=%.2f diff=%.2f zcr=%.3f -> [%s][%s]\n",
        i + 1,
        f.crest_db,
        f.attack_ratio,
        f.diff_ratio,
        f.zcr,
        c.tags[1],
        c.tags[2]
      ))
    end
  end

  reaper.Undo_EndBlock("Analyze Selected Items Features", -1)
  reaper.UpdateArrange()

  reaper.ShowConsoleMsg(string.format("Done. processed=%d skipped=%d\n", processed, skipped))
end

main()
