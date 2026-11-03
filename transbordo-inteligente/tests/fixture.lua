-- Contratos simulados da engine. Nao simula fisica, colisao ou fluxo real de graos.
-- O log real do FS25 confirma que esta biblioteca nao esta exposta ao mod.
coroutine=nil
FillType = {UNKNOWN=0}
Dischargeable = {DISCHARGE_STATE_OFF=0, DISCHARGE_STATE_OBJECT=2, DISCHARGE_STATE_GROUND=1}
Drivable = {CRUISECONTROL_STATE_OFF=0}
Motorized, Wheels = {}, {}
Logging = {info=function() end}
function entityExists(node) return node ~= nil and not node.deleted end

function node(x,z,parent,angle)
    return {x=x or 0,z=z or 0,parent=parent,angle=angle or 0}
end
local function pose(n)
    if n.parent == nil then return n.x, n.z, n.angle end
    local x,z,a = pose(n.parent)
    return x+math.cos(a)*n.x+math.sin(a)*n.z, z-math.sin(a)*n.x+math.cos(a)*n.z, a+n.angle
end
function getWorldTranslation(n)
    local x,z = pose(n)
    return x,0,z
end
function localDirectionToWorld(n,x,y,z)
    local _,_,a = pose(n)
    return math.cos(a)*x+math.sin(a)*z, y, -math.sin(a)*x+math.cos(a)*z
end
function localToWorld(n,x,y,z)
    local px,pz = pose(n)
    local dx,_,dz = localDirectionToWorld(n,x,y,z)
    return px+dx,y,pz+dz
end
function worldToLocal(n,x,y,z)
    local px,pz,a = pose(n)
    return math.cos(a)*(x-px)-math.sin(a)*(z-pz),y,math.sin(a)*(x-px)+math.cos(a)*(z-pz)
end
function localToLocal(from,to,x,y,z)
    return worldToLocal(to,localToWorld(from,x,y,z))
end
AIVehicleUtil = {driveToPoint=function(v,dt,acceleration,allowed,forwards,x,z,speed)
    v.command={dt=dt,allowed=allowed,forwards=forwards,x=x,z=z,speed=speed}
end}

function vehicle(x,z,farm)
    local v={rootNode=node(x,z),farm=farm or 1,isServer=true,isClient=true,
        spec_fillUnit={fillUnits={}},units={},attached={},speed=0,motor=true}
    function v:getOwnerFarmId() return self.farm end
    function v:getAttachedImplements() return self.attached end
    function v:getRootVehicle() return self.rootVehicle or self end
    function v:getAIDirectionNode() return self.rootNode end
    function v:getAISteeringNode() return self.rootNode end
    function v:getFillUnitCapacity(i) return self.units[i] and self.units[i].capacity or 0 end
    function v:getFillUnitFillLevel(i) return self.units[i] and self.units[i].level or 0 end
    function v:getFillUnitFillType(i) return self.units[i] and self.units[i].kind or 0 end
    function v:getFillUnitFreeCapacity(i) return self:getFillUnitCapacity(i)-self:getFillUnitFillLevel(i) end
    function v:getFillUnitSupportsFillType(i,kind) return self.units[i] ~= nil and self.units[i].supported[kind] == true end
    function v:getFillUnitAllowsFillType(i,kind) return self:getFillUnitFillLevel(i) == 0 or self:getFillUnitFillType(i) == kind end
    function v:getFillUnitExactFillRootNode(i) return self.units[i] and self.units[i].fillRoot end
    function v:getLastSpeed() return self.speed end
    function v:getIsAIActive() return self.nativeAI or false end
    function v:getIsMotorStarted() return self.motor end
    function v:startMotor() self.motor=true end
    function v:raiseActive() self.raised=true end
    function v:setCruiseControlState(state) self.cruise=state end
    function v:aiPrepareLoading(i) self.prepared=i end
    return v
end
function unit(v,i,capacity,level,kind,offset)
    v.units[i]={capacity=capacity,level=level,kind=kind,supported={[1]=true,[2]=true},
        fillRoot=node(0,offset or 0,v.rootNode)}
    v.spec_fillUnit.fillUnits[i]={}
end
function discharger(v,index,pipeX,pipeZ)
    v.spec_pipe={currentState=2,targetState=2,automaticDischarge=true}
    v.spec_dischargeable={}
    v.dischargeNode={node=node(pipeX,pipeZ,v.rootNode),fillUnitIndex=index}
    function v:getCurrentDischargeNode() return self.dischargeNode end
    function v:getIsPipeStateChangeAllowed() return true end
    function v:setPipeState(state) self.spec_pipe.currentState=state; self.spec_pipe.targetState=state end
    function v:setDischargeState(state)
        assert(type(state) == 'number' and state ~= Dischargeable.DISCHARGE_STATE_GROUND)
        self.dischargeState=state
    end
    function v:getDischargeTargetObject() return self.raycastObject,self.raycastIndex end
    function v:getCanDischargeToObject() return self.canDischarge == true end
    function v:getIsTurnedOn() return self.turnedOn or false end
    function v:setIsTurnedOn(on) self.turnedOn=on end
end
function makeCombine(x,z,level,farm)
    local v=vehicle(x,z,farm)
    v.spec_combine={}
    unit(v,1,500,500,99) -- combustivel: nao deve entrar no calculo dos graos
    unit(v,2,10000,level,1)
    discharger(v,2,-6,0)
    return v
end
function makeTrailer(x,z,level,kind,farm)
    local v=vehicle(x,z,farm)
    v.spec_trailer={}
    unit(v,3,30000,level or 0,kind or 0)
    return v
end
tractor=vehicle(0,0)
unit(tractor,1,500,500,99)
wagon=vehicle(0,-8)
wagon.rootNode.parent=tractor.rootNode
wagon.rootVehicle=tractor
unit(wagon,2,20000,0,0)
discharger(wagon,2,-5,0)
tractor.attached={{object=wagon}}
combine=makeCombine(0,100,6000)
trailer=makeTrailer(40,0)
g_currentMission={vehicleSystem={vehicles={tractor,combine,trailer}},missionDynamicInfo={isMultiplayer=false}}
g_currentMission.terrainRootNode=node()
g_currentMission.nodeToObject={}
-- A direcao direta nao depende de sensores nem de descritores de cultura.
g_currentMission.fruits=nil
g_fruitTypeManager,CollisionFlag=nil,nil
DensityMapModifier,DensityMapFilter,DensityValueCompareType,DensityCoordType=nil,nil,nil,nil
overlapBox=nil
g_farmlandManager=nil
TI=TransbordoInteligente
E=TI.ESTADOS
TI.onLoad(tractor)
function activate(v) TI.actionEventToggleTransbordo(v or tractor,nil,1) end
function tick(ms,v) TI.onUpdate(v or tractor,ms or 1000) end
function state(v) return (v or tractor).spec_transbordoInteligente.estadoAtual end
function teleport(x,z,v)
    local n=(v or tractor).rootNode
    n.x,n.z,n.angle=x,z,0
end
function selectTrailer()
    TI.mudarEstado(tractor,E.BUSCANDO_CARRETA)
    tick()
    assert(state() == E.APROXIMANDO_CARRETA)
end
function permitUnload(target,index)
    wagon.raycastObject=target or trailer
    wagon.raycastIndex=index or 3
    wagon.canDischarge=true
end
function makeField(x1,z1,x2,z2)
    local polygon={getVerticesList=function() return {x1,z1,x2,z1,x2,z2,x1,z2} end}
    return {getDensityMapPolygon=function() return polygon end}
end
