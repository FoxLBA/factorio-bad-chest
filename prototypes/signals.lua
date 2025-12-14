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
      name = "rbp-book-layer"..i,
      icon = "__rec-blue-plus__/graphics/signals/book_layer_"..i..".png",
      subgroup = "recursive-blueprints-signals",
      order = "b-"..i,
    })
end

local deployer = {
  "command", "cancel", "enviroment", "invert-filter", "rotate-bp",
  "superforce", "quality", "center", "absolute", "wait",
}
for i, name in pairs(deployer) do
  local hidden = nil
  if (name == "quality") and (not mods["quality"]) then
    hidden = true
  end
  table.insert(
    rbp_signals,
    {
      type = "virtual-signal",
      name = "rbp-"..name,
      icon = "__rec-blue-plus__/graphics/signals/deployer_"..name..".png",
      subgroup = "recursive-blueprints-signals",
      order = "c-"..i,
      hidden = hidden,
    })
end

data:extend(rbp_signals)