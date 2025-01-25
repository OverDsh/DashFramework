local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Util.Signal)
local Network = require(script.Parent.Parent.Network.Client)

export type StateManagerClient = {
	SetKey: (self: StateManagerClient, key: any, val: any) -> nil,
	DeleteKey: (self: StateManagerClient, key: any) -> nil,
	UpdateKey: (self: StateManagerClient, key: any, callback: (any) -> any) -> nil,
	GetKey: (self: StateManagerClient, key: any) -> any,
	GetKeyChangedSignal: (self: StateManagerClient, key: any) -> Signal.Signal<any>,
	GetSharedInterface: (name: string) -> SharedSelf | nil,
	RegisterStateInterface: (name: string, initState: {}) -> self | nil,
	GetStateInterface: (name: string) -> self | nil,
	GetStateInterfaceAddedSignal: (name: string) -> Signal.Signal<self>,
}

type self = {
	_state: {},
	_signals: {
		[any]: Signal.Signal<any>,
	},
} & StateManagerClient

type SharedSelf = {
	_state: {},
	_signals: {
		[any]: Signal.Signal<any>,
	},
	_loaded: boolean,
	Loaded: Signal.Signal<nil>,
	IsLoaded: boolean,
} & StateManagerClient

if RunService:IsServer() then
	return {} :: StateManagerClient
end

local StateManagerClient = {}
StateManagerClient.__index = StateManagerClient

local RegisteredStateInterface = {} :: {
	[string]: self,
}
local RegisteredSharedInterface = {} :: {
	[string]: self,
}

local RegisterSignals = {} :: {
	[string]: Signal.Signal<self>,
}

function StateManagerClient.GetSharedInterface(name: string): SharedSelf | nil
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))

	--Use SharedInterface cache
	if RegisteredSharedInterface[name] then
		return RegisteredSharedInterface[name]
	end

	--Request the current data of the sharedInterface
	local sucess, Data = Network.Invoke("_FRAMEWORK/GetSharedInterface", name):timeout(30):await()
	assert(sucess, "Couldn't retrieve shared interface " .. name)
	assert(typeof(Data) == "table", "Error while retrieving shared interface " .. name)

	local self = setmetatable({} :: SharedSelf, StateManagerClient)

	self._state = Data
	self._signals = {}
	self._loaded = false
	self.IsLoaded = false
	self.Loaded = Signal.new()

	--Since roblox is dumb we cant get len of dict and I have to make a shitty loop
	local Len = 0
	for _i, _v in Data do
		Len += 1
	end

	--If there's some data then we flag the Interface as loaded
	if Len > 0 then
		self._loaded = true
		self.IsLoaded = true
	end

	Network.OnEvent("_FRAMEWORK/UpdateSharedInterface-" .. name):Connect(function(changes)
		assert(
			typeof(changes) == "table",
			"Error while hydrating SharedInterface: expected a table, got " .. typeof(changes)
		)

		--Hydrate the current interface (exemple hydrate table: {Key1 = newVal, Key2 = newVal2})
		for i, v in changes do
			if not i or not v then
				continue
			end
			self:SetKey(i, v)
		end

		--If we recieve changes and Interface is not already flagged as loaded, we flag it as loaded
		if not self._loaded then
			self._loaded = true
			self.IsLoaded = true
			self.Loaded:Fire()
		end
	end)

	--Caches the sharedInterface
	RegisteredSharedInterface[name] = self
	return self
end

function StateManagerClient.RegisterStateInterface(name: string, initState: {}): self | nil
	assert(typeof(initState) == "table", "Expected a table, got " .. typeof(initState))
	assert(not RegisteredStateInterface[name], `StateInterface {name} already exists`)

	local self = setmetatable({} :: self, StateManagerClient)

	self._state = initState
	self._signals = {}

	--Add StateInterface to array to be retrieved later
	RegisteredStateInterface[name] = self

	--Check if there's a listener to InterfaceAddedSignal of current interface and notify it
	if RegisterSignals[name] then
		RegisterSignals[name]:Fire(self)
	end
	return self
end

function StateManagerClient.GetStateInterface(name: string): self | nil
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))
	assert(RegisteredStateInterface[name], `StateInterface {name} doesn't exist`)
	return RegisteredStateInterface[name]
end

function StateManagerClient.GetStateInterfaceAddedSignal(name: string): Signal.Signal<self>
	if RegisterSignals[name] then
		--If the signal already exists, return it
		return RegisterSignals[name]
	else
		--Create a new signal and add it to an array to be picked up by the RegisterStateInterface function
		local AddedSignal = Signal.new()
		RegisterSignals[name] = AddedSignal
		return AddedSignal
	end
end

function StateManagerClient:SetKey(key, val)
	self = self :: self
	local signal = self._signals[key]
	if Signal.Is(signal) then
		signal:Fire(val)
	end

	self._state[key] = val
end

function StateManagerClient:DeleteKey(key)
	self = self :: self

	if self._signals[key] then
		self._signals[key]:Destroy()
		self._signals[key] = nil
	end
	self:SetKey(key, nil)
end

function StateManagerClient:UpdateKey(key, callback: (any) -> any)
	self = self :: self
	local old = self:GetKey(key)
	if not old then
		return
	end

	local newVal = callback(old)
	self:SetKey(key, newVal)
end

function StateManagerClient:GetKey(key): any | nil
	self = self :: self
	assert(self._state[key], `Key {key} doesn't exist`)
	return self._state[key]
end

function StateManagerClient:GetKeyChangedSignal(key): Signal.Signal<any>
	self = self :: self
	if not self._signals[key] then
		self._signals[key] = Signal.new()
	end

	return self._signals[key]
end

function StateManagerClient.Is(manager): boolean
	return typeof(manager) == "table" and getmetatable(manager) == StateManagerClient
end

return StateManagerClient
