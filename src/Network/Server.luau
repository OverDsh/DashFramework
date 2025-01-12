local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Util.Signal)
local Promise = require(script.Parent.Util.Promise)
local Network = {
	Compress = require(script.Parent.Modules.Compress).compress,
	Decompress = require(script.Parent.Modules.Compress).decompress,
}

export type ServerNetwork = {
	Fire: (remoteName: string, player: Player, ...any) -> nil,
	Invoke: (remoteName: string, player: Player, ...any) -> any,
	FireAll: (remoteName: string, ...any) -> nil,
	FirePlayerFiltered: (remoteName: string, filter: (player: Player) -> boolean, ...any) -> nil,
	OnEvent: (remoteName: string) -> Signal.Signal<...any>,
	OnInvoke: (remoteName: string, callback: (...any) -> any) -> nil,
}

--[[
a: Simple request from client
b: Simple request from server
c: Invoke from client
d: Invoke from server
e: Response from client
f: Response from server

-When a packet c is sent, server sends a packet f
-When a packet d is recieved, client sends a packet e

]]

type Packet = {
	PacketType: string,
	Payload: { any },
}

local queue = {} :: {
	[string]: {
		[number]: { Packet },
	},
}

local signals = {}
local invokeCallbacks = {}
local invokePromises = {} :: {
	[string]: {
		[number]: {
			Resolve: (...any) -> (),
			Reject: (...any) -> (),
		},
	},
}

if not RunService:IsServer() then
	return {} :: ServerNetwork
end

local MainReliable: RemoteEvent = script.Parent.Remotes:WaitForChild("__MainReliable")
local FlushQueueThread: thread

local function CompressTable(table)
	local JSONData = HttpService:JSONEncode(table)
	local sucess, Compressed = pcall(Network.Compress, JSONData)
	if not sucess or Compressed == nil then
		warn("Error while compressing: " .. Compressed)
		return table
	end
	return Compressed
end

local function DecompressTable(compressedString)
	if typeof(compressedString) == "string" then
		local sucess, Decompressed = pcall(Network.Decompress, compressedString)
		if not sucess or Decompressed == nil then
			warn("Couldnt decompress string: " .. compressedString)
			return
		end
		return HttpService:JSONDecode(Decompressed)
	elseif typeof(compressedString) == "table" then
		return compressedString
	else
		error("Invalid type")
	end
end

-- Converts the queue to compress and send all of the packets of all of the remotes of a player
local function ConvertQueueToClientDispatch()
	local newPlayersTable = {}
	for remoteName, data in queue do
		for userID, packets in data do
			if not newPlayersTable[userID] then
				newPlayersTable[userID] = {}
			end
			newPlayersTable[userID][remoteName] = packets
		end
	end
	return newPlayersTable
end

-- Proccess and clean the queue
local function FlushQueue()
	-- Convert the queue to a client queue
	local ClientDispatch = ConvertQueueToClientDispatch()

	-- Compress and send data to each player
	for userID, data in ClientDispatch do
		local player = Players:GetPlayerByUserId(userID)
		if not player then
			continue
		end
		local compressed = CompressTable(data)
		MainReliable:FireClient(player, compressed)
	end

	-- Clean the queue
	queue = {}
end

local function AddToQueue(remoteName: string, packet: Packet, player: Player)
	assert(player and player:IsDescendantOf(Players), "Expected player, got " .. typeof(player))
	assert(typeof(remoteName) == "string", "Expected string, got " .. typeof(remoteName))
	assert(packet.PacketType, "Invalid packet")

	if not queue[remoteName] then
		queue[remoteName] = {}
	end

	-- Init the player table inside of the remote queue
	if not queue[remoteName][player.UserId] then
		queue[remoteName][player.UserId] = {}
	end

	--Insert the packet into the player remote queue
	table.insert(queue[remoteName][player.UserId], packet)

	--Request a flush at the end of the frame if one isn't already requested
	if not FlushQueueThread or coroutine.status(FlushQueueThread) == "dead" then
		FlushQueueThread = task.delay(0, FlushQueue)
	end
end

local function CreatePacket(isRemoteFunction: boolean, isResponse: boolean, ...): Packet
	local Type = (isRemoteFunction and "d" or (isResponse and "f" or "b"))
	local args = { ... }

	return {
		PacketType = Type,
		Payload = args,
	}
end

local function MakeInvokeResponse(remoteName: string, player: Player, ...)
	assert(player and player:IsDescendantOf(Players), "Expected player, got " .. typeof(player))

	local callback = invokeCallbacks[remoteName]
	if not callback then
		return
	end

	local success, result = pcall(function(plr, ...)
		return table.pack(callback(plr, ...))
	end, player, ...)
	local Packet = CreatePacket(false, true, success, table.unpack(result))
	AddToQueue(remoteName, Packet, player)
end

local function OnInvokeResponse(remoteName: string, player: Player, sucess: boolean, ...)
	assert(player and player:IsDescendantOf(Players), "Expected player, got " .. typeof(player))
	local remotePromises = invokePromises[remoteName]
	if typeof(remotePromises) ~= "table" then
		return
	end

	for _, promise in remotePromises do
		if not promise.Resolve or not promise.Reject then
			continue
		end
		if sucess then
			promise.Resolve(player, ...)
		else
			promise.Reject(player, ...)
		end
	end
end

local function DispatchPackets(remoteName: string, packets: { Packet }, player: Player)
	assert(player and player:IsDescendantOf(Players), "Expected player, got " .. typeof(player))
	for _, packet in packets do
		task.spawn(function()
			local argTable = { player, table.unpack(packet.Payload) }
			local signal = signals[remoteName]

			if packet.PacketType == "a" then
				if not signal then
					return
				end
				signal:Fire(table.unpack(argTable))
			elseif packet.PacketType == "c" then
				MakeInvokeResponse(remoteName, table.unpack(argTable))
			elseif packet.PacketType == "e" then
				OnInvokeResponse(remoteName, table.unpack(argTable))
			end
		end)
	end
end

local function ListenToEvent()
	MainReliable.OnServerEvent:Connect(function(player, compressedPackets)
		local RemotePackets = DecompressTable(compressedPackets)
		assert(typeof(RemotePackets) == "table", "Expected a table, got " .. typeof(RemotePackets))

		for remoteName: string, packets: { Packet } in RemotePackets do
			DispatchPackets(remoteName, packets, player)
		end
	end)
end

function Network.Fire(remoteName: string, player: Player, ...)
	local packet = CreatePacket(false, false, ...)
	AddToQueue(remoteName, packet, player)
end

function Network.Invoke(remoteName: string, player: Player, ...)
	local newPromise = Promise.new(function(resolve, reject)
		if not invokePromises[remoteName] then
			invokePromises[remoteName] = {}
		end
		table.insert(invokePromises[remoteName], { Resolve = resolve, Reject = reject })
	end)

	local packet = CreatePacket(true, false, ...)
	AddToQueue(remoteName, packet, player)

	return newPromise
end

function Network.FireAll(remoteName: string, ...)
	assert(typeof(remoteName) == "string", "Expected a string, got " .. typeof(remoteName))
	for _, player in Players:GetPlayers() do
		Network.Fire(remoteName, player, ...)
	end
end

function Network.FirePlayerFiltered(remoteName: string, filter: (player: Player) -> boolean, ...)
	assert(typeof(remoteName) == "string", "Expected a string, got " .. typeof(remoteName))
	assert(typeof(filter) == "function", "Expected a function, got " .. typeof(filter))

	for _, player in Players:GetPlayers() do
		if filter(player) then
			Network.Fire(remoteName, player, ...)
		end
	end
end

function Network.OnEvent(remoteName: string): Signal.Signal<Player | any>
	if typeof(remoteName) ~= "string" then
		warn("Expected string, got " .. typeof(remoteName))
		return Signal.new()
	end
	local signal = signals[remoteName]
	if not signal then
		signal = Signal.new()
		signals[remoteName] = signal
	end

	return signal
end

function Network.OnInvoke(remoteName: string, callback: (...any) -> any)
	assert(typeof(remoteName) == "string", "Expected a string, got " .. typeof(remoteName))
	invokeCallbacks[remoteName] = callback
end

ListenToEvent()

return Network
