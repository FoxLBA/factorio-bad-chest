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
    type = "int-setting",
    name = "recursive-blueprints-scanner-extra-slots",
    setting_type = "startup",
    minimum_value = 0,
    maximum_value = 50,
    default_value = 10
  },
  {
    type = "bool-setting",
    name = "recursive-blueprints-alternative-deployer-deploy-signal",
    setting_type = "runtime-global",
    default_value = false
  },
  {
    type = "bool-setting",
    name = "recursive-blueprints-alternative-scaner-default",
    setting_type = "runtime-global",
    default_value = true
  }
}
