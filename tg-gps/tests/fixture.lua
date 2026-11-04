-- Minimal GIANTS contracts for offline integration tests, not a game emulator.
nodes, loadedModels, xmlFiles, assetFiles = {}, {}, {}, {}
function makeNode(name, parent, x, y, z)
    local n = {name=name, children={}, x=x or 0, y=y or 0, z=z or 0,
        rx=0, ry=0, rz=0, sx=1, sy=1, sz=1, visible=true}
    nodes[#nodes+1]=n
    if parent ~= nil then link(parent,n) end
    return n
end
function link(parent,node)
    if node.parent then
        for i,n in ipairs(node.parent.children) do if n==node then table.remove(node.parent.children,i); break end end
    end
    node.parent=parent; parent.children[#parent.children+1]=node
end
function getName(n) return n.name end
function getParent(n) return n.parent or 0 end
function getNumOfChildren(n) return #n.children end
function getChildAt(n,i) return n.children[i+1] end
function getTranslation(n) return n.x,n.y,n.z end
function setTranslation(n,x,y,z) n.x,n.y,n.z=x,y,z end
function setRotation(n,x,y,z) n.rx,n.ry,n.rz=x,y,z end
function setScale(n,x,y,z) n.sx,n.sy,n.sz=x,y,z end
function setVisibility(n,v) n.visible=v end
function createTransformGroup(name) return makeNode(name) end
function clone(n) return makeNode(n.name) end
function delete(n)
    if n.xml then n.closed=true; return end
    if n.deleted then return end
    local children={unpack(n.children)}
    for _,c in ipairs(children) do delete(c) end
    if n.parent then
        for i,c in ipairs(n.parent.children) do if c==n then table.remove(n.parent.children,i);break end end
    end
    n.deleted=true; n.children={}; n.parent=nil
end
function getWorldTranslation(n)
    if n.parent then
        local px,py,pz=getWorldTranslation(n.parent)
        local fx,_,fz=localDirectionToWorld(n.parent,0,0,1)
        return px+n.x*fz+n.z*fx, py+n.y, pz-n.x*fx+n.z*fz
    end
    return n.x,n.y,n.z
end
function localDirectionToWorld(n,x,y,z)
    local yaw=n.ry or 0
    local p=n.parent
    while p do yaw=yaw+(p.ry or 0);p=p.parent end
    return x*math.cos(yaw)+z*math.sin(yaw), y, z*math.cos(yaw)-x*math.sin(yaw)
end
function getUserProfileAppPath() return '/test-profile/' end
function createFolder() end
function fileExists(path) return xmlFiles[path]~=nil or assetFiles[path]==true end
local function duplicate(v)
    if type(v)~='table' then return v end
    local r={} for k,x in pairs(v) do r[k]=duplicate(x) end return r
end
function createXMLFile(name,path,root) return {xml=true,path=path,values={}} end
function loadXMLFile(name,path)
    if not xmlFiles[path] then return 0 end
    return {xml=true,path=path,values=duplicate(xmlFiles[path])}
end
function saveXMLFile(xml) xmlFiles[xml.path]=duplicate(xml.values); return true end
function setXMLFloat(xml,key,v) xml.values[key]=v end
setXMLInt,setXMLString=setXMLFloat,setXMLFloat
function getXMLFloat(xml,key) return xml.values[key] end
getXMLInt,getXMLString=getXMLFloat,getXMLFloat
Logging={info=function() end, warning=function() end}
Utils={prependedFunction=function(original,before) return function(...) before(...);return original(...) end end}
TypeManager={finalizeTypes=function() end}
SpecializationUtil={}
g_modIsLoaded={}
listeners={}
function addModEventListener(value) listeners[#listeners+1]=value end
WorkAreaType={AUXILIARY=99}
g_screenWidth,g_screenHeight=1920,1080
Input={KEY_left=1,KEY_right=2,KEY_up=3,KEY_down=4,KEY_pageup=5,KEY_pagedown=6,
    KEY_q=7,KEY_e=8,KEY_r=9,KEY_f=10,KEY_plus=11,KEY_minus=12,
    KEY_home=13,KEY_return=14,KEY_esc=15}
g_gui={getIsGuiVisible=function() return false end}
tractor={rootNode=makeNode('tractor'),tgGpsSupported=true,configFileName='tractor.xml',
    spec_enterable={cameras={}},components={},motorOn=true,lastSpeedReal=0}
tractor.components={{node=tractor.rootNode}}
function tractor:getIsMotorStarted() return self.motorOn end
function tractor:getIsActiveForInput() return true end
function tractor:getAttachedImplements() return self.attached or {} end
function tractor:getLastSpeed() return self.speed or 0 end
tool={rootNode=makeNode('implement',nil,0,0,-8), active=true}
function tool:getIsWorkAreaActive() return self.active end
function tool:getAttachedImplements() return self.attached or {} end
tool.area={start=makeNode('start',tool.rootNode,-3,0,-1),
    width=makeNode('width',tool.rootNode,3,0,-1),height=makeNode('height',tool.rootNode,-3,0,1)}
tool.spec_workArea={workAreas={tool.area}}
tractor.attached={{object=tool}}
g_currentMission={controlledVehicle=tractor,missionInfo={mapId='test'},environment={dayTime=0}}
g_localPlayer={getCurrentVehicle=function() return g_currentMission.controlledVehicle end}
function move(x,z)
    tractor.rootNode.x,tractor.rootNode.z=x,z
    tool.rootNode.x,tool.rootNode.z=x,z-8
end
function route(owner)
    owner.width=6;owner.mode='straight';owner.currentLane=0;owner.currentSection=1
    owner.sourcePoints={{x=0,z=0},{x=0,z=100}}
    owner.basePath=owner.sourcePoints
    owner.guidanceLines={[0]=owner.sourcePoints}
    owner.guidanceSections={}
    owner.fieldBoundary={{x=-30,z=-30},{x=30,z=-30},{x=30,z=120},{x=-30,z=120}}
end

function metadata()
    assetFiles['/maps/native_pda.dds']=true
    local farms={[1]={name='Fazenda Vidal'},[2]={name='Proprietario do campo'}}
    g_farmManager={getFarmById=function(_,id) return farms[id] end}
    function tractor:getOwnerFarmId() return 1 end
    local field={name='Talhao 3',getId=function() return 3 end,
        getDensityMapPolygon=function() return {getVerticesList=function() return {-30,-30,30,-30,30,120,-30,120} end} end}
    local land={id=3,farmId=2,getField=function() return field end}
    g_farmlandManager={getFarmlandAtWorldPosition=function() return land end}
    g_currentMission.hud={ingameMap={worldSizeX=2048,worldSizeZ=2048,
        worldCenterOffsetX=1024,worldCenterOffsetZ=1024,mapOverlay={filename='/maps/native_pda.dds'}}}
    tractor.name='Trator de teste';tool.name='Semeadora de teste'
    TGGPS.monitorContext=nil
end

function workTool(name,width)
    local object={rootNode=makeNode(name),configFileName='implements/'..name..'.xml',spec_sowingMachine={},active=true}
    local area={start=makeNode('start',object.rootNode,-width/2,0,-1),
        width=makeNode('width',object.rootNode,width/2,0,-1),height=makeNode('height',object.rootNode,-width/2,0,1)}
    object.spec_workArea={workAreas={area}}
    function object:getIsWorkAreaActive() return self.active end
    return object
end
