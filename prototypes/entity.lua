-- Blueprint deployer
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
data:extend{deployer}

-- Resource scanner
local accumulator = table.deepcopy(data.raw["accumulator"]["accumulator"])
local substation = table.deepcopy(data.raw["electric-pole"]["substation"])
local con_point = {
  wire = {green = util.by_pixel(27, -6), red = util.by_pixel(26, -2)},
  shadow = {green = util.by_pixel(37, 4), red = util.by_pixel(36, 8)},
}
data:extend{
  {
    type = "constant-combinator",
    name = "recursive-blueprints-scanner",
    icon = "__rec-blue-plus__/graphics/scanner-icon.png",
    --icon_mipmaps = 4,
    icon_size = 64,
    flags = {"placeable-neutral", "player-creation", "hide-alt-info", "not-rotatable"},
    minable = {mining_time = 0.1, result = "recursive-blueprints-scanner"},
    max_health = 200,
    corpse = "substation-remnants",
    dying_explosion = "substation-explosion",
    collision_box = {{-0.7, -0.7}, {0.7, 0.7}},
    selection_box = {{-1, -1}, {1, 1}},
    damaged_trigger_effect = substation.damaged_trigger_effect,
    open_sound = accumulator.open_sound,
    close_sound = accumulator.close_sound,
    vehicle_impact_sound = substation.vehicle_impact_sound,

    allow_copy_paste = false,
    activity_led_light_offsets = {{0,0}, {0,0}, {0,0}, {0,0}},
    activity_led_sprites = {filename = "__core__/graphics/empty.png", size = 1},
    circuit_wire_connection_points = {con_point, con_point, con_point, con_point},
    circuit_wire_max_distance = 9,
    --drawing_box = {{-1, -2.5}, {1, 1}},
    sprites = {
      layers = {
        {
          filename = "__rec-blue-plus__/graphics/hr-scanner.png",
          width = 138,
          height = 270,
          shift = util.by_pixel(0, -31),
          scale = 0.5,
          priority = "high",
        },
        -- Shadow
        ---@diagnostic disable-next-line: assign-type-mismatch
        substation.pictures.layers[2],
      }
    },
  }
}
