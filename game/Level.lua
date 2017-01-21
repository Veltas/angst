local TileTypes = {
	wall = "#",
	start = "S",
}

local Level = {}
Level.Level = true

Level.gridWidth = 0
Level.gridHeight = 0
Level.source = nil
--Level.enemies = nil
Level.wallGrid = nil
Level.player = nil
--Level.start = nil
--Level.finishes = nil

function Level:new(tab)
	tab = tab or {}
	setmetatable(tab, {__index = self})

	-- list lines
	assert(type(tab.source) == "string")
	local lines = {}
	local pos = 1
	while pos <= #tab.source do
		local s1, s2, str = tab.source:find("(.-)\n", pos)
		if not s1 then break end
		table.insert(lines, str)
		pos = s2 + 1
	end
	table.insert(lines, tab.source:sub(pos))
	-- load/check dimensions
	assert(next(lines))
	tab.gridHeight = #lines
	assert(#lines[1] > 0)
	tab.gridWidth = #lines[1]
	for i = 2, #lines do
		assert(#lines[i] == tab.gridWidth)
	end
	-- assign wall grid
	local wallGrid = {}
	for j, line in ipairs(lines) do
		table.insert(wallGrid, {})
		for i = 1, #line do
			table.insert(wallGrid[j], not not (line:sub(i, i) == TileTypes.wall))
		end
	end
	setmetatable(wallGrid, {__index = function () return {} end})
	tab.wallGrid = wallGrid
	-- add player
	for j, line in ipairs(lines) do
		for i = 1, #line do
			if line:sub(i, i) == TileTypes.start then
				assert(not tab.player)
				tab.player = {
					x = g_tileSize * (i - 1),
					y = g_tileSize * (j - 1),
					w = 20,
					h = 20,
					direction = "neutral",
					speed = 0
				}
			end
		end
	end
	assert(tab.player)

	-- start view on player
	g_viewX, g_viewY = tab.player.x - 0.5*g_defaultWidth, tab.player.y - 0.5*g_defaultHeight

	return tab
end

function Level:blockCollision(tab)
	assert(tab and type(tab) == "table" and tab.x and tab.y and tab.w and tab.h)
	local tlCornerX, tlCornerY = math.floor(tab.x / g_tileSize) + 1, math.floor(tab.y / g_tileSize) + 1
	local brCornerX, brCornerY = math.floor((tab.x + tab.w) / g_tileSize) + 1, math.floor((tab.y + tab.h) / g_tileSize) + 1

	local wallGrid = self.wallGrid
	if tlCornerY == brCornerY then
		-- if TL-corner and BR-corner are the same tile then single collision check
		if tlCornerX == brCornerX then
			return wallGrid[tlCornerY][tlCornerX]
		-- X different, check two tiles
		else
			return wallGrid[tlCornerY][tlCornerX] or wallGrid[tlCornerY][tlCornerX+1]
		end
	else
		-- if TL-corner and BR-corner are different we get to do 4 collision checks JOY
		if tlCornerX ~= brCornerX then
			return
				wallGrid[tlCornerY][tlCornerX]     or
				wallGrid[tlCornerY+1][tlCornerX]   or
				wallGrid[tlCornerY][tlCornerX+1]   or
				wallGrid[tlCornerY+1][tlCornerX+1]
		-- just Y different, check two tiles
		else
			return wallGrid[tlCornerY][tlCornerX] or wallGrid[tlCornerY+1][tlCornerX]
		end
	end
end

local maxPlayerSpeed = 3
local playerSpeedIncrement = 0.5
local playerSpeedDecrement = 1
local viewDeadzoneX = 15
local viewDeadzoneY = 10

function Level:step()
	local player = self.player

	-- handle user movement input
	-- determine intended direction
	local intendedDir = "neutral"
	if     love.keyboard.isScancodeDown('a', 'left') then
		intendedDir = "left"
	elseif love.keyboard.isScancodeDown('d', 'right') then
		intendedDir = "right"
	elseif love.keyboard.isScancodeDown('w', 'up') then
		intendedDir = "up"
	elseif love.keyboard.isScancodeDown('s', 'down') then
		intendedDir = "down"
	end
	if intendedDir ~= player.direction then
		-- if intention is to stop, slow down (also spend stationary 'momentum')
		if intendedDir == "neutral" then
			player.speed = player.speed - playerSpeedDecrement
			if player.speed <= 0 then
				player.speed = 0
				player.direction = "neutral"
			end
		-- otherwise, change direction (and speed up if appropriate)
		else
			player.speed = player.speed + playerSpeedIncrement
			if player.speed > maxPlayerSpeed then
				player.speed = maxPlayerSpeed
			end
			player.direction = intendedDir
		end
	-- otherwise, keep moving in direction (and speed up if appropriate)
	else
		player.speed = player.speed + playerSpeedIncrement
		if player.speed > maxPlayerSpeed then
			player.speed = maxPlayerSpeed
		end
	end

	-- handle player velocity
	if player.direction ~= "neutral" then
		-- find projected position
		local projection = {w = player.w, h = player.h}
		if     player.direction == "up" then
			projection.x = player.x
			projection.y = player.y - player.speed
		elseif player.direction == "down" then
			projection.x = player.x
			projection.y = player.y + player.speed
		elseif player.direction == "left" then
			projection.x = player.x - player.speed
			projection.y = player.y
		elseif player.direction == "right" then
			projection.x = player.x + player.speed
			projection.y = player.y
		end
		-- check for collision
		if self:blockCollision(projection) then
			--player.speed = 0
			if     player.direction == "up" then
				player.y = g_tileSize * math.floor(player.y/g_tileSize)
			elseif player.direction == "down" then
				player.y = g_tileSize * math.ceil(player.y/g_tileSize) - player.h - 0.0000001
			elseif player.direction == "left" then
				player.x = g_tileSize * math.floor(player.x/g_tileSize)
			elseif player.direction == "right" then
				player.x = g_tileSize * math.ceil(player.x/g_tileSize) - player.w - 0.0000001
			end
			player.direction = "neutral"
		else
			player.x, player.y = projection.x, projection.y
		end
	end

	-- keep view in a deadzone of the player
	local viewCentreX = player.x - 0.5*g_defaultWidth
	local viewCentreY = player.y - 0.5*g_defaultHeight
	if     g_viewX < viewCentreX - viewDeadzoneX then
		g_viewX = viewCentreX - viewDeadzoneX
	elseif g_viewX > viewCentreX + viewDeadzoneX then
		g_viewX = viewCentreX + viewDeadzoneX
	elseif g_viewY < viewCentreY - viewDeadzoneY then
		g_viewY = viewCentreY - viewDeadzoneY
	elseif g_viewY > viewCentreY + viewDeadzoneY then
		g_viewY = viewCentreY + viewDeadzoneY
	end
end

function Level:draw()
	-- draw player
	love.graphics.setColor(0, 255, 0)
	local player = self.player
	love.graphics.rectangle("fill", player.x, player.y, player.w, player.h)

	-- draw walls
	love.graphics.setColor(40, 40, 40)
	local wallGrid = self.wallGrid
	for j, row in ipairs(wallGrid) do
		for i, occupied in ipairs(row) do
			if occupied then
				love.graphics.rectangle("fill", (i - 1) * g_tileSize, (j - 1) * g_tileSize, g_tileSize, g_tileSize)
			end
		end
	end
end

return Level
