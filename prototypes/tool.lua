-- Offset calculation tool.
local offset_tool_name = "rbp-tool"
local area_view_tool_name = "rbp-area-viewer"
local item_sounds = require("__base__.prototypes.item_sounds")

local c_comb_select
if data.raw["constant-combinator"] then
  c_comb_select =
    {
      border_color = {255, 24, 24},
      mode = {"blueprint"},
      entity_filters = {"constant-combinator"},
      cursor_box_type = "not-allowed",
    }
end

local input1 = {
  type = "custom-input",
  name = "give-"..offset_tool_name,
  key_sequence = "",
  controller_key_sequence = "",
  block_modifiers = true,
  consuming = "game-only",
  item_to_spawn = offset_tool_name,
  action = "spawn-item"
}
local shortcut1 = {
  type = "shortcut",
  name = input1.name,
  order = "e["..offset_tool_name.."]",
  action = "spawn-item",
  associated_control_input = input1.name,
  item_to_spawn = offset_tool_name,
  icon = "__rec-blue-plus__/graphics/coord-x56.png",
  icon_size = 56,
  small_icon = "__rec-blue-plus__/graphics/coord-x24.png",
  small_icon_size = 24
}

local input2 = table.deepcopy(input1)
input2.name = "give-"..area_view_tool_name
input2.item_to_spawn = area_view_tool_name
local shortcut2 = {
  type = "shortcut",
  name = input2.name,
  order = "e["..area_view_tool_name.."]",
  action = "spawn-item",
  associated_control_input = input2.name,
  item_to_spawn = area_view_tool_name,
  icon = "__rec-blue-plus__/graphics/blueprint-deployer-icon.png",
  icon_size = 64,
  small_icon = "__rec-blue-plus__/graphics/blueprint-deployer-icon.png",
  small_icon_size = 64,
}

data:extend{
  {
    type = "selection-tool",
    name = offset_tool_name,
    icon = "__rec-blue-plus__/graphics/signals/deployer_command.png",
    flags = {"not-stackable", "spawnable", "mod-openable", "only-in-cursor"}, --"mod-openable", on_mod_item_opened
    auto_recycle = false,
    subgroup = "spawnables",
    inventory_move_sound = item_sounds.planner_inventory_move,
    pick_sound = item_sounds.planner_inventory_pickup,
    drop_sound = item_sounds.planner_inventory_move,
    stack_size = 1,
    select =
    {
      border_color = {71, 255, 73},
      mode = {"blueprint"}, --"nothing"
      cursor_box_type = "spidertron-remote-to-be-selected",
    },
    alt_select =
    {
      border_color = {239, 153, 34},
      mode = {"blueprint"},
      cursor_box_type = "entity",
    },
    --super_forced_select
    reverse_select = c_comb_select
    --alt_reverse_select
  },
  input1,
  shortcut1,
  {
    type = "selection-tool",
    name = area_view_tool_name,
    icon = "__rec-blue-plus__/graphics/blueprint-deployer-icon.png",
    icon_size = 64,
    flags = {"not-stackable", "spawnable", "mod-openable", "only-in-cursor"},
    auto_recycle = false,
    subgroup = "spawnables",
    inventory_move_sound = item_sounds.planner_inventory_move,
    pick_sound = item_sounds.planner_inventory_pickup,
    drop_sound = item_sounds.planner_inventory_move,
    stack_size = 1,
    select =
    {
      border_color = {128, 128, 255},
      mode = {"entity-with-health"},
      cursor_box_type = "entity",
      entity_filters = {
        "blueprint-deployer2",
        "recursive-blueprints-scanner",
      },
    },
    alt_select =
    {
      border_color = {128, 128, 255},
      mode = {"entity-with-health"},
      cursor_box_type = "entity",
      entity_filters = {
        "blueprint-deployer2",
        "recursive-blueprints-scanner",
      },
    },
  },
  input2,
  shortcut2,
}