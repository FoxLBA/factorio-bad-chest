if data.raw.technology["construction-robotics"]
and data.raw.technology["construction-robotics"].effects then
  -- Construction robotics unlocks deployer chest
  table.insert(
    data.raw.technology["construction-robotics"].effects,
    {type = "unlock-recipe", recipe = "blueprint-deployer"}
  )
  table.insert(
    data.raw.technology["construction-robotics"].effects,
    {type = "unlock-recipe", recipe = "blueprint-deployer2"}
  )
  table.insert(
    data.raw.technology["construction-robotics"].effects,
    {type = "unlock-recipe", recipe = "recursive-blueprints-scanner"}
  )
else
  -- Unlock from the start
  data.raw.recipe["blueprint-deployer"].enabled = true
  data.raw.recipe["blueprint-deployer2"].enabled = true
  data.raw.recipe["recursive-blueprints-scanner"].enabled = true
end
