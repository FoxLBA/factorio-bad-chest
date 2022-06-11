local RB_util = {}

---Find charted areas for given force and surface
---@param force LuaForce
---@param surface LuaSurface
---@param area BoundingBox
function RB_util.find_charted_areas(force, surface, area)
  local x1 = area[1][1]
  local x2 = area[2][1]
  local y1 = area[1][2]
  local y2 = area[2][2]

  local counter = 0
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
    local current_slice = nil
    local bottom_chunk = nil
    local left = chunk_x * 32
    local right = left + 32
    if left < x1 then left = x1 end
    if right > x2 then right = x2 end
    for chunk_y = chuncks_area[1][2], chuncks_area[2][2] do
      if force.is_chunk_charted(surface, {chunk_x, chunk_y}) then
        if not current_slice then
          local top = chunk_y * 32
          local bottom = top + 32
          if top < y1 then top = y1 end
          if bottom > y2 then bottom = y2 end
          current_slice = {{left, top}, {right, bottom}}
        else
          bottom_chunk = chunk_y
        end
      else
        if bottom_chunk then
          local bottom = bottom_chunk * 32 + 32
          if bottom > y2 then bottom = y2 end
          current_slice[2][2] = bottom
        end
        if current_slice then insert(current_line, current_slice) end
        current_slice = nil
        bottom_chunk = nil
        counter = counter + 1
      end
    end
    if bottom_chunk then
      local bottom = bottom_chunk * 32 + 32
      if bottom > y2 then bottom = y2 end
      current_slice[2][2] = bottom
    end
    if current_slice then insert(current_line, current_slice) end
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

function RB_util.enable_automatic_mode(train)
  -- Train is already driving
  if train.speed ~= 0 then return end
  if not train.manual_mode then return end

  -- Train is marked for deconstruction
  for _, carriage in pairs(train.carriages) do
    if carriage.to_be_deconstructed(carriage.force) then return end
  end

  -- Train is waiting for fuel
  for _, carriage in pairs(train.carriages) do
    local requests = carriage.surface.find_entities_filtered{
      type = "item-request-proxy",
      position = carriage.position,
    }
    for _, request in pairs(requests) do
      if request.proxy_target == carriage then
        global.fuel_requests[request.unit_number] = carriage
        script.register_on_entity_destroyed(request)
        return
      end
    end
  end

  -- Turn on automatic mode
  train.manual_mode = false
end

function RB_util.on_built_carriage(entity, tags)
  -- Check for automatic mode tag
  if tags and tags.manual_mode ~= nil and tags.manual_mode == false then
    -- Wait for the entire train to be built
    if tags.train_length == #entity.train.carriages then
      -- Turn on automatic mode
      RB_util.enable_automatic_mode(entity.train)
    end
  end
end

-- Train fuel item-request-proxy has been completed
function RB_util.on_item_request(unit_number)
  local carriage = global.fuel_requests[unit_number]
  if not carriage then return end
  global.fuel_requests[unit_number] = nil
  if carriage.valid and carriage.train then
    -- Done waiting for fuel, we can turn on automatic mode now
    RB_util.enable_automatic_mode(carriage.train)
  end
end

function RB_util.cache_rocks_names()
  local rocks={}
  for name, e_prototype in pairs(game.entity_prototypes) do
    if e_prototype.count_as_rock_for_filtered_deconstruction  then
      rocks[name] = true
    end
  end
  global.rocks_names = rocks
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
