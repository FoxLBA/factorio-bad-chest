-- Offset calculation tool.
local tool_name = "rbp-tool"
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

data:extend{
  {
    type = "selection-tool",
    name = tool_name,
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
  {
    type = "custom-input",
    name = "give-"..tool_name,
    key_sequence = "",
    controller_key_sequence = "",
    block_modifiers = true,
    consuming = "game-only",
    item_to_spawn = tool_name,
    action = "spawn-item"
  },
  {
    type = "shortcut",
    name = "give-"..tool_name,
    order = "e["..tool_name.."]",
    action = "spawn-item",
    associated_control_input = "give-"..tool_name,
    --technology_to_unlock = "construction-robotics",
    unavailable_until_unlocked = true,
    item_to_spawn = tool_name,
    icon = "__rec-blue-plus__/graphics/coord-x56.png",
    icon_size = 56,
    small_icon = "__rec-blue-plus__/graphics/coord-x24.png",
    small_icon_size = 24
  },
}