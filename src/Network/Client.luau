local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Util.Signal)
local Promise = require(script.Parent.Util.Promise)
local Network = {
	Compress = require(script.Parent.Modules.Compress).compress,
	Decompress = require(script.Parent.Modules.Compress).decompress,
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

export type ClientNetwork = {
	Fire: (remoteName: string, ...any) -> nil,
	Invoke: (remoteName: string, ...any) -> any,
	OnEvent: (remoteName: string) -> Signal.Signal<...any>,
	OnInvoke: (remoteName: string, callback: (...any) -> any) -> nil,
}

type Packet = {
	PacketType: string,
	Payload: { any },
}

local queue = {} :: {
	[string]: { Packet },
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

if RunService:IsServer() then
	return {} :: ClientNetwork
end

local MainReliable: RemoteEvent = script.Parent.Remotes:WaitForChild("__MainReliable")
local FlushQueueThread: thread

local function CompressTable(table)
	local JSONData = HttpService:JSONEncode(table)
	local sucess, compressed = pcall(Network.Compress, JSONData)
	if not sucess or compressed == nil then
		warn("Error while compressing: " .. compressed)
		return table
	end
	return compressed
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

-- Proccess and clean the queue
local function FlushQueue()
	local compressed = CompressTable(queue)
	MainReliable:FireServer(compressed)

	queue = {}
end

local function AddToQueue(remoteName: string, packet: Packet)
	assert(typeof(remoteName) == "string", "Expected a string, got " .. typeof(remoteName))
	assert(packet.PacketType, "Invalid packet")

	if not queue[remoteName] then
		queue[remoteName] = {}
	end

	--Insert the packet into the target remote queue
	table.insert(queue[remoteName], packet)

	--Request a flush at the end of the frame if one isn't already requested
	if not FlushQueueThread or coroutine.status(FlushQueueThread) == "dead" then
		FlushQueueThread = task.delay(0, FlushQueue)
	end
end

local function CreatePacket(isRemoteFunction: boolean, isResponse: boolean, ...): Packet
	local Type = (isRemoteFunction and "c" or (isResponse and "e" or "a"))
	local args = { ... }

	return {
		PacketType = Type,
		Payload = args,
	}
end

local function MakeInvokeResponse(remoteName: string, ...)
	local callback = invokeCallbacks[remoteName]
	if not callback then
		return
	end

	local success, result = pcall(function(...)
		return table.pack(callback(...))
	end, ...)
	local Packet = CreatePacket(false, true, success, table.unpack(result))

	AddToQueue(remoteName, Packet)
end

local function OnInvokeResponse(remoteName: string, sucess: boolean, ...)
	local remotePromises = invokePromises[remoteName]
	if typeof(remotePromises) ~= "table" then
		return
	end

	for _, promise in remotePromises do
		if not promise.Resolve or not promise.Reject then
			continue
		end
		if sucess then
			promise.Resolve(...)
		else
			promise.Reject(...)
		end
	end
end

local function DispatchPackets(remoteName: string, packets: { Packet })
	for _, packet in packets do
		task.spawn(function()
			local argTable = packet.Payload
			local signal = signals[remoteName]

			if packet.PacketType == "b" then
				if not signal then
					return
				end
				signal:Fire(table.unpack(argTable))
			elseif packet.PacketType == "d" then
				MakeInvokeResponse(remoteName, table.unpack(argTable))
			elseif packet.PacketType == "f" then
				OnInvokeResponse(remoteName, table.unpack(argTable))
			end
		end)
	end
end

local function ListenToEvent()
	MainReliable.OnClientEvent:Connect(function(compressedPackets)
		local RemotePackets = DecompressTable(compressedPackets)
		assert(typeof(RemotePackets) == "table", "Expected a table, got " .. typeof(RemotePackets))
		for remoteName: string, packets: { Packet } in RemotePackets do
			DispatchPackets(remoteName, packets)
		end
	end)
end

function Network.Fire(remoteName: string, ...)
	local packet = CreatePacket(false, false, ...)
	AddToQueue(remoteName, packet)
end

function Network.Invoke(remoteName: string, ...)
	local newPromise = Promise.new(function(resolve, reject)
		if not invokePromises[remoteName] then
			invokePromises[remoteName] = {}
		end
		table.insert(invokePromises[remoteName], { Resolve = resolve, Reject = reject })
	end)

	local packet = CreatePacket(true, false, ...)
	AddToQueue(remoteName, packet)

	return newPromise
end

function Network.OnEvent(remoteName: string): Signal.Signal<...any>
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
	assert(typeof(remoteName) == "string", "Expected string, got " .. typeof(remoteName))
	invokeCallbacks[remoteName] = callback
end

ListenToEvent()

return Network
