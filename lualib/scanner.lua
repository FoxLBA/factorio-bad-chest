local AreaScanner = {}
-- Military structures https://wiki.factorio.com/Military_units_and_structures
AreaScanner.MILITARY_STRUCTURES = {
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

AreaScanner.DEFAULT_SCANNER_SETTINGS = {
  version = {
    mod_name = script.mod_name,
    version = script.active_mods[script.mod_name]
  },
  scan_area = { --number or signal
    x = 0,
    y = 0,
    width = 64,
    height = 64,
    filter = 0
  },
  filters = {
    show_resources = true,
    show_environment = true, -- trees, rocks, fish
    show_buildings = false,
    show_ghosts = false,
    show_items_on_ground = false,
  },
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

AreaScanner.FILTER_MASK_ORDER = {
  {group = "filters",  name = "show_resources"},
  {group = "filters",  name = "show_environment"},
  {group = "filters",  name = "show_buildings"},
  {group = "filters",  name = "show_ghosts"},
  {group = "filters",  name = "show_items_on_ground"},
  {group = "counters", name = "uncharted"},
  {group = "counters", name = "cliffs"},
  {group = "counters", name = "targets"},
  {group = "counters", name = "water"},
  {group = "counters", name = "resources"},
  {group = "counters", name = "buildings"},
  {group = "counters", name = "ghosts"},
  {group = "counters", name = "items_on_ground"},
  {group = "counters", name = "trees_and_rocks"},
  {group = "counters", name = "to_be_deconstructed"},
}

function AreaScanner.on_tick_scanner(network)
  local scanner = global.scanners[network.deployer.unit_number]
  if not scanner then return end
  if not scanner.network_imput and scanner.previous then return end
  -- Copy values from circuit network to scanner
  local changed = false
  if scanner.previous then
    changed = AreaScanner.signal_changed(scanner, network, "filter")
    if changed then AreaScanner.set_filter_mask(scanner.settings, scanner.previous.filter) end
    changed = AreaScanner.signal_changed(scanner, network, "x") or changed
    changed = AreaScanner.signal_changed(scanner, network, "y") or changed
    changed = AreaScanner.signal_changed(scanner, network, "width") or changed
    changed = AreaScanner.signal_changed(scanner, network, "height") or changed
  else
    changed = true
    AreaScanner.make_previous(scanner)
  end
  if changed then
    -- Scan the new area
    AreaScanner.scan_resources(scanner)
    -- Update any open scanner guis
    for _, player in pairs(game.players) do
      if player.opened
      and player.opened.object_name == "LuaGuiElement"
      and player.opened.name == "recursive-blueprints-scanner"
      and player.opened.tags["recursive-blueprints-id"] == scanner.entity.unit_number then
        AreaScannerGUI.update_scanner_gui(player.opened)
      end
    end
  end
end

-- Copy the signal value from the circuit network or settings.
-- Return true if changed, false if not changed.
function AreaScanner.signal_changed(scanner, network, name)
  local value = AreaScanner.get_number_or_signal_value(scanner.settings.scan_area[name], network)
  value = AreaScanner.sanitize_area(name, value)
  if value ~= scanner.previous[name] then
    scanner.previous[name] = value
    return true
  end
  return false
end

function AreaScanner.on_built_scanner(entity, event)
  local tags = event.tags
  if event.source and event.source.valid then
    -- Copy settings from clone
    tags = {}
    tags.settings = util.table.deepcopy(global.scanners[event.source.unit_number].settings)
  end
  local scanner = AreaScanner.deserialize(entity, tags)
  script.register_on_entity_destroyed(entity)
  AreaScanner.update_scanner_network(scanner)
  AreaScanner.make_previous(scanner)
  AreaScanner.scan_resources(scanner)
end

function AreaScanner.serialize(entity)
  local scanner = global.scanners[entity.unit_number]
  if scanner then
    local tags = {}
    tags.settings = util.table.deepcopy(scanner.settings)
    --Adding old format tags.
    local scan_area = scanner.settings.scan_area
      for i in {"x", "y", "width", "height"} do
        if type(scan_area[i]) == "number" then
          tags[i] = scan_area[i]
          tags[i.."_signal"] = nil
        else
          tags[i] = 0
          tags[i.."_signal"] = scan_area[i]
        end
      end
    return tags
  end
  return nil
end

function AreaScanner.deserialize(entity, tags)
  local scanner = {}
  if tags and tags.settings then
    scanner.settings = util.table.deepcopy(tags.settings)
  else
    scanner.settings = util.table.deepcopy(AreaScanner.DEFAULT_SCANNER_SETTINGS)
  end
  if tags and not tags.settings then
    scanner.settings.scan_area.x = tags.x_signal or tags.x or 0
    scanner.settings.scan_area.y = tags.y_signal or tags.y  or 0
    scanner.settings.scan_area.width = tags.width_signal or tags.width or 64
    scanner.settings.scan_area.height = tags.height_signal or tags.height or 64
  end
  AreaScanner.mark_unknown_signals(scanner.settings)
  AreaScanner.check_input_signals(scanner)
  scanner.entity = entity
  global.scanners[entity.unit_number] = scanner
  return scanner
end

function AreaScanner.check_input_signals(scanner)
  scanner.network_imput = false
  for _, i in pairs(scanner.settings.scan_area) do
    if type(i) == "table" then
      scanner.network_imput = true
      break
    end
  end
end

function AreaScanner.make_previous(scanner)
  if not scanner then return end
  AreaScanner.check_input_signals(scanner)
  if not scanner.network_imput then
    scanner.previous = {}
    scanner.previous.x = scanner.settings.scan_area.x
    scanner.previous.y = scanner.settings.scan_area.y
    scanner.previous.width = scanner.settings.scan_area.width
    scanner.previous.height = scanner.settings.scan_area.height
    scanner.previous.filter = AreaScanner.get_filter_mask(scanner.settings)
    scanner.settings.scan_area.filter = scanner.previous.filter
  else
    local network = global.scanners[scanner.entity.unit_number]
    if not network then return end
    scanner.previous = {}
    scanner.previous.x = AreaScanner.get_number_or_signal_value(scanner.settings.scan_area.x, network)
    scanner.previous.y = AreaScanner.get_number_or_signal_value(scanner.settings.scan_area.y, network)
    scanner.previous.width = AreaScanner.get_number_or_signal_value(scanner.settings.scan_area.width, network)
    scanner.previous.height = AreaScanner.get_number_or_signal_value(scanner.settings.scan_area.height, network)
    if type(scanner.settings.scan_area.filter) == "number" then
      scanner.previous.filter = AreaScanner.get_filter_mask(scanner.settings)
      scanner.settings.scan_area.filter = scanner.previous.filter
    else
      scanner.previous.filter = get_signal(network, scanner.settings.scan_area.filter)
      AreaScanner.set_filter_mask(scanner.settings, scanner.previous.filter)
    end
  end
end

function AreaScanner.on_destroyed_scanner(unit_number)
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
        AreaScannerGUI.destroy_gui(player.opened)
      end
    end
  end
end

-- Cache the circuit networks attached to this scanner
function AreaScanner.update_scanner_network(scanner)
  if scanner.network_imput then
    update_network(scanner.entity)
  else
    global.networks[scanner.entity.unit_number] = nil
  end
end

function AreaScanner.count_mineable_entity(source, dest)
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

---Scan the area for entitys
function AreaScanner.scan_resources(scanner)
  if not scanner then return end
  if not scanner.entity.valid then return end
  if not scanner.previous then return end

  local scanner_settings = scanner.settings
  local force = scanner.entity.force
  local forces = {} --Rough filter.
  if scanner_settings.filters.show_resources or scanner_settings.filters.show_environment or scanner_settings.filters.show_items_on_ground
  or scanner_settings.counters.cliffs.is_shown or scanner_settings.counters.resources.is_shown
  or scanner_settings.counters.items_on_ground.is_shown or scanner_settings.counters.trees_and_rocks.is_shown then
    forces = {"neutral"} --(ore, cliffs, items_on_ground, trees_and_rocks)
  end
  if scanner_settings.counters.targets.is_shown then
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
  if scanner_settings.filters.show_buildings or scanner_settings.filters.show_ghosts
  or scanner_settings.counters.buildings.is_shown or scanner_settings.counters.ghosts.is_shown
  or scanner_settings.counters.to_be_deconstructed.is_shown then
    table.insert(forces, force.name) --(buildings, ghosts, to_be_deconstructed)
  end

  if #forces == 0 then --nothing to scan
    scanner.entity.get_control_behavior().parameters = nil
    return
  end

  local p = scanner.entity.position
  local surface = scanner.entity.surface
  local blacklist = {}
  local scans = {resources = {item = {}, fluid = {}, virtual = {}}, environment = {}, buildings ={}, ghosts = {}, items_on_ground = {}, counters = {}}
  for name, _ in pairs(scanner_settings.counters) do scans.counters[name] = 0 end
  local scan_filter = {force = force, forces = forces, surface = surface, scan_water = scanner_settings.counters.water.is_shown}

  local x = scanner.previous.x
  local y = scanner.previous.y
  -- Align to grid
  if scanner.previous.width % 2 ~= 0 then x = x + 0.5 end
  if scanner.previous.height % 2 ~= 0 then y = y + 0.5 end

  if settings.global["recursive-blueprints-area"].value == "corner" then
    -- Convert from top left corner to center
    x = x + math.floor(scanner.previous.width/2)
    y = y + math.floor(scanner.previous.height/2)
  end

  -- Subtract 1 pixel from the edges to avoid tile overlap
  local x1 = p.x + x - scanner.previous.width/2 + 1/256
  local x2 = p.x + x + scanner.previous.width/2 - 1/256
  local y1 = p.y + y - scanner.previous.height/2 - 1/256
  local y2 = p.y + y + scanner.previous.height/2 - 1/256

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
        AreaScanner.scan_area(scan_filter, area, scans, blacklist)
      else
        -- Add uncharted chunk
        scans.counters.uncharted = scans.counters.uncharted + 1
      end
    end
  end

  -- Copy resources to combinator output
  local behavior = scanner.entity.get_control_behavior()
  local index = 1
  local max_index = behavior.signals_count
  behavior.parameters = nil

  local result1 = {item = {}, fluid = {}, virtual = {}}
  local result2 = {item = {}, fluid = {}, virtual = {}}

  if scanner_settings.filters.show_resources then result1 = scans.resources end
  if scanner_settings.filters.show_environment then AreaScanner.count_mineable_entity(scans.environment, result1) end
  if scanner_settings.filters.show_items_on_ground then result2.item = scans.items_on_ground end
  if scanner_settings.filters.show_buildings then AreaScanner.count_mineable_entity(scans.buildings, result2) end
  if scanner_settings.filters.show_ghosts then AreaScanner.count_mineable_entity(scans.ghosts, result2) end

  -- Counters
  for name, counter_setting in pairs(scanner_settings.counters) do
    if counter_setting.is_shown and counter_setting.signal then -- FILTERS IS OFF!
      local count = scans.counters[name]
      if count ~= 0 then
        if counter_setting.is_negative then count = -count end
        count = AreaScanner.check_scan_signal_collision(count, result1, counter_setting.signal)
        count = AreaScanner.check_scan_signal_collision(count, result2, counter_setting.signal)
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
        count = AreaScanner.check_scan_signal_collision(count, result2, {type = type, name = name})
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

function AreaScanner.check_scan_signal_collision(count, result, signal)
  if result[signal.type][signal.name] then
    count = count + result[signal.type][signal.name]
    result[signal.type][signal.name] = nil
  end
  return count
end

-- Count the entitys in a chunk
function AreaScanner.scan_area(scan_filter, area, scans, blacklist)
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

    elseif AreaScanner.MILITARY_STRUCTURES[entity.type] then
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

-- Out of bounds check.
-- Limit width/height to 999 for better performance.
function AreaScanner.sanitize_area(key, value)
  if key == "filter" then return value end
  if value > 2000000 then value = 2000000 end
  if value < -2000000 then value = -2000000 end
  if key == "width" or key == "height" then
    if value < 0 then value = 0 end
    if value > 999 then value = 999 end
  end
  return value
end

-- Delete signals from uninstalled mods
function AreaScanner.mark_unknown_signals(scanner_settings)
  for _, signal in pairs(scanner_settings.scan_area) do
    if type(signal) == "table" and not GUI_util.get_signal_sprite(signal) then
      signal = {type = "virtual", name = "signal-dot"}
    end
  end
  for _, signal in pairs(scanner_settings.counters) do
    if not GUI_util.get_signal_sprite(signal.signal) then
      signal.signal = {type = "virtual", name = "signal-dot"}
    end
  end
end

function AreaScanner.get_filter_mask(settings)
  local mask = 0
  local pow = math.pow
  local v = false
  for i, filter in pairs(AreaScanner.FILTER_MASK_ORDER) do
    if filter.group == "filters" then
      v = settings.filters[filter.name]
    else
      v = settings.counters[filter.name].is_shown
    end
    if v then mask = mask + pow(2, i) end
  end
  return mask
end

function AreaScanner.set_filter_mask(settings, mask)
  local pow = math.pow
  local band = bit32.band
  for i, filter in pairs(AreaScanner.FILTER_MASK_ORDER) do
    if filter.group == "filters" then
      settings.filters[filter.name] = (band(mask, pow(2, i)) ~= 0)
    else
      settings.counters[filter.name].is_shown = (band(mask, pow(2, i)) ~= 0)
    end
  end
end

function AreaScanner.get_number_or_signal_value(n, network)
  if not n then return nil end
  if type(n) == "number" then return n end
  return get_signal(network, n)
end

return AreaScanner
