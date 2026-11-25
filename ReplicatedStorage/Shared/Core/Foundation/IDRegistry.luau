--!strict
-- Branch replacement is transactional. aliases may chain; story edges may cycle; parent edges may not.
local M={}
function M.new(data:any)
 local branches={};local current={records={},aliases={},reverse={}};local generation=0;local stopped=false;local self={}
 local function build(candidate:any)
  local records,aliases,reverse={},{},{};local recordCount=0;local aliasCount=0
  local function id(v:any) assert(type(v)=='string' and #v>0 and #v<=128,'invalid ID');return v end
  for branch,config in pairs(candidate) do
   id(branch);for key in pairs(config) do assert(key=='definitions' or key=='aliases','unknown branch field') end
   assert(type(config.definitions)=='table' and type(config.aliases)=='table','branch shape')
   for key,r in pairs(config.definitions) do
    assert(type(key)=='number','definitions array required');id(r.id);assert(not records[r.id] and not aliases[r.id],'duplicate ID')
    for field in pairs(r) do assert(field=='id' or field=='key' or field=='value' or field=='parent' or field=='story','unknown definition field') end
    recordCount+=1;assert(recordCount<=256,'definition limit')
    id(r.key);assert(not reverse[r.key],'duplicate reverse key');reverse[r.key]=r.id;records[r.id]=r
   end
   for alias,target in pairs(config.aliases) do aliasCount+=1;assert(aliasCount<=256,'alias limit');id(alias);id(target);assert(not aliases[alias] and not records[alias],'duplicate alias');aliases[alias]=target end
  end
  for alias in pairs(aliases) do assert(not records[alias],'alias shadows definition') end
  local function resolve(name:any)
   id(name);local seen={};while aliases[name] do assert(not seen[name],'alias cycle');seen[name]=true;name=aliases[name] end
   assert(records[name],'missing reference');return name
  end
  for alias in pairs(aliases) do resolve(alias) end
  for _,r in pairs(records) do
   if r.parent then resolve(r.parent) end
   if r.story then assert(type(r.story)=='table','story array');for key,target in pairs(r.story) do assert(type(key)=='number','story array');resolve(target) end end
  end
  local done={}
  local function walk(name:string,path:any)
   if done[name] then return end;assert(not path[name],'containment cycle');path[name]=true
   local parent=records[name].parent;if parent then walk(resolve(parent),path) end
   path[name]=nil;done[name]=true
  end
  for name in pairs(records) do walk(name,{}) end
  return {records=records,aliases=aliases,reverse=reverse}
 end
 function self:ReloadBranch(name:string,config:any)
  if stopped then return false,'STOPPED' end
  local ok,result=pcall(function()
   assert(type(name)=='string' and #name>0 and #name<=128,'branch name')
   local candidate=table.clone(branches);candidate[name]=data:Clone(config,true)
   -- Bound the entire registry, not merely each replacement.
   candidate=data:Clone(candidate,true);local built=build(candidate)
   return {branches=candidate,built=built}
  end)
  if not ok then return false,'INVALID_CONFIG' end
  branches=result.branches;current=result.built;generation+=1;return true
 end
 function self:Define(name:string,definition:any)
  assert(branches[name]==nil,'branch already defined');return self:ReloadBranch(name,definition)
 end
 function self:Resolve(name:string)
  if stopped then return nil end
  local seen={};while current.aliases[name] do if seen[name] then return nil end;seen[name]=true;name=current.aliases[name] end
  local r=current.records[name];if not r then return nil end;return data:Clone(r,true)
 end
 function self:Reverse(key:string) if stopped then return nil end;return current.reverse[key] end
 function self:Snapshot() return data:Clone({generation=generation,branches=branches,stopped=stopped},true) end
 function self:Stop() stopped=true;branches={};current={records={},aliases={},reverse={}} end
 return table.freeze(self)
end
return table.freeze(M)