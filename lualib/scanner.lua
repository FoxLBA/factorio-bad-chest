local AreaScanner = {}
-- Military structures https://wiki.factorio.com/Military_units_and_structures
local MILITARY_STRUCTURES_LIST = {
  "ammo-turret", "artillery-turret", "electric-turret",
  "fluid-turret", "player-port", "radar",
  "simple-entity-with-force", "turret", "unit-spawner",
}

local OLD_SCANNER_SETTINGS = {
  version = {
    mod_name = script.mod_name,
    version = script.active_mods[script.mod_name]
  },
  scan_area = { --number or signal
    x = 0,
    y = 0,
    width = 64,
    height = 64,
    filter = 966,
  },
  filters = {
    blank = false,
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

local function virtual_signal(name)
  return {name=name, type="virtual", quality="normal", comparator="="}
end

local NEW_SCANNER_SETTINGS = {
  version = {
    mod_name = script.mod_name,
    version = script.active_mods[script.mod_name]
  },
  scan_area = { --number or signal
    x = virtual_signal("signal-X"),
    y = virtual_signal("signal-Y"),
    width = virtual_signal("signal-W"),
    height = virtual_signal("signal-H"),
    filter = virtual_signal("signal-F"),
  },
  counters = {
    uncharted   = {signal = virtual_signal("recursive-blueprints-counter-uncharted")},
    cliffs      = {signal = virtual_signal("recursive-blueprints-counter-cliffs")},
    targets     = {signal = virtual_signal("recursive-blueprints-counter-targets")},
    water       = {signal = virtual_signal("recursive-blueprints-counter-water")},
    resources   = {signal = virtual_signal("recursive-blueprints-counter-resources")},
    buildings   = {signal = virtual_signal("recursive-blueprints-counter-buildings")},
    ghosts      = {signal = virtual_signal("recursive-blueprints-counter-ghosts")},
    items_on_ground = {signal = virtual_signal("recursive-blueprints-counter-items_on_ground")},
    trees_and_rocks = {signal = virtual_signal("recursive-blueprints-counter-trees_and_rocks")},
    to_be_deconstructed = {signal = virtual_signal("recursive-blueprints-counter-to_be_deconstructed")},
  }
}

local circuit_red = defines.wire_connector_id.circuit_red
local circuit_green = defines.wire_connector_id.circuit_green

AreaScanner.FILTER_MASK_ORDER = {
  {group = "filters",  name = "blank"},
  {group = "filters",  name = "resources"},
  {group = "filters",  name = "trees_and_rocks"},
  {group = "filters",  name = "buildings"},
  {group = "filters",  name = "ghosts"},
  {group = "filters",  name = "items_on_ground"},
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
  {group = "filters",  name = "to_be_deconstructed"},
}

function AreaScanner.on_tick()
  local f =  AreaScanner.on_tick_scanner
  for i, s in pairs(storage.scanners) do
    if s.entity.valid then
      f(s)
    else
      AreaScanner.on_destroyed(i)
    end
  end
end

function AreaScanner.on_tick_scanner(scanner)
  local previous = scanner.previous
  if not scanner.network_imput and previous then return end
  -- Copy values from circuit network to scanner
  local changed = false
  if previous then
    local current  = scanner.current
    local get_signal = scanner.entity.get_signal
    if not scanner.settings or not scanner.settings.scan_area then
      for name, param in pairs(AreaScanner.DEFAULT_SCANNER_SETTINGS.scan_area) do
        local value = get_signal(param, circuit_red, circuit_green)
        if value ~= previous[name] then
          previous[name] = value
          current[name]  = AreaScanner.sanitize_area(name, value)
          changed = true
        end
      end
    else
      for name, param in pairs(scanner.settings.scan_area) do
        local value = param
        if type(param) == "table" then value = get_signal(param, circuit_red, circuit_green) end
        if value ~= previous[name] then
          previous[name] = value
          current[name]  = AreaScanner.sanitize_area(name, value)
          changed = true
        end
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

function AreaScanner.on_built(entity, event)
  local tags = event.tags
  if event.source and event.source.valid then
    -- Copy settings from clone
    tags = {}
    tags.settings = util.table.deepcopy(storage.scanners[event.source.unit_number].settings)
  end
  RB_util.clear_constant_combinator(entity.get_control_behavior())
  local scanner = AreaScanner.deserialize(entity, tags)
  script.register_on_object_destroyed(entity)
  AreaScanner.make_previous(scanner)
  AreaScanner.scan_resources(scanner)
end

function AreaScanner.serialize(entity)
  local scanner = storage.scanners[entity.unit_number]
  if scanner and scanner.settings then
    if not scanner.settings.scan_area and not scanner.settings.counters then
      return nil
    end
    local tags = {}
    tags.settings = util.table.deepcopy(scanner.settings)
    return tags
  end
  return nil
end

function AreaScanner.deserialize(entity, tags)
  local scanner = {}
  if tags and tags.settings then
    scanner.settings = util.table.deepcopy(tags.settings)
  else
    --scanner.settings = nil
    --scanner.settings = util.table.deepcopy(AreaScanner.DEFAULT_SCANNER_SETTINGS)
    --scanner.settings.counters = nil
  end
  if tags and not tags.settings then
    if not scanner.settings then scanner.settings = {} end
    scanner.settings.scan_area = {
      x = tags.x_signal or tags.x or 0,
      y = tags.y_signal or tags.y or 0,
      width = tags.width_signal or tags.width or 64,
      height = tags.height_signal or tags.height or 64,
      filter = 966
    }
    scanner.settings.counters = util.table.deepcopy(OLD_SCANNER_SETTINGS.counters)
  end
  AreaScanner.mark_unknown_signals(scanner.settings)
  AreaScanner.check_input_signals(scanner)
  scanner.entity = entity
  storage.scanners[entity.unit_number] = scanner
  return scanner
end

function AreaScanner.check_input_signals(scanner)
  if not scanner.settings or not scanner.settings.can_area then
    scanner.network_imput = true
    return
  end
  scanner.network_imput = false
  for _, i in pairs(scanner.settings.scan_area) do
    if type(i) == "table" then
      scanner.network_imput = true
      break
    end
  end
end

function AreaScanner.make_previous(scanner)
  AreaScanner.check_input_signals(scanner)
  local a = scanner.settings or AreaScanner.DEFAULT_SCANNER_SETTINGS
  a = a.scan_area or AreaScanner.DEFAULT_SCANNER_SETTINGS.scan_area
  if not scanner.network_imput then
    --All inputs are constants.
    scanner.previous = {x = a.x, y = a.y, width = a.width, height = a.height, filter = a.filter}
    scanner.current  = {x = a.x, y = a.y, width = a.width, height = a.height, filter = a.filter}
  else
    local entity = scanner.entity
    local previous = {x = 0, y = 0, width = 0, height = 0, filter = 0}
    local current  = {x = 0, y = 0, width = 0, height = 0, filter = 0}
    local get_signal = entity.get_signal
    for name, param in pairs(a) do
      local value = param
      if type(param) == "table" then value = get_signal(param, circuit_red, circuit_green) end
      ---@diagnostic disable-next-line: assign-type-mismatch
      previous[name] = value
      current[name] = AreaScanner.sanitize_area(name, value)
    end
    scanner.previous = previous
    scanner.current = current
  end
end

function AreaScanner.on_destroyed(unit_number)
  local scanner = storage.scanners[unit_number]
  if scanner then
    -- Remove opened scanner gui
    for _, player in pairs(game.players) do
      if player.opened
      and player.opened.object_name == "LuaGuiElement"
      and player.opened.name == "recursive-blueprints-scanner"
      and player.opened.tags["recursive-blueprints-id"] == unit_number then
        AreaScannerGUI.destroy_gui(player.opened)
      end
    end
    --Remove hidden io entity
    if scanner.output_entity and scanner.output_entity.valid then
      scanner.output_entity.destroy()
    end
    --Remove from list
    storage.scanners[unit_number] = nil
  end
end

function AreaScanner.get_or_create_output_behavior(scanner)
  local entity = scanner.entity
  local b = scanner.output_entity
  if not b or not b.valid then
    b = entity.surface.create_entity{
      name = "recursive-blueprints-hidden-io",
      position = entity.position,
      force = entity.force,
      create_build_effect_smoke = false,
    }
    scanner.output_entity = b
    local def = defines.wire_connector_id
    local hidden_con = b.get_wire_connector(def.circuit_red, true)
    hidden_con.connect_to(entity.get_wire_connector(def.circuit_red, true))
    hidden_con = b.get_wire_connector(def.circuit_green, true)
    hidden_con.connect_to(entity.get_wire_connector(def.circuit_green, true))
  end
  return b.get_control_behavior()
end

local function count_mineable(prototypes, source, dest, merge)
  --source[name]=count
  --dest[type][quality][name]=count
  local counter = 0
  if merge then
    for name, count in pairs(source) do
      local m_p = prototypes[name].mineable_properties
      if m_p and m_p.minable and m_p.products then
        counter = counter + count
        for _, p in pairs(m_p.products) do
          local amount = p.amount
          if p.amount_min and p.amount_max then
            amount = (p.amount_min + p.amount_max) / 2
            amount = amount * p.probability
          end
          dest[p.type]["normal"][p.name] = (dest[p.type]["normal"][p.name] or 0) + (amount or 0) * count
        end
      end
    end
  else
    for name, count in pairs(source) do
      local m_p = prototypes[name].mineable_properties
      if m_p and m_p.minable and m_p.products then
        counter = counter + count
      end
    end
  end
  return counter
end

local function count_placeable(prototypes, source, dest, merge)
  --source[quality][name]=count
  --dest[type][quality][name]=count
  if not source then return 0 end
  local counter = 0
  if merge then
    for q, q_list in pairs(source) do
      for name, count in pairs(q_list) do
        local itpt = prototypes[name].items_to_place_this
        if itpt and (#itpt > 0) then
          counter = counter + count
          local i_name = itpt[1].name
          dest.item[q][i_name] = (dest.item[q][i_name] or 0) + (itpt[1].count or 0) * count
        end
      end
    end
  else
    for _, q_list in pairs(source) do
      for name, count in pairs(q_list) do
        local itpt = prototypes[name].items_to_place_this
        if itpt and (#itpt > 0) then
          counter = counter + count
        end
      end
    end
  end
  return counter
end

---Scan the area for entitys
function AreaScanner.scan_resources(scanner)
  if not scanner then return end
  if not scanner.entity.valid then return end

  local force = scanner.entity.force
  local surface = scanner.entity.surface
  local scan_area_settings = scanner.current
  local scan_area = AreaScanner.get_scan_area(scanner.entity.position, scan_area_settings)
  local filter = scan_area_settings.filter --Refer to AreaScanner.FILTER_MASK_ORDER to understand the meaning of bitmasks.

  local areas, uncharted = RB_util.find_charted_areas(force, surface, scan_area)
  local scans -- See the description of AreaScanner.scan_area
  if #areas == 1 then --Both scanning functions must be consistent!
    scans = AreaScanner.scan_area_no_hash(surface, areas[1], force, filter)
  else
    scans = AreaScanner.scan_area(surface, areas, force, filter)
  end

  scans.counters.uncharted = uncharted
  local band = bit32.band
  local ql = RB_util.get_quality_lists
  if band(filter, 512) > 0 then --water
    local water = 0
    for _, area in pairs(areas)do
      local a = table.deepcopy(area)
      RB_util.area_shrink_1_pixel(a)
      water = water + surface.count_tiles_filtered{area = a, collision_mask = "water_tile"}
    end
    scans.counters.water = water
  end
  if band(filter, 4112) > 0 then --ghost_tiles
    local t = ql()
    for _, area in pairs(areas)do
      local a = table.deepcopy(area)
      RB_util.area_shrink_1_pixel(a)
      for _, entity in pairs(surface.find_entities_filtered{area = a, force = force, name = "tile-ghost"}) do
        local n = entity.ghost_name
        local q = entity.quality.name
        t[q][n] = (t[q][n] or 0) + 1
      end
    end
    scans.ghost_tiles = t
  end
  if band(filter, 65536) > 0 then --to_be_deconstructed tiles
    local t = {} -- Tiles do not have quality.
    for _, area in pairs(areas)do
      local a = table.deepcopy(area)
      RB_util.area_shrink_1_pixel(a)
      for _, entity in pairs(surface.find_tiles_filtered{area = a, force = force, to_be_deconstructed = true}) do
        local n = entity.name
        t[n] = (t[n] or 0) + 1
      end
    end
    scans.to_be_deconstructed_tiles = {}
    scans.to_be_deconstructed_tiles.normal = t
  end

  local result1 = {item = ql(), fluid = ql(), virtual = ql()} -- counters, ore, trees, rocks, fish
  local result2 = {item = ql(), fluid = ql(), virtual = ql()} -- buildings, ghosts, items on ground
  if band(filter, 2) > 0 then count_mineable(prototypes.entity, scans.resources, result1, true) end --show_resources
  scans.counters.trees_and_rocks = count_mineable(prototypes.entity, scans.environment, result1, (band(filter, 4) > 0)) --show_environment
  if band(filter, 32) > 0 then result2.item = scans.items_on_ground end --show_items_on_ground
  scans.counters.buildings = count_placeable(prototypes.entity, scans.buildings, result2, (band(filter, 8) > 0)) --show_buildings
  scans.counters.ghosts = count_placeable(prototypes.entity, scans.ghosts, result2, (band(filter, 16) > 0))
                        + count_placeable(prototypes.tile, scans.ghost_tiles, result2, (band(filter, 16) > 0)) --show_ghosts
  --to_be_deconstructed_tiles does not require counting because it counts as "deconstructible-tile-proxy" entity.
  count_placeable(prototypes.entity, scans.to_be_deconstructed, result2, (band(filter, 65536) > 0))
  count_placeable(prototypes.tile, scans.to_be_deconstructed_tiles, result2, (band(filter, 65536) > 0)) --show to_be_deconstructed

  -- Copy resources to combinator output
  local behavior_section = RB_util.clear_constant_combinator(AreaScanner.get_or_create_output_behavior(scanner))
  if not behavior_section or not behavior_section.valid then return end
  local index = 1

  -- Counters
  local counters = scanner.settings or AreaScanner.DEFAULT_SCANNER_SETTINGS
  counters = counters.counters or AreaScanner.DEFAULT_SCANNER_SETTINGS.counters
  local c_filter = AreaScanner.get_list_from_filter(filter).counters
  for name, counter_setting in pairs(counters) do
    local signal = counter_setting.signal
    if c_filter[name] and signal then
      local count = scans.counters[name]
      if count and count ~= 0 then
        signal.quality = "normal"
        signal.comparator = "="
        if counter_setting.is_negative then count = -count end
        count = AreaScanner.check_scan_signal_collision(count, result1, signal)
        count = AreaScanner.check_scan_signal_collision(count, result2, signal)
        if count > 2147483647 then count = 2147483647 end -- Avoid int32 overflow
        if count < -2147483648 then count = -2147483648 end
                                ---@diagnostic disable-next-line: missing-fields
        behavior_section.set_slot(index, {value=signal, min=count})
        index = index + 1
      end
    end
  end
  -- ore, trees, rocks, fish
  for t, t_list in pairs(result1) do
    for q, q_list in pairs(t_list) do
      for n, count in pairs(q_list) do
        if count ~= 0 then
          local signal = {type=t, name=n, quality=q, comparator="="}
          count = AreaScanner.check_scan_signal_collision(count, result2, signal)
          if count > 2147483647 then count = 2147483647 end
                    ---@diagnostic disable-next-line: missing-fields
          behavior_section.set_slot(index, {value=signal, min=count})
          index = index + 1
        end
      end
    end
  end

  -- buildings, ghosts, items on ground
  result1 = {}
  for t, t_list in pairs(result2) do
    for q, q_list in pairs(t_list) do
      for n, c in pairs(q_list) do
        if c ~= 0 then
          if c > 2147483647 then c = 2147483647 end
          table.insert(result1, {value={type=t, name=n, quality=q, comparator="="}, min=c})
        end
      end
    end
  end
  local qlv = storage.quality_levels
  table.sort(result1,
    function(s1, s2)
      if s1.min == s2.min then
        if s1.value.name == s2.value.name then
          return qlv[s1.value.quality] < qlv[s2.value.quality]
        end
        return s1.value.name < s2.value.name
      end
      return s1.min > s2.min
    end
  )
  for _, result in ipairs(result1) do
    --if index > 100 then break end
    behavior_section.set_slot(index, result)
    index = index + 1
  end
end

function AreaScanner.check_scan_signal_collision(count, result, signal)
  if result[signal.type][signal.quality][signal.name] then
    count = count + result[signal.type][signal.quality][signal.name]
    result[signal.type][signal.quality][signal.name] = nil
  end
  return count
end

local function get_enemy_forces(force)
  local forces = {}
  for _, enemy in pairs(game.forces) do
    if force ~= enemy
    and enemy.name ~= "neutral"
    and not force.get_friend(enemy)
    and not force.get_cease_fire(enemy) then
      table.insert(forces, enemy.name)
    end
  end
  return forces
end

local function get_forces_exept(force)
  local forces = {}
  for _, f in pairs(game.forces) do
    if f ~= force then
      table.insert(forces, f.name)
    end
  end
  return forces
end

-- Count the entitys in charted area
-- Output:
--[[
  scans = {
    resources[entity_name] = 0,
    environment[entity_name] = 0,
          buildings[quality_name][entity_name] = 0,
             ghosts[quality_name][entity_name] = 0,
        ghost_tiles[quality_name][entity_name] = 0, -- It is added outside of this function because it counts tiles.
    items_on_ground[quality_name][entity_name] = 0,
    counters = {
      uncharted = 0, -- It is added outside of this function because it counts chunks.
      cliffs = 0,
      targets = 0,
      water = 0, -- It is added outside of this function because it counts tiles.
      resources = 0,
      buildings = 0, -- It is counted from the outside as mineable.
      ghosts = 0, -- It is counted from the outside as mineable.
      items_on_ground = 0,
      trees_and_rocks = 0, -- It is counted from the outside as mineable.
      to_be_deconstructed = 0,
    }
  }
]]
function AreaScanner.scan_area(surface, areas, scanner_force, filter)
  local band = bit32.band
  local ql = RB_util.get_quality_lists
  local ROCKS = storage.rocks_names2
  local INFINITE_RESOURCES = storage.infinite_resources
  local resources = {}
  local environment = {}
  local buildings = ql()
  local ghosts = ql()
  local items_on_ground = ql()
  local to_be_deconstructed = ql()
  local counters = {resources = 0, cliffs = 0, items_on_ground = 0, to_be_deconstructed = 0, targets = 0}

  if band(filter, 1026) > 0 then -- Ore
    local blacklist = {}
    local count = 0
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
        local e_pos  = entity.position
        local hash = entity.name .. "_" .. e_pos.x .. "_" .. e_pos.y
        if not blacklist[hash] then
          local e_name = entity.name
          local amount = entity.amount
          if INFINITE_RESOURCES[e_name] then amount = 1 end
          resources[e_name] = (resources[e_name] or 0) + amount
          count = count + 1
          blacklist[hash] = true
        end
      end
    end
    counters.resources = count
  end -- Ore

  if band(filter, 16388) > 0 then -- Trees, fish, rocks
    local blacklist = {}
    local blacklist_rocks = {}
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, type = {"tree", "fish"}}) do
        local e_pos  = entity.position
        local e_name = entity.name
        local hash = e_name .. "_" .. e_pos.x .. "_" .. e_pos.y
        if not blacklist[hash] then
          environment[e_name] = (environment[e_name] or 0) + 1
          blacklist[hash] = true
        end
      end
      for _, entity in pairs(surface.find_entities_filtered{area = area, name = ROCKS}) do
        local e_pos  = entity.position
        local e_name = entity.name
        local hash = e_name .. "_" .. e_pos.x .. "_" .. e_pos.y
        if not blacklist_rocks[hash] then
          environment[e_name] = (environment[e_name] or 0) + 1
          blacklist_rocks[hash] = true
        end
      end
    end
  end -- Trees, fish, rocks

  if band(filter, 2056) > 0 then -- Buildings
    local blacklist = {}
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, force = get_forces_exept(scanner_force), name = "entity-ghost", invert=true}) do
        local n = entity.name
        local p  = entity.position
        local hash = n .. "_" .. p.x .. "_" .. p.y
        if not blacklist[hash] then
          local q = entity.quality.name
          buildings[q][n] = (buildings[q][n] or 0) + 1
          blacklist[hash] = true
        end
      end
    end
  end -- Buildings

  if band(filter, 4112) > 0 then -- Ghosts
    local blacklist = {}
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, force = scanner_force, name = "entity-ghost"}) do
        local n = entity.ghost_name
        local p  = entity.position
        local hash = n .. "_" .. p.x .. "_" .. p.y
        if not blacklist[hash] then
          local q = entity.quality.name
          ghosts[q][n] = (ghosts[q][n] or 0) + 1
          blacklist[hash] = true
        end
      end
    end
  end -- Ghosts

  if band(filter, 98304) > 0 then -- to_be_deconstructed
    local blacklist = {}
    local count = 0
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, force = scanner_force, to_be_deconstructed = true}) do
        local e_pos  = entity.position
        local hash = entity.name .. "_" .. e_pos.x .. "_" .. e_pos.y
        if not blacklist[hash] then
          count = count + 1
          local n = entity.name
          local q = entity.quality.name
          to_be_deconstructed[q][n] = (to_be_deconstructed[q][n] or 0) + 1
          blacklist[hash] = true
        end
      end
    end
    counters.to_be_deconstructed = count
  end -- to_be_deconstructed

  if band(filter, 8224) > 0 then -- Items on ground
    local blacklist = {}
    local count = 0
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, type = "item-entity"}) do
        local p  = entity.position
        local hash = entity.name .. "_" .. p.x .. "_" .. p.y
        if not blacklist[hash] then
          local s = entity.stack
          local q = s.quality.name
          items_on_ground[q][s.name] = (items_on_ground[q][s.name] or 0) + s.count
          count = count + 1
          blacklist[hash] = true
        end
      end
    end
    counters.items_on_ground = count
  end -- Items on ground

  if band(filter, 128) > 0 then -- Cliffs
    local blacklist = {}
    local count = 0
    for _, area in pairs(areas) do
      for _, entity in pairs(surface.find_entities_filtered{area = area, type = "cliff"}) do
        local e_pos  = entity.position
        local hash = entity.name .. "_" .. e_pos.x .. "_" .. e_pos.y
        if not blacklist[hash] then
          count = count + 1
          blacklist[hash] = true
        end
      end
    end
    counters.cliffs = count
  end -- Cliffs

  if band(filter, 256) > 0 then -- Enemy base
    local forces = get_enemy_forces(scanner_force)
    if #forces > 0 then
      local blacklist = {}
      local count = 0
      for _, area in pairs(areas) do
        for _, entity in pairs(surface.find_entities_filtered{area = area, force = forces, type = MILITARY_STRUCTURES_LIST}) do
          local e_pos  = entity.position
          local hash = entity.name .. "_" .. e_pos.x .. "_" .. e_pos.y
          if not blacklist[hash] then
            count = count + 1
            blacklist[hash] = true
          end
        end
      end
      counters.targets = count
    end
  end -- Enemy base

  return {resources = resources, environment = environment, buildings = buildings, ghosts = ghosts, items_on_ground = items_on_ground, counters = counters, to_be_deconstructed = to_be_deconstructed}
end

-- Almost a complete copy of "AreaScanner.scan_area()"
function AreaScanner.scan_area_no_hash(surface, area, scanner_force, filter)
  local band = bit32.band
  local ql = RB_util.get_quality_lists
  local ROCKS = storage.rocks_names2
  local INFINITE_RESOURCES = storage.infinite_resources
  local resources = {}
  local environment = {}
  local buildings = ql()
  local ghosts = ql()
  local items_on_ground = ql()
  local to_be_deconstructed = ql()
  local counters = {resources = 0, cliffs = 0, items_on_ground = 0, to_be_deconstructed = 0, targets = 0}

  if band(filter, 2) > 0 then -- Ore
    for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
      local e_name = entity.name
      local amount = entity.amount
      if INFINITE_RESOURCES[e_name] then amount = 1 end
      resources[e_name] = (resources[e_name] or 0) + amount
    end
  end -- Ore

  if band(filter, 1024) > 0 then -- ore count
    counters.resources = surface.count_entities_filtered{area = area, type = "resource"}
  end  -- ore count

  if band(filter, 16388) > 0 then -- Trees, fish, rocks
    for _, entity in pairs(surface.find_entities_filtered{area = area, type = {"tree", "fish"}}) do
      local e_name = entity.name
      environment[e_name] = (environment[e_name] or 0) + 1
    end
    for _, entity in pairs(surface.find_entities_filtered{area = area, name = ROCKS}) do
      local e_name = entity.name
      environment[e_name] = (environment[e_name] or 0) + 1
    end
  end -- Trees, fish, rocks

  if band(filter, 2056) > 0 then -- Buildings
    for _, entity in pairs(surface.find_entities_filtered{area = area, force = get_forces_exept(scanner_force), name = "entity-ghost", invert=true}) do
      local n = entity.name
      local q = entity.quality.name
      buildings[q][n] = (buildings[q][n] or 0) + 1
    end
  end -- Buildings

  if band(filter, 4112) > 0 then -- Ghosts
    for _, entity in pairs(surface.find_entities_filtered{area = area, force = scanner_force, name = "entity-ghost"}) do
      local n = entity.ghost_name
      local q = entity.quality.name
        ghosts[q][n] = (ghosts[q][n] or 0) + 1
    end
  end -- Ghosts

  if band(filter, 32768) > 0 then -- to_be_deconstructed count
    counters.to_be_deconstructed = surface.count_entities_filtered{area = area, force = scanner_force, to_be_deconstructed = true}
  end -- to_be_deconstructed count

  if band(filter, 65536) > 0 then -- to_be_deconstructed entitys
    for _, entity in pairs(surface.find_entities_filtered{area = area, force = scanner_force, to_be_deconstructed = true}) do
      local n = entity.name
      local q = entity.quality.name
      to_be_deconstructed[q][n] = (to_be_deconstructed[q][n] or 0) + 1
    end
  end -- to_be_deconstructed entitys

  if band(filter, 8224) > 0 then -- Items on ground
    local count = 0
    for _, entity in pairs(surface.find_entities_filtered{area = area, type = "item-entity"}) do
      local s = entity.stack
      local q = s.quality.name
      items_on_ground[q][s.name] = (items_on_ground[q][s.name] or 0) + s.count
      count = count + 1
    end
    counters.items_on_ground = count
  end -- Items on ground

  if band(filter, 128) > 0 then -- Cliffs
    counters.cliffs = surface.count_entities_filtered{area = area, type = "cliff"}
  end -- Cliffs

  if band(filter, 256) > 0 then -- Enemy base
    local forces = get_enemy_forces(scanner_force)
    if #forces > 0 then
      counters.targets = surface.count_entities_filtered{area = area, force = forces, type = MILITARY_STRUCTURES_LIST}
    end
  end -- Enemy base

  return {resources = resources, environment = environment, buildings = buildings, ghosts = ghosts, items_on_ground = items_on_ground, counters = counters, to_be_deconstructed = to_be_deconstructed}
end

-- Out of bounds check.
-- Limit width/height to 999 for better performance.
function AreaScanner.sanitize_area(key, value)
  if key == "width" or key == "height" then
    if value < 0 then value = 0 end
    if value > 999 then value = 999 end
  elseif key ~= "filter" then
    if value > 8388600 then value = 8388600 end
    if value < -8388600 then value = -8388600 end
  end
  return value
end

-- Delete signals from uninstalled mods
function AreaScanner.mark_unknown_signals(scanner_settings)
  if not scanner_settings then return end
  for _, signal in pairs(scanner_settings.scan_area or {}) do
    if type(signal) == "table" and not GUI_util.get_signal_sprite(signal) then
      signal = {type = "virtual", name = "signal-dot"}
    end
  end
  for _, signal in pairs(scanner_settings.counters or {}) do
    if not GUI_util.get_signal_sprite(signal.signal) then
      signal.signal = {type = "virtual", name = "signal-dot"}
    end
  end
end

function AreaScanner.get_list_from_filter(bitmap)
  local pow = math.pow
  local band = bit32.band
  local list = {filters={}, counters={}}
  for i, filter in pairs(AreaScanner.FILTER_MASK_ORDER) do
    list[filter.group][filter.name] = (band(bitmap, pow(2, i-1)) ~= 0)
  end
  return list
end

function AreaScanner.get_filter_from_list(list)
  local bitmap = 0
  local pow = math.pow
  for i, filter in pairs(AreaScanner.FILTER_MASK_ORDER) do
    if list[filter.group][filter.name] then bitmap = bitmap + pow(2, i-1) end
  end
  return bitmap
end

function AreaScanner.cache_infinite_resources()
  local resources={}
  local filter = {{filter = "type", type = "resource"}}
  for name, e_prototype in pairs(prototypes.get_entity_filtered(filter)) do
    if e_prototype.infinite_resource  then
      resources[name] = true
    end
  end
  storage.infinite_resources = resources
end

function AreaScanner.toggle_default_settings()
  if settings.global["recursive-blueprints-old-scaner-default"].value then
    AreaScanner.DEFAULT_SCANNER_SETTINGS = OLD_SCANNER_SETTINGS
  else
    AreaScanner.DEFAULT_SCANNER_SETTINGS = NEW_SCANNER_SETTINGS
  end
end

---Calculate the scanning area based on the position and settings of the scanner.
---@param scaner_position MapPosition
---@param area_settings table
---@return BoundingBox
function AreaScanner.get_scan_area(scaner_position, area_settings)
  local x = area_settings.x
  local y = area_settings.y
  local w = area_settings.width
  local h = area_settings.height
  local area
  if settings.global["recursive-blueprints-area"].value == "corner" then
    area = {
      {scaner_position.x + x, scaner_position.y + y},
      {scaner_position.x + x + w, scaner_position.y + y + h}
    }
  else
    -- Align to grid
    if w % 2 ~= 0 then x = x + 0.5 end
    if h % 2 ~= 0 then y = y + 0.5 end
    area = {
      {scaner_position.x + x - w/2, scaner_position.y + y - h/2},
      {scaner_position.x + x + w/2, scaner_position.y + y + h/2}
    }
  end
  RB_util.area_normalize(area)
  RB_util.area_check_limits(area)
  return area
end

--AreaScanner.toggle_default_settings()
AreaScanner.DEFAULT_SCANNER_SETTINGS = NEW_SCANNER_SETTINGS
return AreaScanner
