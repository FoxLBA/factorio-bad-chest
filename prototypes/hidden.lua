local hidden_IO = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
hidden_IO.name = "recursive-blueprints-hidden-io"
hidden_IO.minable = {mining_time = 0.1, results = {}}
hidden_IO.order = "zzz"
hidden_IO.collision_box = {{0,0}, {0,0}}
hidden_IO.collision_mask = {layers={["water_tile"]=true}, colliding_with_tiles_only=true}
hidden_IO.selection_box = {{0,0}, {0,0}} --nil
hidden_IO.flags =
{
  "placeable-player",
  "placeable-off-grid",
  "not-repairable",
  "not-on-map",
  "not-deconstructable",
  "not-blueprintable",
  "hide-alt-info",
  "not-flammable",
  "not-upgradable",
  "not-in-kill-statistics",
}
hidden_IO.hidden = true
hidden_IO.fast_replaceable_group = nil
hidden_IO.allow_copy_paste = false
hidden_IO.selectable_in_game = false
hidden_IO.sprites = { filename = "__rec-blue-plus__/graphics/empty.png", size = 1 }
hidden_IO.activity_led_sprites = { filename = "__rec-blue-plus__/graphics/empty.png", size = 1 }
hidden_IO.draw_circuit_wires = false

data:extend{hidden_IO}
