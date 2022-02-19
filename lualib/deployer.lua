-- Command signals
local DEPLOY_SIGNAL = {name="construction-robot", type="item"}
local DECONSTRUCT_SIGNAL = {name="deconstruction-planner", type="item"}
local COPY_SIGNAL = {name="signal-C", type="virtual"}
local X_SIGNAL = {name="signal-X", type="virtual"}
local Y_SIGNAL = {name="signal-Y", type="virtual"}
local WIDTH_SIGNAL = {name="signal-W", type="virtual"}
local HEIGHT_SIGNAL = {name="signal-H", type="virtual"}
local ROTATE_SIGNAL = {name="signal-R", type="virtual"}
local NESTED_DEPLOY_SIGNALS = {DEPLOY_SIGNAL}
for i = 1, 5 do
    table.insert(
        NESTED_DEPLOY_SIGNALS,
        {name="signal-"..i, type="virtual"}
    )
end

function deploy_blueprint(bp, network)
  if not bp then return end
  if not bp.valid_for_read then return end
  if not bp.is_blueprint_setup() then return end

  -- Rotate
  local rotation = get_signal(network, ROTATE_SIGNAL)
  local direction = defines.direction.north
  if (rotation == 1) then
    direction = defines.direction.east
  elseif (rotation == 2) then
    direction = defines.direction.south
  elseif (rotation == 3) then
    direction = defines.direction.west
  end

  -- Shift x,y coordinates
  local position = {
    x = network.deployer.position.x + get_signal(network, X_SIGNAL),
    y = network.deployer.position.y + get_signal(network, Y_SIGNAL),
  }

  -- Check for building out of bounds
  if position.x > 1000000
  or position.x < -1000000
  or position.y > 1000000
  or position.y < -1000000 then
    return
  end

  -- Build blueprint
  local result = bp.build_blueprint{
    surface = network.deployer.surface,
    force = network.deployer.force,
    position = position,
    direction = direction,
    force_build = true,
  }

  -- Raise event for ghosts created
  for _, ghost in pairs(result) do
    script.raise_event(defines.events.script_raised_built, {
      entity = ghost,
      stack = bp,
    })
  end
end

function deconstruct_area(bp, network, deconstruct)
  local area = get_area(network)
  local force = network.deployer.force
  if deconstruct == false then
    -- Cancel area
    network.deployer.surface.cancel_deconstruct_area{
      area = area,
      force = force,
      skip_fog_of_war = false,
      item = bp,
    }
  else
    -- Deconstruct area
    local deconstruct_self = network.deployer.to_be_deconstructed(force)
    network.deployer.surface.deconstruct_area{
      area = area,
      force = force,
      skip_fog_of_war = false,
      item = bp,
    }
    if not deconstruct_self then
       -- Don't deconstruct myself in an area order
      network.deployer.cancel_deconstruction(force)
    end
  end
end

function upgrade_area(bp, network, upgrade)
  local area = get_area(network)
  if upgrade == false then
    -- Cancel area
    network.deployer.surface.cancel_upgrade_area{
      area = area,
      force = network.deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  else
    -- Upgrade area
    network.deployer.surface.upgrade_area{
      area = area,
      force = network.deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  end
end

function on_tick_deployer(network)
  if not network.red and not network.green then return end
  -- Read deploy signal
  local deploy = get_signal(network, DEPLOY_SIGNAL)
  local bp = nil
  if deploy > 0 then
    bp = network.deployer.get_inventory(defines.inventory.chest)[1]
    if not bp.valid_for_read then return end

    -- Pick item from blueprint book
    if bp.is_blueprint_book then
      local inventory = nil
      for i=1, 6 do
        inventory = bp.get_inventory(defines.inventory.item_main)
        if #inventory < 1 then return end -- Got an empty book, nothing to do
        deploy = get_signal(network, NESTED_DEPLOY_SIGNALS[i])
        if (deploy == 0) or (deploy > #inventory) then break end -- Navigation is no longer applicable
        bp = inventory[deploy]
        if not bp.valid_for_read then return end -- Got an empty slot
        if not bp.is_blueprint_book then break end
      end
      
      -- Pick active item from nested blueprint books
      bp = get_nested_blueprint(bp)
      if not bp or not bp.valid_for_read then return end
    end

    if bp.is_blueprint then
      -- Deploy blueprint
      deploy_blueprint(bp, network)
    elseif bp.is_deconstruction_item then
      -- Deconstruct area
      deconstruct_area(bp, network, true)
    elseif bp.is_upgrade_item then
      -- Upgrade area
      upgrade_area(bp, network, true)
    end
    return
  end

  if deploy == -1 then
    bp = network.deployer.get_inventory(defines.inventory.chest)[1]
    if not bp.valid_for_read then return end
    if bp.is_deconstruction_item then
      -- Cancel deconstruction in area
      deconstruct_area(bp, network, false)
    elseif bp.is_upgrade_item then
      -- Cancel upgrade in area
      upgrade_area(bp, network, false)
    end
    return
  end

  -- Read deconstruct signal
  local deconstruct = get_signal(network, DECONSTRUCT_SIGNAL)
  if deconstruct == -1 then
    -- Deconstruct area
    deconstruct_area(bp, network, true)
    return
  elseif deconstruct == -2 then
    -- Deconstruct self
    network.deployer.order_deconstruction(network.deployer.force)
    return
  elseif deconstruct == -3 then
    -- Cancel deconstruction in area
    deconstruct_area(bp, network, false)
    return
  end

  -- Read copy signal
  local copy = get_signal(network, COPY_SIGNAL)
  if copy == 1 then
    -- Copy blueprint
    copy_blueprint(network)
    return
  elseif copy == -1 then
    -- Delete blueprint
    local stack = network.deployer.get_inventory(defines.inventory.chest)[1]
    if not stack.valid_for_read then return end
    if stack.is_blueprint
    or stack.is_blueprint_book
    or stack.is_upgrade_item
    or stack.is_deconstruction_item then
      stack.clear()
    end
    return
  end
end

function get_area(network)
  local X = get_signal(network, X_SIGNAL)
  local Y = get_signal(network, Y_SIGNAL)
  local W = get_signal(network, WIDTH_SIGNAL)
  local H = get_signal(network, HEIGHT_SIGNAL)

  if W < 1 then W = 1 end
  if H < 1 then H = 1 end

  if settings.global["recursive-blueprints-area"].value == "corner" then
    -- Convert from top left corner to center
    X = X + math.floor((W - 1) / 2)
    Y = Y + math.floor((H - 1) / 2)
  end

  -- Align to grid
  if W % 2 == 0 then X = X + 0.5 end
  if H % 2 == 0 then Y = Y + 0.5 end

  -- Subtract 1 pixel from the edges to avoid tile overlap
  -- 2 / 256 = 0.0078125
  W = W - 0.0078125
  H = H - 0.0078125

  local position = network.deployer.position
  return {
    {position.x + X - W/2, position.y + Y - H/2},
    {position.x + X + W/2, position.y + Y + H/2},
  }
end

function copy_blueprint(network)
  local inventory = network.deployer.get_inventory(defines.inventory.chest)
  if not inventory.is_empty() then return end
  for _, signal in pairs(global.blueprint_signals) do
    -- Check for a signal before doing an expensive search
    if get_signal(network, signal) >= 1 then
      -- Signal exists, now we have to search for the blueprint
      local stack = find_stack_in_network(network.deployer, signal.name)
      if stack then
        inventory[1].set_stack(stack)
        return
      end
    end
  end
end

-- Breadth-first search for an item in the circuit network
-- If there are multiple items, returns the closest one (least wire hops)
function find_stack_in_network(deployer, item_name)
  local present = {
    [con_hash(deployer, defines.circuit_connector_id.container, defines.wire_type.red)] =
    {
      entity = deployer,
      connector = defines.circuit_connector_id.container,
      wire = defines.wire_type.red,
    },
    [con_hash(deployer, defines.circuit_connector_id.container, defines.wire_type.green)] =
    {
      entity = deployer,
      connector = defines.circuit_connector_id.container,
      wire = defines.wire_type.green,
    }
  }
  local past = {}
  local future = {}
  while next(present) do
    for key, con in pairs(present) do
      -- Search connecting wires
      for _, def in pairs(con.entity.circuit_connection_definitions) do
        -- Wire color and connection points must match
        if def.target_entity.unit_number
        and def.wire == con.wire
        and def.source_circuit_id == con.connector then
          local hash = con_hash(def.target_entity, def.target_circuit_id, def.wire)
          if not past[hash] and not present[hash] and not future[hash] then
            -- Search inside the entity
            local stack = find_stack_in_container(def.target_entity, item_name)
            if stack then return stack end

            -- Add entity connections to future searches
            future[hash] = {
              entity = def.target_entity,
              connector = def.target_circuit_id,
              wire = def.wire
            }
          end
        end
      end
      past[key] = true
    end
    present = future
    future = {}
  end
end

function find_stack_in_container(entity, item_name)
  if entity.type == "container" or entity.type == "logistic-container" then
    local inventory = entity.get_inventory(defines.inventory.chest)
    for i = 1, #inventory do
      if inventory[i].valid_for_read and inventory[i].name == item_name then
        return inventory[i]
      end
    end
  elseif entity.type == "inserter" then
    local behavior = entity.get_control_behavior()
    if behavior
    and behavior.circuit_read_hand_contents
    and entity.held_stack.valid_for_read
    and entity.held_stack.name == item_name then
      return entity.held_stack
    end
  end
end

function get_nested_blueprint(bp)
  if not bp then return end
  if not bp.valid_for_read then return end
  while bp.is_blueprint_book do
    if not bp.active_index then return end
    bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
    if not bp.valid_for_read then return end
  end
  return bp
end

-- Collect all modded blueprint signals in one table
function cache_blueprint_signals()
  global.blueprint_signals = {}
  for _, item in pairs(game.item_prototypes) do
    if item.type == "blueprint"
    or item.type == "blueprint-book"
    or item.type == "upgrade-item"
    or item.type == "deconstruction-item" then
      table.insert(global.blueprint_signals, {name=item.name, type="item"})
    end
  end
end
