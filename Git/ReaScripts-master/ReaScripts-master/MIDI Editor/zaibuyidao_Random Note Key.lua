-- @description Random Note Key
-- @version 1.0.2
-- @author zaibuyidao
-- @changelog
--   New Script
-- @links
--   https://www.soundengine.cn/user/%E5%86%8D%E8%A3%9C%E4%B8%80%E5%88%80
--   https://github.com/zaibuyidao/ReaScripts
-- @donate http://www.paypal.me/zaibuyidao
-- @about Random Note Script Series, filter "zaibuyidao random note" in ReaPack or Actions to access all scripts.

local ZBYDFuncPath = reaper.GetResourcePath() .. '/Scripts/zaibuyidao Scripts/Utility/zaibuyidao_Functions.lua'
if reaper.file_exists(ZBYDFuncPath) then
  dofile(ZBYDFuncPath)
  if not checkSWSExtension() or not checkJSAPIExtension() then return end
else
  local errorMsg = "Error - Missing Script (错误 - 缺失脚本)\n\n" ..
  "[English]\nThe required 'zaibuyidao Functions' script file was not found. Please ensure the file is correctly placed at:\n" ..
  ZBYDFuncPath:gsub('%\\', '/') .. "\n\nIf the file is missing, you can install it via ReaPack by searching for 'zaibuyidao Functions' in the ReaPack package browser.\n\n" ..
  "[中文]\n必需的 'zaibuyidao Functions' 脚本文件未找到。请确保文件正确放置在以下位置：\n" ..
  ZBYDFuncPath:gsub('%\\', '/') .. "\n\n如果文件缺失，您可以通过 ReaPack 包浏览器搜索并安装 'zaibuyidao Functions'。\n"

  reaper.MB(errorMsg, "Missing Script Error/脚本文件缺失错误", 0)

  if reaper.APIExists('ReaPack_BrowsePackages') then
    reaper.ReaPack_BrowsePackages('zaibuyidao Functions')
  else
    local reapackErrorMsg = "Error - ReaPack Not Found (错误 - 未找到 ReaPack)\n\n" ..
    "[English]\nThe ReaPack extension is not found. Please install ReaPack to manage and install REAPER scripts and extensions easily. Visit https://reapack.com for installation instructions.\n\n" ..
    "[中文]\n未找到 ReaPack 扩展。请安装 ReaPack 来便捷地管理和安装 REAPER 脚本及扩展。访问 https://reapack.com 获取安装指南。\n"

    reaper.MB(reapackErrorMsg, "ReaPack Not Found/未找到 ReaPack", 0)
  end
  return
end

local language = getSystemLanguage()
local getTakes = getAllTakes()

reaper.Undo_BeginBlock()

local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
if not take or not reaper.TakeIsMIDI(take) then return end

local key_min = reaper.GetExtState("RandomNoteKey", "Min")
if (key_min == "") then key_min = "C5" end
local key_max = reaper.GetExtState("RandomNoteKey", "Max")
if (key_max == "") then key_max = "C6" end
local key_signature = reaper.GetExtState("RandomNoteKey", "Key")
if (key_signature == "") then key_signature = "C" end
local octave_display_offset = reaper.GetExtState("RandomNoteKey", "Offset")
if (octave_display_offset == "") then octave_display_offset = "0" end

if language == "简体中文" then
    title = "随机音符调号"
    captions_csv = "最小音符:,最大音符:,调号:,八度偏移 (+/-):"
elseif language == "繁體中文" then
    title = "隨機音符調號"
    captions_csv = "最小音符:,最大音符:,調號:,八度偏移 (+/-):"
else
    title = "Random Note Key"
    captions_csv = "Key Min:,Key Max:,Key Signature:,Octave Offset (+/-):"
end

local uok, uinput = reaper.GetUserInputs(title, 4, captions_csv,  key_min ..','.. key_max ..','.. key_signature ..','.. octave_display_offset)
if not uok then return reaper.SN_FocusMIDIEditor() end
key_min, key_max, key_signature, octave_display_offset = uinput:match("(.*),(.*),(.*),(.*)")

reaper.SetExtState("RandomNoteKey", "Min", key_min, false)
reaper.SetExtState("RandomNoteKey", "Max", key_max, false)
reaper.SetExtState("RandomNoteKey", "Key", key_signature, false)
reaper.SetExtState("RandomNoteKey", "Offset", octave_display_offset, false)

local offsetValue = octave_display_offset * 12
local key_map = {} --音名和键位表
local octave, key --音名和键位，用于插入键值对

for i = 0 , 11 do
    octave = "C" .. i
    key = i * 12
    key_map[octave] = key
    octave = "C#" .. i
    key = i * 12 + 1
    key_map[octave] = key
    octave = "D" .. i
    key = i * 12 + 2
    key_map[octave] = key
    octave = "D#" .. i
    key = i * 12 + 3
    key_map[octave] = key
    octave = "E" .. i
    key = i * 12 + 4
    key_map[octave] = key
    octave = "F" .. i
    key = i * 12 + 5
    key_map[octave] = key
    octave = "F#" .. i
    key = i * 12 + 6
    key_map[octave] = key
    octave = "G" .. i
    key = i * 12 + 7
    key_map[octave] = key
    octave = "G#" .. i
    key = i * 12 + 8
    key_map[octave] = key
    octave = "A" .. i
    key = i * 12 + 9
    key_map[octave] = key
    octave = "A#" .. i
    key = i * 12 + 10
    key_map[octave] = key
    octave = "B" .. i
    key = i * 12 + 11
    key_map[octave] = key
end

if key_map[key_min] > 127 then
    key_map[key_min] = 127
elseif key_map[key_min] < 0 then
    key_map[key_min] = 0
elseif key_map[key_max] > 127 then
    key_map[key_max] = 127
elseif key_map[key_max] < 0 then
    key_map[key_max] = 0
elseif key_map[key_min] > key_map[key_max] then
    local t = key_map[key_max]
    key_map[key_max] = key_map[key_min]
    key_map[key_min] = t
end

if key_map[key_min] == key_map[key_max] then
    return
        reaper.MB("Random interval is empty, please re-enter", "Error", 0),
        reaper.SN_FocusMIDIEditor()
end

local diff = (key_map[key_max]+1) - key_map[key_min]
local sel_note = false

reaper.MIDI_DisableSort(take)
local sel = reaper.MIDI_EnumSelNotes(take, -1)
if sel ~= -1 then sel_note = true end

local flag
if reaper.GetToggleCommandStateEx(32060, 40681) == 1 then
    reaper.MIDIEditor_LastFocused_OnCommand(40681, 0) -- Options: Correct overlapping notes while editing
    flag = true
end

local _, notecnt, _, _ = reaper.MIDI_CountEvts(take)

for i = 0, notecnt - 1 do
    local _, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    local scales = {0,2,4,5,7,9,11} --大调音阶表
    local scales_map = {[0]=1,[2]=2,[4]=3,[5]=4,[7]=5,[9]=6,[11]=7} --大调音阶表的查询表，可以得到音高在音阶表中的位置
    local scales_pos = {[0]=0,[1]=0,[2]=2,[3]=2,[4]=4,[5]=5,[6]=5,[7]=7,[8]=7,[9]=9,[10]=9,[11]=11} --12半音的音阶表，可以通过0-11的数字得到一个在音阶中的数字
    local tones_map = {["C"]=0, ["C#"]=1, ["D"]=2, ["D#"]=3, ["E"]=4, ["F"]=5, ["F#"]=6, ["G"]=7, ["G#"]=8, ["A"]=9, ["A#"]=10, ["B"]=11} --音名所对应的数字

    if selected or not sel_note then
        pitch = tonumber(key_map[key_min]+math.random(diff))-1
        local tempPitch=pitch-tones_map[key_signature]+offsetValue+12
        local p = tempPitch%12
        local b = tempPitch-p
        local tp = scales_map[scales_pos[p]]
        local rp = ((tp-1)%7)+1
        local result = b+scales[rp]+tones_map[key_signature]
        reaper.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, result, nil, false)
    end
end

reaper.MIDI_Sort(take)
if flag then
    reaper.MIDIEditor_LastFocused_OnCommand(40681, 0)
end

reaper.Undo_EndBlock(title, -1)
reaper.UpdateArrange()
reaper.SN_FocusMIDIEditor()