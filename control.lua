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

local DEBUG_LOG = false
local INTERVAL = 30 * 60

local LOG_INIT = "Tidying pls."
local LOG_NETWORK = "Processing network: %d"
local LOG_NO_PORTS = "Network %d has no valid roboports or is otherwise invalid."
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
local TYPE_ICE_PLATFORM = "ice-platform"
local TYPE_FOUNDATION = "foundation"

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

local ITEM_TO_TILE = {
	[TYPE_BRICK] = TYPE_PATH,
	[TYPE_CONCRETE] = TYPE_CONCRETE,
	[TYPE_REFINED] = TYPE_REFINED,
}
local UPGRADEABLE_PAVEMENTS = { TYPE_PATH, TYPE_CONCRETE, }

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
---@field capacity number
---@field force LuaForce|ForceID
---@field surface LuaSurface
---@field ports TidyPort[]
---@field items { [string]: number }
---@field bots number

---@class storage
---@field networks TidyNetwork[]


local getClearableEntities, countClearableEntities
do
	---@type EntitySearchFilters
	local filter = {
		type = { TYPE_TREE, TYPE_SIMPLE, TYPE_CLIFF, },
		to_be_deconstructed = false,
	}

	---@param surface LuaSurface
	---@param area BoundingBox
	---@return LuaEntity[]
	getClearableEntities = function(surface, area)
		filter.area = area
		return surface.find_entities_filtered(filter)
	end

	---@param surface LuaSurface
	---@param area BoundingBox
	---@return number
	countClearableEntities = function(surface, area)
		filter.area = area
		return surface.count_entities_filtered(filter)
	end
end

-- Virgin/natural_width tiles are tiles that are placed at map generation
local getTilesNatural, countTilesNatural
do
	-- XXX We should generate this from the prototype data
	-- tileproto.is_foundation, .allows_being_covered
	-- itemproto.place_as_tile_result.result = tileproto
	local IGNORE_TILES = {
		-- XXX when these tiles are present we need to pause and reevaluate after landfilling is done
		["natural-yumako-soil"] = true,
		["artificial-yumako-soil"] = true,
		["overgrowth-yumako-soil"] = true,
		["natural-jellynut-soil"] = true,
		["artificial-jellynut-soil"] = true,
		["overgrowth-jellynut-soil"] = true,
	}

	---@type TileSearchFilters
	local filter = {
		--has_hidden_tile = false,
		--has_double_hidden_tile = false,
		--has_tile_ghost = false,
		to_be_deconstructed = false,
		collision_mask = MASK_GROUND_TILE,
		name = {},
		-- ZZZ Unfortunately, invert also inverts collision_mask and potentially some of the other properties
	}

	---@param surface LuaSurface
	---@param limit number|nil
	---@param area BoundingBox
	---@return LuaTile[]
	getTilesNatural = function(surface, limit, area)
		if #filter.name == 0 then
			local protos = prototypes.get_tile_filtered({
				{ filter = "item-to-place",  invert = true,               mode = "and", },
				{ filter = "collision-mask", mask_mode = "layers-equals", mask = "ground_tile", mode = "and", },
			})
			for name in pairs(protos) do
				if not IGNORE_TILES[name] then
					table.insert(filter.name, name)
				end
			end
			-- XXX
			print(serpent.block(filter.name))
		end

		filter.limit = limit
		filter.area = area
		return surface.find_tiles_filtered(filter)
	end

	---@param surface LuaSurface
	---@param limit number|nil
	---@param area BoundingBox
	---@return number
	countTilesNatural = function(surface, limit, area)
		if #filter.name == 0 then
			local protos = prototypes.get_tile_filtered({
				{ filter = "item-to-place",  invert = true,               mode = "and", },
				{ filter = "collision-mask", mask_mode = "layers-equals", mask = "ground_tile", mode = "and", },
			})
			for name in pairs(protos) do
				if not IGNORE_TILES[name] then
					table.insert(filter.name, name)
				end
			end
			-- XXX
			print(serpent.block(filter.name))
		end

		filter.limit = limit
		filter.area = area
		return surface.count_tiles_filtered(filter)
	end
end


local getTilesManMade, countTilesManMade
do
	---@type TileSearchFilters
	local filter

	---@param surface LuaSurface
	---@param limit number|nil
	---@param area BoundingBox
	---@return LuaTile[]
	getTilesManMade = function(surface, limit, area)
		if not filter then
			filter = {
				--has_hidden_tile = true,
				has_tile_ghost = false,
				to_be_deconstructed = false,
				collision_mask = MASK_GROUND_TILE,
			}

			-- XXX We should generate this from the prototype data
			if script.active_mods["space-age"] then
				filter.name = { TYPE_LANDFILL, TYPE_ICE_PLATFORM, TYPE_FOUNDATION, }
			else
				filter.name = TYPE_LANDFILL
			end
		end
		filter.limit = limit
		filter.area = area
		return surface.find_tiles_filtered(filter)
	end

	---@param surface LuaSurface
	---@param limit number|nil
	---@param area BoundingBox
	---@return number
	countTilesManMade = function(surface, limit, area)
		if not filter then
			filter = {
				--has_hidden_tile = true,
				has_tile_ghost = false,
				to_be_deconstructed = false,
				collision_mask = MASK_GROUND_TILE,
			}

			-- XXX We should generate this from the prototype data
			if script.active_mods["space-age"] then
				filter.name = { TYPE_LANDFILL, TYPE_ICE_PLATFORM, TYPE_FOUNDATION, }
			else
				filter.name = TYPE_LANDFILL
			end
		end
		filter.limit = limit
		filter.area = area
		return surface.count_tiles_filtered(filter)
	end
end

local getTilesUpgradeable, countTilesUpgradeable
do
	---@type TileSearchFilters
	local filter = {
		has_tile_ghost = false,
		to_be_deconstructed = false,
		collision_mask = MASK_GROUND_TILE,
	}

	---@param surface LuaSurface
	---@param limit number|nil
	---@param area BoundingBox
	---@param upgrade TileID[]
	---@return LuaTile[]
	getTilesUpgradeable = function(surface, limit, area, upgrade)
		filter.area = area
		filter.name = upgrade
		filter.limit = limit
		return surface.find_tiles_filtered(filter)
	end

	---@param surface LuaSurface
	---@param limit number|nil
	---@param area BoundingBox
	---@param upgrade TileID[]
	---@return number
	countTilesUpgradeable = function(surface, limit, area, upgrade)
		filter.area = area
		filter.name = upgrade
		filter.limit = limit
		return surface.count_tiles_filtered(filter)
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
			capacity = force.worker_robots_storage_bonus + 1,
		}
		table.insert(nets, skynet)
		index = #nets
	end
	return nets[index]
end

---@param roboport LuaEntity
---@param area BoundingBox
---@return number, number, number
local function getPotentialJobs(roboport, area)
	local possibleExpansions = countTilesNatural(roboport.surface, nil, area)
	if possibleExpansions == 0 then
		possibleExpansions = countTilesManMade(roboport.surface, nil, area)
	end
	return possibleExpansions,
		countTilesUpgradeable(roboport.surface, nil, area, UPGRADEABLE_PAVEMENTS),
		countClearableEntities(roboport.surface, area)
end

-- So when you're creating a new network;
-- 1. The first roboport you plop down creates a new network.
-- 2. The second roboport you plop down in range creates a new network
-- 3. The roboport from #1 is adopted into the network from #2
-- ... ffs

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
				local possibleExpansions, possibleUpgrades, possibleTidying = getPotentialJobs(roboport, maxArea)
				if possibleExpansions > 0 or possibleUpgrades > 0 or possibleTidying > 0 then
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

local attemptBuild
do
	---@param net TidyNetwork
	---@param type string
	---@param position MapPosition
	---@return number
	local function build(net, type, position)
		local count = 0

		local ent = {
			name = TYPE_TILE_GHOST,
			position = position,
			inner_name = ITEM_TO_TILE[type],
			force = net.force,
		}

		if net.surface.can_place_entity(ent) then
			-- ZZZ why was this here?
			--ent.expires = false
			if net.surface.create_entity(ent) then
				-- Account for worker robot capacity a bit. We reduce researched capacity by -1.
				--count = (1 * (1 / math.max(1, net.capacity - 1)))
				count = 1
			end
		end

		return count
	end

	---@param net TidyNetwork
	---@param position MapPosition
	---@param ... string
	attemptBuild = function(net, position, ...)
		local used = 0
		for i = 1, select("#", ...) do
			local item = (select(i, ...))
			if net.items[item] > 0 then
				local usedNow = build(net, item, position)
				used = used + usedNow
				net.bots = net.bots - usedNow
				net.items[item] = net.items[item] - math.ceil(usedNow)
				return used
			end
		end
		return used
	end
end

---@param net TidyNetwork
---@param area BoundingBox
---@param tidy boolean
---@return boolean
local function tidyExpand(net, area, tidy)
	local tiles = getTilesNatural(net.surface, net.bots, area)
	if #tiles == 0 then
		tiles = getTilesManMade(net.surface, net.bots, area)
	end

	local used = 0
	for _, tile in next, tiles do
		used = used + attemptBuild(net, tile.position, TYPE_REFINED, TYPE_CONCRETE, TYPE_BRICK)
		if net.bots < 1 then return used > 0 end
	end

	if tidy then
		for _, clear in next, getClearableEntities(net.surface, area) do
			if not clear.to_be_deconstructed() and (clear.type ~= TYPE_CLIFF or net.items[TYPE_EXPLOSIVES] > 0) then
				clear.order_deconstruction(net.force)
				used = used + 1
				net.bots = net.bots - 1
				if net.bots < 1 then return used > 0 end
			end
		end
	end

	return used > 0
end

local countItems = {
	ITEM_REFINED,
	ITEM_CONCRETE,
	ITEM_BRICK,
	ITEM_EXPLOSIVES,
}

---@param net TidyNetwork
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
	---@type { [LuaEntity]: number }
	local ghosts = {}

	log(LOG_INIT)

	for j = #nets, 1, -1 do
		local net = nets[j]
		log(LOG_NETWORK, net.id)

		for i = #net.ports, 1, -1 do
			if not validPort(net.ports[i].roboport) or net.ports[i].roboport.logistic_network.network_id ~= net.id then
				local rp = net.ports[i].roboport
				table.remove(net.ports, i)
				if rp and rp.valid then
					if rp.logistic_cell and rp.logistic_cell.valid and #rp.logistic_cell.neighbours > 0 then
						-- Adopt into neighbouring network
						addPorts(rp)
					else
						-- Recheck this port later
						storage.forget[rp] = true
					end
				end
			end
		end

		if #net.ports == 0 or not net.force or not net.force.valid or not net.surface or not net.surface.valid then
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
							if not ghosts[roboport] then
								ghosts[roboport] = net.surface.count_entities_filtered({
									area = port.buildArea,
									name = TYPE_TILE_GHOST,
									force = roboport.force,
									limit = 1,
								})
							end
							if ghosts[roboport] == 0 then
								expanded[roboport] = tidyExpand(net, port.buildArea, port.radius < port.maxRadius)

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
							end
						end
						if net.bots < 1 then break end
					end

					if net.bots > 0 then
						-- We've expanded, now see if we can upgrade
						local upgradeTargets = recalcUpgradeTargets(net)

						for _, port in next, net.ports do
							if not port.doneUpgrading and not expanded[port.roboport] and port.maxEnergy == port.roboport.energy then
								if #upgradeTargets > 0 then
									local max = math.max(net.items[TYPE_CONCRETE], net.items[TYPE_REFINED], 0)
									if max > 0 then
										-- We dont need to recheck this because expanded[] will fail
										-- for those ports that built anything
										if not ghosts[port.roboport] then
											ghosts[port.roboport] = net.surface.count_entities_filtered({
												area = port.upgradeArea,
												name = TYPE_TILE_GHOST,
												force = port.roboport.force,
												limit = 1,
											})
										end
										if ghosts[port.roboport] == 0 then
											local upgrades = getTilesUpgradeable(
												net.surface,
												math.min(max, net.bots),
												port.upgradeArea,
												upgradeTargets
											)
											if #upgrades == 0 then
												port.doneUpgrading = true
											else
												local used = 0
												for _, tile in next, upgrades do
													used = used +
														attemptBuild(
															net,
															tile.position,
															TYPE_REFINED,
															TYPE_CONCRETE
														)
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
						net.ports[i], net.ports[x] = net.ports[x], net.ports[i]
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

script.on_nth_tick(INTERVAL, tidypls)
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
	if not storage.networks or not storage.forget then return end

	-- Make sure we reevaluate all nets and ports

	-- First, remove all ports from all nets that are no longer valid, and put them
	-- into storage.forget if they still exist.

	for _, net in next, storage.networks do
		for j = #net.ports, 1, -1 do
			local rob = net.ports[j].roboport
			if not validPort(rob) or rob.logistic_network.network_id ~= net.id then
				if rob and rob.valid then
					-- Recheck this port later
					storage.forget[rob] = true
				end
				table.remove(net.ports, j)
			end
		end
	end

	-- Second, nuke all empty or invalid nets
	for i = #storage.networks, 1, -1 do
		local net = storage.networks[i]
		if net.ports == 0 or not net.force or not net.force.valid or not net.surface or not net.surface.valid then
			-- But preserve all valid roboports. Not sure if there can ever be any though
			for _, port in next, net.ports do
				if port.roboport and port.roboport.valid then
					storage.forget[port.roboport] = true
				end
			end
			table.remove(storage.networks, i)
		end
	end

	-- Third, revive any forgotten roboports that are still valid and that still have work to do
	for port in pairs(storage.forget) do
		if port and port.valid then
			local max = port.logistic_cell.construction_radius
			local area = {
				{ port.position.x - max, port.position.y - max, },
				{ port.position.x + max, port.position.y + max, },
			}
			local exp, ups, tidyings = getPotentialJobs(port, area)
			if exp ~= 0 or ups ~= 0 or tidyings ~= 0 then
				-- Clear first because addPorts checks validPort, which checks .forget
				storage.forget[port] = nil
				addPorts(port)
			end
		else
			storage.forget[port] = nil
		end
	end

	-- Fourth, upgrade the radius of all registered ports if necessary
	for _, net in next, storage.networks do
		net.capacity = net.force.worker_robots_storage_bonus + 1

		for _, port in next, net.ports do
			if port.roboport.logistic_cell.construction_radius ~= port.maxRadius then
				port.maxRadius = port.roboport.logistic_cell.construction_radius
				port.upgradeArea = {
					{ port.roboport.position.x - port.maxRadius, port.roboport.position.y - port.maxRadius, },
					{ port.roboport.position.x + port.maxRadius, port.roboport.position.y + port.maxRadius, },
				}
				local exp, ups, tidyings = getPotentialJobs(port.roboport, port.upgradeArea)
				port.doneExpanding = (exp == 0)
				port.doneUpgrading = (ups == 0) and (tidyings == 0) -- XXX double check
			end
		end
	end

	-- Fifth, find any roboports in the networks that we've missed for some reason
	for _, net in next, storage.networks do
		local port = net.ports[1]
		if port then
			local rp = port.roboport
			if rp and rp.valid and rp.logistic_network then
				local ln = rp.logistic_network
				local ports = {}
				for _, cell in next, ln.cells do
					table.insert(ports, cell.owner)
				end
				-- addPorts checks storage.forget and valid and so forth, so just add indiscriminately
				addPorts(table.unpack(ports))
			end
		end
	end
end)
