local Level = require("game.Level")

function love.load()
	require("global")

	love.window.setMode(g_defaultWidth, g_defaultHeight, {
		fullscreen = true,
		fullscreentype = "desktop",
	})
	love.resize(love.window.getMode())
	love.graphics.setDefaultFilter("linear", "nearest", 0)
	love.graphics.setBackgroundColor(240, 240, 230)

	g_testImage = love.graphics.newImage("assets/test.png")

	require("levels")

	g_currentLevel = Level:new{source = g_levelData1}
end

function love.resize(w, h)
	g_windowWidth, g_windowHeight = w, h
end

local dtotal = 0
function love.update(dt)
	-- Limit to 1/30 updates
	dtotal = dtotal + dt
	if dtotal >= 1/30 then
		dtotal = dtotal - 1/30
	else
		return
	end
	if g_currentLevel then
		g_currentLevel:step()
	end
end

function love.draw()
	-- Setup view coordinates
	local xFac = g_windowWidth/g_defaultWidth
	local yFac = g_windowHeight/g_defaultHeight
	local shrink, aScale, aWidth, aHeight, screenX, screenY, barSize
	if xFac < yFac then
		shrink = "y"
		aWidth = g_windowWidth
		aHeight = xFac/yFac * g_windowHeight
		local shrinkSpace = g_windowHeight - aHeight
		barSize = shrinkSpace/2
		screenX = 0
		screenY = barSize
		aScale = xFac
	else
		shrink = "x"
		aWidth = yFac/xFac * g_windowWidth
		aHeight = g_windowHeight
		local shrinkSpace = g_windowWidth - aWidth
		barSize = shrinkSpace/2
		screenX = barSize
		screenY = 0
		aScale = yFac
	end
	love.graphics.push()
	love.graphics.translate(screenX, screenY)
	love.graphics.push()
	love.graphics.scale(aScale, aScale)
	love.graphics.push()
	love.graphics.translate(-g_viewX, -g_viewY)

	if g_currentLevel then
		g_currentLevel:draw()
	end

	love.graphics.pop()
	love.graphics.pop()
	love.graphics.pop()
	love.graphics.setColor(0, 0, 0)
	if shrink == "y" then
		love.graphics.rectangle("fill", 0, 0, g_windowWidth, barSize)
		love.graphics.rectangle("fill", 0, g_windowHeight - barSize, g_windowWidth, barSize)
	else
		love.graphics.rectangle("fill", 0, 0, barSize, g_windowHeight)
		love.graphics.rectangle("fill", g_windowWidth - barSize, 0, barSize, g_windowHeight)
	end
end
