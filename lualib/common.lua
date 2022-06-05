-- Cache the circuit networks attached to the entity
-- The entity must be valid
function update_network(entity)
  if entity.name == "recursive-blueprints-scanner" then
    -- Resource scanner only uses circuit networks if one of the signals is set
    local scanner = global.scanners[entity.unit_number]
    if not scanner.network_imput then return end
  end
  local network = global.networks[entity.unit_number]
  if not network then
    network = {deployer = entity}
    global.networks[entity.unit_number] = network
  end
  if not network.red or not network.red.valid then
    network.red = entity.get_circuit_network(defines.wire_type.red)
  end
  if not network.green or not network.green.valid then
    network.green = entity.get_circuit_network(defines.wire_type.green)
  end
end

-- Return integer value for given Signal: {type=, name=}
-- The red and green networks must be valid or nil
function get_signal(network, signal)
  local value = 0
  if network.red then
    value = value + network.red.get_signal(signal)
  end
  if network.green then
    value = value + network.green.get_signal(signal)
  end

  -- Mimic circuit network integer overflow
  if value > 2147483647 then value = value - 4294967296 end
  if value < -2147483648 then value = value + 4294967296 end
  return value
end

-- Create a unique key for a circuit connector
function con_hash(entity, connector, wire)
  return entity.unit_number .. "-" .. connector .. "-" .. wire
end
