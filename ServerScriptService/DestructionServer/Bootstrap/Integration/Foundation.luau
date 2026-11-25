--!strict
-- Server-only composition. Destruction stays in bootstrap; this exposes hookable APIs.
local M={}
function M.new(deps:any)
 local F=deps.Shared.Core.Foundation
 local data=require(F.ContractData).new()
 local contracts=require(F.HookDataContracts).new(data)
 local empty={kind='object',fields={}}
 local str={kind='string',min=1,max=128}
 contracts:Define('Foundation.ReadWill',1,empty,'Will')
 contracts:Define('Foundation.ReadDid',1,{kind='any'},'Event')
 contracts:Define('Destruction.DidRebuild',1,{kind='object',fields={ok={kind='boolean'}}},'Event')
 contracts:Seal()
 local bus=require(F.EventBus).new(data,contracts)
 local ids=require(F.IDRegistry).new(data)
 local api=require(F.APIGateway).new(data,bus,{id='ServerBootstrap',scopes={'foundation.read','destruction.read'}})
 local commands=require(F.CommandBus).new(data,api)
 local function register(name,scope,input,output,fn,hooks)
  api:Register(name,{version=1,scope=scope,input=input,output=output,will=if hooks then 'Foundation.ReadWill' else nil,did=if hooks then 'Foundation.ReadDid' else nil},fn)
 end
 register('IDRegistryAPI.Resolve','foundation.read',{kind='object',fields={id=str}},{kind='object',fields={found={kind='boolean'},definition={kind='any',optional=true}}},function(args)
  local definition=ids:Resolve(args.id);return {found=definition~=nil,definition=definition}
 end)
 register('IDRegistryAPI.Introspect','foundation.read',empty,{kind='any'},function() return ids:Snapshot() end,true)
 register('EventBus.Introspect','foundation.read',empty,{kind='any'},function() return bus:Snapshot() end,true)
 register('DestructionAPI.Health','destruction.read',empty,{kind='object',fields={available={kind='boolean'}}},function()
  return {available=true}
 end,true)
 api:Seal();commands:Register('destruction.health','DestructionAPI.Health');commands:Register('ids.inspect','IDRegistryAPI.Introspect');commands:Seal()
 local lifecycle=require(F.ManifestLifecycle).new({
  {name='Contracts',Start=function() return true end,Stop=function() bus:Stop() end},
  {name='IDs',dependencies={'Contracts'},Start=function()
   return ids:Define('foundation',{definitions={{id='system.destruction',key='DestructionAPI',value={owner='ServerBootstrap'}}},aliases={['legacy.destruction']='system.destruction'}})
  end,Stop=function() ids:Stop() end},
  {name='Gateway',dependencies={'IDs'},Start=function() return true end,Stop=function() commands:Stop();api:Stop() end},
 })
 local self={API=api,Commands=commands,Events=bus}
 function self:Start() return lifecycle:Start() end
 function self:Stop()
  lifecycle:Stop()
  -- Constructors are active before Start; lifecycle only owns entries it started.
  -- These services have idempotent Stop, including after startup rollback.
  commands:Stop();api:Stop();ids:Stop();bus:Stop()
 end
 function self:Snapshot() return data:Clone({lifecycle=lifecycle:Snapshot(),apis=api:Snapshot(),commands=commands:Snapshot(),contracts=contracts:Snapshot()},true) end
 return table.freeze(self)
end
return table.freeze(M)
