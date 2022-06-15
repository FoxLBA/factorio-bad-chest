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

function AreaScanner.on_tick_scanner(scanner)
  local previous = scanner.previous
  if not scanner.network_imput and previous then return end
  if not scanner.entity.valid then return end
  -- Copy values from circuit network to scanner
  local changed = false
  if previous then
    local current  = scanner.current
    local get_signal = scanner.entity.get_merged_signal
    for name, param in pairs(scanner.settings.scan_area) do
      local value = param
      if type(param) == "table" then value = get_signal(param) end
      if value ~= previous[name] then
        previous[name] = value
        current[name]  = AreaScanner.sanitize_area(name, value)
        if name == "filter" then AreaScanner.set_filter_mask(scanner.settings, value) end
        changed = true
      end
    end
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

function AreaScanner.on_built_scanner(entity, event)
  local tags = event.tags
  if event.source and event.source.valid then
    -- Copy settings from clone
    tags = {}
    tags.settings = util.table.deepcopy(global.scanners[event.source.unit_number].settings)
  end
  local scanner = AreaScanner.deserialize(entity, tags)
  script.register_on_entity_destroyed(entity)
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
    for _, i in pairs({"x", "y", "width", "height"}) do
      if type(scan_area[i]) == "number" then
        tags[i] = scan_area[i]
      else
        tags[i] = 0
        tags[i.."_signal"] = {type = scan_area[i].type, name = scan_area[i].name}
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
    scanner.settings.scan_area = {
      x = tags.x_signal or tags.x or 0,
      y = tags.y_signal or tags.y or 0,
      width = tags.width_signal or tags.width or 64,
      height = tags.height_signal or tags.height or 64,
      filter = 966
    }
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
  local a = scanner.settings.scan_area
  if not scanner.network_imput then
    --All inputs are constants.
    local f = AreaScanner.get_filter_mask(scanner.settings) -- the settings are in prioroty for the filter.
    scanner.previous = {x = a.x, y = a.y, width = a.width, height = a.height, filter = f}
    scanner.current  = {x = a.x, y = a.y, width = a.width, height = a.height, filter = f}
    a.filter = f
  else
    local entity = scanner.entity
    local previous = {x = 0, y = 0, width = 0, height = 0, filter = 0}
    local current  = {x = 0, y = 0, width = 0, height = 0, filter = 0}
    local get_signal = entity.get_merged_signal
    for name, param in pairs(a) do
      local value = param
      if type(param) == "table" then value = get_signal(param) end
      if name == "filter" then
        if type(param) == "table" then
          AreaScanner.set_filter_mask(scanner.settings, value)
        else
          --ignore constant number for the filter, the settings are in prioroty.
          value = AreaScanner.get_filter_mask(scanner.settings)
          a.filter = value
        end
      end
      previous[name] = value
      current[name] = AreaScanner.sanitize_area(name, value)
    end
    scanner.previous = previous
    scanner.current = current
  end
end

function AreaScanner.on_destroyed_scanner(unit_number)
  local scanner = global.scanners[unit_number]
  if scanner then
    global.scanners[unit_number] = nil
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

function AreaScanner.count_mineable_entity(source, dest)
  local counter = 0
  for name, count in pairs(source) do
    local prototype = game.entity_prototypes[name]
    local m_p = prototype.mineable_properties
    if m_p and m_p.minable and m_p.products then
      counter = counter + count
      for _, product in pairs(m_p.products) do
        local amount = product.amount
        if product.amount_min and product.amount_max then
          amount = (product.amount_min + product.amount_max) / 2
          amount = amount * product.probability
        end
        dest[product.type][product.name] = (dest[product.type][product.name] or 0) + (amount or 0) * count
      end
    end
  end
  return counter
end

---Scan the area for entitys
function AreaScanner.scan_resources(scanner)
  if not scanner then return end
  if not scanner.entity.valid then return end

  local scanner_settings = scanner.settings
  local filters = scanner_settings.filters
  local counters = scanner_settings.counters
  local force = scanner.entity.force
  local forces = {} --Rough filter.
  if filters.show_resources or filters.show_environment or filters.show_items_on_ground
  or counters.cliffs.is_shown or counters.resources.is_shown
  or counters.items_on_ground.is_shown or counters.trees_and_rocks.is_shown then
    forces = {"neutral"} --(ore, cliffs, items_on_ground, trees_and_rocks)
  end
  if counters.targets.is_shown then
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
  if filters.show_buildings or filters.show_ghosts
  or counters.buildings.is_shown or counters.ghosts.is_shown
  or counters.to_be_deconstructed.is_shown then
    table.insert(forces, force.name) --(buildings, ghosts, to_be_deconstructed)
  end

  if #forces == 0 and not counters.water.is_shown
  and not counters.uncharted.is_shown then --nothing to scan
    scanner.entity.get_control_behavior().parameters = nil
    return
  end

  local surface = scanner.entity.surface
  local scan_area_settings = scanner.current
  local x = scan_area_settings.x
  local y = scan_area_settings.y
  local w = scan_area_settings.width
  local h = scan_area_settings.height
  local p = scanner.entity.position
  local scan_area
  if settings.global["recursive-blueprints-area"].value == "corner" then
    scan_area = {
      {p.x + x, p.y + y},
      {p.x + x + w, p.y + y + h}
    }
  else
    -- Align to grid
    if w % 2 ~= 0 then x = x + 0.5 end
    if h % 2 ~= 0 then y = y + 0.5 end
    scan_area = {
      {p.x + x - w/2, p.y + y - h/2},
      {p.x + x + w/2, p.y + y + h/2}
    }
  end

  local areas, uncharted = RB_util.find_charted_areas(force, surface, scan_area)
  local scans
  if #areas == 1 then --Both scanning functions must be consistent!
    scans = AreaScanner.scan_area_no_hash(surface, areas[1], force, forces)
  else
    scans = AreaScanner.scan_area(surface, areas, force, forces)
  end
  scans.counters.uncharted = uncharted
  if counters.water.is_shown then
    local water = 0
    for _, area in pairs(areas)do
      water = water + surface.count_tiles_filtered{area = area, collision_mask = "water-tile"}
    end
    scans.counters.water = water
  end

  local result1 = {item = {}, fluid = {}, virtual = {}}
  local result2 = {item = {}, fluid = {}, virtual = {}}
  if filters.show_resources then AreaScanner.count_mineable_entity(scans.resources, result1) end
  if filters.show_environment then scans.counters.trees_and_rocks = AreaScanner.count_mineable_entity(scans.environment, result1) end
  if filters.show_items_on_ground then result2.item = scans.items_on_ground end
  if filters.show_buildings then scans.counters.buildings = AreaScanner.count_mineable_entity(scans.buildings, result2) end
  if filters.show_ghosts then scans.counters.ghosts = AreaScanner.count_mineable_entity(scans.ghosts, result2) end

  -- Copy resources to combinator output
  local behavior = scanner.entity.get_control_behavior()
  local index = 1
  local max_index = behavior.signals_count
  behavior.parameters = nil

  -- Counters
  for name, counter_setting in pairs(counters) do
    if counter_setting.is_shown and counter_setting.signal then
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

-- Count the entitys in charted area
function AreaScanner.scan_area(surface, areas, scanner_force, forces)
  local ROCKS = global.rocks_names
  local INFINITE_RESOURCES = global.infinite_resources
  local resources = {}
  local environment = {}
  local buildings = {}
  local ghosts = {}
  local items_on_ground = {}
  local counters = {resources = 0, cliffs = 0, items_on_ground = 0, to_be_deconstructed = 0, targets = 0}
  if #forces > 0 then
    local blacklist = {}
    for _, area in pairs(areas) do
      local result = {}
      result = surface.find_entities_filtered{area = area, force = forces}
      for _, entity in pairs(result) do
        local e_type = entity.type
        local e_name = entity.name
        local e_pos  = entity.position
        local hash = e_name .. "_" .. e_pos.x .. "_" .. e_pos.y
        if blacklist[hash] then
          -- We already counted this
        elseif e_type == "resource" then
          local amount = entity.amount
          if INFINITE_RESOURCES[e_name] then amount = 1 end
          resources[e_name] = (resources[e_name] or 0) + amount
          counters.resources = counters.resources + 1

        elseif e_type == "tree" or e_type == "fish" or ROCKS[e_name] then
          -- Trees, fish, rocks
          environment[e_name] = (environment[e_name] or 0) + 1

        elseif e_type == "cliff" then
          counters.cliffs = counters.cliffs + 1

        elseif e_type == "item-entity" then
          local stack = entity.stack
          items_on_ground[stack.name] = (items_on_ground[stack.name] or 0) + stack.count
          counters.items_on_ground = counters.items_on_ground + stack.count

        elseif entity.force == scanner_force then
          -- ghosts and buildings (scanner's force)
          if e_name == "entity-ghost" then
            local ghost_name = entity.ghost_name
            ghosts[ghost_name] = (ghosts[ghost_name] or 0) + 1
          else
            if not entity.has_flag("hidden") then
              buildings[e_name] = (buildings[e_name] or 0) + 1
              if entity.to_be_deconstructed() then
                counters.to_be_deconstructed = counters.to_be_deconstructed + 1
              end
            end
          end

        elseif AreaScanner.MILITARY_STRUCTURES[e_type] then
          -- Enemy base
          counters.targets = counters.targets + 1

        end
        -- Mark as counted
        blacklist[hash] = true
      end
    end
  end
  return {resources = resources, environment = environment, buildings = buildings, ghosts = ghosts, items_on_ground = items_on_ground, counters = counters}
end

-- Almost a complete copy of "AreaScanner.scan_area()"
function AreaScanner.scan_area_no_hash(surface, area, scanner_force, forces)
  local ROCKS = global.rocks_names
  local INFINITE_RESOURCES = global.infinite_resources
  local resources = {}
  local environment = {}
  local buildings = {}
  local ghosts = {}
  local items_on_ground = {}
  local counters = {resources = 0, cliffs = 0, items_on_ground = 0, to_be_deconstructed = 0, targets = 0}
  if #forces > 0 then
    local result = {}
    result = surface.find_entities_filtered{area = area, force = forces}
    for _, entity in pairs(result) do
      local e_type = entity.type
      local e_name = entity.name
      if e_type == "resource" then
        local amount = entity.amount
        if INFINITE_RESOURCES[e_name] then amount = 1 end
        resources[e_name] = (resources[e_name] or 0) + amount
        counters.resources = counters.resources + 1
      elseif e_type == "tree" or e_type == "fish" or ROCKS[e_name] then
        environment[e_name] = (environment[e_name] or 0) + 1
      elseif e_type == "cliff" then
        counters.cliffs = counters.cliffs + 1
      elseif e_type == "item-entity" then
        local stack = entity.stack
        items_on_ground[stack.name] = (items_on_ground[stack.name] or 0) + stack.count
        counters.items_on_ground = counters.items_on_ground + stack.count
      elseif entity.force == scanner_force then
        if e_name == "entity-ghost" then
          local ghost_name = entity.ghost_name
          ghosts[ghost_name] = (ghosts[ghost_name] or 0) + 1
        else
          if not entity.has_flag("hidden") then
            buildings[e_name] = (buildings[e_name] or 0) + 1
            if entity.to_be_deconstructed() then
              counters.to_be_deconstructed = counters.to_be_deconstructed + 1
            end
          end
        end
      elseif AreaScanner.MILITARY_STRUCTURES[e_type] then
        counters.targets = counters.targets + 1
      end
    end
  end
  return {resources = resources, environment = environment, buildings = buildings, ghosts = ghosts, items_on_ground = items_on_ground, counters = counters}
end

-- Out of bounds check.
-- Limit width/height to 999 for better performance.
function AreaScanner.sanitize_area(key, value)
  if key == "width" or key == "height" then
    if value < 0 then value = 0 end
    if value > 999 then value = 999 end
  elseif key ~= "filter" then
    if value > 2000000 then value = 2000000 end
    if value < -2000000 then value = -2000000 end
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

function AreaScanner.cache_infinite_resources()
  local resources={}
  local filter = {{filter = "type", type = "resource"}}
  for name, e_prototype in pairs(game.get_filtered_entity_prototypes(filter)) do
    if e_prototype.infinite_resource  then
      resources[name] = true
    end
  end
  global.infinite_resources = resources
end

return AreaScanner
