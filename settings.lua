data:extend{
  {
    type = "string-setting",
    name = "recursive-blueprints-area",
    setting_type = "runtime-global",
    default_value = "corner",
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
    default_value = "zero",
    allowed_values = {"construction_robot", "zero", "both"}
  },
  {
    type = "string-setting",
    name = "recursive-blueprints-tool-area",
    setting_type = "runtime-per-user",
    default_value = "corner",
    allowed_values = {"center", "corner"},
  },
  {
    type = "string-setting",
    name = "recursive-blueprints-tool-coordinates",
    setting_type = "runtime-per-user",
    default_value = "relative",
    allowed_values = {"relative", "absolute"},
  },
}
