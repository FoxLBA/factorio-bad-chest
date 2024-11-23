local rbp_signals = {
  {
    type = "item-subgroup",
    name = "recursive-blueprints-signals",
    group = "signals",
    order = "recursive-blueprints",
  }
}
counters = {
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

data:extend(rbp_signals)