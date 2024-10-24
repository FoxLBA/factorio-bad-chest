local item_sounds = require("__base__.prototypes.item_sounds")

data:extend{
  {
    type = "item",
    name = "blueprint-deployer",
    icon = "__rec-blue-plus__/graphics/blueprint-deployer-icon.png",
    icon_size = 64,
    inventory_move_sound = item_sounds.metal_chest_inventory_move,
    pick_sound = item_sounds.metal_chest_inventory_pickup,
    drop_sound = item_sounds.metal_chest_inventory_move,
    subgroup = "logistic-network",
    order = "c[signal]-b[blueprint-deployer]",
    place_result = "blueprint-deployer",
    stack_size = 50,
  },
  {
    type = "item",
    name = "recursive-blueprints-scanner",
    icon = "__rec-blue-plus__/graphics/scanner-icon.png",
    icon_size = 64,
    inventory_move_sound = item_sounds.metal_large_inventory_move,
    pick_sound = item_sounds.metal_large_inventory_pickup,
    drop_sound = item_sounds.metal_large_inventory_move,
    subgroup = "circuit-network",
    order = "d[other]-c[recursive-blueprints-scanner]",
    place_result = "recursive-blueprints-scanner",
    stack_size = 50,
  },
}
