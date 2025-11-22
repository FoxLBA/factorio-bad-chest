-- Offset calculation tool.
local tool_name = "rbp-tool"
local RB_util = RB_util
local FLAG_SIGNALS = RBP_defines.FLAG_SIGNALS

local F = {}

--LMB (calc area parameters)
function F.on_player_selected_area(event)
  if event.item ~= tool_name then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if not storage.offset_tool_data then storage.offset_tool_data = {} end
  local record = storage.offset_tool_data
  local coord_flag = (settings.get_player_settings(event.player_index)["recursive-blueprints-tool-coordinates"].value == "relative") and -1 or 1
  local e_pos = {0, 0}
  if coord_flag <= 0 then
    --relative
    if not record[event.player_index] or not record[event.player_index].position then
      player.print({"recursive-blueprints-tool.err-not-selected"})
      return
    end
    record = record[event.player_index]
    if (not record.surface) or (not record.surface.valid) or event.surface.index ~= record.surface.index then
      player.print({"recursive-blueprints-tool.err-wrong-surface"})
      return
    end
    e_pos = record.position
  else
    --absolute
    if not record[event.player_index] then
      record[event.player_index] = {}
    end
    record = record[event.player_index]
  end

  local area = RB_util.convert_BoundingBox_to_area(event.area)
  RB_util.area_round_up(area)
  local area_center, area_size = RB_util.area_find_center_and_size(area)
  local offset = {}
  local area_flag = (settings.get_player_settings(event.player_index)["recursive-blueprints-tool-area"].value == "corner") and -1 or 1
  if area_flag <= 0 then
    offset = {area[1][1] - e_pos[1], area[1][2] - e_pos[2]}
  else
    offset = {math.floor(area_center[1] - e_pos[1]), math.floor(area_center[2] - e_pos[2])}
  end
  record.last = {offset, area_size}

  if coord_flag <= 0 then
    --relative
    if 1200 < event.tick - record.tick then
      player.print({"recursive-blueprints-tool.offsets", offset[1], offset[2], area_size[1], area_size[2], record.gps_tag})
      record.tick = event.tick
    else
      player.print({"recursive-blueprints-tool.offsets-no-gps", offset[1], offset[2], area_size[1], area_size[2]})
    end
  else
    --absolute
    player.print({"recursive-blueprints-tool.offsets", offset[1], offset[2], area_size[1], area_size[2], "(0,0)"})
  end
end

--Shift + LMB (select entity as reference point)
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

---@param c_comb LuaEntity Constant combinator entity
---@return LuaLogisticSection?
local function get_c_comb_section_1(c_comb)
  if c_comb.valid and c_comb.type == "constant-combinator" then
    local behavior = c_comb.get_control_behavior() ---@cast behavior LuaConstantCombinatorControlBehavior
    if behavior and behavior.valid then
      if behavior.sections_count == 0 then behavior.add_section() end
      return behavior.get_section(1)
    end
  end
end

---@param c_comb LuaEntity Constant combinator entity
---@param filters LogisticFilter[] The signals that need to be set. limitation: sigmals without quality only!
---@return boolean
local function set_or_add_signals_to_constant_combinator(c_comb, filters)
  local section = get_c_comb_section_1(c_comb)
  if section and section.valid and section.is_manual then
    local search_list = {}
    local spots_needed = #filters
    local empty_spots = {}
    for _, filter in pairs(filters) do
      search_list[filter.value] = filter
    end
    if section.filters_count>0 then
      --modify existing values and cache empty spots indexes.
      for index, filter in pairs(section.filters) do
        if filter.value and search_list[filter.value.name] then
          if not filter.value.quality or (filter.value.quality == "normal") then
            section.set_slot(index, search_list[filter.value.name])
            search_list[filter.value.name] = nil
            spots_needed = spots_needed - 1
          end
        elseif not filter.value and spots_needed>0 then
          table.insert(empty_spots, index)
          spots_needed = spots_needed - 1
        end
      end
    end
    for _, filter in pairs(search_list) do
      if #empty_spots == 0 then
        section.set_slot(section.filters_count+1, filter)
      else
        section.set_slot(empty_spots[1], filter)
        table.remove(empty_spots, 1)
      end
    end
    return true
  end
  return false
end

--RMB or Ctrl+LMB (Write to c-comb)
function F.on_player_reverse_selected_area(event)
  if event.item ~= tool_name then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local record = storage.offset_tool_data or {}
  if (not record[event.player_index]) or (not record[event.player_index].last) then
    player.print({"recursive-blueprints-tool.err-no-data"})
    return
  end
  local data = record[event.player_index].last
  local area_flag = (settings.get_player_settings(event.player_index)["recursive-blueprints-tool-area"].value == "corner") and -1 or 1
  local coord_flag = (settings.get_player_settings(event.player_index)["recursive-blueprints-tool-coordinates"].value == "relative") and -1 or 1
  local signals = {
    {value = "signal-X", min = data[1][1]},
    {value = "signal-Y", min = data[1][2]},
    {value = "signal-W", min = data[2][1]},
    {value = "signal-H", min = data[2][2]},
    {value = FLAG_SIGNALS.center.name, min = area_flag},
    {value = FLAG_SIGNALS.absolute.name, min = coord_flag},
  }
  if event.entities then
    for _, e in pairs(event.entities) do
      if set_or_add_signals_to_constant_combinator(e, signals) then
        player.print({"recursive-blueprints-tool.data-loaded", e.gps_tag})
        return
      end
    end
  end
  player.print({"recursive-blueprints-tool.err-not-found2"})
end

--[[
--Shift + RMB
function F.on_player_alt_reverse_selected_area(event)
end

--Right-click to open
function F.on_mod_item_opened(event)
  if event.item.name ~= tool_name then return end
end
]]

return F
