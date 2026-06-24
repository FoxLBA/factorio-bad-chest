local function migrate_from_other_fork(event)
--Migrate deployers and scanners to new mod name (from DaveMcW's "Recursive Blueprints" mod)
--Last version 1.2.7 for F1.1
  if (event.mod_changes["recursive-blueprints"]
  and event.mod_changes["recursive-blueprints"].old_version) then
    for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities_filtered({name = {"blueprint-deployer", "recursive-blueprints-scanner"}})) do
        if entity.name == "blueprint-deployer" then
          storage.deployers[entity.unit_number] = entity
        elseif entity.name == "recursive-blueprints-scanner" then
          AreaScanner.on_built(entity, {})
        end
      end
    end
  end
end

local function new_scanner_data(event)
  --Migrate to new scanner data format (changed in 1.3.11 for F1.1).
  if RB_util.check_verion(event.mod_changes["rec-blue-plus"].old_version, "1.3.11") then
    for _, scanner in pairs(storage.scanners or {}) do
      AreaScanner.on_built(scanner.entity, {tags = scanner})
    end
  end
end

local function new_scanner_io(event)
  --Migrate to new scanner I/O (changed in 1.4.1 for F2.0).
  --Clear the output signals of the scanner (it is actually a constant combinator) and add a hidden c-comb.
  if RB_util.check_verion(event.mod_changes["rec-blue-plus"].old_version, "1.4.1") then
    for i, scanner in pairs(storage.scanners or {}) do
      local entity = scanner.entity
      if entity.valid then
        local old_behavior = entity.get_control_behavior()
        local b = AreaScanner.get_or_create_output_behavior(scanner)
        if (old_behavior.sections_count > 0) and (old_behavior.sections[1].filters_count > 0) then
          b.sections[1].filters = old_behavior.sections[1].filters
        end
        RB_util.clear_constant_combinator(old_behavior)
      else
        AreaScanner.on_destroyed(i)
      end
    end
  end
end

local function new_deployer2_io(event)
  --Migrate to new BAD Chest I/O (changed in 1.5.0 for F2.1).
  --Remove the hidden constant combinator that removes the contents of the chest from the signals (if there is one).
  --Activates the separation of the output signals of the chest (added in Factorio 2.1).
  if RB_util.check_verion(event.mod_changes["rec-blue-plus"].old_version, "1.5.0") then
    for _, deployer in pairs(storage.deployers2) do
      local e = deployer.entity
      if e and e.valid and not deployer.is_input_combined then
        if deployer.output_compensate and deployer.output_compensate.valid then
          deployer.output_compensate.destroy()
          deployer.output_compensate = nil
        end
        local container_output = {red = true, green = true}
        local cb = e.get_control_behavior()
        if cb and cb.output_networks then
          if deployer.input_main == defines.wire_connector_id.circuit_red then
            container_output.green = false
          else
            container_output.red = false
          end
          cb.output_networks = container_output
        end
      end
    end
  end
end

local function on_mods_changed(event)
  if not storage.deployers2 then storage.deployers2 = {} end --added in 1.4.4 for F2.0

  if (event and event.mod_changes) then
    migrate_from_other_fork(event)
    if (event.mod_changes["rec-blue-plus"] and event.mod_changes["rec-blue-plus"].old_version) then
      new_scanner_data(event)
      new_scanner_io(event)
      new_deployer2_io(event)
    end
  end
end

return on_mods_changed