local TileTypes = {
	wall = "#",
	start = "S",
	enemy = "A",
	finish = "F",
}

local enemyPatrolSpeed = 3.5
local enemyChaseSpeed = 3

local playerW, playerH = 20, 20
local enemyW, enemyH = 20, 20

local maxPlayerSpeed = 3
local playerSpeedIncrement = 0.5
local playerSpeedDecrement = 1
local viewDeadzoneX = 15
local viewDeadzoneY = 10
local shyDistance = 75
local hurtSpeed = 2.0

local Level = {}
Level.Level = true

Level.gridWidth = 0
Level.gridHeight = 0
Level.source = nil
Level.enemies = nil
Level.wallGrid = nil
Level.pathGrid = nil
Level.player = nil
Level.gameOver = false
Level.finishes = nil
Level.success = false

function Level:loadItem(c, i, j)
	local wallGrid = self.wallGrid
	local pathGrid = self.pathGrid
	local finishes = self.finishes
	-- assign grid values
	wallGrid[j][i] = not not (c == TileTypes.wall)
	pathGrid[j][i] =
		({
			[">"] = "right",
			["<"] = "left",
			["^"] = "up",
			["v"] = "down",
			["V"] = "down",
		})[c] or false
	-- detect player / enemies
	if     c == TileTypes.start then
		assert(not self.player)
		self.player = {
			x = g_tileSize * (i - 1) + (g_tileSize - playerW)/2,
			y = g_tileSize * (j - 1) + (g_tileSize - playerH)/2,
			w = playerW,
			h = playerH,
			direction = "neutral",
			speed = 0,
			health = 100
		}
	elseif c == TileTypes.enemy then
		table.insert(self.enemies, {
			x = g_tileSize * (i - 1) + (g_tileSize - enemyW)/2,
			y = g_tileSize * (j - 1) + (g_tileSize - enemyH)/2,
			w = enemyW,
			h = enemyH,
			direction = "neutral",
			speed = enemyPatrolSpeed,
			mode = "patrol",
		})
	elseif c == TileTypes.finish then
		table.insert(finishes, {
			x = g_tileSize * (i - 1) + (g_tileSize - enemyW)/2,
			y = g_tileSize * (j - 1) + (g_tileSize - enemyH)/2,
			w = g_tileSize,
			h = g_tileSize,
		})
	end
end

function Level:new(tab)
	tab = tab or {}
	setmetatable(tab, {__index = self})

	love.mouse.setVisible(false)

	assert(type(tab.extra) == "table")

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
	-- load data
	tab.wallGrid = {}
	tab.pathGrid = {}
	tab.enemies = {}
	tab.finishes = {}
	for j, line in ipairs(lines) do
		tab.wallGrid[j] = {}
		tab.pathGrid[j] = {}
		for i = 1, #line do
			tab:loadItem(line:sub(i, i), i, j)
		end
	end
	for _, extra in ipairs(tab.extra) do
		tab:loadItem(extra[1], extra[2], extra[3])
	end
	assert(tab.player)
	setmetatable(tab.wallGrid, {__index = function () return {} end})
	setmetatable(tab.pathGrid, {__index = function () return {} end})

	-- start view on player
	g_viewX, g_viewY = tab.player.x - 0.5*g_defaultWidth, tab.player.y - 0.5*g_defaultHeight

	return tab
end

function Level:gridCollision(grid, tab)
	assert(tab and type(tab) == "table" and tab.x and tab.y and tab.w and tab.h)
	local tlCornerX, tlCornerY = math.floor(tab.x / g_tileSize) + 1, math.floor(tab.y / g_tileSize) + 1
	local brCornerX, brCornerY = math.floor((tab.x + tab.w) / g_tileSize) + 1, math.floor((tab.y + tab.h) / g_tileSize) + 1

	if tlCornerY == brCornerY then
		-- if TL-corner and BR-corner are the same tile then single collision check
		if tlCornerX == brCornerX then
			return grid[tlCornerY][tlCornerX]
		-- X different, check two tiles
		else
			return grid[tlCornerY][tlCornerX] or grid[tlCornerY][tlCornerX+1]
		end
	else
		-- if TL-corner and BR-corner are different we get to do 4 collision checks JOY
		if tlCornerX ~= brCornerX then
			return
				grid[tlCornerY][tlCornerX]     or
				grid[tlCornerY+1][tlCornerX]   or
				grid[tlCornerY][tlCornerX+1]   or
				grid[tlCornerY+1][tlCornerX+1]
		-- just Y different, check two tiles
		else
			return grid[tlCornerY][tlCornerX] or grid[tlCornerY+1][tlCornerX]
		end
	end
end

function Level:boxCollision(b1, b2, isNestedInv)
	-- top left b1
	if b2.x <= b1.x and b1.x <= b2.x+b2.w and b2.y <= b1.y and b1.y <= b2.y+b2.h then
		return true
	-- top right b1
	elseif b2.x <= b1.x+b1.w and b1.x+b1.w <= b2.x+b2.w and b2.y <= b1.y and b1.y <= b2.y+b2.h then
		return true
	-- bottom left b1
	elseif b2.x <= b1.x and b1.x <= b2.x+b2.w and b2.y <= b1.y+b1.h and b1.y+b1.h <= b2.y+b2.h then
		return true
	-- bottom right b1
	elseif b2.x <= b1.x+b1.w and b1.x+b1.w <= b2.x+b2.w and b2.y <= b1.y+b1.h and b1.y+b1.h <= b2.y+b2.h then
		return true
	end
	-- test b2's corners instead
	if not isNestedInv then
		return self:boxCollision(b2, b1, true)
	end
	-- otherwise no intersection
	return false
end

function Level:motion(tab, autoReflect)
	-- handle entity velocity
	if tab.direction ~= "neutral" then
		-- find projected position
		local projection = {w = tab.w, h = tab.h}
		if     tab.direction == "up" then
			projection.x = tab.x
			projection.y = tab.y - tab.speed
		elseif tab.direction == "down" then
			projection.x = tab.x
			projection.y = tab.y + tab.speed
		elseif tab.direction == "left" then
			projection.x = tab.x - tab.speed
			projection.y = tab.y
		elseif tab.direction == "right" then
			projection.x = tab.x + tab.speed
			projection.y = tab.y
		end
		-- check for collision
		if self:gridCollision(self.wallGrid, projection) then
			local gridX, gridY
			if autoReflect then
				gridX = math.floor((tab.x+0.5*tab.w)/g_tileSize) + 1
				gridY = math.floor((tab.y+0.5*tab.h)/g_tileSize) + 1
			end
			if     tab.direction == "up" then
				tab.y = g_tileSize * math.floor(tab.y/g_tileSize)
			elseif tab.direction == "down" then
				tab.y = g_tileSize * math.ceil(tab.y/g_tileSize) - tab.h - 0.0000001
			elseif tab.direction == "left" then
				tab.x = g_tileSize * math.floor(tab.x/g_tileSize)
			elseif tab.direction == "right" then
				tab.x = g_tileSize * math.ceil(tab.x/g_tileSize) - tab.w - 0.0000001
			end
			if autoReflect and (tab.direction == "up" or tab.direction == "down") then
				if self.wallGrid[gridY][gridX-1] and not self.wallGrid[gridY][gridX+1] then
					tab.direction = "right"
				elseif self.wallGrid[gridY][gridX+1] and not self.wallGrid[gridY][gridX-1] then
					tab.direction = "left"
				end
			elseif autoReflect and (tab.direction == "left" or tab.direction == "right") then
				if self.wallGrid[gridY+1][gridX] and not self.wallGrid[gridY-1][gridX] then
					tab.direction = "up"
				elseif self.wallGrid[gridY-1][gridX] and not self.wallGrid[gridY+1][gridX] then
					tab.direction = "down"
				end
			end
		else
			tab.x, tab.y = projection.x, projection.y
		end
	end
end

function Level:step()
	local player = self.player

	-- handle user movement input (while game not over)
	-- determine intended direction
	local intendedDir = "neutral"
	if not self.gameOver then
		if     love.keyboard.isScancodeDown('a', 'left') then
			intendedDir = "left"
		elseif love.keyboard.isScancodeDown('d', 'right') then
			intendedDir = "right"
		elseif love.keyboard.isScancodeDown('w', 'up') then
			intendedDir = "up"
		elseif love.keyboard.isScancodeDown('s', 'down') then
			intendedDir = "down"
		end
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
	self:motion(player)

	-- move enemies
	for _, enemy in pairs(self.enemies) do
		self:motion(enemy, true)
		-- redirect on path cells
		local redirect = self:gridCollision(self.pathGrid, enemy)
		if redirect then
			-- confirm enemy is in an appropriate position to redirect!
			local modX = enemy.x % g_tileSize
			local modY = enemy.y % g_tileSize
			local xCheck = 0 <= modX and modX <= 0.5*(g_tileSize-enemy.w)
			local yCheck = 0 <= modY and modY <= 0.5*(g_tileSize-enemy.h)
			if xCheck and yCheck then
				enemy.direction = redirect
			end
		end
	end

	-- if we hit finish tile ... success!
	for _, finish in pairs(self.finishes) do
		if self:boxCollision(player, finish) then
			self.success = true
			break
		end
	end

	-- check player proximity to enemies
	for _, enemy in pairs(self.enemies) do
		if math.sqrt((player.x - enemy.x)^2 + (player.y - enemy.y)^2) < shyDistance then
			player.health = player.health - hurtSpeed
			if player.health <= 0 then
				player.health = 0
				self.gameOver = true
			end
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
	love.graphics.push()
	love.graphics.translate(-g_viewX, -g_viewY)

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

	-- draw finishes
	love.graphics.setColor(0, 200, 0)
	for _, finish in pairs(self.finishes) do
		love.graphics.rectangle("fill", finish.x, finish.y, finish.w, finish.h)
	end

	-- draw player
	love.graphics.setColor(0, 255, 0)
	local player = self.player
	love.graphics.rectangle("fill", player.x, player.y, player.w, player.h)

	-- draw enemies
	love.graphics.setColor(180, 30, 30)
	local enemies = self.enemies
	for _, enemy in pairs(enemies) do
		love.graphics.rectangle("fill", enemy.x, enemy.y, enemy.w, enemy.h)
	end

	love.graphics.pop()

	-- draw hurtangle
	love.graphics.setColor(255, 0, 0, 100 - self.player.health)
	love.graphics.rectangle("fill", 0, 0, g_defaultWidth, g_defaultHeight)

	-- draw meter
	love.graphics.setColor(255, 0, 0)
	love.graphics.rectangle("fill", 20, 20, 0.01 * (100 - player.health) * (g_defaultWidth - 40), 10)

	-- draw GAME OVER
	if self.gameOver then
		love.graphics.setColor(0, 0, 0)
		love.graphics.print("GAME OVER", g_defaultWidth*.5 - 133, g_defaultHeight*.5 - 20, 0, 1, 1)
	end
end

return Level
