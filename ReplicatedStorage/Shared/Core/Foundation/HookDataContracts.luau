--!strict
local M={}
function M.new(data:any)
 local definitions={};local sealed=false;local self={}
 function self:Define(name:string,version:number,schema:any,kind:string)
  assert(not sealed and type(name)=='string' and #name>0 and #name<=128 and not definitions[name],'invalid or duplicate contract')
  assert(type(version)=='number' and version>=1 and version%1==0,'invalid version');assert(kind=='Event' or kind=='Will','invalid hook kind')
  definitions[name]=table.freeze({name=name,version=version,schema=data:Compile(schema),kind=kind})
 end
 function self:Seal() sealed=true end
 function self:Get(name:string) return definitions[name] end
 function self:Snapshot() return data:Clone(definitions,true) end
 return table.freeze(self)
end
return table.freeze(M)