--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Signal = require(ReplicatedStorage.Framework.Network.Util.Signal)
--[[
^P@@@@@@@@@@@@@@&&&&&&&&&&&&J.     7B@@&&&&&&&&&&&&&&&&&&&&&&&B!
  ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J:    .?B@@@@@@@@@@@@@@@@@@@@@@@@@G!
    ^5&@@@@@@@@@@@@@@@@@@@@@@@@&Y:     7B@@@@@@@@@@@@@@@@@@@@@@@@@B7.
      :Y&@@@@@@@@@@@@@@@@@@@@@@@@&5^     !G@@@@@@@@@@@@@@@@@@@@@@@@@#?.
        :J#@@@@@@@@@@@@@@@@@@@@@@@@@P~     ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J.
          .?#@@@@@@@@@@@@@@@@@@@@@@@@@P~     ^P@@@@@@@@@@@@@@@@@@@@@@@@@&J:
            .7B@@@@@@@@@@@@@@@@@@@@@@@@@G!     ^5&@@@@@@@@@@@@@@@@@@@@@@@@&Y:
               7B@@@@@@@@@@@@@@@@@@@@@@@@@B7     :Y&@@@@@@@@@@@@@@@@@@@@@@@@&5^
                 !G@@@@@@@@@@@@@@@@@@@@@@@@@B7.    :J#@@@@@@@@@@@@@@@@@@@@@@@@@P~
                   ~P@@@@@@@@@@@@@@@@@@@@@@@@@#?.    .?#@@@@@@@@@@@@@@@@@@@@@@@@@P~
                     ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J:    .7B@@@@@@@@@@@@@@@@@@@@@@@@@G!
                       ^5&@@@@@@@@@@@@@@@@@@@@@@@@&Y^     7B@@@@@@@@@@@@@@@@@@@@@@@@@B7
                         :Y&@@@@@@@@@@@@@@@@@@@@@@@@@5^     !G@@@@@@@@@@@@@@@@@@@@@@@@@B?.
                           :J&@@@@@@@@@@@@@@@@@@@@@@@@@P~     ~P@@@@@@@@@@@@@@@@@@@@@@@@@#?.
                             .J#@@@@@@@@@@@@@@@@@@@@@@@@@G!     ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J:
                               .?B@@@@@@@@@@@@@@@@@@@@@@@@@G!     ^5&@@@@@@@@@@@@@@@@@@@@@@@@&Y:
                                  7B@@@@@@@@@@@@@@@@@@@@@@@@@B7.    :Y&@@@@@@@@@@@@@@@@@@@@@@@@&5^
                                    !G@@@@@@@@@@@@@@@@@@@@@@@@@#J.    :J&@@@@@@@@@@@@@@@@@@@@@@@@@P~
                                    ~G@@@@@@@@@@@@@@@@@@@@@@@@@&Y.    :J&@@@@@@@@@@@@@@@@@@@@@@@@@G!
                                  !G@@@@@@@@@@@@@@@@@@@@@@@@@#?.    ^Y&@@@@@@@@@@@@@@@@@@@@@@@@@P~
                               .7B@@@@@@@@@@@@@@@@@@@@@@@@@B7.    ^5&@@@@@@@@@@@@@@@@@@@@@@@@@5^
                             .?#@@@@@@@@@@@@@@@@@@@@@@@@@B!     ~P@@@@@@@@@@@@@@@@@@@@@@@@@&5^
                           :J#@@@@@@@@@@@@@@@@@@@@@@@@@G!     !G@@@@@@@@@@@@@@@@@@@@@@@@@&Y:
                         :Y&@@@@@@@@@@@@@@@@@@@@@@@@@P~     !G@@@@@@@@@@@@@@@@@@@@@@@@@#J:
                       ^5&@@@@@@@@@@@@@@@@@@@@@@@@&5^    .7B@@@@@@@@@@@@@@@@@@@@@@@@@B?.
                     ^5@@@@@@@@@@@@@@@@@@@@@@@@@&Y:    .?#@@@@@@@@@@@@@@@@@@@@@@@@@G!
                   ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J:    :J#@@@@@@@@@@@@@@@@@@@@@@@@@P~
                 !G@@@@@@@@@@@@@@@@@@@@@@@@@#?.    :Y&@@@@@@@@@@@@@@@@@@@@@@@@@5^
               7B@@@@@@@@@@@@@@@@@@@@@@@@@B7.    ^5&@@@@@@@@@@@@@@@@@@@@@@@@&5^
            .?B@@@@@@@@@@@@@@@@@@@@@@@@@G!     ^5@@@@@@@@@@@@@@@@@@@@@@@@@&Y:
          .?#@@@@@@@@@@@@@@@@@@@@@@@@@G~     ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J:
        :J&@@@@@@@@@@@@@@@@@@@@@@@@@P~     !G@@@@@@@@@@@@@@@@@@@@@@@@@#?.
      :Y&@@@@@@@@@@@@@@@@@@@@@@@@&5^     7B@@@@@@@@@@@@@@@@@@@@@@@@@B7.
    ^5&@@@@@@@@@@@@@@@@@@@@@@@@&Y:    .7B@@@@@@@@@@@@@@@@@@@@@@@@@B!
  ~P@@@@@@@@@@@@@@@@@@@@@@@@@#J:    .?#@@@@@@@@@@@@@@@@@@@@@@@@@G!
^P@@@@@@@@@@@@@@@@@@@@@@@@@&J.     ?#@@&&&&&&&&&&&&&&&&&&&&&&&G~

Dsh Framework @ 2024-2025
Made by OverDsh
]]

local DIR = script.Parent
local Util = DIR.Util

local Framework = {
	Network = require(DIR.Network.Server),
	State = require(DIR.State.Server),
	Util = {
		Promise = require(Util.Promise),
		Signal = require(Util.Signal),
	},
	IsServerLoaded = false,
	ServerLoadedSignal = Signal.new(),
}

if not RunService:IsServer() then
	script:Destroy()
	return Framework
end

local started = false
type Service = {
	Init: ((...any) -> nil)?,
	Start: ((...any) -> nil)?,
}
local services = {} :: { [string]: Service }

function Framework.LoadService(module: ModuleScript)
	assert(not started, "Couldn't register service: Framework running")
	assert(module:IsA("ModuleScript"), "Couldn't register service: provided controller is not a module")
	assert(not services[module.Name], `Couldn't register service: service already registered with name: {module.Name}`)

	local require = require
	services[module.Name] = require(module)
end

function Framework.AddServiceFolder(dir: Instance, loadDescendants: boolean?)
	assert(not started, "Couldn't register dir: Framework running")
	assert(dir.GetChildren, "Couldn't register dir: can't loop through dir")

	for _, module: Instance in dir:GetChildren() do
		if module:IsA("ModuleScript") then
			Framework.LoadService(module)
		elseif loadDescendants and module:IsA("Folder") then
			Framework.AddServiceFolder(module, loadDescendants)
		end
	end
end

function Framework.GetService(name: string)
	assert(started, "Couldn't retrieve service, please run Framework first")
	assert(typeof(name) == "string", "Provided name is not a string, please provide a string")
	assert(services[name], `Service "{name}" is not registered`)

	return services[name]
end

function Framework.Start()
	if started then
		return Framework.Util.Promise.reject("Framework already started")
	end
	local promises = {}

	return Framework.Util.Promise.new(function(resolve, reject)
		for _, service in services do
			if typeof(service["Init"]) == "function" then
				table.insert(promises, Framework.Util.Promise.try(service.Init))
			end
		end
		for _, service in services do
			if typeof(service["Start"]) == "function" then
				table.insert(promises, Framework.Util.Promise.try(service.Start))
			end
		end
		Framework.Util.Promise
			.all(promises)
			:andThen(function()
				resolve()
				started = true
				Framework.IsServerLoaded = true
				Framework.ServerLoadedSignal:Fire()
			end)
			:catch(reject)
	end)
end

return Framework
