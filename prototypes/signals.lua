local rbp_signals = {
  {
    type = "item-subgroup",
    name = "recursive-blueprints-signals",
    group = "signals",
    order = "recursive-blueprints",
  }
}
local counters = {
  "uncharted", "cliffs", "targets", "water", "resources",
  "buildings", "ghosts", "items_on_ground", "trees_and_rocks", "to_be_deconstructed",
}

for i, name in pairs(counters) do
  table.insert(
    rbp_signals,
    {
      type = "virtual-signal",
      name = "recursive-blueprints-counter-"..name,
      icon = "__rec-blue-plus__/graphics/signals/counter_"..name..".png",
      subgroup = "recursive-blueprints-signals",
      order = "a-"..(i-1),
      localised_name = {"recursive-blueprints.counter-name-"..name},
      localised_description = {"recursive-blueprints.counter-tooltip-"..name},
    })
end

for i = 1, 6 do
  table.insert(
    rbp_signals,
    {
      type = "virtual-signal",
      name = "recursive-blueprints-book-layer"..i,
      icon = "__rec-blue-plus__/graphics/signals/book_layer_"..i..".png",
      subgroup = "recursive-blueprints-signals",
      order = "b-"..i,
    })
end

local deployer = {"command", "cancel", "enviroment", "invert-filter", "rotate-bp", "superforce", "quality"}
for i, name in pairs(deployer) do
  table.insert(
    rbp_signals,
    {
      type = "virtual-signal",
      name = "recursive-blueprints-deployer-"..name,
      icon = "__rec-blue-plus__/graphics/signals/deployer_"..name..".png",
      subgroup = "recursive-blueprints-signals",
      order = "c-"..i,
    })
end

if not mods["quality"] then
  rbp_signals[#rbp_signals].hidden = true
end

data:extend(rbp_signals)