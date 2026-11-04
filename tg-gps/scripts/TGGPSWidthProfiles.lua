-- Width belongs to the selected implement itself and follows it between tractors.
-- Keep older tractor/combination entries only for migration and compatibility.
TGGPSWidthProfiles={}
TGGPSWidthProfiles.__index=TGGPSWidthProfiles
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function call(object,name,...)
    if object and type(object[name])=='function' then
        local ok,value=pcall(object[name],object,...);if ok then return value end
    end
end
TGGPSWidthProfiles.localSerial=0
function TGGPSWidthProfiles.noteIdentity(id)
    local n=type(id)=='string' and tonumber(id:match('^local:(%d+)$'))
    if n then TGGPSWidthProfiles.localSerial=math.max(TGGPSWidthProfiles.localSerial,n) end
end
function TGGPSWidthProfiles:identity(target)
    if type(target.tgGpsProfileId)=='string' and target.tgGpsProfileId~='' then return target.tgGpsProfileId end
    local native=call(target,'getUniqueId') or target.uniqueId
    if native~=nil and tostring(native)~='' then target.tgGpsProfileId='uid:'..tostring(native)
    else
        local path=self.owner:getSavePath():gsub('%.xml$','_profiles.xml')
        if fileExists and fileExists(path) and loadXMLFile and getXMLInt then
            local xml=loadXMLFile('TGGPSProfileIds',path)
            if xml and xml~=0 then
                local n=getXMLInt(xml,'tgGpsProfiles#serial')
                if finite(n) and n>=0 and n<1000000000 then self.localSerial=math.max(self.localSerial,n) end
                delete(xml)
            end
        end
        TGGPSWidthProfiles.localSerial=math.max(TGGPSWidthProfiles.localSerial,self.localSerial or 0)+1
        target.tgGpsProfileId='local:'..TGGPSWidthProfiles.localSerial
        if createXMLFile and setXMLInt and saveXMLFile then
            if createFolder then createFolder(getUserProfileAppPath()..TGGPS.SAVE_FOLDER) end
            local xml=createXMLFile('TGGPSProfileIds',path,'tgGpsProfiles')
            if xml and xml~=0 then setXMLInt(xml,'tgGpsProfiles#serial',TGGPSWidthProfiles.localSerial);saveXMLFile(xml);delete(xml) end
        end
    end
    return target.tgGpsProfileId
end
function TGGPSWidthProfiles.key(vehicle)
    local names,visited={},{}
    local function scan(object)
        if not object or visited[object] then return end
        visited[object]=true
        if object~=vehicle then
            local id=call(object,'getUniqueId') or object.uniqueId
            names[#names+1]=tostring(object.configFileName or object.typeName or 'implement')..'@'..tostring(id or '')
        end
        for _,entry in pairs(call(object,'getAttachedImplements') or {}) do scan(entry.object) end
    end
    scan(vehicle);table.sort(names)
    return TGGPSContext.machineKind(vehicle)..'|'..table.concat(names,'|')
end
function TGGPSWidthProfiles.detect(vehicle)
    local tool=TGGPSContext.implement(vehicle) or vehicle
    local spec=tool and tool.spec_workArea
    local width,minX,maxX=0,math.huge,-math.huge
    local rx,rz,ignored=1,0,0
    if tool and tool.rootNode and localDirectionToWorld then rx,ignored,rz=localDirectionToWorld(tool.rootNode,1,0,0) end
    if spec and getWorldTranslation then
        for _,area in pairs(spec.workAreas or {}) do
            if area.start and area.start~=0 and area.width and area.width~=0
                and area.functionName~='processRidgeMarkerArea'
                and area.functionName~='processCombineSwathArea'
                and area.functionName~='processCombineChopperArea'
                and not (WorkAreaType and WorkAreaType.AUXILIARY~=nil and area.type==WorkAreaType.AUXILIARY) then
                local ax,_,az=getWorldTranslation(area.start)
                local bx,_,bz=getWorldTranslation(area.width)
                minX=math.min(minX,ax*rx+az*rz,bx*rx+bz*rz)
                maxX=math.max(maxX,ax*rx+az*rz,bx*rx+bz*rz)
            end
        end
        width=maxX-minX
    end
    if width>0.5 then return math.max(1,math.min(50,width)) end
    local value=call(tool,'getAttacherToolWorkingWidth')
    if finite(value) and value>0.5 then return math.max(1,math.min(50,value)) end
end
function TGGPSWidthProfiles.new(owner)
    return setmetatable({owner=owner},TGGPSWidthProfiles)
end
function TGGPSWidthProfiles:select(vehicle)
    if not vehicle or not vehicle.tgGpsSupported then self.vehicle,self.selection,self.target=nil,nil,nil;return false end
    local key=self.key(vehicle)
    local target=TGGPSContext.implement(vehicle) or vehicle
    if self.vehicle==vehicle and self.target==target then
        if self.owner:selectImplementSession(self:identity(target)) and #self.owner.sourcePoints>=2 then
            -- A saved field session may have been built before this implement's
            -- width changed in another field. Rebuild using its current width.
            local section=self.owner.currentSection
            self.owner:rebuildGuidance()
            if self.owner:getLanePath(self.owner.currentLane,section) then self.owner.currentSection=section end
        end
        return false
    end
    vehicle.tgGpsWidths=vehicle.tgGpsWidths or {}
    local width=target.tgGpsWorkingWidth
    -- Migrate a matching older profile; a new object never borrows an unrelated width.
    if not finite(width) and (target==vehicle or target.uniqueId~=nil or call(target,'getUniqueId')~=nil) then
        width=vehicle.tgGpsWidths[key]
    end
    if not finite(width) or width<1 or width>50 then width=self.detect(vehicle) or 6 end
    vehicle.tgGpsWidths[key]=width
    target.tgGpsWorkingWidth=width
    self.vehicle,self.selection,self.target=vehicle,key,target
    self.owner:stopAutosteer()
    self.owner.monitorContext=nil
    self.owner:selectImplementSession(self:identity(target))
    self.owner.width=width
    self.owner.monitorContext=nil
    if self.owner.coverage then self.owner.coverage:endRun() end
    if #self.owner.sourcePoints>=2 then self.owner:rebuildGuidance() end
    return true
end
function TGGPSWidthProfiles:remember(width)
    if self.vehicle and self.selection and finite(width) then
        self.vehicle.tgGpsWidths[self.selection]=math.max(1,math.min(50,width))
        self.target.tgGpsWorkingWidth=math.max(1,math.min(50,width))
    end
end
function TGGPSWidthProfiles:resetCurrent()
    if not self.target then return end
    self.target.tgGpsWorkingWidth=nil
    self.vehicle.tgGpsWidths[self.selection]=nil
    self.target=nil
    self:select(self.owner:getControlledVehicle())
end
function TGGPSWidthProfiles.register(schema,namespace)
    if not schema or not XMLValueType then return end
    local base='vehicles.vehicle(?).'..namespace
    schema:register(XMLValueType.INT,base..'#widthProfileCount','TG GPS implement width count')
    schema:register(XMLValueType.STRING,base..'.widthProfile(?)#key','TG GPS implement identity')
    schema:register(XMLValueType.FLOAT,base..'.widthProfile(?)#width','TG GPS width in meters')
    schema:register(XMLValueType.FLOAT,base..'#workingWidth','TG GPS width of this machine')
    schema:register(XMLValueType.STRING,base..'#profileId','TG GPS independent machine profile')
end
function TGGPSWidthProfiles.load(vehicle,savegame,namespace)
    vehicle.tgGpsWidths={}
    if not savegame or savegame.resetVehicles or not savegame.xmlFile or not savegame.xmlFile.getValue then return end
    local xml,key=savegame.xmlFile,savegame.key..'.'..namespace
    local id=xml:getValue(key..'#profileId')
    if type(id)=='string' and #id>0 and #id<=192 then vehicle.tgGpsProfileId=id;TGGPSWidthProfiles.noteIdentity(id) end
    local ownWidth=xml:getValue(key..'#workingWidth')
    if finite(ownWidth) and ownWidth>=1 and ownWidth<=50 then vehicle.tgGpsWorkingWidth=ownWidth end
    local count=xml:getValue(key..'#widthProfileCount',0)
    if not finite(count) or count<0 or count>200 or count%1~=0 then return end
    for i=0,count-1 do
        local base=key..string.format('.widthProfile(%d)',i)
        local identity,width=xml:getValue(base..'#key'),xml:getValue(base..'#width')
        if type(identity)=='string' and #identity<=8192 and finite(width) and width>=1 and width<=50 then
            vehicle.tgGpsWidths[identity]=width
        end
    end
end
function TGGPSWidthProfiles.save(vehicle,xml,key)
    if not xml or not xml.setValue then return end
    if finite(vehicle.tgGpsWorkingWidth) then xml:setValue(key..'#workingWidth',vehicle.tgGpsWorkingWidth) end
    if vehicle.tgGpsProfileId then xml:setValue(key..'#profileId',vehicle.tgGpsProfileId) end
    local keys={}
    for identity,width in pairs(vehicle.tgGpsWidths or {}) do
        if finite(width) and width>=1 and width<=50 then keys[#keys+1]=identity end
    end
    table.sort(keys)
    local count=math.min(200,#keys)
    xml:setValue(key..'#widthProfileCount',count)
    for i=1,count do
        local base=key..string.format('.widthProfile(%d)',i-1)
        xml:setValue(base..'#key',keys[i]);xml:setValue(base..'#width',vehicle.tgGpsWidths[keys[i]])
    end
end
