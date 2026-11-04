-- Width belongs to the actual vehicle, with independent entries for each
-- attached implement combination. Native savegame serialization preserves it.
TGGPSWidthProfiles={}
TGGPSWidthProfiles.__index=TGGPSWidthProfiles
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function call(object,name,...)
    if object and type(object[name])=='function' then
        local ok,value=pcall(object[name],object,...);if ok then return value end
    end
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
    local value=call(vehicle,'getAttacherToolWorkingWidth')
    if finite(value) and value>0.5 then return math.max(1,math.min(50,value)) end
    local tool=TGGPSContext.implement(vehicle)
    value=call(tool,'getAttacherToolWorkingWidth')
    if finite(value) and value>0.5 then return math.max(1,math.min(50,value)) end
    local spec=tool and tool.spec_workArea
    local width=0
    if spec and getWorldTranslation then
        for _,area in pairs(spec.workAreas or {}) do
            if area.start and area.width then
                local ax,_,az=getWorldTranslation(area.start)
                local bx,_,bz=getWorldTranslation(area.width)
                width=math.max(width,math.sqrt((bx-ax)^2+(bz-az)^2))
            end
        end
    end
    if width>0.5 then return math.max(1,math.min(50,width)) end
end
function TGGPSWidthProfiles.new(owner)
    return setmetatable({owner=owner},TGGPSWidthProfiles)
end
function TGGPSWidthProfiles:select(vehicle)
    if not vehicle or not vehicle.tgGpsSupported then self.vehicle,self.selection=nil,nil;return false end
    local key=self.key(vehicle)
    if self.vehicle==vehicle and self.selection==key then return false end
    vehicle.tgGpsWidths=vehicle.tgGpsWidths or {}
    local width=vehicle.tgGpsWidths[key]
    if not finite(width) or width<1 or width>50 then width=self.detect(vehicle) or 6 end
    vehicle.tgGpsWidths[key]=width
    self.vehicle,self.selection=vehicle,key
    self.owner:stopAutosteer()
    self.owner.width=width
    self.owner.monitorContext=nil
    if self.owner.coverage then self.owner.coverage:endRun() end
    if #self.owner.sourcePoints>=2 then self.owner:rebuildGuidance() end
    return true
end
function TGGPSWidthProfiles:remember(width)
    if self.vehicle and self.selection and finite(width) then
        self.vehicle.tgGpsWidths[self.selection]=math.max(1,math.min(50,width))
    end
end
function TGGPSWidthProfiles.register(schema,namespace)
    if not schema or not XMLValueType then return end
    local base='vehicles.vehicle(?).'..namespace
    schema:register(XMLValueType.INT,base..'#widthProfileCount','TG GPS implement width count')
    schema:register(XMLValueType.STRING,base..'.widthProfile(?)#key','TG GPS implement identity')
    schema:register(XMLValueType.FLOAT,base..'.widthProfile(?)#width','TG GPS width in meters')
end
function TGGPSWidthProfiles.load(vehicle,savegame,namespace)
    vehicle.tgGpsWidths={}
    if not savegame or savegame.resetVehicles or not savegame.xmlFile or not savegame.xmlFile.getValue then return end
    local xml,key=savegame.xmlFile,savegame.key..'.'..namespace
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
