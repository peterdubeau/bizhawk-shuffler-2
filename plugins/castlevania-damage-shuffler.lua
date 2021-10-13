local plugin = {}

plugin.name = "Castlevania Damage Shuffler"
plugin.author = "DuSpaceBoat"
plugin.settings =
{
	--  TBD
}

plugin.description =
[[
	Automatically swaps games any time Player takes damage. 
  Right now only works with specific hashes, will add more later?

  Modified from authorblues and kalimag's Mega Man damage Shuffler

	Supports:
	- Castlevania 1
  - Castlevania 2
  - Castlevania 3
]]

local prevdata = {}
local NO_MATCH = 'NONE'

local swap_scheduled = false

local shouldSwap = function() return false end

-- update value in prevdata and return whether the value has changed, new value, and old value
-- value is only considered changed if it wasn't nil before
local function update_prev(key, value)
	local prev_value = prevdata[key]
	prevdata[key] = value
	local changed = prev_value ~= nil and value ~= prev_value
	return changed, value, prev_value
end

local function generic_swap(gamemeta)
	return function(data)
		-- if a method is provided and we are not in normal gameplay, don't ever swap
		if gamemeta.gmode and not gamemeta.gmode() then
			return false
		end

		local currhp = gamemeta.gethp()
		local currlc = gamemeta.getlc()

		local maxhp = gamemeta.maxhp()
		local minhp = gamemeta.minhp or 0

		-- health must be within an acceptable range to count
		-- ON ACCOUNT OF ALL THE GARBAGE VALUES BEING STORED IN THESE ADDRESSES
		if currhp < minhp or currhp > maxhp then
			return false
		end

		-- retrieve previous health and lives before backup
		local prevhp = data.prevhp
		local prevlc = data.prevlc

		data.prevhp = currhp
		data.prevlc = currlc

		-- this delay ensures that when the game ticks away health for the end of a level,
		-- we can catch its purpose and hopefully not swap, since this isnt damage related
		if data.hpcountdown ~= nil and data.hpcountdown > 0 then
			data.hpcountdown = data.hpcountdown - 1
			if data.hpcountdown == 0 and currhp > minhp then
				return true
			end
		end

		-- if the health goes to 0, we will rely on the life count to tell us whether to swap
		if prevhp ~= nil and currhp < prevhp then
			data.hpcountdown = gamemeta.delay or 3
		end

		-- check to see if the life count went down
		if prevlc ~= nil and currlc < prevlc then
			return true
		end

		return false
	end
end


local gamedata = {
	['cv1nes']={ -- Castlevania NES
		gethp=function() return mainmemory.read_u8(0x0045) end,
		getlc=function() return mainmemory.read_u8(0x002A) end,
		maxhp=function() return 64 end,
	},
	['cv2nes']={ -- Castlevania 2 NES
		gethp=function() return mainmemory.read_u8(0x0080) end, -- This is called 'energy' in data crystal, test o confrim
		getlc=function() return mainmemory.read_u8(0x0031) end,
		maxhp=function() return 30 end, -- confirm this is max health
	},
	['cv3nes']={ -- Castlevania 3 NES
		gethp=function() return mainmemory.read_u8(0x003C) end,
		getlc=function() return mainmemory.read_u8(0x0035) end,
		maxhp=function() return 30 end, -- Not sure on max, have to double check
	}
}

local function get_tag_from_hash(target)
	local resp = nil
	local fp = io.open('plugins/castlevania-hashes.dat', 'r')
	for x in fp:lines() do
		local hash, tag = x:match("^([0-9A-Fa-f]+)%s+(%S+)")
		if hash == target then resp = tag; break end
	end
	fp:close()
	return resp
end

local backupchecks = {
}

---- Here we are ----

local function get_game_tag()
	-- try to just match the rom hash first
	local tag = get_tag_from_hash(gameinfo.getromhash())
	if tag ~= nil and gamedata[tag] ~= nil then return tag end

	-- check to see if any of the rom name samples match
	local name = gameinfo.getromname()
	for _,check in pairs(backupchecks) do
		if check.test() then return check.tag end
	end

	return nil
end

function plugin.on_setup(data, settings)
	data.tags = data.tags or {}
end

function plugin.on_game_load(data, settings)
	local tag = data.tags[gameinfo.getromhash()] or get_game_tag()
	data.tags[gameinfo.getromhash()] = tag or NO_MATCH

	-- first time through with a bad match, tag will be nil
	-- can use this to print a debug message only the first time
	if tag ~= nil and tag ~= NO_MATCH then
		print('current game: ' .. tag)
		local gamemeta = gamedata[tag]
		local func = gamemeta.func or generic_swap
		shouldSwap = func(gamemeta)
	elseif tag == nil then
		print(string.format('unrecognized? %s (%s)',
			gameinfo.getromname(), gameinfo.getromhash()))
	end
end

function plugin.on_frame(data, settings)
	-- run the check method for each individual game
	if swap_scheduled then return end

	local schedule_swap, delay = shouldSwap(prevdata)
	if schedule_swap and frames_since_restart > 10 then
		swap_game_delay(delay or 3)
		swap_scheduled = true
	end
end

return plugin
