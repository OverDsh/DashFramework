local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Util.Signal)
local Network = require(script.Parent.Parent.Network.Client)

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
} & StateManager

type SharedSelf = {
	_state: {},
	_signals: {
		[any]: Signal.Signal<any>,
	},
	_loaded: boolean,
	Loaded: Signal.Signal<nil>,
	IsLoaded: boolean,
} & StateManager

local StateManager = {}
StateManager.__index = StateManager

if not RunService:IsClient() then
	script:Destroy()
	return StateManager
end
if script.Parent:FindFirstChild("Server") then
	script.Parent:FindFirstChild("Server"):Destroy()
end

local RegisteredStateInterface = {} :: {
	[string]: self,
}
local RegisteredSharedInterface = {} :: {
	[string]: self,
}

local RegisterSignals = {} :: {
	[string]: Signal.Signal<self>,
}

function StateManager.GetSharedInterface(name: string): SharedSelf | nil
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))
	if RegisteredSharedInterface[name] then
		return RegisteredSharedInterface[name]
	end

	local sucess, Data = Network.Invoke("_FRAMEWORK/GetSharedInterface", name):timeout(30):await()
	assert(sucess, "Couldn't retrieve shared interface " .. name)
	assert(typeof(Data) == "table", "Error while retrieving shared interface " .. name)

	local self = setmetatable({} :: SharedSelf, StateManager)

	self._state = Data
	self._signals = {}
	self._loaded = false
	self.IsLoaded = false
	self.Loaded = Signal.new()

	if #Data ~= 0 then
		self._loaded = true
		self.Loaded:Fire()
	end

	Network.OnEvent("_FRAMEWORK/UpdateSharedInterface-" .. name):Connect(function(changes)
		if typeof(changes) ~= "table" then
			return
		end

		for i, v in changes do
			if not i or not v then
				continue
			end
			self:SetKey(i, v)
		end

		if not self._loaded then
			self._loaded = true
			self.IsLoaded = true
			self.Loaded:Fire()
		end
	end)

	RegisteredSharedInterface[name] = self
	return self
end

function StateManager.RegisterStateInterface(name: string, initState: {}): self | nil
	assert(typeof(initState) == "table", "Expected a table, got " .. typeof(initState))
	assert(not RegisteredStateInterface[name], `StateInterface {name} already exists`)

	local self = setmetatable({} :: self, StateManager)

	self._state = initState
	self._signals = {}

	RegisteredStateInterface[name] = self
	if RegisterSignals[name] then
		RegisterSignals[name]:Fire(self)
	end
	return self
end

function StateManager.GetStateInterface(name: string): self | nil
	assert(typeof(name) == "string", "Expected a string, got " .. typeof(name))
	assert(RegisteredStateInterface[name], `StateInterface {name} doesn't exist`)
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
	local old = self:GetKey(key)
	if not old then
		return
	end

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

return StateManager
