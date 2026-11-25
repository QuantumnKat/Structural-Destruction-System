--!strict

type Handler = (data: any) -> ()

export type Router = {
	On: (action: string, handler: Handler) -> (),
	Connect: () -> (),
	Destroy: () -> (),
}

local ClientRouter = {}

function ClientRouter.new(remote: RemoteEvent): Router
	local handlers: {[string]: Handler} = {}
	local connection: RBXScriptConnection? = nil

	local router: Router = {
		On = function(action: string, handler: Handler)
			handlers[action] = handler
		end,

		Connect = function()
			if connection then
				return
			end
			connection = remote.OnClientEvent:Connect(function(action: string, data: any)
				local handler = handlers[action]
				if handler then
					handler(data)
				end
			end)
		end,

		Destroy = function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			table.clear(handlers)
		end,
	}

	return router
end

return ClientRouter