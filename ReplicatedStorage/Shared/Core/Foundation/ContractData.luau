--!strict
-- Plain JSON-shaped data only. Every traversal is bounded, including schema definitions.
local M={}
export type Schema={kind:string, fields:{[string]:Schema}?, item:Schema?, optional:boolean?, max:number?, min:number?}
function M.new(options:any?)
 local opts=options or {};local depth=opts.maxDepth or 16;local nodes=opts.maxNodes or 4096;local bytes=opts.maxBytes or 65536
 for _,v in {depth,nodes,bytes} do assert(type(v)=='number' and v%1==0 and v>=1 and v<=1000000,'invalid limit') end
 assert(depth<=64,'depth limit too large')
 local self={}
 function self:Clone(value:any,freeze:boolean?)
  local count,total=0,0;local active={}
  local function visit(v:any,d:number):any
   count+=1;assert(count<=nodes and d<=depth,'data budget exceeded')
   local t=type(v)
   if t=='nil' or t=='boolean' then return v end
   if t=='number' then assert(v==v and math.abs(v)<math.huge,'nonfinite number');return v end
   if t=='string' then total+=#v;assert(total<=bytes,'string budget exceeded');return v end
   assert(t=='table' and getmetatable(v)==nil,'plain serializable data required');assert(not active[v],'cycle');active[v]=true
   local out={};local numeric,strings,n,maxIndex=0,0,0,0
   for k,x in pairs(v) do
    n+=1;assert(n<=nodes,'entry budget exceeded')
    if type(k)=='number' then assert(k>=1 and k%1==0 and k<=nodes,'invalid array index');numeric+=1;maxIndex=math.max(maxIndex,k)
    else assert(type(k)=='string','invalid object key');strings+=1;total+=#k;assert(total<=bytes,'key budget exceeded') end
    out[k]=visit(x,d+1)
   end
   assert(numeric==0 or (strings==0 and maxIndex==numeric),'mixed or sparse table');active[v]=nil
   return if freeze then table.freeze(out) else out
  end
  return visit(value,0)
 end
 function self:Compile(def:any)
  local schema=self:Clone(def,true)
  local function check(s:any)
   assert(type(s)=='table','invalid schema');local k=s.kind
   assert(k=='any' or k=='string' or k=='number' or k=='boolean' or k=='object' or k=='array','unknown schema kind')
   for key in pairs(s) do assert(key=='kind' or key=='fields' or key=='item' or key=='optional' or key=='max' or key=='min','unknown schema property') end
   assert(s.optional==nil or type(s.optional)=='boolean','invalid optional')
   for _,key in {'min','max'} do if s[key]~=nil then assert(type(s[key])=='number','invalid bound') end end
   assert(not s.min or not s.max or s.min<=s.max,'inverted bounds')
   if k=='object' then assert(type(s.fields)=='table','fields required');for name,field in pairs(s.fields) do assert(type(name)=='string','field name');check(field) end else assert(s.fields==nil,'unexpected fields') end
   if k=='array' then assert(type(s.item)=='table','item required');check(s.item) else assert(s.item==nil,'unexpected item') end
  end
  check(schema);return schema
 end
 function self:Validate(schema:any,value:any)
  local ok,result=pcall(function()
   local copy=self:Clone(value,true)
   local function match(s:any,v:any)
    if v==nil then assert(s.optional,'required value');return end
    local k=s.kind
    if k=='any' then return end
    if k=='object' then
     assert(type(v)=='table','object expected');for key,x in pairs(v) do assert(type(key)=='string' and s.fields[key],'unknown field');match(s.fields[key],x) end
     for key,field in pairs(s.fields) do if v[key]==nil then match(field,nil) end end
    elseif k=='array' then
     assert(type(v)=='table','array expected');for key,x in pairs(v) do assert(type(key)=='number','array expected');match(s.item,x) end
     assert(not s.max or #v<=s.max,'array too long');assert(not s.min or #v>=s.min,'array too short')
    else
     assert(type(v)==k,'type mismatch');local n=if k=='string' then #v elseif k=='number' then v else nil
     if n then assert(not s.max or n<=s.max,'above bound');assert(not s.min or n>=s.min,'below bound') end
    end
   end
   match(schema,copy);return copy
  end)
  if not ok then return false,'INVALID_DATA' end
  return true,result
 end
 return table.freeze(self)
end
return table.freeze(M)