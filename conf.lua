-- LÖVE reads this before the window opens.
function love.conf(t)
	t.identity = "spacegame_proto"      -- save folder name (settings, Slab layout, screenshots)
	t.version = "11.5"
	t.console = false

	t.window.title = "Space Shooter Prototype - Flight Toy"
	t.window.width = 1280
	t.window.height = 720
	t.window.minwidth = 960
	t.window.minheight = 540
	t.window.resizable = true
	t.window.vsync = 1

	-- No audio in the flight toy yet (the design doc puts audio later).
	t.modules.audio = false
	t.modules.sound = false
end
