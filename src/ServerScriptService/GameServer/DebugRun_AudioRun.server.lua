local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Mod = require(RS.Game.Minigames.AudioSyncTest.GameController)

task.delay(2, function()
	if #Players:GetPlayers() == 0 then return end
	local mount = Instance.new("Folder", workspace)
	mount.Name = "MG_AudioSync_Test"

	local ctx = {
		sessionId = "dbg-"..math.random(1000,9999),
		players = Players:GetPlayers(),
		mountFolder = mount,
	}

	local mg = Mod.Create(ctx)
	mg:Setup(ctx)
	mg:Start()
	mg:Teardown()
	mount:Destroy()
end)
