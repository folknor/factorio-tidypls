-------------------------------------------------------------------------------
-- TIDY PLS
--
-- Most of the code here was initially RIPPED LIKE A SAVAGE from concreep-redux
-- https://github.com/utoxin/concreep-redux
--
-- Which means that this code is also licensed under the MIT license.
-- There's an argument that the license needs to be included in the actual source
-- files, however I've worked on relicensing exceptionally large codebases from
-- multiple licenses TO multiple licenses - and I disagree.
--
-- COME AT ME lulz

local DEBUG_LOG = true

local LOG_INIT = "Tidying pls."
local LOG_NETWORK = "Processing network: %d"
local LOG_NO_PORTS = "Network %d has no valid roboports."
local LOG_NUMPORTS = " - Available roboports: %d"
local LOG_SURFACE = " - Surface: %s#%d"
local LOG_NUMBOTS = " - Available bots: %d"
local LOG_ITEMCOUNT = " - Item: %s: %d"
local LOG_RADIUS_INCREASED = " - Roboport radius increased: %s"
local LOG_DONE_EXPANDING = " - Roboport done expanding: %s"
local LOG_EXPANDED = " - Expanded port %s: %d bots remaining"
local LOG_UPGRADED = " - Upgraded port %s: %d bots remaining"
local LOG_DONE = " - Roboport is done: %s"
local LOG_DISABLED = " - Tidying has been disabled for this network."

---@param var string
---@param ... string|number
local function log(var, ...)
	if not DEBUG_LOG then return end
	print("TIDY: ", var:format(...))
end

local MASK_GROUND_TILE = "ground_tile"
local TYPE_TILE_GHOST = "tile-ghost"
local TYPE_CLIFF = "cliff"
local TYPE_TREE = "tree"
local TYPE_SIMPLE = "simple-entity"
local TYPE_LANDFILL = "landfill"

local FIND_FILTER_CLEAR = { type = { TYPE_TREE, TYPE_SIMPLE, TYPE_CLIFF, }, }
local TYPE_ROBOPORT = "roboport"
local FIND_FILTER = { type = TYPE_ROBOPORT, }

local TYPE_CONCRETE = "concrete"
local TYPE_BRICK = "stone-brick"
local TYPE_REFINED = "refined-concrete"
local TYPE_PATH = "stone-path"
local TYPE_EXPLOSIVES = "cliff-explosives"

local ITEM_EXPLOSIVES = { name = TYPE_EXPLOSIVES, quality = "normal", }
local ITEM_CONCRETE = { name = TYPE_CONCRETE, quality = "normal", }
local ITEM_BRICK = { name = TYPE_BRICK, quality = "normal", }
local ITEM_REFINED = { name = TYPE_REFINED, quality = "normal", }

local C_LUA_EVENT = "folk-tidypls-toggle"
local C_TECH_ENABLE = "folk-tidypls"

---@class TidyPort
---@field roboport LuaEntity
---@field doneExpanding boolean
---@field doneUpgrading boolean
---@field upgradeArea BoundingBox @The full construction area of the roboport in which it can upgrade its tiles.
---@field radius number
---@field maxRadius number
---@field buildArea BoundingBox @The current build area, as determined by the .radius.
---@field maxEnergy number

---@class TidyNetwork
---@field id number
---@field force LuaForce|ForceID
---@field surface LuaSurface
---@field ports TidyPort[]
---@field items { [string]: number }
---@field bots number

---@class storage
---@field networks TidyNetwork[]


local getVirginFilter
do
	local filter = {
		has_hidden_tile = false,
		collision_mask = MASK_GROUND_TILE,
	}
	getVirginFilter = function(bots, area)
		filter.has_hidden_tile = false
		filter.name = nil
		filter.limit = bots
		filter.area = area
		return filter
	end
end

local getUpgradeFilter
do
	local filter = {
		collision_mask = MASK_GROUND_TILE,
	}
	getUpgradeFilter = function(area, tiles, bots)
		filter.area = area
		filter.name = tiles
		filter.limit = bots
		return filter
	end
end

--Is this a valid roboport?
---@param ent LuaEntity
---@return boolean
local function validPort(ent)
	return ent and
		ent.valid and
		ent.type == TYPE_ROBOPORT and
		ent.prototype.electric_energy_source_prototype and
		ent.logistic_cell and
		ent.logistic_cell.valid and
		ent.logistic_cell.construction_radius > 0 and
		ent.logistic_cell.logistic_network and
		ent.logistic_cell.logistic_network.valid and
		ent.logistic_cell.logistic_network.network_id and
		ent.logistic_cell.logistic_network.network_id > 0 and
		not storage.forget[ent] and
		not ent.logistic_cell.mobile
end

---@param nid number
---@param surface LuaSurface
---@param force LuaForce|ForceID
---@return TidyNetwork
local function getTidyNetworkByNID(nid, surface, force)
	---@type TidyNetwork[]
	local nets = storage.networks

	local index = -1
	for j, net in next, nets do
		if net.id == nid then
			index = j
			break
		end
	end

	if index == -1 then
		---@type TidyNetwork
		local skynet = {
			id = nid,
			surface = surface,
			force = force,
			ports = {},
			items = {},
			bots = 0,
		}
		table.insert(nets, skynet)
		index = #nets
	end
	return nets[index]
end

---@param roboport LuaEntity
---@param area BoundingBox
---@return number, number
local function getPotentialExpansionsAndUpgrades(roboport, area)
	local expansionFilter = {
		has_hidden_tile = false,
		collision_mask = MASK_GROUND_TILE,
		area = area,
	}
	local possibleExpansions = roboport.surface.count_tiles_filtered(expansionFilter)
	if possibleExpansions == 0 then
		expansionFilter.has_hidden_tile = true
		expansionFilter.name = TYPE_LANDFILL
		possibleExpansions = roboport.surface.count_tiles_filtered(expansionFilter)
	end

	local possibleUpgrades = roboport.surface.count_tiles_filtered({
		collision_mask = MASK_GROUND_TILE,
		name = { TYPE_PATH, TYPE_CONCRETE, },
		area = area,
	})

	return possibleExpansions, possibleUpgrades
end

---@param ... LuaEntity
local function addPorts(...)
	for i = 1, select("#", ...) do
		---@type LuaEntity
		local roboport = (select(i, ...))
		if validPort(roboport) then
			local already = false
			-- Check to see that this roboport is not part of any existing network
			for _, net in next, storage.networks do
				for _, p in next, net.ports do
					if p.roboport and p.roboport.valid and p.roboport.unit_number == roboport.unit_number then
						already = true
						break
					end
				end
				if already then break end
			end
			if not already then
				local max = roboport.logistic_cell.construction_radius
				local maxArea = {
					{ roboport.position.x - max, roboport.position.y - max, },
					{ roboport.position.x + max, roboport.position.y + max, },
				}
				local possibleExpansions, possibleUpgrades = getPotentialExpansionsAndUpgrades(roboport, maxArea)
				if possibleExpansions > 0 or possibleUpgrades > 0 then
					local nid = roboport.logistic_cell.logistic_network.network_id
					local net = getTidyNetworkByNID(nid, roboport.surface, roboport.force)

					---@type TidyPort
					local port = {
						roboport = roboport,
						radius = 3,
						maxRadius = max,
						doneUpgrading = (possibleUpgrades == 0),
						doneExpanding = (possibleExpansions == 0),
						maxEnergy = roboport.prototype.electric_energy_source_prototype.buffer_capacity,
						upgradeArea = maxArea,
						buildArea = {
							{ roboport.position.x - 3, roboport.position.y - 3, },
							{ roboport.position.x + 3, roboport.position.y + 3, },
						},
					}

					table.insert(net.ports, port)
				end
			end
		end
	end
end

-- This gets called when the mod inits, or when we tick and there's zero ports in storage
local function findPorts()
	for _, surface in pairs(game.surfaces) do
		addPorts(table.unpack(surface.find_entities_filtered(FIND_FILTER)))
	end
end

local function initTidyPls()
	---@type TidyNetwork[]
	storage.networks = {}
	---@type { [LuaEntity]: boolean }
	storage.forget = {}
	findPorts()
end

---@param net TidyNetwork
---@param type string
---@param position MapPosition
---@return number
local function build(net, type, position)
	local count = 0

	local ent = {
		name = TYPE_TILE_GHOST,
		position = position,
		inner_name = type,
		force = net.force,
	}

	if net.surface.create_entity(ent) then
		count = 1
	end

	FIND_FILTER_CLEAR.area = { { position.x - 0.2, position.y - 0.2, }, { position.x + 0.8, position.y + 0.8, }, }

	for _, clear in next, net.surface.find_entities_filtered(FIND_FILTER_CLEAR) do
		if clear.type ~= TYPE_CLIFF or net.items[TYPE_EXPLOSIVES] > 0 then
			clear.order_deconstruction(net.force)
			count = count + 1
		end
	end

	return count
end

---@param net TidyNetwork
---@param position MapPosition
---@param ... string
local function attemptBuild(net, position, ...)
	local used = 0
	for i = 1, select("#", ...) do
		local item = (select(i, ...))
		if net.items[item] > 0 then
			-- ZZZ decreasing by usedNow isn't strictly correct because it also includes other cleanup stuff, but meh
			local usedNow = build(net, item, position)
			used = used + usedNow
			net.bots = net.bots - usedNow
			net.items[TYPE_REFINED] = net.items[TYPE_REFINED] - usedNow
			return used
		end
	end
	return used
end

---@param net TidyNetwork
---@param area BoundingBox
---@return boolean
local function tidyExpand(net, area)
	local virginFilter = getVirginFilter(net.bots, area)
	local virgins = net.surface.find_tiles_filtered(virginFilter)

	if #virgins == 0 then
		virginFilter.has_hidden_tile = true
		virginFilter.name = "landfill"
		virgins = net.surface.find_tiles_filtered(virginFilter)
	end

	local used = 0
	for _, tile in next, virgins do
		used = used + attemptBuild(net, tile.position, TYPE_REFINED, TYPE_CONCRETE, TYPE_BRICK)
		if net.bots < 1 then return used > 0 end
	end
	return used > 0
end

local countItems = {
	ITEM_REFINED,
	ITEM_CONCRETE,
	ITEM_BRICK,
	ITEM_EXPLOSIVES,
}

local function recalcUpgradeTargets(net)
	local ret = {}
	if net.items[TYPE_REFINED] > 0 or net.items[TYPE_CONCRETE] > 0 then
		table.insert(ret, TYPE_PATH)
	end

	if net.items[TYPE_REFINED] > 0 then
		table.insert(ret, TYPE_CONCRETE)
	end
	return ret
end

local function tidypls()
	if not storage.networks then initTidyPls() end
	if #storage.networks == 0 then findPorts() end

	---@type TidyNetwork[]
	local nets = storage.networks

	---@type { [LuaEntity]: boolean }
	local expanded = {}
	---@type { [LuaEntity]: boolean }
	local upgraded = {}

	log(LOG_INIT)

	for j = #nets, 1, -1 do
		local net = nets[j]
		log(LOG_NETWORK, net.id)

		for i = #net.ports, 1, -1 do
			if not validPort(net.ports[i].roboport) or net.ports[i].roboport.logistic_network.network_id ~= net.id then
				if net.ports[i].roboport and net.ports[i].roboport.valid then
					-- Recheck this port later
					storage.forget[net.ports[i].roboport] = true
				end
				table.remove(net.ports, i)
			end
		end

		if #net.ports == 0 then
			log(LOG_NO_PORTS, net.id)
			table.remove(nets, j)
		else
			log(LOG_NUMPORTS, #net.ports)

			local researched = net.force.technologies[C_TECH_ENABLE] and
				net.force.technologies[C_TECH_ENABLE].researched

			local enabled = false
			for _, player in pairs(game.players) do
				if player.force == net.force then
					enabled = player.is_shortcut_toggled(C_LUA_EVENT)
					break
				end
			end
			if not enabled then
				log(LOG_DISABLED)
			end

			local first = net.ports[1].roboport
			local available = first.logistic_network.available_construction_robots
			local total = first.logistic_network.all_construction_robots
			if (available / total) < 0.1 then break end

			log(LOG_SURFACE, first.surface.name, first.surface.index)
			net.bots = math.floor(total * 0.1)
			log(LOG_NUMBOTS, net.bots)

			if net.bots > 0 and researched and enabled then
				local any = false

				for _, item in next, countItems do
					local c = first.logistic_network.get_item_count(item) - 100
					net.items[item.name] = c
					log(LOG_ITEMCOUNT, item.name, c)
					if c > 0 then any = true end
				end

				if any then
					-- utoxin pls what is this
					if net.force.max_successful_attempts_per_tick_per_construction_queue * 60 < net.bots then
						net.force.max_successful_attempts_per_tick_per_construction_queue = math.floor(net.bots / 60)
					end

					-- First check if we can expand at all
					for _, port in next, net.ports do
						if not port.doneExpanding and port.maxEnergy == port.roboport.energy then
							local roboport = port.roboport
							-- Dont do anything if there's any ghosts in the build area
							if net.surface.count_entities_filtered({
									area = port.buildArea,
									name = TYPE_TILE_GHOST,
									force = roboport.force,
								}) == 0 then
								expanded[roboport] = tidyExpand(net, port.buildArea)

								if not expanded[roboport] then
									if port.radius < port.maxRadius then
										log(LOG_RADIUS_INCREASED, roboport.backer_name)
										port.radius = port.radius + 1
										port.buildArea = {
											{ roboport.position.x - port.radius, roboport.position.y - port.radius, },
											{ roboport.position.x + port.radius, roboport.position.y + port.radius, },
										}
										-- Dont upgrade around this roboport.
										-- The mod has probably been added to the game mid-run
										expanded[roboport] = true
									else
										-- Roboport is done expanding.
										port.doneExpanding = true
										log(LOG_DONE_EXPANDING, roboport.backer_name)
									end
								else
									log(LOG_EXPANDED, roboport.backer_name, net.bots)
								end

								if net.bots < 1 then break end
							end
						end
					end

					if net.bots > 0 then
						-- We've expanded, now see if we can upgrade
						local upgradeTargets = recalcUpgradeTargets(net)

						for _, port in next, net.ports do
							if not port.doneUpgrading and not expanded[port.roboport] and port.maxEnergy == port.roboport.energy then
								if #upgradeTargets > 0 then
									local max = math.max(net.items[TYPE_CONCRETE], net.items[TYPE_REFINED], 0)
									if max > 0 then
										local upgradeFilter = getUpgradeFilter(
											port.upgradeArea,
											upgradeTargets,
											math.min(max, net.bots)
										)
										local upgrades = net.surface.find_tiles_filtered(upgradeFilter)
										if #upgrades == 0 then
											port.doneUpgrading = true
										else
											local used = 0
											for _, tile in next, upgrades do
												-- ZZZ decreasing by usedNow isn't strictly correct because it also includes other cleanup stuff, but meh
												used = used +
													attemptBuild(net, tile.position, TYPE_REFINED,
																 TYPE_CONCRETE)
												if net.bots < 1 or (net.items[TYPE_REFINED] < 1 and net.items[TYPE_CONCRETE] < 1) then
													break
												end
											end
											upgraded[port.roboport] = used > 0
										end

										if upgraded[port.roboport] then
											log(LOG_UPGRADED, port.roboport.backer_name, net.bots)
											upgradeTargets = recalcUpgradeTargets(net)
											if #upgradeTargets == 0 then break end
										end
										if net.bots < 1 then break end
									else
										break
									end
								else
									break
								end
							end
							if port.doneExpanding and port.doneUpgrading then
								log(LOG_DONE, port.roboport.backer_name)
								storage.forget[port.roboport] = true
							end
						end
					end

					-- Shufflefeet penguins
					for i = #net.ports, 2, -1 do
						local x = math.random(i)
						net.ports[x], net.ports[j] = net.ports[j], net.ports[x]
					end
				end
			end
		end
	end
end

---@param event OnBuiltEntity|OnRobotBuiltEntity|OnEntityCloned|ScriptRaisedRevive
local function built(event)
	local ent = event.destination or event.entity
	if ent and ent.valid and ent.type == TYPE_ROBOPORT then
		if not storage.networks or not storage.forget then
			initTidyPls()
		end
		if validPort(ent) then
			addPorts(ent)
		end
	end
end

script.on_event(defines.events.on_built_entity, built)
script.on_event(defines.events.on_robot_built_entity, built)
script.on_event(defines.events.on_entity_cloned, built)
script.on_event(defines.events.script_raised_revive, built)

script.on_nth_tick(30 * 60, tidypls)
script.on_init(initTidyPls)
script.on_configuration_changed(initTidyPls)

local INFO_TOGGLED_FORCE = { "folk-tidypls.enabled-force", }
local INFO_TOGGLED_BY = "folk-tidypls.enabled-by"

local function keyCombo(event)
	local clicker = game.players[event.player_index]
	if not clicker or not clicker.valid then return end

	-- You can toggle it with the keyboard shortcut even if it's not researched so we check
	local researched = clicker.force.technologies[C_TECH_ENABLE] and clicker.force.technologies[C_TECH_ENABLE]
		.researched
	if not researched then return end

	local state = clicker.is_shortcut_toggled(C_LUA_EVENT)
	for _, pl in pairs(game.players) do
		if pl.force == clicker.force then
			pl.set_shortcut_toggled(C_LUA_EVENT, not state)
			pl.print({ INFO_TOGGLED_BY, clicker.name, })
		end
	end
end

script.on_event(C_LUA_EVENT, keyCombo)
script.on_event(defines.events.on_lua_shortcut, function(event)
	---@cast event OnLuaShortcut
	if not event or event.prototype_name ~= C_LUA_EVENT then return end
	keyCombo(event)
end)

script.on_event(defines.events.on_research_finished, function(event)
	---@cast event OnResearchFinished
	if event.research.name == C_TECH_ENABLE then
		for _, pl in pairs(game.players) do
			if pl.force == event.research.force then
				pl.set_shortcut_toggled(C_LUA_EVENT, true)
				pl.print(INFO_TOGGLED_FORCE)
			end
		end
	end

	if storage.forget then
		for port in pairs(storage.forget) do
			if port and port.valid then
				local max = port.logistic_cell.construction_radius
				local area = {
					{ port.position.x - max, port.position.y - max, },
					{ port.position.x + max, port.position.y + max, },
				}
				local exp, ups = getPotentialExpansionsAndUpgrades(port, area)
				if exp ~= 0 or ups ~= 0 then
					-- Clear first because addPorts checks validPort, which checks .forget
					storage.forget[port] = nil
					addPorts(port)
				end
			else
				storage.forget[port] = nil
			end
		end
	end

	if not storage.networks then return end
	for _, net in next, storage.networks do
		for i = #net.ports, 1, -1 do
			if not validPort(net.ports[i].roboport) or net.ports[i].roboport.logistic_network.network_id ~= net.id then
				if net.ports[i].roboport and net.ports[i].roboport.valid then
					-- Recheck this port later
					storage.forget[net.ports[i].roboport] = true
				end
				table.remove(net.ports, i)
			end
		end

		for _, port in next, net.ports do
			if port.roboport.logistic_cell.construction_radius ~= port.maxRadius then
				port.maxRadius = port.roboport.logistic_cell.construction_radius
				port.upgradeArea = {
					{ port.roboport.position.x - port.maxRadius, port.roboport.position.y - port.maxRadius, },
					{ port.roboport.position.x + port.maxRadius, port.roboport.position.y + port.maxRadius, },
				}
				local exp, ups = getPotentialExpansionsAndUpgrades(port.roboport, port.upgradeArea)
				port.doneExpanding = (exp == 0)
				port.doneUpgrading = (ups == 0)
			end
		end
	end
end)
