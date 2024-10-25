data:extend{
  {
    type = "string-setting",
    name = "recursive-blueprints-area",
    setting_type = "runtime-global",
    default_value = "center",
    allowed_values = {"center", "corner"},
  },
  {
    type = "string-setting",
    name = "recursive-blueprints-logging",
    setting_type = "runtime-global",
    default_value = "never",
    allowed_values = {"never", "with_L_greater_than_zero", "with_L_greater_or_equal_to_zero", "always"},
  },
  {
    type = "string-setting",
    name = "recursive-blueprints-deployer-deploy-signal",
    setting_type = "runtime-global",
    default_value = "construction_robot",
    allowed_values = {"construction_robot", "zero", "both"}
  },
  {
    type = "bool-setting",
    name = "recursive-blueprints-old-scaner-default",
    setting_type = "runtime-global",
    default_value = false
  }
}
