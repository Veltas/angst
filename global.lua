g_tileSize = 32

g_defaultWidth, g_defaultHeight = 16*g_tileSize, 9*g_tileSize

g_windowWidth, g_windowHeight = g_defaultWidth, g_defaultHeight

g_viewX, g_viewY = 0, 0

g_coordStackReady = false

g_currentLevel = nil

function xc(coord)
	return g_windowWidth / g_defaultWidth * coord
end

function yc(coord)
	return g_windowHeight / g_defaultHeight * coord
end
