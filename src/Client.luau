--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

Dsh Framewok @ 2024-2025
Made by OverDsh
]]

local DIR = script.Parent
local Util = DIR.Util

local Framework = {
	LocalPlayer = Players.LocalPlayer,
	Network = require(DIR.Network.Client),
	State = require(DIR.State.Client),
	Util = {
		Promise = require(Util.Promise),
		Signal = require(Util.Signal),
	},
}

if not RunService:IsClient() then
	script:Destroy()
	return Framework
end
if script.Parent:FindFirstChild("Server") then
	script.Parent:FindFirstChild("Server"):Destroy()
end

local started = false

type Controller = {
	Init: ((...any) -> ...unknown)?,
	Start: ((...any) -> ...unknown)?,
}

local controllers = {} :: { [string]: Controller }

function Framework.LoadController(module: ModuleScript?)
	assert(not started, "Couldn't register controller: Framework running")
	assert(
		module ~= nil and module:IsA("ModuleScript"),
		"Couldn't register controller: provided controller is not a module"
	)
	assert(
		not controllers[module.Name],
		`Couldn't register controller: controller already registered with name: {module.Name}`
	)

	local require = require
	controllers[module.Name] = require(module)
end

function Framework.AddControllerFolder(dir: Instance, loadDescendants: boolean?)
	assert(not started, "Couldn't register dir: Framework running")
	assert(dir.GetChildren, "Couldn't register dir: can't loop through dir")

	for _, module: Instance in dir:GetChildren() do
		if module:IsA("ModuleScript") then
			Framework.LoadController(module)
		elseif loadDescendants and module:IsA("Folder") then
			Framework.AddControllerFolder(module, loadDescendants)
		end
	end
end

function Framework.GetController(name: string)
	assert(started, "Couldn't retrieve controller, please run Framework first")
	assert(typeof(name) == "string", "Provided name is not a string, please provide a string")
	assert(controllers[name], `Controller "{name}" is not registered`)

	return controllers[name]
end

function Framework.Start()
	if started then
		return Framework.Util.Promise.reject("Framework already started")
	end
	started = true
	local promises = {}

	return Framework.Util.Promise.new(function(resolve)
		for _, controller in controllers do
			if typeof(controller["Init"]) == "function" then
				table.insert(promises, Framework.Util.Promise.try(controller.Init))
			end
		end
		for _, controller in controllers do
			if typeof(controller["Start"]) == "function" then
				table.insert(promises, Framework.Util.Promise.try(controller.Start))
			end
		end
		resolve(Framework.Util.Promise.all(promises))
	end)
end

return Framework
