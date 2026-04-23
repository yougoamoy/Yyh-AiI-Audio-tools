reaper.Undo_BeginBlock()

local num_items = reaper.CountMediaItems(0)
local first_track = reaper.GetTrack(0, 0)

for i = 0, num_items - 1 do
    local item = reaper.GetMediaItem(0, i)
    local item_track = reaper.GetMediaItem_Track(item)
    if item_track ~= first_track then
        local is_muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
        reaper.SetMediaItemSelected(item, is_muted ~= 1)
    end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Select all unmuted items (exclude first track)", -1)
