local GUI_util = {}
-- Entity status lookup tables
GUI_util.STATUS_NAME = {
  [defines.entity_status.working] = "entity-status.working",
  [defines.entity_status.disabled] = "entity-status.disabled",
  [defines.entity_status.marked_for_deconstruction] = "entity-status.marked-for-deconstruction",
}
GUI_util.STATUS_SPRITE = {
  [defines.entity_status.working] = "utility/status_working",
  [defines.entity_status.disabled] = "utility/status_not_working",
  [defines.entity_status.marked_for_deconstruction] = "utility/status_not_working",
}

---Add a titlebar with a drag area and close [X] button
---@param element LuaGuiElement The element to add the frame to.
---@param drag_target LuaGuiElement
---@param caption LocalisedString
---@param close_button_name LocalisedString?
---@param close_button_tooltip LocalisedString?
function GUI_util.add_titlebar(element, drag_target, caption, close_button_name, close_button_tooltip)
  local titlebar = element.add{type = "flow"}
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

---Add status indicator and entity preview
---@param element LuaGuiElement The element to add the frame to.
---@param entity LuaEntity The entity that will be shown in the preview.
function GUI_util.add_status_indicator(element, entity)
  local indicator = element.add{type = "flow", direction = "vertical"}
  local status_flow = indicator.add{
    type = "flow",
    style = "status_flow",
  }
  status_flow.style.vertical_align = "center"
  status_flow.add{
    type = "sprite",
    style = "status_image",
    sprite = GUI_util.STATUS_SPRITE[entity.status],
  }
  status_flow.add{
    type = "label",
    caption = {GUI_util.STATUS_NAME[entity.status]},
  }
  local preview_frame = indicator.add{
    type = "frame",
    style = "entity_button_frame",
  }
  local preview = preview_frame.add{
    type = "entity-preview",
  }
  preview.entity = entity
  preview.style.height = 148
  preview.style.horizontally_stretchable = true
end

function GUI_util.format_amount(amount)
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

function GUI_util.get_localised_name(signal)
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

function GUI_util.get_root_element(element)
  while element.parent.name ~= "screen" do element = element.parent end
  return element
end

function GUI_util.get_signal_sprite(signal)
  if not signal.name then return end
  if signal.type == "item" and game.item_prototypes[signal.name] then
    return "item/" .. signal.name
  elseif signal.type == "fluid" and game.fluid_prototypes[signal.name] then
    return "fluid/" .. signal.name
  elseif signal.type == "virtual" and game.virtual_signal_prototypes[signal.name] then
    return "virtual-signal/" .. signal.name
  end
end

-- Format data for the signal-or-number button
function GUI_util.set_slot_button(button, value, signal)
  if type(signal) == "table" then
    button.caption = ""
    button.style.natural_width = 40
    button.sprite = GUI_util.get_signal_sprite(signal)
    button.tooltip = {"",
      "[font=default-bold][color=255,230,192]",
      GUI_util.get_localised_name(signal),
      "[/color][/font]",
    }
  else
    button.caption = GUI_util.format_amount(value)
    button.style.natural_width = button.caption:len() * 12 + 4
    button.sprite = nil
    button.tooltip = {"gui.constant-number"}
  end
end

-- Collect all visible circuit network signals.
-- Sort them by group and subgroup.
function GUI_util.cache_signals()
  global.gui_util_groups = {}
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
          if #global.gui_util_groups == 0 or global.gui_util_groups[#global.gui_util_groups].name ~= group.name then
            table.insert(global.gui_util_groups, {name = group.name, subgroups = {}})
          end
          table.insert(global.gui_util_groups[#global.gui_util_groups].subgroups, signals)
        end
      end
    end
  end
end

---Adds tabs frame with signals for selection.
---@param element LuaGuiElement The element to add the frame to.
---@param selected_signal table
function GUI_util.add_signal_select_frame(element, selected_signal)
  local inner_frame = element.add{type = "frame", style = "inside_shallow_frame", direction = "vertical"}

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
  for i = 1, #global.gui_util_groups do
    if global.gui_util_groups[i].name == "signals" then selected_tab = i end
  end
  --local matching_button = nil

  -- Signals are stored in a tabbed pane
  local tabbed_pane = inner_frame.add{
    type = "tabbed-pane",
    style = "recursive-blueprints-tabbed-pane",
  }
  tabbed_pane.style.bottom_margin = 4
  for g, group in pairs(global.gui_util_groups) do
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
              sprite = GUI_util.get_signal_sprite(signal),
              tags = {["recursive-blueprints-signal"] = signal},
              tooltip = {"",
                "[font=default-bold][color=255,230,192]",
                GUI_util.get_localised_name(signal),
                "[/color][/font]",
              },
            }
            if signal.type == selected_signal.type and signal.name == selected_signal.name then
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
  if #tabbed_pane.tabs >= selected_tab then tabbed_pane.selected_tab_index = selected_tab end

  -- Add fake tab buttons with images
  local tab_bar = tab_scroll_pane.add{
    type = "table",
    style = "filter_group_table",
    column_count = 6,
  }
  tab_bar.style.width = 420
  for i = 1, #global.gui_util_groups do GUI_util.add_tab_button(tab_bar, i, selected_tab) end
  if #global.gui_util_groups <= 1 then
    -- No tab bar
    tab_scroll_pane.style.maximal_height = 0
  elseif #global.gui_util_groups <= 6 then
    -- Single row tab bar
    tab_scroll_pane.style.maximal_height = 64
  else
    -- Multi row tab bar
    tab_scroll_pane.style.maximal_height = 144
    tabbed_pane.style = "recursive-blueprints-tabbed-pane-multiple"
  end
end

function GUI_util.highlight_tab_button(button, index)
  local column = index % 6
  if #global.gui_util_groups > 6 then
    button.style = "recursive-blueprints-tab-button-selected-grid"
  elseif column == 1 then
    button.style = "recursive-blueprints-tab-button-left"
  elseif column == 0 then
    button.style = "recursive-blueprints-tab-button-right"
  else
    button.style = "recursive-blueprints-tab-button-selected"
  end
end

-- Add tab button for signal select frame.
function GUI_util.add_tab_button(row, i, selected)
  local name = global.gui_util_groups[i].name
  local button = row.add{
    type = "sprite-button",
    style = "recursive-blueprints-tab-button",
    tooltip = {"item-group-name." .. name},
    tags = {["recursive-blueprints-tab-index"] = i},
  }
  if #global.gui_util_groups > 6 then
    button.style = "filter_group_button_tab"
  end
  if game.is_valid_sprite_path("item-group/" .. name) then
    button.sprite = "item-group/" .. name
  else
    button.caption = {"item-group-name." .. name}
  end

  -- Highlight selected tab
  if i == selected then
    GUI_util.highlight_tab_button(button, i)
    if i > 6 then
      button.parent.parent.scroll_to_element(button, "top-third")
    end
  end
end

-- Switch tabs in signal select frame.
function GUI_util.select_tab_by_index(element, index)
  local tab_bar = element.parent
  -- Un-highlight old tab button
  for i = 1, #tab_bar.children do
    if #global.gui_util_groups > 6 then
      tab_bar.children[i].style = "filter_group_button_tab"
    else
      tab_bar.children[i].style = "recursive-blueprints-tab-button"
    end
  end
  GUI_util.highlight_tab_button(element, index)
  -- Show new tab content
  tab_bar.parent.parent.children[2].selected_tab_index = index
  --tab_bar.gui.screen["recursive-blueprints-signal"].children[1].children[2].children[2].selected_tab_index = index
end

return GUI_util
