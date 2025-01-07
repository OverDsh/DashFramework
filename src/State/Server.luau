local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Util.Signal)
local ClientInterface = require(script.Parent.Modules.ClientInterface)
local Network = require(script.Parent.Parent.Network.Server)

type StateManager = {
	SetKey: (self: StateManager, key: any, val: any) -> nil,
	DeleteKey: (self: StateManager, key: any) -> nil,
	UpdateKey: (self: StateManager, key: any, callback: (any) -> any) -> nil,
	GetKey: (self: StateManager, key: any) -> any,
	GetKeyChangedSignal: (self: StateManager, key: any) -> Signal.Signal<any>,
}

type self = {
	_state: {},
	_signals: {
		[any]: Signal.Signal<any>,
	},
	Client: ClientInterface.ClientManager,
} & StateManager

local StateManager = {}
StateManager.__index = StateManager

if not RunService:IsServer() then
	script:Destroy()
	return StateManager
end

local RegisteredStateInterface = {} :: {
	[string]: self,
}
local RegisterSignals = {} :: {
	[string]: Signal.Signal<self>,
}

function StateManager.RegisterStateInterface(name: string, initState: {}): self | nil
	assert(typeof(initState) == "table", "Expected a table, got " .. typeof(initState))
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))
	assert(not RegisteredStateInterface[name], `StateInterface {name} already exists`)

	local self = setmetatable({} :: self, StateManager)

	self._state = initState
	self._signals = {}
	local NewClientInterface = ClientInterface.new(name)
	assert(ClientInterface, "Couldn't generate ClientInterface for " .. name)
	self.Client = NewClientInterface

	RegisteredStateInterface[name] = self
	if RegisterSignals[name] then
		RegisterSignals[name]:Fire(self)
	end
	return self
end

function StateManager.GetStateInterface(name: string): self | nil
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))
	if not RegisteredStateInterface[name] then
		warn("StateInterface not registered")
		return
	end
	return RegisteredStateInterface[name]
end

function StateManager.GetStateInterfaceAddedSignal(name: string): Signal.Signal<self>
	local AddedSignal = Signal.new()
	if RegisteredStateInterface[name] then
		AddedSignal:FireDeferred(RegisteredStateInterface[name])
		return AddedSignal
	elseif RegisterSignals[name] then
		return RegisterSignals[name]
	else
		RegisterSignals[name] = AddedSignal
		return AddedSignal
	end
end

function StateManager:SetKey(key, val)
	self = self :: self
	local signal = self._signals[key]
	if Signal.Is(signal) then
		signal:Fire(val)
	end

	self._state[key] = val
end

function StateManager:DeleteKey(key)
	self = self :: self

	if self._signals[key] then
		self._signals[key]:Destroy()
		self._signals[key] = nil
	end
	self:SetKey(key, nil)
end

function StateManager:UpdateKey(key, callback: (any) -> any)
	self = self :: self
	local old = assert(self:GetKey(key), "Key " .. tostring(key) .. " doesn't exist")

	local newVal = callback(old)
	self:SetKey(key, newVal)
end

function StateManager:GetKey(key): any | nil
	self = self :: self
	assert(self._state[key], `Key {key} doesn't exist`)
	return self._state[key]
end

function StateManager:GetKeyChangedSignal(key): Signal.Signal<any>
	self = self :: self
	if not self._signals[key] then
		self._signals[key] = Signal.new()
	end

	return self._signals[key]
end

function StateManager.Is(manager): boolean
	return typeof(manager) == "table" and getmetatable(manager) == StateManager
end

Network.OnInvoke("_FRAMEWORK/GetSharedInterface", function(player, name)
	local SM = StateManager.GetStateInterface(name) or StateManager.GetStateInterfaceAddedSignal(name):Wait()
	return SM.Client:GetPlayerData(player) or {}
end)

return StateManager
