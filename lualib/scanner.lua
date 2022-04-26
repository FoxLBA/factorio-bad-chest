-- Entity status lookup tables
local STATUS_NAME = {
  [defines.entity_status.working] = "entity-status.working",
  [defines.entity_status.disabled] = "entity-status.disabled",
  [defines.entity_status.marked_for_deconstruction] = "entity-status.marked-for-deconstruction",
}
local STATUS_SPRITE = {
  [defines.entity_status.working] = "utility/status_working",
  [defines.entity_status.disabled] = "utility/status_not_working",
  [defines.entity_status.marked_for_deconstruction] = "utility/status_not_working",
}

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

function on_built_scanner(entity, event)
  local scanner = {
    x = 0,
    y = 0,
    width = 64,
    height = 64,
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
  end
  mark_unknown_signals(scanner)
  scanner.entity = entity
  global.scanners[entity.unit_number] = scanner
  script.register_on_entity_destroyed(entity)
  update_scanner_network(scanner)
  scan_resources(scanner)
end

-- Delete signals from uninstalled mods
function mark_unknown_signals(scanner)
  for _, signal in pairs{"x_signal", "y_signal", "width_signal", "height_signal"} do
    if scanner[signal] and not get_signal_sprite(scanner[signal]) then
      scanner[signal] = {type = "virtual", name = "signal-unknown"}
    end
  end
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

-- Copy the signal value from the circuit network
-- Return true if changed, false if not changed
function signal_changed(scanner, network, name, signal_name)
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

function destroy_gui(element)
  local gui = get_root_element(element)
  -- Destroy dependent gui
  local screen = gui.gui.screen
  if gui.name == "recursive-blueprints-scanner" and screen["recursive-blueprints-signal"] then
    screen["recursive-blueprints-signal"].destroy()
  end
  -- Destroy gui
  gui.destroy()
  reset_scanner_gui_style(screen)
end

function get_root_element(element)
  while element.parent.name ~= "screen" do
    element = element.parent
  end
  return element
end

-- Turn off highlighted scanner button
function reset_scanner_gui_style(screen)
  local gui = screen["recursive-blueprints-scanner"]
  if not gui then return end
  local input_flow = gui.children[2].children[3].children[1].children[2]
  for i = 1, 4 do
    input_flow.children[i].children[2].style = "recursive-blueprints-slot"
  end
end

-- Add a titlebar with a drag area and close [X] button
function add_titlebar(gui, drag_target, caption, close_button_name, close_button_tooltip)
  local titlebar = gui.add{type = "flow"}
  titlebar.drag_target = drag_target
  titlebar.add{
    type = "label",
    style = "frame_title",
    caption = caption,
    ignored_by_interaction = true,
  }
  local filler = titlebar.add{
    type = "empty-widget",
    style = "draggable_space",
    ignored_by_interaction = true,
  }
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  if close_button_name then
    titlebar.add{
      type = "sprite-button",
      name = close_button_name,
      style = "frame_action_button",
      sprite = "utility/close_white",
      hovered_sprite = "utility/close_black",
      clicked_sprite = "utility/close_black",
      tooltip = close_button_tooltip,
    }
  end
end

-- Build the scanner gui
function create_scanner_gui(player, entity)
  local scanner = global.scanners[entity.unit_number]

  -- Destroy any old versions
  if player.gui.screen["recursive-blueprints-scanner"] then
    player.gui.screen["recursive-blueprints-scanner"].destroy()
  end

  -- Heading
  local gui = player.gui.screen.add{
    type = "frame",
    name = "recursive-blueprints-scanner",
    direction = "vertical",
    tags = {["recursive-blueprints-id"] = entity.unit_number}
  }
  gui.auto_center = true
  add_titlebar(gui, gui, entity.localised_name, "recursive-blueprints-close", {"gui.close-instruction"})
  local inner_frame = gui.add{
    type = "frame",
    style = "entity_frame",
    direction = "vertical",
  }

  -- Status indicator
  local status_flow = inner_frame.add{
    type = "flow",
    style = "status_flow",
  }
  status_flow.style.vertical_align = "center"
  status_flow.add{
    type = "sprite",
    style = "status_image",
    sprite = STATUS_SPRITE[entity.status],
  }
  status_flow.add{
    type = "label",
    caption = {STATUS_NAME[entity.status]},
  }
  local preview_frame = inner_frame.add{
    type = "frame",
    style = "entity_button_frame",
  }
  local preview = preview_frame.add{
    type = "entity-preview",
  }
  preview.entity = entity
  preview.style.height = 148
  preview.style.horizontally_stretchable = true

  -- Scan area
  local main_flow = inner_frame.add{
    type = "flow",
  }
  local left_flow = main_flow.add{
    type = "flow",
    direction = "vertical",
  }
  left_flow.style.right_margin = 8
  left_flow.add{
    type = "label",
    style = "heading_3_label",
    caption = {"description.scan-area"},
  }
  local input_flow = left_flow.add{
    type = "flow",
    direction = "vertical",
  }
  input_flow.style.horizontal_align = "right"

  -- X button and label
  local x_flow = input_flow.add{
    type = "flow",
  }
  x_flow.style.vertical_align = "center"
  x_flow.add{
    type = "label",
    caption = {"", {"description.x-offset"}, ":"}
  }
  x_flow.add{
    type = "sprite-button",
    style = "recursive-blueprints-slot",
    name = "recursive-blueprints-scanner-x"
  }

  -- Y button and label
  local y_flow = input_flow.add{
    type = "flow",
  }
  y_flow.style.vertical_align = "center"
  y_flow.add{
    type = "label",
    caption = {"", {"description.y-offset"}, ":"}
  }
  y_flow.add{
    type = "sprite-button",
    style = "recursive-blueprints-slot",
    name = "recursive-blueprints-scanner-y"
  }

  -- Width button and label
  local width_flow = input_flow.add{
    type = "flow",
  }
  width_flow.style.vertical_align = "center"
  width_flow.add{
    type = "label",
    caption = {"", {"gui-map-generator.map-width"}, ":"}
  }
  width_flow.add{
    type = "sprite-button",
    style = "recursive-blueprints-slot",
    name = "recursive-blueprints-scanner-width"
  }

  -- Height button and label
  local height_flow = input_flow.add{
    type = "flow",
  }
  height_flow.style.vertical_align = "center"
  height_flow.add{
    type = "label",
    caption = {"", {"gui-map-generator.map-height"}, ":"}
  }
  height_flow.add{
    type = "sprite-button",
    style = "recursive-blueprints-slot",
    name = "recursive-blueprints-scanner-height"
  }

  -- Minimap
  local minimap_frame = main_flow.add{
    type = "frame",
    style = "entity_button_frame",
  }
  minimap_frame.style.size = 256
  minimap_frame.style.vertical_align = "center"
  minimap_frame.style.horizontal_align = "center"
  local minimap = minimap_frame.add{
    type = "minimap",
    surface_index = entity.surface.index,
    force = entity.force.name,
    position = entity.position,
  }
  minimap.style.minimal_width = 16
  minimap.style.minimal_height = 16
  minimap.style.maximal_width = 256
  minimap.style.maximal_height = 256

  inner_frame.add{type = "line"}

  -- Output signals
  inner_frame.add{
    type = "label",
    style = "heading_3_label",
    caption = {"description.output-signals"},
  }
  local scroll_pane = inner_frame.add{
    type = "scroll-pane",
    style = "recursive-blueprints-scroll",
    direction = "vertical",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  }
  scroll_pane.style.maximal_height = 164
  local scroll_frame = scroll_pane.add{
    type = "frame",
    style = "filter_scroll_pane_background_frame",
    direction = "vertical",
  }
  scroll_frame.style.width = 400
  scroll_frame.style.minimal_height = 40
  local slots = scanner.entity.prototype.item_slot_count
  for i = 1, slots, 10 do
    local row = scroll_frame.add{
      type = "flow",
      style = "packed_horizontal_flow",
    }
    for j = 0, 9 do
      if i+j <= slots then
        row.add{
          type = "sprite-button",
          style = "recursive-blueprints-output",
        }
      end
    end
  end

  -- Display current values
  update_scanner_gui(gui)
  return gui
end

-- Build the "select a signal or constant" gui
function create_signal_gui(element)
  local screen = element.gui.screen
  local primary_gui = screen["recursive-blueprints-scanner"]
  local id = primary_gui.tags["recursive-blueprints-id"]
  local scanner = global.scanners[id]
  local field = element.name:sub(30)
  local target = scanner[field.."_signal"] or {}

  -- Highlight the button that opened the gui
  reset_scanner_gui_style(screen)
  element.style = "recursive-blueprints-slot-selected"

  -- Destroy any old version
  if screen["recursive-blueprints-signal"] then
    screen["recursive-blueprints-signal"].destroy()
  end

  -- Place gui slightly to the right of center
  local location = primary_gui.location
  local scale = game.get_player(element.player_index).display_scale
  location.x = location.x + 126 * scale
  location.y = location.y - 60 * scale

  -- Heading
  local gui = screen.add{
    type = "frame",
    name = "recursive-blueprints-signal",
    style = "invisible_frame",
    direction = "vertical",
    tags = {
      ["recursive-blueprints-id"] = id,
      ["recursive-blueprints-field"] = field,
    }
  }
  gui.location = location
  local signal_select = gui.add{
    type = "frame",
    direction = "vertical",
  }
  add_titlebar(signal_select, gui, {"gui.select-signal"}, "recursive-blueprints-close")
  local inner_frame = signal_select.add{
    type = "frame",
    style = "inside_shallow_frame",
    direction = "vertical",
  }

  -- Create tab bar, but don't add tabs until we know which one is selected
  local tab_scroll_pane = inner_frame.add{
    type = "scroll-pane",
    style = "recursive-blueprints-scroll",
    direction = "vertical",
    horizontal_scroll_policy = "never",
    vertical_scroll_policy = "auto",
  }
  tab_scroll_pane.style.padding = 0
  tab_scroll_pane.style.width = 424

  -- Open the signals tab if nothing is selected
  local selected_tab = 1
  for i = 1, #global.groups do
    if global.groups[i].name == "signals" then
      selected_tab = i
    end
  end
  local matching_button = nil

  -- Signals are stored in a tabbed pane
  local tabbed_pane = inner_frame.add{
    type = "tabbed-pane",
    style = "recursive-blueprints-tabbed-pane",
  }
  tabbed_pane.style.bottom_margin = 4
  for g, group in pairs(global.groups) do
    -- We can't display images in tabbed-pane tabs,
    -- so make them invisible and use fake image tabs instead.
    local tab = tabbed_pane.add{
      type = "tab",
      style = "recursive-blueprints-invisible-tab",
    }
    -- Add scrollbars in case there are too many signals
    local scroll_pane = tabbed_pane.add{
      type = "scroll-pane",
      style = "recursive-blueprints-scroll",
      direction = "vertical",
      horizontal_scroll_policy = "never",
      vertical_scroll_policy = "auto",
    }
    scroll_pane.style.height = 364
    scroll_pane.style.maximal_width = 424
    local scroll_frame = scroll_pane.add{
      type = "frame",
      style = "filter_scroll_pane_background_frame",
      direction = "vertical",
    }
    scroll_frame.style.width = 400
    scroll_frame.style.minimal_height = 40
    -- Add signals
    for i = 1, #group.subgroups do
      for j = 1, #group.subgroups[i], 10 do
        local row = scroll_frame.add{
          type = "flow",
          style = "packed_horizontal_flow",
        }
        for k = 0, 9 do
          if j+k <= #group.subgroups[i] then
            local signal = group.subgroups[i][j+k]
            local button = row.add{
              type = "sprite-button",
              style = "slot_button",
              name = "recursive-blueprints-signal-"..g.."-"..i.."-"..(j+k),
              sprite = get_signal_sprite(signal),
              tags = {["recursive-blueprints-signal"] = signal},
              tooltip = {"",
                "[font=default-bold][color=255,230,192]",
                get_localised_name(signal),
                "[/color][/font]",
              },
            }
            if signal.type == target.type and signal.name == target.name then
              -- This is the selected signal!
              button.style = "recursive-blueprints-signal-selected"
              scroll_pane.scroll_to_element(button, "top-third")
              selected_tab = g
            end
          end
        end
      end
    end
    -- Add the invisible tabs and visible signal pages to the tabbed-pane
    tabbed_pane.add_tab(tab, scroll_pane)
  end
  if #tabbed_pane.tabs >= 1 then
    tabbed_pane.selected_tab_index = selected_tab
  end

  -- Add fake tab buttons with images
  local tab_bar = tab_scroll_pane.add{
    type = "table",
    style = "filter_group_table",
    column_count = 6,
  }
  tab_bar.style.width = 420
  for i = 1, #global.groups do
    add_tab_button(tab_bar, i, selected_tab)
  end
  if #global.groups <= 1 then
    -- No tab bar
    tab_scroll_pane.style.maximal_height = 0
  elseif #global.groups <= 6 then
    -- Single row tab bar
    tab_scroll_pane.style.maximal_height = 64
  else
    -- Multi row tab bar
    tab_scroll_pane.style.maximal_height = 144
    tabbed_pane.style = "recursive-blueprints-tabbed-pane-multiple"
  end

  -- Set a constant
  local set_constant = gui.add{
    type = "frame",
    direction = "vertical",
  }
  add_titlebar(set_constant, gui, {"gui.or-set-a-constant"})
  local inner_frame = set_constant.add{
    type = "frame",
    style = "entity_frame",
    direction = "horizontal",
  }
  inner_frame.style.vertical_align = "center"

  -- Slider settings
  local maximum_value = 28  -- 10 * log(999)
  local allow_negative = false
  if (field == "x" or field == "y") then
    maximum_value = 74  -- 2 * 10 * log(10000)
    allow_negative = true
  end

  -- Slider
  local slider = inner_frame.add{
    type = "slider",
    name = "recursive-blueprints-slider",
    maximum_value = maximum_value,
  }
  slider.style.top_margin = 8
  slider.style.bottom_margin = 8

  -- Text field
  local textfield = inner_frame.add{
    type = "textfield",
    name = "recursive-blueprints-constant",
    numeric = true,
    allow_negative = allow_negative,
  }
  textfield.style.width = 80
  textfield.style.horizontal_align = "center"
  if scanner[field.."_signal"] then
    textfield.text = "0"
  else
    textfield.text = tostring(scanner[field])
    copy_text_value(textfield)
  end

  -- Submit button
  local filler = inner_frame.add{type = "empty-widget"}
  filler.style.horizontally_stretchable = "on"
  inner_frame.add{
    type = "button",
    style = "recursive-blueprints-set-button",
    name = "recursive-blueprints-set-constant",
    caption = {"gui.set"},
  }

  return gui
end

function add_tab_button(row, i, selected)
  -- Add tab button
  local name = global.groups[i].name
  local button = row.add{
    type = "sprite-button",
    style = "recursive-blueprints-tab-button",
    name = "recursive-blueprints-tab-button-" .. i,
    tooltip = {"item-group-name." .. name},
  }
  if #global.groups > 6 then
    button.style = "filter_group_button_tab"
  end
  if game.is_valid_sprite_path("item-group/" .. name) then
    button.sprite = "item-group/" .. name
  else
    button.caption = {"item-group-name." .. name}
  end

  -- Highlight selected tab
  if i == selected then
    highlight_tab_button(button, i)
    if i > 6 then
      button.parent.parent.scroll_to_element(button, "top-third")
    end
  end
end

function sanitize_area(key, value)
  -- Out of bounds check
  if value > 2000000 then value = 2000000 end
  if value < -2000000 then value = -2000000 end

  -- Limit width/height to 999 for better performance
  if key == "width" or key == "height" then
    if value < 0 then value = 0 end
    if value > 999 then value = 999 end
  end

  return value
end

-- Copy constant value from signal gui to scanner gui
function set_scanner_value(element)
  local screen = element.gui.screen
  local scanner_gui = screen["recursive-blueprints-scanner"]
  if not scanner_gui then return end
  local scanner = global.scanners[scanner_gui.tags["recursive-blueprints-id"]]
  local signal_gui = screen["recursive-blueprints-signal"]
  local key = signal_gui.tags["recursive-blueprints-field"]
  local value = tonumber(element.parent.children[2].text) or 0
  value = sanitize_area(key, value)

  -- Disable signal
  scanner[key.."_signal"] = nil
  update_scanner_network(scanner)

  -- Run a scan if the area has changed
  if scanner[key] ~= value then
    scanner[key] = value
    scan_resources(scanner)
  end

  -- The user might have changed a signal without changing the area,
  -- so always refresh the gui.
  update_scanner_gui(scanner_gui)
  reset_scanner_gui_style(screen)

  -- Close signal gui
  signal_gui.destroy()
end

-- Copy signal from signal gui to scanner gui
function set_scanner_signal(element)
  local screen = element.gui.screen
  local signal_gui = screen["recursive-blueprints-signal"]
  local scanner_gui = screen["recursive-blueprints-scanner"]
  if not scanner_gui then return end
  local scanner = global.scanners[scanner_gui.tags["recursive-blueprints-id"]]
  local key = signal_gui.tags["recursive-blueprints-field"]

  scanner[key.."_signal"] = element.tags["recursive-blueprints-signal"]
  update_scanner_network(scanner)
  update_scanner_gui(scanner_gui)
  reset_scanner_gui_style(screen)

  -- Close signal gui
  signal_gui.destroy()
end

-- Copy value from slider to text field
function copy_slider_value(element)
  local gui = get_root_element(element)
  local field = gui.tags["recursive-blueprints-field"]
  local value = 0
  if field == 'x' or field == 'y' then
    -- 1-9(+1) 10-90(+10) 100-900(+100) 1000-10000(+1000)
    if element.slider_value < 10 then
      value = 1000 * (element.slider_value - 10)
    elseif element.slider_value < 19 then
      value = 100 * (element.slider_value - 19)
    elseif element.slider_value < 28 then
      value = 10 * (element.slider_value - 28)
    elseif element.slider_value < 47 then
      value = element.slider_value - 37
    elseif element.slider_value < 56 then
      value = 10 * (element.slider_value - 46)
    elseif element.slider_value < 65 then
      value = 100 * (element.slider_value - 55)
    else
      value = 1000 * (element.slider_value - 64)
    end
  else
    -- 1-10(+1) 20-100(+10) 200-999(+100)
    if element.slider_value < 11 then
      value = element.slider_value
    elseif element.slider_value < 20 then
      value = 10 * (element.slider_value - 9)
    elseif element.slider_value < 28 then
      value = 100 * (element.slider_value - 18)
    else
      value = 999
    end
  end
  element.parent["recursive-blueprints-constant"].text = tostring(value)
end

-- Copy value from text field to slider
function copy_text_value(element)
  local gui = get_root_element(element)
  local field = gui.tags["recursive-blueprints-field"]
  local text_value = tonumber(element.text) or 0
  local value = 0
  if field == 'x' or field == 'y' then
    if text_value <= -1000 then
      value = math.floor(text_value / 1000 + 10.5)
    elseif text_value <= -100 then
      value = math.floor(text_value / 100 + 19.5)
    elseif text_value <= -10 then
      value = math.floor(text_value / 10 + 28.5)
    elseif text_value <= 10 then
      value = math.floor(text_value + 37.5)
    elseif text_value <= 100 then
      value = math.floor(text_value / 10 + 46.5)
    elseif text_value <= 1000 then
      value = math.floor(text_value / 100 + 55.5)
    else
      value = math.floor(text_value / 1000 + 64.5)
    end
  else
    if text_value <= 10 then
      value = text_value
    elseif text_value <= 100 then
      value = math.floor(text_value / 10 + 9.5)
    elseif text_value < 999 then
      value = math.floor(text_value / 100 + 18.5)
    else
      value = 28
    end
  end
  element.parent["recursive-blueprints-slider"].slider_value = value
end

-- Switch tabs
function set_signal_gui_tab(element, index)
  local tab_bar = element.parent
  -- Un-highlight old tab button
  for i = 1, #tab_bar.children do
    if #global.groups > 6 then
      tab_bar.children[i].style = "filter_group_button_tab"
    else
      tab_bar.children[i].style = "recursive-blueprints-tab-button"
    end
  end
  highlight_tab_button(element, index)
  -- Show new tab content
  tab_bar.gui.screen["recursive-blueprints-signal"].children[1].children[2].children[2].selected_tab_index = index
end

function highlight_tab_button(button, index)
  local column = index % 6
  if #global.groups > 6 then
    button.style = "recursive-blueprints-tab-button-selected-grid"
  elseif column == 1 then
    button.style = "recursive-blueprints-tab-button-left"
  elseif column == 0 then
    button.style = "recursive-blueprints-tab-button-right"
  else
    button.style = "recursive-blueprints-tab-button-selected"
  end
end

-- Populate gui with the latest data
function update_scanner_gui(gui)
  local scanner = global.scanners[gui.tags["recursive-blueprints-id"]]
  if not scanner then return end
  if not scanner.entity.valid then return end

  -- Update area dimensions
  local input_flow = gui.children[2].children[3].children[1].children[2]
  set_slot_button(input_flow.children[1].children[2], scanner.x, scanner.x_signal)
  set_slot_button(input_flow.children[2].children[2], scanner.y, scanner.y_signal)
  set_slot_button(input_flow.children[3].children[2], scanner.width, scanner.width_signal)
  set_slot_button(input_flow.children[4].children[2], scanner.height, scanner.height_signal)

  -- Update minimap
  local x = scanner.x
  local y = scanner.y
  if settings.global["recursive-blueprints-area"].value == "corner" then
    -- Convert from top left corner to center
    x = x + math.floor(scanner.width/2)
    y = y + math.floor(scanner.height/2)
  end
  local minimap = gui.children[2].children[3].children[2].children[1]
  minimap.position = {
    scanner.entity.position.x + x,
    scanner.entity.position.y + y,
  }
  local largest = math.max(scanner.width, scanner.height)
  if largest == 0 then
    largest = 32
  end
  minimap.zoom = 256 / largest
  minimap.style.natural_width = scanner.width / largest * 256
  minimap.style.natural_height = scanner.height / largest * 256

  update_scanner_output(gui.children[2].children[6].children[1], scanner.entity)
end

-- Display all constant-combinator output signals in the gui
function update_scanner_output(output_flow, entity)
  local behavior = entity.get_control_behavior()
  for i = 1, entity.prototype.item_slot_count do
    -- 10 signals per row
    local row = math.ceil(i / 10)
    local col = (i-1) % 10 + 1
    local button = output_flow.children[row].children[col]
    local signal = behavior.get_signal(i)
    if signal and signal.signal and signal.signal.name then
      -- Display signal and value
      button.number = signal.count
      button.sprite = get_signal_sprite(signal.signal)
      button.tooltip = {"",
       "[font=default-bold][color=255,230,192]",
       get_localised_name(signal.signal),
       ":[/color][/font] ",
       util.format_number(signal.count),
      }
    else
      -- Display empty slot
      button.number = nil
      button.sprite = nil
      button.tooltip = ""
    end
  end
end

-- Format data for the signal-or-number button
function set_slot_button(button, value, signal)
  if signal then
    button.caption = ""
    button.style.natural_width = 40
    button.sprite = get_signal_sprite(signal)
    button.tooltip = {"",
      "[font=default-bold][color=255,230,192]",
      get_localised_name(signal),
      "[/color][/font]",
    }
  else
    button.caption = format_amount(value)
    button.style.natural_width = button.caption:len() * 12 + 4
    button.sprite = nil
    button.tooltip = {"gui.constant-number"}
  end
end

-- Scan the area for resources
function scan_resources(scanner)
  if not scanner then return end
  if not scanner.entity.valid then return end
  local resources = {item = {}, fluid = {}, virtual = {}}
  local p = scanner.entity.position
  local force = scanner.entity.force
  local surface = scanner.entity.surface
  local x = scanner.x
  local y = scanner.y
  local blacklist = {}

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
        count_resources(force, surface, area, resources, blacklist)
      else
        -- Add uncharted chunk
        resources.virtual["signal-black"] = (resources.virtual["signal-black"] or 0) + 1
      end
    end
  end

  -- Copy resources to combinator output
  local behavior = scanner.entity.get_control_behavior()
  local index = 1
  for type, resource in pairs(resources) do
    for name, count in pairs(resource) do
      -- Avoid int32 overflow
      if count > 2147483647 then count = 2147483647 end
      if count ~= 0 then
        behavior.set_signal(index, {signal={type=type, name=name}, count=count})
        index = index + 1
      end
    end
  end
  -- Set the remaining output slots to nil
  local max = scanner.entity.prototype.item_slot_count
  while index <= max do
    behavior.set_signal(index, nil)
    index = index + 1
  end
end

-- Count the resources in a chunk
function count_resources(force, surface, area, resources, blacklist)
  local forces = {"neutral"}
  if global.artillery_shell then
    -- Count enemy bases too
    for _, enemy in pairs(game.forces) do
      if force ~= enemy
      and not force.get_friend(enemy)
      and not force.get_cease_fire(enemy) then
        table.insert(forces, enemy.name)
      end
    end
  end

  -- Search the area
  local result = surface.find_entities_filtered{
    area = area,
    force = forces,
  }
  for _, resource in pairs(result) do
    local hash = pos_hash(resource, 0, 0)
    local prototype = resource.prototype
    if blacklist[hash] then
      -- We already counted this
    elseif resource.type == "resource" then
      -- Mining drill resources
      local type = prototype.mineable_properties.products[1].type
      local name = prototype.mineable_properties.products[1].name
      local amount = resource.amount
      if prototype.infinite_resource then
        amount = 1
      end
      resources[type][name] = (resources[type][name] or 0) + amount
    elseif global.cliff_explosives and resource.type == "cliff" then
      -- Cliff
      resources.item["cliff-explosives"] = (resources.item["cliff-explosives"] or 0) - 1
    elseif global.artillery_shell and MILITARY_STRUCTURES[resource.type] then
      -- Enemy base
      resources.item["artillery-shell"] = (resources.item["artillery-shell"] or 0) - 1
    elseif (resource.type == "tree" or resource.type == "fish" or prototype.count_as_rock_for_filtered_deconstruction)
    and prototype.mineable_properties.minable
    and prototype.mineable_properties.products then
      -- Trees, fish, rocks
      for _, product in pairs(prototype.mineable_properties.products) do
        local amount = product.amount
        if product.amount_min and product.amount_max then
          amount = (product.amount_min + product.amount_max) / 2
          amount = amount * product.probability
        end
        resources[product.type][product.name] = (resources[product.type][product.name] or 0) + amount
      end
    end
    -- Mark as counted
    blacklist[hash] = true
  end
  -- Water
  resources.fluid["water"] = (resources.fluid["water"] or 0) + surface.count_tiles_filtered{
    area = {{round(area[1][1]), round(area[1][2])},{round(area[2][1]), round(area[2][2])}},
    collision_mask = "water-tile",
  }
end

function get_signal_sprite(signal)
  if not signal.name then return end
  if signal.type == "item" and game.item_prototypes[signal.name] then
    return "item/" .. signal.name
  elseif signal.type == "fluid" and game.fluid_prototypes[signal.name] then
    return "fluid/" .. signal.name
  elseif signal.type == "virtual" and game.virtual_signal_prototypes[signal.name] then
    return "virtual-signal/" .. signal.name
  end
end

function get_localised_name(signal)
  if not signal.type or not signal.name then return "" end
  if signal.type == "item" then
    if game.item_prototypes[signal.name] then
      return game.item_prototypes[signal.name].localised_name
    else
      return {"item-name." .. signal.name}
    end
  elseif signal.type == "fluid" then
    if game.fluid_prototypes[signal.name] then
      return game.fluid_prototypes[signal.name].localised_name
    else
      return {"fluid-name." .. signal.name}
    end
  elseif signal.type == "virtual" then
    if game.virtual_signal_prototypes[signal.name] then
      return game.virtual_signal_prototypes[signal.name].localised_name
    else
      return {"virtual-signal-name." .. signal.name}
    end
  end
  return ""
end

function format_amount(amount)
  if amount >= 1000000000 then
    return math.floor(amount / 1000000000) .. "G"
  elseif amount >= 1000000 then
    return math.floor(amount / 1000000) .. "M"
  elseif amount >= 1000 then
    return math.floor(amount / 1000) .. "k"
  elseif amount > -1000 then
    return amount
  elseif amount > -1000000 then
    return math.ceil(amount / 1000) .. "k"
  elseif amount > -1000000000 then
    return math.ceil(amount / 1000000) .. "M"
  else
    return math.ceil(amount / 1000000000) .. "G"
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
