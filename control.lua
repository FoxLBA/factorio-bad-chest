require "util"
require "lualib.logging"
require "lualib.common"
require "lualib.deployer"
RB_util = require "lualib.rb-util"
GUI_util = require "lualib.gui-util"
AreaScannerGUI = require "lualib.scanner-gui"
AreaScanner = require "lualib.scanner"

local function on_init()
  global.deployers = {}
  global.fuel_requests = {}
  global.scanners = {}
  global.blueprints = {}
  GUI_util.cache_signals()
  AreaScanner.mark_unknown_signals(AreaScanner.DEFAULT_SCANNER_SETTINGS)
  cache_blueprint_signals()
end

local function on_mods_changed(event)
  global.blueprints = {}

  -- Check deleted signals in the default scanner settings.
  GUI_util.cache_signals()
  AreaScanner.mark_unknown_signals(AreaScanner.DEFAULT_SCANNER_SETTINGS)

  --Migrate deployers and scanners to new mod name
  if (event and event.mod_changes) and
  (event.mod_changes["recursive-blueprints"]
  and event.mod_changes["recursive-blueprints"].old_version) then
    for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities_filtered({name = {"blueprint-deployer", "recursive-blueprints-scanner"}})) do
        if entity.name == "blueprint-deployer" then
          global.deployers[entity.unit_number] = entity
        elseif entity.name == "recursive-blueprints-scanner" then
          AreaScanner.on_built_scanner(entity, {})
        end
      end
    end
  end

  --Migrate to new scanner data format.
  if (event and event.mod_changes)
  and (event.mod_changes["rec-blue-plus"]
  and event.mod_changes["rec-blue-plus"].old_version
  and event.mod_changes["rec-blue-plus"].old_version < "1.3.1") then
    for _, scanner in pairs(global.scanners or {}) do
      if not scanner.settings then
        AreaScanner.on_built_scanner(scanner.entity, {tags = scanner})
      end
    end
  end

  -- Delete signals from uninstalled mods
  if not global.scanners then global.scanners = {} end
  for _, scanner in pairs(global.scanners) do
    AreaScanner.mark_unknown_signals(scanner.settings)
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

  cache_blueprint_signals()
end

local function on_setting_changed(event)
  if event.setting == "recursive-blueprints-area" then
    -- Refresh scanners
    for _, scanner in pairs(global.scanners) do
      AreaScanner.scan_resources(scanner)
    end
  end
end

local function on_tick()
  for _, deployer in pairs(global.deployers) do
    on_tick_deployer(deployer)
  end
  for _, scanner in pairs(global.scanners) do
    AreaScanner.on_tick_scanner(scanner)
  end
end

local function on_built(event)
  local entity = event.created_entity or event.entity or event.destination
  if not entity or not entity.valid then return end

  -- Support automatic mode for trains
  if entity.train then
    RB_util.on_built_carriage(entity, event.tags)
    return
  end

  if entity.name == "blueprint-deployer" then
    global.deployers[entity.unit_number] = entity
  elseif entity.name == "recursive-blueprints-scanner" then
    AreaScanner.on_built_scanner(entity, event)
  end
end

local function on_entity_destroyed(event)
  if not event.unit_number then return end
  RB_util.on_item_request(event.unit_number)
  AreaScanner.on_destroyed_scanner(event.unit_number)
end

local function on_player_setup_blueprint(event)
  -- Find the blueprint item
  local player = game.get_player(event.player_index)
  local bp = nil
  if player and player.blueprint_to_setup and player.blueprint_to_setup.valid_for_read then bp = player.blueprint_to_setup
  elseif player and player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint then bp = player.cursor_stack end
  if not bp or not bp.is_blueprint_setup() then
    -- Maybe the player is selecting new contents for a blueprint?
    bp = global.blueprints[event.player_index]
  end

  if bp and bp.is_blueprint_setup() then
    local mapping = event.mapping.get()
    local blueprint_entities = bp.get_blueprint_entities()
    local found = false
    if blueprint_entities then
      for _, bp_entity in pairs(blueprint_entities) do
        local entity = mapping[bp_entity.entity_number]
        if entity.train and not entity.train.manual_mode then
          --Add train tags for automatic mode
          found = true
          if not bp_entity.tags then bp_entity.tags = {} end
          bp_entity.tags.automatic_mode = true
          bp_entity.tags.length = #entity.train.carriages

        elseif bp_entity.name == "recursive-blueprints-scanner" then
          found = true
          bp_entity.control_behavior = nil
          if entity then
            bp_entity.tags = AreaScanner.serialize(entity)
          end
        end
      end
      if found then
        bp.set_blueprint_entities(blueprint_entities)
      end
    end
  end
end

local function on_gui_opened(event)
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
    local player = game.players[event.player_index]
    player.opened = AreaScannerGUI.create_scanner_gui(player, event.entity)
  end
end

local function on_gui_closed(event)
  -- Remove scanner gui
  if event.gui_type == defines.gui_type.custom
  and event.element
  and event.element.valid
  and event.element.name == "recursive-blueprints-scanner" then
    AreaScannerGUI.destroy_gui(event.element)
  end
end

local function on_gui_click(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-close" then
    -- Remove gui
    AreaScannerGUI.destroy_gui(event.element)
  elseif name == "recursive-blueprints-signal-select-button" then
    -- Open the signal gui to pick a value
    AreaScannerGUI.create_signal_gui(event.element)
  elseif name == "recursive-blueprints-set-constant" then
    -- Copy constant value back to scanner gui
    AreaScannerGUI.set_scanner_value(event.element)
  elseif name == "recursive-blueprints-counter-settings" then
    AreaScannerGUI.toggle_counter_settings_frame(event.element)
  elseif name == "recursive-blueprints-reset-counters" then
    AreaScannerGUI.reset_counter_settings(event.element)
  elseif name == "" and event.element.tags then
    local tags = event.element.tags
    if tags["recursive-blueprints-signal"] then
      AreaScannerGUI.set_scanner_signal(event.element)
    elseif tags["recursive-blueprints-tab-index"] then
      GUI_util.select_tab_by_index(event.element, tags["recursive-blueprints-tab-index"])
    end
  end
end

local function on_gui_confirmed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-constant" then
    -- Copy constant value back to scanner gui
    AreaScannerGUI.set_scanner_value(event.element)
  elseif name == "recursive-blueprints-filter-constant" then
    AreaScannerGUI.set_scanner_value(event.element)
  end
end

local function on_gui_text_changed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-constant" then
    -- Update slider
    AreaScannerGUI.copy_text_value(event.element)
  elseif name == "recursive-blueprints-filter-constant" then
    AreaScannerGUI.copy_filter_text_value(event.element)
  end
end

local function on_gui_value_changed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end

  if name == "recursive-blueprints-slider" then
    -- Update number field
    AreaScannerGUI.copy_slider_value(event.element)
  end
end

local function on_gui_checked_state_changed(event)
  if not event.element.valid then return end
  local name = event.element.name
  if not name then return end
  if name == "recursive-blueprints-counter-checkbox" then
    AreaScannerGUI.counter_checkbox_change(event.element)
  elseif name == "" and event.element.tags then
    local tags = event.element.tags
    if tags["recursive-blueprints-filter-checkbox-field"] then
      AreaScannerGUI.copy_filter_value(event.element)
    end
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
script.on_event(defines.events.on_gui_checked_state_changed, on_gui_checked_state_changed)

-- Ignore ghost build events
local filter = {{filter = "ghost", invert = true}}
script.on_event(defines.events.on_built_entity, on_built, filter)
script.on_event(defines.events.on_entity_cloned, on_built, filter)
script.on_event(defines.events.on_robot_built_entity, on_built, filter)
script.on_event(defines.events.script_raised_built, on_built, filter)
script.on_event(defines.events.script_raised_revive, on_built, filter)
