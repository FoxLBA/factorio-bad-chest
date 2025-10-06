-- Offset calculation tool.
local tool_name = "rbp-tool"

local F = {}

--calc offset.
--LMB
function F.on_player_selected_area(event)
  if event.item ~= tool_name then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local record = storage.offset_tool_data or {}
  if not record[event.player_index] then
    player.print({"recursive-blueprints-tool.err-not-selected"})
    return
  end
  record = record[event.player_index]

  -- calc offsets
  if event.surface.index ~= record.surface.index then
    player.print({"recursive-blueprints-tool.err-wrong-surface"})
    return
  end
  local area = RB_util.convert_BoundingBox_to_area(event.area)
  RB_util.area_round_up(area)
  local area_center, area_size = RB_util.area_find_center_and_size(area)
  local offset = {}
  local e_pos = record.position
  if settings.global["recursive-blueprints-area"].value == "corner" then
    offset = {area[1][1] - e_pos[1], area[1][2] - e_pos[2]}
  else
    offset = {math.floor(area_center[1] - e_pos[1]), math.floor(area_center[2] - e_pos[2])}
  end
  if 1200 < event.tick - record.tick then
    player.print({"recursive-blueprints-tool.offsets", offset[1], offset[2], area_size[1], area_size[2], record.gps_tag})
    record.tick = event.tick
  else
    player.print({"recursive-blueprints-tool.offsets-no-gps", offset[1], offset[2], area_size[1], area_size[2]})
  end
end

--select entity
--Shift + LMB
function F.on_player_alt_selected_area(event)
  if event.item ~= tool_name then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if event.entities then
    for _, e in pairs(event.entities) do
      if e.valid then
        if not storage.offset_tool_data then storage.offset_tool_data = {} end
        storage.offset_tool_data[event.player_index] = {
          entity = e,
          surface = e.surface,
          position = {math.floor(e.position.x), math.floor(e.position.y)},
          gps_tag = e.gps_tag,
          tick = event.tick,
        }
        player.print({"recursive-blueprints-tool.ref-selected", e.gps_tag})
        return
      end
    end
  end
  player.print({"recursive-blueprints-tool.err-not-found"})
end

--[[
--RMB
function F.on_player_reverse_selected_area(event)
end

--Shift + RMB
function F.on_player_alt_reverse_selected_area(event)
end

--Right-click to open
function F.on_mod_item_opened(event)
  if event.item.name ~= tool_name then return end
end
]]

return F
