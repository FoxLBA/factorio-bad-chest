require "util"
require "lualib.common"
require "lualib.deployer"
require "lualib.scanner"

function on_init()
  global.deployers = {}
  global.fuel_requests = {}
  global.networks = {}
  global.scanners = {}
  global.blueprints = {}
  on_mods_changed()
end

function on_mods_changed(event)
  global.deployer_index = nil
  global.cliff_explosives = (game.item_prototypes["cliff-explosives"] ~= nil)
  global.artillery_shell = (game.item_prototypes["artillery-shell"] ~= nil)
  if not global.networks then
    global.networks = {}
  end
  global.blueprints = {}

  -- Migrations
  if event
  and event.mod_changes
  and event.mod_changes["recursive-blueprints"]
  and event.mod_changes["recursive-blueprints"].old_version then
    -- Migrate fuel requests
    if event.mod_changes["recursive-blueprints"].old_version < "1.1.5" then
      local new_fuel_requests = {}
      for _, request in pairs(global.fuel_requests or {}) do
        if request.proxy and request.proxy.valid then
          new_fuel_requests[request.proxy.unit_number] = request.entity
        end
      end
      global.fuel_requests = new_fuel_requests
    end
    -- Migrate deployer index
    if event.mod_changes["recursive-blueprints"].old_version < "1.1.8" then
      global.net_cache = nil
      local new_deployers = {}
      for _, deployer in pairs(global.deployers or {}) do
        if deployer.valid then
          new_deployers[deployer.unit_number] = deployer
        end
      end
      global.deployers = new_deployers
    end
  end

  -- Construction robotics unlocks recipes
  for _, force in pairs(game.forces) do
    if force.technologies["construction-robotics"]
    and force.technologies["construction-robotics"].researched then
      force.recipes["blueprint-deployer"].enabled = true
      force.recipes["recursive-blueprints-scanner"].enabled = true
    end
  end

  -- Close all scanner guis
  for _, player in pairs(game.players) do
    if player.opened
    and player.opened.object_name == "LuaGuiElement"
    and player.opened.name:sub(1, 21) == "recursive-blueprints-" then
      player.opened = nil
    end
  end

  -- Delete signals from uninstalled mods
  if not global.scanners then global.scanners = {} end
  for _, scanner in pairs(global.scanners) do
    mark_unknown_signals(scanner)
  end

  cache_blueprint_signals()
  cache_scanner_signals()
end

function on_setting_changed(event)
  if event.setting == "recursive-blueprints-area" then
    -- Refresh scanners
    for _, scanner in pairs(global.scanners) do
      scan_resources(scanner)
    end
  end
end

function on_tick()
  -- Check one deployer per tick for new circuit network connections
  local index = global.deployer_index
  global.deployer_index = next(global.deployers, global.deployer_index)
  if global.deployers[index] then
    if global.deployers[index].valid then
      update_network(global.deployers[index])
    else
      global.deployers[index] = nil
      global.networks[index] = nil
    end
  end

  -- Read all circuit networks
  for _, network in pairs(global.networks) do
    if network.deployer.valid then
      if network.red and not network.red.valid then
        network.red = nil
      end
      if network.green and not network.green.valid then
        network.green = nil
      end
      if network.deployer.name == "recursive-blueprints-scanner" then
        on_tick_scanner(network)
      else
        on_tick_deployer(network)
      end
    end
  end
end

function on_built(event)
  local entity = event.created_entity or event.entity or event.destination
  if not entity or not entity.valid then return end

  -- Support automatic mode for trains
  if entity.train then
    on_built_carriage(entity, event.tags)
    return
  end

  -- If entity is a blueprint deployer, cache circuit network connections
  if entity.name == "blueprint-deployer" then
    global.deployers[entity.unit_number] = entity
    update_network(entity)
    return
  end

  -- Turn on resource scanner
  if entity.name == "recursive-blueprints-scanner" then
    global.deployers[entity.unit_number] = entity
    on_built_scanner(entity, event)
    return
  end

  -- If neighbor is a blueprint deployer, update circuit network connections
  local connections = entity.circuit_connection_definitions
  if connections then
    for _, connection in pairs(connections) do
      if connection.target_entity.valid
      and connection.target_entity.name == "blueprint-deployer" then
        update_network(connection.target_entity)
      end
    end
  end
end

function on_entity_destroyed(event)
  if not event.unit_number then return end
  on_item_request(event.unit_number)
  on_destroyed_scanner(event.unit_number)
end

function on_player_setup_blueprint(event)
  -- Search the selected area for interesting prototypes
  -- These prototypes help align the blueprint even if they are not used
  local player = game.get_player(event.player_index)
  local entities = player.surface.find_entities_filtered {
    area = event.area,
    force = player.force,
    type = {
      "locomotive",
      "cargo-wagon",
      "fluid-wagon",
      "artillery-wagon",
      "straight-rail",
      "curved-rail",
      "constant-combinator",
    },
  }

  -- Check for scanners and automatic trains
  local found_tag = false
  for _, entity in pairs(entities) do
    if entity.type == "locomotive" and not entity.train.manual_mode then
      found_tag = true
      break
    elseif entity.name == "recursive-blueprints-scanner" then
      found_tag = true
      break
    end
  end
  if not found_tag then return end

  -- Find the blueprint item
  local bp = get_blueprint_to_setup(player) or get_nested_blueprint(player.cursor_stack)
  if not bp or not bp.valid_for_read or not bp.is_blueprint or not bp.is_blueprint_setup() then
    -- Maybe the player is selecting new contents for a blueprint?
    bp = global.blueprints[event.player_index]
  end

  -- Add custom tags to blueprint
  local tags = create_tags(entities)
  add_tags_to_blueprint(tags, bp)
end

function on_gui_opened(event)
  -- Save a reference to the blueprint item in case the player selects new contents
  global.blueprints[event.player_index] = nil
  if event.gui_type == defines.gui_type.item
  and event.item
  and event.item.valid_for_read
  and event.item.is_blueprint then
    global.blueprints[event.player_index] = event.item
  end

  -- Replace constant-combinator gui with scanner gui
  if event.gui_type == defines.gui_type.entity
  and event.entity
  and event.entity.valid
  and event.entity.name == "recursive-blueprints-scanner" then
    local player = game.get_player(event.player_index)
    player.opened = create_scanner_gui(player, event.entity)
  end
end

function on_gui_closed(event)
  -- Remove scanner gui
  if event.gui_type == defines.gui_type.custom
  and event.element
  and event.element.valid
  and event.element.name == "recursive-blueprints-scanner" then
    destroy_gui(event.element)
  end
end

function on_gui_click(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end
  if name:sub(1, 21) ~= "recursive-blueprints-" then return end

  if name == "recursive-blueprints-close" then
    -- Remove gui
    destroy_gui(event.element)
  elseif name:sub(1, 29) == "recursive-blueprints-scanner-" then
    -- Open the signal gui to pick a value
    create_signal_gui(event.element)
  elseif name == "recursive-blueprints-set-constant" then
    -- Copy constant value back to scanner gui
    set_scanner_value(event.element)
  elseif name:sub(1, 28) == "recursive-blueprints-signal-" then
    -- Copy signal back to scanner gui
    set_scanner_signal(event.element)
  elseif name:sub(1, 32) == "recursive-blueprints-tab-button-" then
    -- Switch tabs
    set_signal_gui_tab(event.element, tonumber(name:sub(33)))
  end
end

function on_gui_confirmed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-constant" then
    -- Copy constant value back to scanner gui
    set_scanner_value(event.element)
  end
end

function on_gui_text_changed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-constant" then
    -- Update slider
    copy_text_value(event.element)
  end
end

function on_gui_value_changed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-slider" then
    -- Update number field
    copy_slider_value(event.element)
  end
end

-- Global events
script.on_init(on_init)
script.on_configuration_changed(on_mods_changed)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_closed, on_gui_closed)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_confirmed, on_gui_confirmed)
script.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)
script.on_event(defines.events.on_gui_value_changed, on_gui_value_changed)
script.on_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)
script.on_event(defines.events.on_entity_destroyed, on_entity_destroyed)
script.on_event(defines.events.on_runtime_mod_setting_changed, on_setting_changed)

-- Ignore ghost build events
local filter = {{filter = "ghost", invert = true}}
script.on_event(defines.events.on_built_entity, on_built, filter)
script.on_event(defines.events.on_entity_cloned, on_built, filter)
script.on_event(defines.events.on_robot_built_entity, on_built, filter)
script.on_event(defines.events.script_raised_built, on_built, filter)
script.on_event(defines.events.script_raised_revive, on_built, filter)
