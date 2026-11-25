--!strict
local M={}
function M.new(data:any,gateway:any)
 local commands={};local sealed=false;local stopped=false;local self={}
 function self:Register(name:string,apiName:string)
  assert(not stopped and not sealed and type(name)=='string' and #name>0 and #name<=128 and not commands[name],'invalid command')
  assert(type(apiName)=='string' and gateway:Snapshot()[apiName],'unregistered API');commands[name]=apiName
 end
 function self:Seal() sealed=true end
 function self:Dispatch(name:string,args:any,meta:any)
  if stopped then return table.freeze({ok=false,error='STOPPED'}) end
  local api=commands[name];if not api then return table.freeze({ok=false,error='UNKNOWN_COMMAND'}) end
  return gateway:Call(api,args,meta)
 end
 function self:Snapshot() return data:Clone(commands,true) end
 function self:Stop() stopped=true;table.clear(commands) end
 return table.freeze(self)
end
return table.freeze(M)