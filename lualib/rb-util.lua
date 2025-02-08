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

function RB_util.area_get_from_offsets(x, y, w, h)
  local area
  if settings.global["recursive-blueprints-area"].value == "corner" then
    area = {
      {x, y},
      {x + w, y + h}
    }
  else
    -- Align to grid
    if w % 2 ~= 0 then x = x + 0.5 end
    if h % 2 ~= 0 then y = y + 0.5 end
    area = {
      {x - w/2, y - h/2},
      {x + w/2, y + h/2}
    }
  end
  RB_util.area_normalize(area)
  RB_util.area_check_limits(area)
  return area
end

local function find_stack_in_entity(entity, item_name)
  local e_type = entity.type
  if e_type == "container" or e_type == "logistic-container" then
    local inventory = entity.get_inventory(defines.inventory.chest)
    for i = 1, #inventory do
      if inventory[i].valid_for_read and inventory[i].name == item_name then
        return inventory[i]
      end
    end
  elseif e_type == "inserter" then
    local behavior = entity.get_control_behavior()
    e_held_stack = entity.held_stack
    if behavior
    and behavior.circuit_read_hand_contents
    and e_held_stack.valid_for_read
    and e_held_stack.name == item_name then
      return e_held_stack
    end
  end
end

-- Create a unique key for a circuit connector
local function con_hash(connector)
  return connector.owner.unit_number .. "-" .. connector.wire_connector_id
end

---Breadth-first search for an item in the circuit network.
---If there are multiple items, returns the closest one (least wire hops).
---@param entity LuaEntity The entity that the search starts with.
---@param item_name string The name of the item.
---@param red boolean Search in the red network?
---@param green boolean Search in the green network?
---@return LuaItemStack | nil
function RB_util.find_stack_in_network(entity, item_name, red, green)
  local present = {}
  if red then
    local c = entity.get_wire_connector(defines.wire_connector_id.circuit_red, false)
    present[con_hash(c)] = c
  end
  if green then
    local c = entity.get_wire_connector(defines.wire_connector_id.circuit_green, false)
    present[con_hash(c)] = c
  end
  local past = {}
  local future = {}
  while next(present) do
    for key, current_con in pairs(present) do
      -- Search connecting wires
      if current_con and current_con.real_connections then
        for _, w_con in pairs(current_con.real_connections) do
          local distant_con = w_con.target
          if distant_con.valid and distant_con.owner and distant_con.owner.valid then
            local hash = con_hash(distant_con)
            if not past[hash] and not present[hash] and not future[hash] then
              -- Search inside the entity
              local stack = find_stack_in_entity(distant_con.owner, item_name)
              if stack then return stack end
              -- Add wier connector to future searches
              future[hash] = distant_con
            end
          end
        end
      end
      past[key] = true
    end
    present = future
    future = {}
  end
  return nil
end

function RB_util.is_BP(s)
  return s and s.valid_for_read and (s.is_blueprint or s.is_blueprint_book or s.is_upgrade_item or s.is_deconstruction_item)
end


-- Collect all modded blueprint signals in one table
local function cache_blueprint_signals()
  local blueprint_signals = {}
  local filter ={
    {filter = "type", type="blueprint"},
    {filter = "type", type="blueprint-book"},
    {filter = "type", type="upgrade-item"},
    {filter = "type", type="deconstruction-item"}
  }
  for _, item in pairs(prototypes.get_item_filtered(filter)) do
    table.insert(blueprint_signals, {name=item.name, type="item"})
  end
  storage.blueprint_signals = blueprint_signals
end

local function cache_rocks_names()
  --local rocks={}
  local rocks2={}
  for name, e_prototype in pairs(prototypes.entity) do
    if e_prototype.count_as_rock_for_filtered_deconstruction  then
      --rocks[name] = true
      table.insert(rocks2, name)
    end
  end
  --storage.rocks_names = rocks
  storage.rocks_names2 = rocks2
end

local function cache_quality_names()
  local quality_names={}
  local quality_levels={}
  for name, q in pairs(prototypes.quality) do
    table.insert(quality_names, name)
    quality_levels[name] = q.level
  end
  storage.quality_names = quality_names
  storage.quality_levels = quality_levels
end

local function create_common_bp_plans()
  if not storage.plans then
    storage.plans = {game.create_inventory(1), game.create_inventory(1), game.create_inventory(1)}
    storage.plans[1][1].set_stack("deconstruction-planner")
    storage.plans[2][1].set_stack("upgrade-planner")
  elseif #storage.plans == 2 then
    table.insert(storage.plans, game.create_inventory(1))
  end
end

function RB_util.cache_in_storage()
  cache_blueprint_signals() --storage.blueprint_signals
  cache_rocks_names() --storage.rocks_names, storage.rocks_names2
  cache_quality_names() --storage.quality_names, storage.quality_levels
  create_common_bp_plans() --storage.plans
end

function RB_util.get_quality_lists()
  local a = {}
  for _, n in pairs(storage.quality_names) do a[n] = {} end
  return a
end

function RB_util.get_elem_from_signal(signal)
  if signal.type == "item" then
    return {type="item-with-quality", name=signal.name, quality=signal.quality or "normal"}
  elseif signal.type == "virtual" then
    return {type="signal", signal_type="virtual", name=signal.name}
  end
  return {type=signal.type, name=signal.name}
end

---Delete all signals in constant combinator end return LuaLogisticSection if possible.
---@param behavior LuaControlBehavior|LuaConstantCombinatorControlBehavior|nil
---@return LuaLogisticSection|nil
function RB_util.clear_constant_combinator(behavior)
  if not behavior or not behavior.valid then return nil end
  if behavior.sections_count > 1 then while(behavior.remove_section(1)) do end end
  if behavior.sections_count == 0 then behavior.add_section() end
  if not behavior.sections or #behavior.sections == 0 then return nil end
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
  return {type=signal.type, name=signal.name, quality=signal.quality or "normal", comparator="="}
end

function RB_util.check_verion(old, target)
  local a1, b1, c1 = string.match(old, "(%d+).(%d+).(%d+)")
  local a2, b2, c2 = string.match(target, "(%d+).(%d+).(%d+)")
  local cmp = tonumber(a1) - tonumber(a2)
  if cmp < 0 then
    return true
  elseif cmp == 0 then
    cmp = tonumber(b1) - tonumber(b2)
    if cmp < 0 then
      return true
    elseif cmp == 0 then
      return tonumber(c1) < tonumber(c2)
    end
  end
  return false
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
