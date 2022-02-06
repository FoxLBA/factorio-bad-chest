local rbp_signals = {
  {
    type = "item-subgroup",
    name = "recursive-blueprints-signals",
    group = "signals",
    order = "recursive-blueprints"
  }
}

for i = 1, 5 do
  table.insert(
    rbp_signals,
    {
      type = "virtual-signal",
      name = "recursive-blueprints-layer"..i,
      icons = {
        { icon = "__base__/graphics/icons/construction-robot.png", icon_size = 64, icon_mipmaps = 4 },
        { 
          icon = "__base__/graphics/icons/signal/signal_"..i..".png", icon_size = 64, icon_mipmaps = 4,
          scale = 0.25, shift = {-2, -8}
        },
      },
      icon_size = 64,
      subgroup = "recursive-blueprints-signals",
      order = "a-a"..i,
      localised_name = {"virtual-signal-name.recursive-blueprints-layer", ""..i}
    })
end

data:extend(rbp_signals)
