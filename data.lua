local input = {
	type = "custom-input",
	name = "folk-tidypls-toggle",
	key_sequence = "",
	consuming = "none",
}

local shortcut = {
	type = "shortcut",
	name = "folk-tidypls-toggle",
	icon = "__folk-tidypls__/graphics/tidyicon.png",
	small_icon = "__folk-tidypls__/graphics/tidyicon.png",
	order = "c[custom-actions]-s[toggle-tidypls]",
	action = "lua",
	icon_size = 112,
	small_icon_size = 112,
	style = "default",
	associated_control_input = "folk-tidypls-toggle",
	technology_to_unlock = "folk-tidypls",
	unavailable_until_unlocked = true,
	toggleable = true,
}

local tech = {
	type = "technology",
	name = "folk-tidypls",
	icon = "__folk-tidypls__/graphics/tech.png",
	icon_size = 256,
	effects = {
		{
			type = "nothing",
			use_icon_overlay_constant = false,
			icon = "__folk-tidypls__/graphics/tidyicon.png",
			icon_size = 112,
			effect_description = { "folk-tidypls.tech-tooltip", },
		},
	},
	prerequisites = { "construction-robotics", "radar", },
	unit =
	{
		count = 100,
		ingredients =
		{
			{ "automation-science-pack", 1, },
			{ "logistic-science-pack",   1, },
			{ "chemical-science-pack",   1, },
		},
		time = 30,
	},
}

_G.data:extend({ input, shortcut, tech, })
