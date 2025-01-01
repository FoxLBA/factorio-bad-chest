local deployer = table.deepcopy(data.raw["container"]["steel-chest"])
deployer.name = "blueprint-deployer"
deployer.icon = "__rec-blue-plus__/graphics/blueprint-deployer-icon.png"
deployer.minable.result = "blueprint-deployer"
deployer.inventory_size = 1
deployer.inventory_type = "normal"
deployer.se_allow_in_space = true
deployer.picture.layers = {
  {
    filename = "__rec-blue-plus__/graphics/hr-blueprint-deployer.png",
    width = 66,
    height = 72,
    shift = util.by_pixel(0, -2.5),
    scale = 0.5,
    priority = "high",
  },
  {
    filename = "__base__/graphics/entity/roboport/roboport-base-animation.png",
    width = 83,
    height = 59,
    shift = util.by_pixel(0.25, -17),
    scale = 0.5,
    priority = "high",
  },
  -- Shadow
  table.deepcopy(data.raw["container"]["iron-chest"].picture.layers[2])
}

local item_sounds = require("__base__.prototypes.item_sounds")
data:extend{
  deployer,
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
    type = "recipe",
    name = "blueprint-deployer",
    results = {{type="item", name="blueprint-deployer", amount=1}},
    enabled = false,
    ingredients = {
      {type="item", name="steel-chest", amount=1},
      {type="item", name="electronic-circuit", amount=3},
      {type="item", name="advanced-circuit", amount=1},
    },
  },
}

local deployer2 = table.deepcopy(deployer)
deployer2.name = "blueprint-deployer2"
data:extend{deployer2}