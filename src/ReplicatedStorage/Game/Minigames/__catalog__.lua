local RS = game:GetService("ReplicatedStorage")
local Minigames = RS.Game.Minigames

return {
	-- ...otros
	{ id = "AudioRun", module = Minigames.AudioRun.GameController, weight = 1 },
}
