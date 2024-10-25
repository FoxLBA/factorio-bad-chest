local RB_util = {}

---Find charted areas for given force and surface.
---@param force LuaForce
---@param surface LuaSurface
---@param area BoundingBox
---@return BoundingBox[] result
---@return int32 counter
function RB_util.find_charted_areas(force, surface, area)
  local x1 = area[1][1]
  local x2 = area[2][1]
  local y1 = area[1][2]
  local y2 = area[2][2]

  local counter = 0 --count of uncharted chunks.
  local area_lines = {}
  local floor = math.floor
  local insert = table.insert
  local chuncks_area = {
    {floor(x1 / 32), floor(y1 / 32)},
    {floor(x2 / 32), floor(y2 / 32)}
  }
  -- Find all charted chunks and combine then into groups of lines.
  for chunk_x = chuncks_area[1][1], chuncks_area[2][1] do
    local current_line = {}
    local top_chunk = nil
    local bottom_chunk = nil
    local left = chunk_x * 32
    local right = left + 32
    if left < x1 then left = x1 end
    if right > x2 then right = x2 end
    for chunk_y = chuncks_area[1][2], chuncks_area[2][2] do
      if force.is_chunk_charted(surface, {chunk_x, chunk_y}) then
        bottom_chunk = chunk_y
        if not top_chunk then top_chunk = chunk_y end
      else
        if top_chunk then
          local top = top_chunk * 32
          local bottom = bottom_chunk * 32 + 32
          if top < y1 then top = y1 end
          if bottom > y2 then bottom = y2 end
          insert(current_line, {{left, top}, {right, bottom}})
          top_chunk = nil
        end
        counter = counter + 1
      end
    end
    if top_chunk then
      local top = top_chunk * 32
      local bottom = bottom_chunk * 32 + 32
      if top < y1 then top = y1 end
      if bottom > y2 then bottom = y2 end
      insert(current_line, {{left, top}, {right, bottom}})
    end
    insert(area_lines, current_line)
  end
  if counter == 0 then return {area}, 0 end
  -- Merge adjacent lines if they have same higth.
  local result = {}
  local found_one = false
  for i, line in ipairs(area_lines) do
    for _, slice in ipairs(line) do
      for j = i, #area_lines - 1 do
        for k, next_line_slice in ipairs(area_lines[j+1]) do
          if slice[1][2] == next_line_slice[1][2]
          and slice[2][2] == next_line_slice[2][2] then
            slice[2][1] = next_line_slice[2][1]
            table.remove(area_lines[j+1], k)
            found_one = true
            break
          end
        end
        if not found_one then break end
        found_one = false
      end
      insert(result, slice)
    end
  end
  return result, counter
end

---Subtract 1 pixel from the edges to avoid tile overlap.
---@param a BoundingBox
---@return BoundingBox
function RB_util.area_shrink_1_pixel(a)
  local pixel = 0.00390625 -- 1/256
  a[1][1] = a[1][1] + pixel
  a[1][2] = a[1][2] + pixel
  a[2][1] = a[2][1] - pixel
  a[2][2] = a[2][2] - pixel
  return a
end

---Check the limits of the coordinates and reduce the size of BoundingBox if necessary.
---@param a BoundingBox
---@return BoundingBox
function RB_util.area_check_limits(a)
  local limit = 8388600 -- ~2^23
  if a[1][1] > limit  then a[1][1] = limit  end
  if a[1][1] < -limit then a[1][1] = -limit end
  if a[1][2] > limit  then a[1][2] = limit  end
  if a[1][2] < -limit then a[1][2] = -limit end
  if a[2][1] > limit  then a[2][1] = limit  end
  if a[2][1] < -limit then a[2][1] = -limit end
  if a[2][2] > limit  then a[2][2] = limit  end
  if a[2][2] < -limit then a[2][2] = -limit end
  return a
end

---Calculate the center of the BoundingBox.
---@param a BoundingBox
---@return MapPosition, MapPosition
function RB_util.area_find_center_and_size(a)
  local s =  {a[2][1] - a[1][1], a[2][2] - a[1][2]}
  return {a[1][1] + s[1]/2, a[1][2] + s[2]/2}, s
end

---@param a BoundingBox
---@return BoundingBox
function RB_util.area_normalize(a)
  if a[1][1] > a[2][1] then a[1][1], a[2][1] = a[2][1], a[1][1] end
  if a[1][2] > a[2][2] then a[1][2], a[2][2] = a[2][2], a[1][2] end
  return a
end

function RB_util.cache_rocks_names()
  local rocks={}
  local rocks2={}
  for name, e_prototype in pairs(prototypes.entity) do
    if e_prototype.count_as_rock_for_filtered_deconstruction  then
      rocks[name] = true
      table.insert(rocks2, name)
    end
  end
  storage.rocks_names = rocks
  storage.rocks_names2 = rocks2
end

---Delete all signals in constant combinator end return LuaLogisticSection if pissible.
---@param behavior LuaConstantCombinatorControlBehavior
---@return LuaLogisticSection|nil
function RB_util.clear_constant_combinator(behavior)
  if not behavior or not behavior.valid then return nil end
  if behavior.sections_count > 1 then while(behavior.remove_section(1)) do end end
  local section = behavior.sections[1]
  if not section.is_manual then return nil end
  section.filters = {}
  section.multiplier = 1
  section.group = ""
  section.active = true
  behavior.enabled = true
  return section
end

---@param signal table
---@return SignalFilter
function RB_util.get_signal_filter(signal)
  return {type=signal.type, name=signal.name, quality="normal", comparator="="}
end

function RB_util.warning_msgs(msg_i)
  if (msg_i < 0) or (msg_i > 1) then return end
  if not storage.arning_msg then storage.arning_msg = {} end
  if (not storage.arning_msg[msg_i]) or (storage.arning_msg[msg_i] < (game.tick)) then
    storage.arning_msg[msg_i] = game.tick + 10*60*60 --10min
    if msg_i == 1 then
      game.print("Deployer automatic deconstruction is disabled due to the possibility of the game crash./nWaiting for fix. Latest checked version of Factorio 2.0.10")
    end
  end
end

-->>DEPRICATET FUNCTIONS>>--

function RB_util.round(n)
  return math.floor(n + 0.5)
end

-- Create a unique key for a blueprint entity
function RB_util.pos_hash(entity, x_offset, y_offset)
  return entity.name .. "_" .. (entity.position.x + x_offset) .. "_" .. (entity.position.y + y_offset)
end

-- Calculate the position offset between two sets of entities
-- Returns nil if the two sets cannot be aligned
-- Requires that table1's keys are generated using pos_hash()
function RB_util.calculate_offset(table1, table2)
  -- Scan table 1
  local table1_names = {}
  for _, entity in pairs(table1) do
    -- Build index of entity names
    table1_names[entity.name] = true
  end

  -- Scan table 2
  local total = 0
  local anchor = nil
  for _, entity in pairs(table2) do
    if table1_names[entity.name] then
      -- Count appearances
      total = total + 1
      -- Pick an anchor entity to compare with table 1
      if not anchor then anchor = entity end
    end
  end
  if not anchor then return end

  for _, entity in pairs(table1) do
    if anchor.name == entity.name then
      -- Calculate the offset to an entity in table 1
      local x_offset = entity.position.x - anchor.position.x
      local y_offset = entity.position.y - anchor.position.y

      -- Check if the offset works for every entity in table 2
      local count = 0
      for _, entity in pairs(table2) do
        if table1[RB_util.pos_hash(entity, x_offset, y_offset)] then
          count = count + 1
        end
      end
      if count == total then
        return {x = x_offset, y = y_offset}
      end
    end
  end
end

return RB_util
