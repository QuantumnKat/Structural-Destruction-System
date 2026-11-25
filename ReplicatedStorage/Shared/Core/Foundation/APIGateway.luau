--!strict
-- Server composition owns this constructor and principal. Never bind Call to a remote.
local M={}
-- ok describes the handler/output, NOT notification delivery. Never retry a committed
-- handler because event.ok=false. Publish validates the event schema before listeners;
-- dynamic output/event incompatibility is reported separately, without rollback/retry.
export type Result={ok:boolean,value:any?,error:string?,event:{ok:boolean,error:string?}?}
function M.new(data:any,bus:any,principal:any)
 local trusted=data:Clone(principal,true);assert(type(trusted.id)=='string' and type(trusted.scopes)=='table','trusted principal required')
 local scopes={};for _,scope in ipairs(trusted.scopes) do assert(type(scope)=='string','scope string required');scopes[scope]=true end
 local entries={};local busy=false;local stopped=false;local sealed=false;local self={}
 function self:Register(name:string,def:any,handler:any)
  assert(not sealed and not stopped and type(name)=='string' and #name>0 and #name<=128 and not entries[name],'invalid API registration')
  assert(type(handler)=='function' and type(def.scope)=='string' and #def.scope>0,'handler/scope required')
  assert(type(def.version)=='number' and def.version>=1 and def.version%1==0 and def.version<math.huge,'version required')
  for _,key in {'will','did'} do
   assert(def[key]==nil or type(def[key])=='string','invalid hook name')
   if def[key] then
    local contract=bus:GetContract(def[key])
    assert(contract and contract.kind==(if key=='will' then 'Will' else 'Event'),'unknown or wrong-phase hook')
   end
  end
  entries[name]={input=data:Compile(def.input),output=data:Compile(def.output),scope=def.scope,version=def.version,will=def.will,did=def.did,handler=handler}
 end
 function self:Seal() sealed=true end
 function self:Call(name:string,input:any,meta:any):Result
  if stopped then return table.freeze({ok=false,error='STOPPED'}) end
  if busy then return table.freeze({ok=false,error='REENTRANT'}) end
  local e=entries[name];if not e then return table.freeze({ok=false,error='UNKNOWN_API'}) end
  if not scopes[e.scope] then return table.freeze({ok=false,error='FORBIDDEN'}) end
  local valid,copy=data:Validate(e.input,input);if not valid then return table.freeze({ok=false,error='INVALID_INPUT'}) end
  busy=true
  local thread=coroutine.create(function()
   if e.will then local allowed=bus:Decide(e.will,copy,meta);if not allowed then return {ok=false,error='DENIED'} end end
   local value=e.handler(copy) -- trusted principal is deliberately not forwarded
   local outputOK,output=data:Validate(e.output,value)
   if not outputOK then return {ok=false,error='INVALID_OUTPUT'} end
   if e.did then
    -- Handler already ran. A rejected/failed notification must not masquerade as
    -- INTERNAL or silently claim delivery; expose sanitized delivery status.
    local sent,delivered,reason=pcall(function() return bus:Publish(e.did,output,meta) end)
    local status=table.freeze({ok=sent and delivered==true,error=if not sent then 'DELIVERY_FAILED' elseif not delivered then reason else nil})
    return {ok=true,value=output,event=status}
   end
   return {ok=true,value=output}
  end)
  local ran,result=coroutine.resume(thread)
  if coroutine.status(thread)~='dead' then coroutine.close(thread);ran=false end
  busy=false
  if not ran then return table.freeze({ok=false,error='INTERNAL'}) end
  return table.freeze(result)
 end
 function self:Snapshot()
  local result={};for name,e in pairs(entries) do result[name]={version=e.version,scope=e.scope,input=e.input,output=e.output,will=e.will,did=e.did} end
  return data:Clone(result,true)
 end
 function self:Stop() stopped=true;table.clear(entries) end
 return table.freeze(self)
end
return table.freeze(M)