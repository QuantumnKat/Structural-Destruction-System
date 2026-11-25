--!strict
-- One-shot lifecycle. Failed Start includes the partially started entry in rollback.
local M={}
function M.new(entries:any)
 assert(type(entries)=='table' and getmetatable(entries)==nil and #entries<=128,'invalid manifest')
 local byName={};local order={};local running={};local state='new';local stopErrors=0;local self={}
 local entryCount=0
 for key in pairs(entries) do entryCount+=1;assert(type(key)=='number' and key%1==0 and key>=1 and key<=#entries,'manifest must be dense array') end
 assert(entryCount==#entries,'manifest must be dense array')
 for _,e in ipairs(entries) do
  assert(type(e)=='table' and getmetatable(e)==nil and type(e.name)=='string' and #e.name>0 and #e.name<=128 and not byName[e.name] and type(e.Start)=='function' and type(e.Stop)=='function','invalid entry')
  local source=e.dependencies or {};assert(type(source)=='table' and getmetatable(source)==nil,'invalid dependencies')
  local deps=table.clone(source);assert(#deps<=128,'dependency limit')
  local depCount=0
  for key,dep in pairs(deps) do depCount+=1;assert(type(key)=='number' and key%1==0 and key>=1 and key<=#deps and type(dep)=='string','dense dependency array required') end
  assert(depCount==#deps,'dense dependency array required')
  byName[e.name]={name=e.name,Start=e.Start,Stop=e.Stop,dependencies=deps}
 end
 local visiting,done={},{}
 local function visit(name:string)
  assert(byName[name],'missing dependency');if done[name] then return end;assert(not visiting[name],'dependency cycle');visiting[name]=true
  for _,dep in ipairs(byName[name].dependencies) do visit(dep) end
  visiting[name]=nil;done[name]=true;table.insert(order,byName[name])
 end
 local names={};for name in pairs(byName) do table.insert(names,name) end;table.sort(names);for _,name in names do visit(name) end
 local function call(fn:any)
  local thread=coroutine.create(fn);local ok,value=coroutine.resume(thread)
  if coroutine.status(thread)~='dead' then coroutine.close(thread);return false end
  return ok and value~=false
 end
 local function unwind()
  for i=#running,1,-1 do local entry=running[i];running[i]=nil;if not call(entry.Stop) then stopErrors+=1 end end
 end
 function self:Start()
  if state=='running' then return true end;if state~='new' then return false,'TERMINATED' end;state='starting'
  for _,entry in order do
   table.insert(running,entry)
   if not call(entry.Start) then state='failed';unwind();return false,'START_FAILED' end
  end
  state='running';return true
 end
 function self:Stop() if state=='stopped' then return end;assert(state~='starting','cannot stop during Start');state='stopped';unwind() end
 function self:Snapshot() local namesOut={};for _,e in order do table.insert(namesOut,e.name) end;return table.freeze({state=state,order=table.freeze(namesOut),stopErrors=stopErrors}) end
 return table.freeze(self)
end
return table.freeze(M)