-- Scanner area input slot
data.raw["gui-style"]["default"]["recursive-blueprints-slot"] = {
  type = "button_style",
  parent = "slot_button_in_shallow_frame",
  font = "default-game",
  default_font_color = {1, 1, 1},
  hovered_font_color = {1, 1, 1},
  clicked_font_color = {1, 1, 1},
  horizontal_align = "center",
  minimal_width = 40,
  natural_width = 40,
  maximal_width = 80,
  draw_shadow_under_picture = false,
}

-- Scanner area input slot (selected)
data.raw["gui-style"]["default"]["recursive-blueprints-slot-selected"] = {
  type = "button_style",
  parent = "recursive-blueprints-slot",
  default_graphical_set = table.deepcopy(data.raw["gui-style"]["default"]["slot_button"].selected_graphical_set),
  clicked_graphical_set = table.deepcopy(data.raw["gui-style"]["default"]["slot_button"].selected_graphical_set),
}

-- Input signal (selected)
data.raw["gui-style"]["default"]["recursive-blueprints-signal-selected"] = {
  type = "button_style",
  parent = "slot_button",
  default_graphical_set = table.deepcopy(data.raw["gui-style"]["default"]["slot_button"].selected_graphical_set),
  clicked_graphical_set = table.deepcopy(data.raw["gui-style"]["default"]["slot_button"].selected_graphical_set),
}

-- Output signal (hovered)
data.raw["gui-style"]["default"]["recursive-blueprints-output"] = {
  type = "button_style",
  parent = "slot_button",
  clicked_graphical_set = table.deepcopy(data.raw["gui-style"]["default"]["slot_button"].selected_graphical_set),
  hovered_graphical_set = table.deepcopy(data.raw["gui-style"]["default"]["slot_button"].selected_graphical_set),
  draw_shadow_under_picture = false,
}

-- Green set button without tooltip
data.raw["gui-style"]["default"]["recursive-blueprints-set-button"] = {
  type = "button_style",
  parent = "green_button",
  tooltip = "",
}

-- Scroll pane
data.raw["gui-style"]["default"]["recursive-blueprints-scroll"] = {
  type = "scroll_pane_style",
  padding = 2,
  minimal_height = 44,
  extra_padding_when_activated = 0,
  horizontally_stretchable = "off",
  background_graphical_set = {
    corner_size = 1,
    position = {41, 7},
  },
}

-- Tabbed pane
local tabbed_pane = {
  type = "tabbed_pane_style",
  tab_content_frame = {
    type = "frame_style",
    top_padding = 10,
    bottom_padding = 6,
    left_padding = 10,
    right_padding = 10,
    top_margin = 2,
    --graphical_set = {
    --  base = table.deepcopy(data.raw["gui-style"]["default"]["filter_tabbed_pane"].tab_content_frame.graphical_set.base.center)
    --},
  },
}
data.raw["gui-style"]["default"]["recursive-blueprints-tabbed-pane"] = tabbed_pane

-- Tabbed pane (multiple rows)
local multi_tabbed_pane = table.deepcopy(tabbed_pane)
multi_tabbed_pane.tab_content_frame.bottom_padding = 10
data.raw["gui-style"]["default"]["recursive-blueprints-tabbed-pane-multiple"] = multi_tabbed_pane

-- Real tab button
data.raw["gui-style"]["default"]["recursive-blueprints-invisible-tab"] = {
  type = "tab_style",
  width = 0,
  padding = 0,
  font = "recursive-blueprints-invisible-font",
}

-- Fake tab button
local group_tab = table.deepcopy(data.raw["gui-style"]["default"]["filter_group_tab"])
group_tab.default_graphical_set.base.left_bottom = {position = {102, 9}, size = {8, 8}}
group_tab.default_graphical_set.base.bottom = {position = {110, 9}, size = {1, 8}}
group_tab.default_graphical_set.base.right_bottom = {position = {111, 9}, size = {8, 8}}
local tab_button = {
  type = "button_style",
  width = 70,
  height = 64,
  default_graphical_set = group_tab.default_graphical_set,
  hovered_graphical_set = group_tab.hover_graphical_set,
  clicked_graphical_set = group_tab.pressed_graphical_set,
  left_click_sound = group_tab.left_click_sound,
  padding = 2,
  font = "default-game",
  default_font_color = {255, 255, 255},
  hovered_font_color = {255, 255, 255},
  clicked_font_color = {255, 255, 255},
}
data.raw["gui-style"]["default"]["recursive-blueprints-tab-button"] = tab_button

-- Fake tab button (selected)
local tab_button_selected = table.deepcopy(tab_button)
tab_button_selected.default_graphical_set = group_tab.selected_graphical_set
tab_button_selected.hovered_graphical_set = group_tab.selected_graphical_set
tab_button_selected.clicked_graphical_set = group_tab.selected_graphical_set
data.raw["gui-style"]["default"]["recursive-blueprints-tab-button-selected"] = tab_button_selected

-- Fake tab button (selected, left)
local tab_button_left = table.deepcopy(tab_button)
tab_button_left.default_graphical_set = group_tab.left_edge_selected_graphical_set
tab_button_left.hovered_graphical_set = group_tab.left_edge_selected_graphical_set
tab_button_left.clicked_graphical_set = group_tab.left_edge_selected_graphical_set
data.raw["gui-style"]["default"]["recursive-blueprints-tab-button-left"] = tab_button_left

-- Fake tab button (selected, right)
local tab_button_right = table.deepcopy(tab_button)
tab_button_right.default_graphical_set = group_tab.right_edge_selected_graphical_set
tab_button_right.hovered_graphical_set = group_tab.right_edge_selected_graphical_set
tab_button_right.clicked_graphical_set = group_tab.right_edge_selected_graphical_set
data.raw["gui-style"]["default"]["recursive-blueprints-tab-button-right"] = tab_button_right

-- Grid tab button (selected)
local grid_selected = table.deepcopy(data.raw["gui-style"]["default"]["filter_group_button_tab_slightly_larger"].selected_graphical_set)
data.raw["gui-style"]["default"]["recursive-blueprints-tab-button-selected-grid"] = {
  type = "button_style",
  parent = "filter_group_button_tab_slightly_larger",
  default_graphical_set = grid_selected,
  hovered_graphical_set = grid_selected,
  clicked_graphical_set = grid_selected,
}

data.raw["gui-style"]["default"]["recursive-blueprints-checkbox-minus"] = {
  type = "checkbox_style",
  parent = "checkbox",
  checkmark = {position = {456, 160}, size = {28, 28}}
}
