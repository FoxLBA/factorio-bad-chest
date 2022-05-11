require "scanner-gui"

-- Military structures https://wiki.factorio.com/Military_units_and_structures
local MILITARY_STRUCTURES = {
  ["ammo-turret"] = true,
  ["artillery-turret"] = true,
  ["electric-turret"] = true,
  ["fluid-turret"] = true,
  ["player-port"] = true,
  ["radar"] = true,
  ["simple-entity-with-force"] = true,
  ["turret"] = true,
  ["unit-spawner"] = true,
}

local DEFAULT_SCANNER_SETTINGS = {
  show_resources = true,
  show_environment = true, -- trees, rocks, fish
  show_buildings = false,
  show_ghosts = false,
  show_items_on_ground = false,
  counters = {
    uncharted   = {is_shown = true, signal = {name="signal-black", type="virtual"}, is_negative = false},
    cliffs      = {is_shown = true, signal = {name="cliff-explosives", type="item"}, is_negative = true},
    targets     = {is_shown = true, signal = {name="artillery-shell", type="item"}, is_negative = true},
    water       = {is_shown = true, signal = {name="water", type="fluid"}, is_negative = false},
    resources   = {is_shown = false, signal = {name="signal-O", type="virtual"}, is_negative = false},
    buildings   = {is_shown = false, signal = {name="signal-B", type="virtual"}, is_negative = false},
    ghosts      = {is_shown = false, signal = {name="signal-G", type="virtual"}, is_negative = false},
    items_on_ground = {is_shown = false, signal = {name="signal-I", type="virtual"}, is_negative = false},
    trees_and_rocks = {is_shown = false, signal = {name="signal-T", type="virtual"}, is_negative = false},
    to_be_deconstructed = {is_shown = false, signal = {name="signal-D", type="virtual"}, is_negative = false},
  }
}

-- Copy the signal value from the circuit network.
-- Return true if changed, false if not changed.
local function signal_changed(scanner, network, name, signal_name)
  if scanner[signal_name] then
    local value = get_signal(network, scanner[signal_name])
    value = sanitize_area(name, value)
    if scanner[name] ~= value then
      scanner[name] = value
      return true
    end
  end
  return false
end

function on_tick_scanner(network)
  local scanner = global.scanners[network.deployer.unit_number]
  if not scanner then return end
  -- Copy values from circuit network to scanner
  local changed = signal_changed(scanner, network, "x", "x_signal")
  changed = signal_changed(scanner, network, "y", "y_signal") or changed
  changed = signal_changed(scanner, network, "width", "width_signal") or changed
  changed = signal_changed(scanner, network, "height", "height_signal") or changed
  if changed then
    -- Scan the new area
    scan_resources(scanner)
    -- Update any open scanner guis
    for _, player in pairs(game.players) do
      if player.opened
      and player.opened.object_name == "LuaGuiElement"
      and player.opened.name == "recursive-blueprints-scanner"
      and player.opened.tags["recursive-blueprints-id"] == scanner.entity.unit_number then
        update_scanner_gui(player.opened)
      end
    end
  end
end

--TODO: change to scanner_settings.
function on_built_scanner(entity, event)
  local scanner = {
    x = 0,
    y = 0,
    width = 64,
    height = 64,
    filter = 483
  }
  local tags = event.tags
  if event.source and event.source.valid then
    -- Copy settings from clone
    tags = util.table.deepcopy(global.scanners[event.source.unit_number])
  end
  if tags then
    -- Copy settings from blueprint tags
    scanner.x = tags.x
    scanner.x_signal = tags.x_signal
    scanner.y = tags.y
    scanner.y_signal = tags.y_signal
    scanner.width = tags.width
    scanner.width_signal = tags.width_signal
    scanner.height = tags.height
    scanner.height_signal = tags.height_signal
    scanner.filter = tags.filter or 0
    scanner.filter_signal = tags.filter_signal
  end
  mark_unknown_signals(scanner)
  scanner.entity = entity
  global.scanners[entity.unit_number] = scanner
  script.register_on_entity_destroyed(entity)
  update_scanner_network(scanner)
  scan_resources(scanner)
end

function on_destroyed_scanner(unit_number)
  local scanner = global.scanners[unit_number]
  if scanner then
    global.scanners[unit_number] = nil
    global.networks[unit_number] = nil
    for _, player in pairs(game.players) do
      -- Remove scanner gui
      if player.opened
      and player.opened.object_name == "LuaGuiElement"
      and player.opened.name == "recursive-blueprints-scanner"
      and player.opened.tags["recursive-blueprints-id"] == unit_number then
        destroy_gui(player.opened)
      end
    end
  end
end

-- Cache the circuit networks attached to this scanner
function update_scanner_network(scanner)
  if scanner.x_signal or scanner.y_signal or scanner.width_signal or scanner.height_signal then
    update_network(scanner.entity)
  else
    global.networks[scanner.entity.unit_number] = nil
  end
end

local function count_mineable_entity(source, dest)
  for name, count in pairs(source) do
    for _, product in pairs(game.entity_prototypes[name].mineable_properties.products) do
      local amount = product.amount
      if product.amount_min and product.amount_max then
        amount = (product.amount_min + product.amount_max) / 2
        amount = amount * product.probability
      end
      dest[product.type][product.name] = (dest[product.type][product.name] or 0) + (amount or 0) * count
    end
  end
end

-- Count the entitys in a chunk
local function scan_area(scan_filter, area, scans, blacklist)
  local result = scan_filter.surface.find_entities_filtered{
    area = area,
    force = scan_filter.forces,
  }
  for _, entity in pairs(result) do
    local hash = pos_hash(entity, 0, 0)
    local prototype = entity.prototype
    if blacklist[hash] then
      -- We already counted this
    elseif entity.type == "resource" then
      local type = prototype.mineable_properties.products[1].type
      local name = prototype.mineable_properties.products[1].name
      local amount = entity.amount
      if prototype.infinite_resource then amount = 1 end
      scans.resources[type][name] = (scans.resources[type][name] or 0) + amount
      scans.counters.resources = scans.counters.resources + amount

    elseif entity.type == "cliff" then
      scans.counters.cliffs = scans.counters.cliffs + 1

    elseif entity.force == scan_filter.force then
      -- ghosts and buildings (scanner's force)
      if entity.name == "entity-ghost" then
        scans.ghosts[entity.ghost_prototype.name] = (scans.ghosts[entity.ghost_prototype.name] or 0) + 1
        scans.counters.ghosts = scans.counters.ghosts + 1
      elseif prototype.flags and not prototype.flags.hidden
      and prototype.mineable_properties.minable
      and prototype.mineable_properties.products then
        scans.buildings[prototype.name] = (scans.buildings[prototype.name] or 0) + 1
        scans.counters.buildings = scans.counters.buildings + 1
        if entity.status and entity.status == defines.entity_status.marked_for_deconstruction then
          scans.counters.to_be_deconstructed = scans.counters.to_be_deconstructed + 1
        end
      end

    elseif MILITARY_STRUCTURES[entity.type] then
      -- Enemy base
      scans.counters.targets = scans.counters.targets + 1

    elseif (entity.type == "tree" or entity.type == "fish" or prototype.count_as_rock_for_filtered_deconstruction)
    and prototype.mineable_properties.minable
    and prototype.mineable_properties.products then
      -- Trees, fish, rocks
      scans.environment[prototype.name] = (scans.environment[prototype.name] or 0) + 1

    elseif entity.type == "item-entity" then
      scans.items_on_ground[entity.stack.name] = (scans.items_on_ground[entity.stack.name] or 0) + entity.stack.count
      scans.counters.items_on_ground = scans.counters.items_on_ground + entity.stack.count
    end
    -- Mark as counted
    blacklist[hash] = true
  end

  if scan_filter.scan_water then
    scans.counters.water = scans.counters.water + scan_filter.surface.count_tiles_filtered{
      area = {{round(area[1][1]), round(area[1][2])},{round(area[2][1]), round(area[2][2])}},
      collision_mask = "water-tile",
    }
  end
end

local function check_scan_signal_collision(count, result, signal)
  if result[signal.type][signal.name] then
    count = count + result[signal.type][signal.name]
    result[signal.type][signal.name] = nil
  end
  return count
end

-- Scan the area for entitys
function scan_resources(scanner)
  if not scanner then return end
  if not scanner.entity.valid then return end
  local scanner_settings = DEFAULT_SCANNER_SETTINGS --scanner.settings

  --TODO: enable filters
  local force = scanner.entity.force
  local forces = {} --Rough filter.
  if true or scanner_settings.show_resources or scanner_settings.show_environment or scanner_settings.show_items_on_ground
  or scanner_settings.counters.cliffs.is_shown or scanner_settings.counters.resources.is_shown
  or scanner_settings.counters.items_on_ground.is_shown or scanner_settings.counters.trees_and_rocks.is_shown then
    forces = {"neutral"} --(ore, cliffs, items_on_ground, trees_and_rocks)
  end
  if true or scanner_settings.targets.is_shown then
    -- Count enemy bases
    for _, enemy in pairs(game.forces) do
      if force ~= enemy
      and enemy.name ~= "neutral"
      and not force.get_friend(enemy)
      and not force.get_cease_fire(enemy) then
        table.insert(forces, enemy.name)
      end
    end
  end
  if true or scanner_settings.show_buildings or scanner_settings.show_ghosts
  or scanner_settings.counters.buildings.is_shown or scanner_settings.counters.ghosts.is_shown
  or scanner_settings.counters.to_be_deconstructed.is_shown then
    table.insert(forces, force.name) --(buildings, ghosts, to_be_deconstructed)
  end

  if #forces == 0 then return end  --nothing to scan

  local p = scanner.entity.position
  local surface = scanner.entity.surface
  local blacklist = {}
  local scans = {resources = {item = {}, fluid = {}, virtual = {}}, environment = {}, buildings ={}, ghosts = {}, items_on_ground = {}, counters = {}}
  for name, _ in pairs(scanner_settings.counters) do scans.counters[name] = 0 end
  local scan_filter = {force = force, forces = forces, surface = surface, scan_water = scanner_settings.counters.water.is_shown}

  local x = scanner.x
  local y = scanner.y
  -- Align to grid
  if scanner.width % 2 ~= 0 then x = x + 0.5 end
  if scanner.height % 2 ~= 0 then y = y + 0.5 end

  if settings.global["recursive-blueprints-area"].value == "corner" then
    -- Convert from top left corner to center
    x = x + math.floor(scanner.width/2)
    y = y + math.floor(scanner.height/2)
  end

  -- Subtract 1 pixel from the edges to avoid tile overlap
  local x1 = p.x + x - scanner.width/2 + 1/256
  local x2 = p.x + x + scanner.width/2 - 1/256
  local y1 = p.y + y - scanner.height/2 - 1/256
  local y2 = p.y + y + scanner.height/2 - 1/256

  -- Search one chunk at a time
  for x = x1, math.ceil(x2 / 32) * 32, 32 do
    for y = y1, math.ceil(y2 / 32) * 32, 32 do
      local chunk_x = math.floor(x / 32)
      local chunk_y = math.floor(y / 32)
      -- Chunk must be charted
      if force.is_chunk_charted(surface, {chunk_x, chunk_y}) then
        local left = chunk_x * 32
        local right = left + 32
        local top = chunk_y * 32
        local bottom = top + 32
        if left < x1 then left = x1 end
        if right > x2 then right = x2 end
        if top < y1 then top = y1 end
        if bottom > y2 then bottom = y2 end
        local area = {{left, top}, {right, bottom}}
        scan_area(scan_filter, area, scans, blacklist)
      else
        -- Add uncharted chunk
        scans.counters.uncharted = scans.counters.uncharted + 1
      end
    end
  end

  -- Copy resources to combinator output
  -- TODO: enable filters
  local behavior = scanner.entity.get_control_behavior()
  local index = 1
  local max_index = behavior.signals_count
  behavior.parameters = nil

  local result1 = {item = {}, fluid = {}, virtual = {}}
  local result2 = {item = {}, fluid = {}, virtual = {}}

  if true or scanner_settings.show_resources then result1 = scans.resources end
  if true or scanner_settings.show_environment then count_mineable_entity(scans.environment, result1) end
  if true or scanner_settings.show_items_on_ground then result2.item = scans.items_on_ground end
  if true or scanner_settings.show_buildings then count_mineable_entity(scans.buildings, result2) end
  if true or scanner_settings.show_ghosts then count_mineable_entity(scans.ghosts, result2) end

  -- Counters
  for name, counter_setting in pairs(scanner_settings.counters) do
    if true or counter_setting.is_shown and counter_setting.signal then -- FILTERS IS OFF!
      local count = scans.counters[name]
      if count ~= 0 then
        if counter_setting.is_negative then count = -count end
        count = check_scan_signal_collision(count, result1, counter_setting.signal)
        count = check_scan_signal_collision(count, result2, counter_setting.signal)
        if count > 2147483647 then count = 2147483647 end -- Avoid int32 overflow
        if count < -2147483648 then count = -2147483648 end
        behavior.set_signal(index, {signal=counter_setting.signal, count=count})
        index = index + 1
      end
    end
  end
  -- ore, trees, rocks, fish
  for type, result in pairs(result1) do
    for name, count in pairs(result) do
      if count ~= 0 then
        count = check_scan_signal_collision(count, result2, {type = type, name = name})
        if count > 2147483647 then count = 2147483647 end
        behavior.set_signal(index, {signal={type=type, name=name}, count=count})
        index = index + 1
      end
    end
  end
  -- buildings, ghosts, items on ground
  result1 = {}
  for type, result in pairs(result2) do
    for name, count in pairs(result) do
      if count ~= 0 then
        if count > 2147483647 then count = 2147483647 end
        table.insert(result1, {signal={type=type, name=name}, count=count})
      end
    end
  end
  table.sort(result1,
    function(s1, s2)
      if s1.count == s2.count then return s1.signal.name < s2.signal.name end
      return s1.count > s2.count
    end
  )
  for _, result in ipairs(result1) do
    if index > max_index then break end
    behavior.set_signal(index, result)
    index = index + 1
  end
end

-- Out of bounds check.
-- Limit width/height to 999 for better performance.
function sanitize_area(key, value)
  if value > 2000000 then value = 2000000 end
  if value < -2000000 then value = -2000000 end
  if key == "width" or key == "height" then
    if value < 0 then value = 0 end
    if value > 999 then value = 999 end
  end
  return value
end

-- Delete signals from uninstalled mods
function mark_unknown_signals(scanner)
  for _, signal in pairs{"x_signal", "y_signal", "width_signal", "height_signal", "filter_signal"} do
    if scanner[signal] and not get_signal_sprite(scanner[signal]) then
      scanner[signal] = {type = "virtual", name = "signal-unknown"}
    end
  end
end

-- Collect all visible circuit network signals.
-- Sort them by group and subgroup.
function cache_scanner_signals()
  global.groups = {}
  for _, group in pairs(game.item_group_prototypes) do
    for _, subgroup in pairs(group.subgroups) do
      if subgroup.name == "other" or subgroup.name == "virtual-signal-special" then
        -- Hide special signals
      else
        local signals = {}
        -- Item signals
        local items = game.get_filtered_item_prototypes{
          {filter = "subgroup", subgroup = subgroup.name},
          {filter = "flag", flag = "hidden", invert = true, mode = "and"},
        }
        for _, item in pairs(items) do
          if item.subgroup == subgroup then
            table.insert(signals, {type = "item", name = item.name})
          end
        end
        -- Fluid signals
        local fluids = game.get_filtered_fluid_prototypes{
          {filter = "subgroup", subgroup = subgroup.name},
          {filter = "hidden", invert = true, mode = "and"},
        }
        for _, fluid in pairs(fluids) do
          if fluid.subgroup == subgroup then
            table.insert(signals, {type = "fluid", name = fluid.name})
          end
        end
        -- Virtual signals
        for _, signal in pairs(game.virtual_signal_prototypes) do
          if signal.subgroup == subgroup then
            table.insert(signals, {type = "virtual", name = signal.name})
          end
        end
        -- Cache the visible signals
        if #signals > 0 then
          if #global.groups == 0 or global.groups[#global.groups].name ~= group.name then
            table.insert(global.groups, {name = group.name, subgroups = {}})
          end
          table.insert(global.groups[#global.groups].subgroups, signals)
        end
      end
    end
  end
end
