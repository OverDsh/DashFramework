local RunService = game:GetService("RunService")

local Client = require(script.Client)
local Server = require(script.Server)

if RunService:IsClient() then
	return {
		Server = {} :: Server.Server,
		Client = Client :: Client.Client,
	}
else
	return {
		Server = Server :: Server.Server,
		Client = {} :: Client.Client,
	}
end
