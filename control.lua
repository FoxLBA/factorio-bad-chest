require "util"
local Deployer = require "lualib.deployer"
local Deployer2 = require "lualib.deployer2"
RB_util = require "lualib.rb-util"
GUI_util = require "lualib.gui-util"
AreaScannerGUI = require "lualib.scanner-gui"
AreaScanner = require "lualib.scanner"
local OC_Tool = require "lualib.tool"

local function init_caches()
  RB_util.cache_in_storage()
  GUI_util.cache_signals()
  AreaScanner.cache_infinite_resources()
  -- Check deleted signals in the default scanner settings.
  AreaScanner.mark_unknown_signals(AreaScanner.DEFAULT_SCANNER_SETTINGS)
end

local function dolly_moved_entity(event)
  local entity = event.moved_entity ---@type LuaEntity
  local scanner = storage.scanners[entity.unit_number]
  if scanner and scanner.output_entity and scanner.output_entity.valid then
    scanner.output_entity.teleport(entity.position)
    return
  end
  local deployer2 = storage.deployers2[entity.unit_number]
  if deployer2 then deployer2:dolly_moved() end
end

local function register_events()
  if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["dolly_moved_entity_id"] then
    script.on_event(remote.call("PickerDollies", "dolly_moved_entity_id"), dolly_moved_entity)
  end
end

local function on_init()
  storage.deployers = {}
  storage.deployers2 = {}
  storage.scanners = {}
  storage.blueprints = {}
  init_caches()
  register_events()
end

local function on_mods_changed(event)
  init_caches()
  if not storage.deployers2 then storage.deployers2 = {} end

  --Migrate deployers and scanners to new mod name
  if (event and event.mod_changes) and
  (event.mod_changes["recursive-blueprints"]
  and event.mod_changes["recursive-blueprints"].old_version) then
    for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities_filtered({name = {"blueprint-deployer", "recursive-blueprints-scanner"}})) do
        if entity.name == "blueprint-deployer" then
          storage.deployers[entity.unit_number] = entity
        elseif entity.name == "recursive-blueprints-scanner" then
          AreaScanner.on_built(entity, {})
        end
      end
    end
  end

  --Migrate to new scanner data format (changed in 1.3.11).
  if (event and event.mod_changes)
  and (event.mod_changes["rec-blue-plus"]
  and event.mod_changes["rec-blue-plus"].old_version) then
    if RB_util.check_verion(event.mod_changes["rec-blue-plus"].old_version, "1.3.11") then
      for _, scanner in pairs(storage.scanners or {}) do
        AreaScanner.on_built(scanner.entity, {tags = scanner})
      end
    end
  end

  --Migrate to new scanner io (changed in 1.4.1).
  if (event and event.mod_changes)
  and (event.mod_changes["rec-blue-plus"]
  and event.mod_changes["rec-blue-plus"].old_version) then
    if RB_util.check_verion(event.mod_changes["rec-blue-plus"].old_version, "1.4.1") then
      for i, scanner in pairs(storage.scanners or {}) do
        local entity = scanner.entity
        if entity.valid then
          local old_behavior = entity.get_control_behavior()
          local b = AreaScanner.get_or_create_output_behavior(scanner)
          if (old_behavior.sections_count > 0) and (old_behavior.sections[1].filters_count > 0) then
            b.sections[1].filters = old_behavior.sections[1].filters
          end
          RB_util.clear_constant_combinator(old_behavior)
        else
          AreaScanner.on_destroyed(i)
        end
      end
    end
  end

  -- Delete signals from uninstalled mods
  for _, scanner in pairs(storage.scanners) do
    AreaScanner.mark_unknown_signals(scanner.settings)
  end

  -- Construction robotics unlocks recipes
  for _, force in pairs(game.forces) do
    if force.technologies["construction-robotics"]
    and force.technologies["construction-robotics"].researched then
      force.recipes["blueprint-deployer"].enabled = true
      force.recipes["blueprint-deployer2"].enabled = true
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
end

local function on_setting_changed(event)
  if event.setting == "recursive-blueprints-area" then
    -- Refresh scanners
    for _, scanner in pairs(storage.scanners) do
      AreaScanner.scan_resources(scanner)
    end
  elseif event.setting == "recursive-blueprints-logging" then
    Deployer.toggle_logging()
    Deployer2.toggle_logging()
  elseif event.setting == "recursive-blueprints-deployer-deploy-signal" then
    Deployer.toggle_deploy_signal_setting()
  end
end

local function on_tick()
  Deployer.on_tick()
  AreaScanner.on_tick()
  Deployer2.on_tick()
end

local function on_built(event)
  local entity = event.created_entity or event.entity or event.destination
  if not entity or not entity.valid then return end

  if entity.name == "blueprint-deployer" then
    Deployer.on_built(entity)
  elseif entity.name == "blueprint-deployer2" then
    Deployer2.on_built(entity)
  elseif entity.name == "recursive-blueprints-scanner" then
    AreaScanner.on_built(entity, event)
  end
end

local function on_object_destroyed(event)
  if not event.useful_id then return end
  if event.type ~= defines.target_type.entity then return end
  local id = event.useful_id
  AreaScanner.on_destroyed(id)
  Deployer.on_destroyed(id)
  Deployer2.on_destroy(id)
end

local function on_player_setup_blueprint(event)
  -- Find the blueprint item
  local player = game.get_player(event.player_index)
  local stack = event.stack
  local bp = nil
  if player and player.blueprint_to_setup and player.blueprint_to_setup.valid_for_read then bp = player.blueprint_to_setup
  --  elseif player and player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint then bp = player.cursor_stack end
  elseif stack and stack.valid_for_read and stack.is_blueprint then bp = stack end
  if not bp or not bp.is_blueprint_setup() then
    -- Maybe the player is selecting new contents for a blueprint?
    bp = storage.blueprints[event.player_index]
  end

  if bp and bp.valid and bp.is_blueprint and bp.is_blueprint_setup() then
    local mapping = event.mapping.get()
    for index, entity in pairs(mapping) do
      if entity and entity.name and entity.name == "recursive-blueprints-scanner" then
        local tags = AreaScanner.serialize(entity)
        if tags then bp.set_blueprint_entity_tags(index, tags) end
      end
    end
  end
end

local function on_gui_opened(event)
  -- Save a reference to the blueprint item in case the player selects new contents
  storage.blueprints[event.player_index] = nil
  if event.gui_type == defines.gui_type.item
  and event.item
  and event.item.valid_for_read
  and event.item.is_blueprint then
    storage.blueprints[event.player_index] = event.item
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
script.on_load(register_events)
script.on_configuration_changed(on_mods_changed)
---@diagnostic disable: param-type-mismatch
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_closed, on_gui_closed)
script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_confirmed, on_gui_confirmed)
script.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)
script.on_event(defines.events.on_gui_value_changed, on_gui_value_changed)
script.on_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
script.on_event(defines.events.on_runtime_mod_setting_changed, on_setting_changed)
script.on_event(defines.events.on_gui_checked_state_changed, on_gui_checked_state_changed)

-- Ignore ghost build events
local filter = {
  {filter = "name", name = "blueprint-deployer"},
  {filter = "name", name = "blueprint-deployer2"},
  {filter = "name", name = "recursive-blueprints-scanner"},
}
script.on_event(defines.events.on_built_entity, on_built, filter)
script.on_event(defines.events.on_entity_cloned, on_built, filter)
script.on_event(defines.events.on_robot_built_entity, on_built, filter)
script.on_event(defines.events.script_raised_built, on_built, filter)
script.on_event(defines.events.script_raised_revive, on_built, filter)
script.on_event(defines.events.on_space_platform_built_entity, on_built, filter)

script.on_event(defines.events.on_player_selected_area, OC_Tool.on_player_selected_area)
script.on_event(defines.events.on_player_alt_selected_area, OC_Tool.on_player_alt_selected_area)
script.on_event(defines.events.on_player_reverse_selected_area, OC_Tool.on_player_reverse_selected_area)
--script.on_event(defines.events.on_player_alt_reverse_selected_area, OM_Tool.on_player_alt_reverse_selected_area)
--script.on_event(defines.events.on_mod_item_opened, OM_Tool.on_mod_item_opened)
