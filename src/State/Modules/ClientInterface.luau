local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Network = require(script.Parent.Parent.Parent.Network.Server)
local ClientInterface = {}
ClientInterface.__index = ClientInterface

local Signal = require(script.Parent.Parent.Util.Signal)

export type ClientManager = {
	GetPlayerData: (self: ClientManager, player: Player) -> { any },
	SetPlayerData: (self: ClientManager, player: Player, val: {}) -> nil,
	DeletePlayerData: (self: ClientManager, player: Player) -> nil,
	UpdatePlayerData: (self: ClientManager, player: Player, callback: (any) -> any) -> nil,
	SetPlayerKey: (self: ClientManager, player: Player, key: any, val: any) -> nil,
	DeletePlayerKey: (self: ClientManager, player: Player, key: any) -> nil,
	UpdatePlayerKey: (self: ClientManager, player: Player, key: any, callback: (any) -> any) -> nil,
	GetPlayerKey: (self: ClientManager, player: Player, key: any) -> any,
	GetPlayerKeyChangedSignal: (self: ClientManager, player: Player, key: any) -> Signal.Signal<any>,
	GetPlayerDataChangedSignal: (self: ClientManager, player: Player) -> Signal.Signal<any>,
}

type self = {
	_state: {},
	_signals: { [Player]: { [any]: Signal.Signal<any> } },
	_dataChangedSignal: { [Player]: Signal.Signal<any> },
	_name: string,
} & ClientManager

if not RunService:IsServer() then
	return {} :: ClientManager
end

local RegisteredInterfaces = {} :: { [string]: self }

function ClientInterface.new(name: string): self | nil
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))
	assert(not RegisteredInterfaces[name], "ClientInterface " .. name .. " is already registered")
	local self = setmetatable({} :: self, ClientInterface)

	self._name = name
	self._state = {}
	self._signals = {}
	self._dataChangedSignal = {}

	return self
end

function ClientInterface:GetPlayerData(player: Player)
	self = self :: self
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end

	return self._state[player]
end

function ClientInterface:SetPlayerData(player: Player, val: {})
	self = self :: self
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	if typeof(val) ~= "table" then
		warn("Expected a table, got " .. typeof(val))
		return
	end

	Network.Fire("_FRAMEWORK/UpdateSharedInterface-" .. self._name, player, val)
	if Signal.Is(self._dataChangedSignal[player]) then
		self._dataChangedSignal[player]:Fire(val)
	end
	self._state[player] = val
end

function ClientInterface:DeletePlayerData(player: Player)
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self
	local playerSignals = self._signals[player]
	if playerSignals then
		for _, v in playerSignals do
			v:Destroy()
		end
	end
	if Signal.Is(self._dataChangedSignal[player]) then
		self._dataChangedSignal[player]:Destroy()
	end
	self._dataChangedSignal[player] = nil
	self._signals[player] = {}
	self:SetPlayerData(player, {})
end

function ClientInterface:UpdatePlayerData(player: Player, callback: (old: any) -> any)
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self
	local old = self:GetPlayerData(player)
	if not old then
		return
	end

	local newVal = callback(old)
	self:SetPlayerData(player, newVal)
end

function ClientInterface:SetPlayerKey(player: Player, key, val)
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		warn("Expected a table, got " .. typeof(player))
		return
	end
	self = self :: self
	if not self._signals[player] then
		self._signals[player] = {}
	end
	local signal = self._signals[player][key]
	if Signal.Is(signal) then
		signal:Fire(val)
	end

	if not self._state[player] then
		self._state[player] = {}
	end

	local changes = {}
	changes[key] = val
	Network.Fire("_FRAMEWORK/UpdateSharedInterface-" .. self._name, player, changes)

	self._state[player][key] = val
	if Signal.Is(self._dataChangedSignal[player]) then
		self._dataChangedSignal[player]:Fire(self:GetPlayerData(player))
	end
end

function ClientInterface:DeletePlayerKey(player: Player, key)
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self

	if self._signals[player] and self._signals[player][key] then
		self._signals[player][key]:Destroy()
		self._signals[player][key] = nil
	end

	self:SetPlayerKey(player, key, nil)

	if self._state[player] and self._state[player][key] then
		self._state[player][key] = nil
	end
end

function ClientInterface:GetPlayerKey(player: Player, key): any | nil
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self
	if not self._state[player] or not self._state[player][key] then
		warn(`Key {key} doesn't exist`)
		return
	end
	return self._state[player][key]
end

function ClientInterface:UpdatePlayerKey(player: Player, key, callback: (any) -> any)
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self
	local old = self:GetPlayerKey(player, key)
	if not old then
		return
	end

	local newVal = callback(old)
	self:SetPlayerKey(player, key, newVal)
end

function ClientInterface:GetPlayerKeyChangedSignal(player: Player, key): Signal.Signal<any> | nil
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self
	if not self._signals[player] then
		self._signals[player] = {}
	end
	if not self._signals[player][key] then
		self._signals[player][key] = Signal.new()
	end

	return self._signals[player][key]
end

function ClientInterface:GetPlayerDataChangedSignal(player: Player): Signal.Signal<any> | nil
	if typeof(player) ~= "Instance" or not player:IsDescendantOf(Players) then
		return
	end
	self = self :: self
	if not Signal.Is(self._dataChangedSignal[player]) then
		self._dataChangedSignal[player] = Signal.new()
	end

	return self._dataChangedSignal[player]
end

return ClientInterface
