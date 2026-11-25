--!strict
-- Synchronous non-yielding listeners: yielding is treated as failure and cancelled.
local M={}
function M.new(data:any,contracts:any)
 local lists={};local serial=0;local sequence=0;local stopped=false;local active={};local failures=0;local self={}
 local function invoke(fn:any,envelope:any)
  local thread=coroutine.create(fn);local ok,value=coroutine.resume(thread,envelope)
  if coroutine.status(thread)~='dead' then coroutine.close(thread);return false,nil end
  return ok,value
 end
 function self:Subscribe(name:string,fn:any,priority:number?)
  assert(not stopped and contracts:Get(name),'unknown/stopped hook');assert(type(fn)=='function','listener required')
  local p=priority or 0;assert(type(p)=='number' and p==p and math.abs(p)<math.huge,'invalid priority')
  serial+=1;local entry={id=serial,fn=fn,priority=p,live=true};local list=lists[name] or {};lists[name]=list
  assert(#list<128,'listener limit');table.insert(list,entry);table.sort(list,function(a,b) return a.priority>b.priority or (a.priority==b.priority and a.id<b.id) end)
  return function() if not entry.live then return end;entry.live=false;local i=table.find(list,entry);if i then table.remove(list,i) end end
 end
 local function deliver(name:string,payload:any,meta:any,kind:string)
  if stopped then return false,'STOPPED' end
  local contract=contracts:Get(name);if not contract or contract.kind~=kind then return false,'UNKNOWN_CONTRACT' end
  if active[name] then return false,'REENTRANT' end
  local ok,copy=data:Validate(contract.schema,payload);if not ok then return false,'INVALID_DATA' end
  if type(meta)~='table' or getmetatable(meta)~=nil or type(meta.tick)~='number' or meta.tick<0 or meta.tick%1~=0 or meta.tick==math.huge or type(meta.traceId)~='string' or #meta.traceId<1 or #meta.traceId>128 then return false,'INVALID_METADATA' end
  -- The envelope shares the payload budget; reject overhead overflow before any delivery.
  local built,envelope=pcall(function() return data:Clone({name=name,version=contract.version,traceId=meta.traceId,tick=meta.tick,sequence=sequence+1,payload=copy},true) end)
  if not built then return false,'ENVELOPE_BUDGET' end
  sequence+=1
  active[name]=true;local denied=false;local list=table.clone(lists[name] or {})
  for _,e in list do if e.live and not stopped then
   local ran,decision=invoke(e.fn,envelope)
   if not ran then failures+=1 end
   if kind=='Will' and (not ran or (decision~=nil and decision~='Allow' and decision~='Abstain') or decision=='Deny') then denied=true end
  end end
  active[name]=nil
  if stopped then return false,'STOPPED' end
  if denied then return false,'DENIED' end
  return true,envelope
 end
 function self:GetContract(name:string) return contracts:Get(name) end
 function self:Publish(name:string,payload:any,meta:any) return deliver(name,payload,meta,'Event') end
 function self:Decide(name:string,payload:any,meta:any) return deliver(name,payload,meta,'Will') end
 function self:Snapshot()
  local counts={};for name,list in pairs(lists) do counts[name]=#list end
  return data:Clone({stopped=stopped,sequence=sequence,listenerErrors=failures,listeners=counts},true)
 end
 function self:Stop() if stopped then return end;stopped=true;for _,list in pairs(lists) do for _,e in list do e.live=false end end;table.clear(lists) end
 return table.freeze(self)
end
return table.freeze(M)