-- Named guidance library. Map/farm scoped; records are copied, validated and
-- rebuilt before replacing live guidance. Loading never engages steering.
TGGPSCourseLibrary = {}
TGGPSCourseLibrary.__index = TGGPSCourseLibrary
local NUMBERS = {"width", "currentLane", "currentSection", "trackOffset", "headlandDepth", "turnSpeed", "turnRadius", "turnSide", "heading"}
local STRINGS = {"name", "mapId", "farmName", "ownerName", "fieldId", "fieldName", "mode","profileId"}
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {} for k, v in pairs(value) do result[k] = clone(v) end return result
end
local function pointsValid(points, minimum)
    if type(points) ~= "table" or #points < minimum or #points > 10000 then return false end
    for _, p in ipairs(points) do if type(p) ~= "table" or not finite(p.x) or not finite(p.z)
        or math.abs(p.x) > 1000000 or math.abs(p.z) > 1000000 then return false end end
    return true
end
function TGGPSCourseLibrary.valid(record)
    if type(record) ~= "table" or type(record.name) ~= "string" or #record.name == 0 or #record.name > 192
        or not pointsValid(record.sourcePoints, 2) then return false end
    if record.mode ~= "field" and record.mode ~= "straight" and record.mode ~= "curve" and record.mode~="border" then return false end
    for _, name in ipairs(NUMBERS) do if not finite(record[name]) then return false end end
    if record.width < 1 or record.width > 50 or math.abs(record.trackOffset) > 1000
        or math.abs(record.currentLane) > 1000 or record.currentLane % 1 ~= 0
        or record.currentSection < 1 or record.currentSection % 1 ~= 0
        or record.headlandDepth < 6 or record.headlandDepth > 50
        or record.turnSpeed < 2 or record.turnSpeed > 8 or record.turnRadius < 5 or record.turnRadius > 15
        or (record.turnSide ~= 1 and record.turnSide ~= -1) then return false end
    if record.mode=='border' and not pointsValid(record.fieldBoundary,3) then return false end
    if record.mode == "field" then
        if not pointsValid(record.fieldBoundary, 3) or not pointsValid({record.fieldOrigin}, 1)
            or type(record.fieldDirection) ~= "table" or not finite(record.fieldDirection.dx)
            or not finite(record.fieldDirection.dz) then return false end
        if record.fieldDirection.dx ^ 2 + record.fieldDirection.dz ^ 2 < 0.000001 then return false end
    end
    if record.fieldCurveReference and #record.fieldCurveReference>0 and not pointsValid(record.fieldCurveReference,2) then return false end
    return true
end
function TGGPSCourseLibrary.new(owner)
    local self = setmetatable({owner = owner, records = {}, nextId = 1}, TGGPSCourseLibrary)
    self:read()
    return self
end
function TGGPSCourseLibrary:path()
    return self.owner:getSavePath():gsub("%.xml$", "_library.xml")
end
function TGGPSCourseLibrary:snapshot(name)
    self.owner:syncWorkingWidth()
    local o, c = self.owner, self.owner:getMonitorContext()
    local r = {name = name, mapId = TGGPSContext.mapId(), farmId = c.farmId,profileId=o.activeImplementId,
        farmName = c.farmName, ownerName = c.ownerName, fieldId = c.fieldId, fieldName = c.fieldName,
        mode = o.mode, width = o.width, currentLane = o.currentLane, currentSection = o.currentSection,
        trackOffset = o.trackOffset or 0, heading = TGGPSContext.heading(o.basePath),
        headlandEnabled = o.headlandEnabled, headlandDepth = o.headlandDepth, turnSpeed = o.turnSpeed,
        turnRadius = o.turnRadius, turnSide = o.turnSide, autoLaneSelection = o.autoLaneSelection,
        sourcePoints = clone(o.sourcePoints), fieldBoundary = clone(o.fieldBoundary),
        fieldOrigin = clone(o.fieldOrigin), fieldDirection = clone(o.fieldDirection),
        fieldCurveReference=clone(o.mode=='field' and o.fieldCurveReference or {})}
    return r
end
function TGGPSCourseLibrary:saveSnapshot(record, name)
    if self.readError then return false,"Biblioteca existente invalida; arquivo preservado, confira uma copia de seguranca" end
    if #self.records >= 200 then return false, "Biblioteca cheia (200 trajetos neste mapa)" end
    record = clone(record)
    if not record.profileId or record.profileId=='' then record.profileId=self.owner.activeImplementId end
    record.name = tostring(name or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if not self.valid(record) then return false, "Nome ou geometria de trajeto invalido" end
    record.id = self.nextId
    self.records[#self.records + 1] = record
    self.nextId = self.nextId + 1
    if not self:write() then
        table.remove(self.records); self.nextId = record.id
        return false, "Nao foi possivel salvar a biblioteca no disco"
    end
    return true, record
end
function TGGPSCourseLibrary:list(filter,shared)
    self.owner:syncWorkingWidth()
    local context, result = self.owner:getMonitorContext(), {}
    filter = tostring(filter or ""):lower()
    for _, r in ipairs(self.records) do
        local text = table.concat({r.name, r.fieldName or "", r.fieldId or "", string.format("%.1f", r.heading)}, " "):lower()
        if (shared or r.profileId==self.owner.activeImplementId) and r.mapId == TGGPSContext.mapId() and (r.farmId == nil or context.farmId == nil or r.farmId == context.farmId)
            and (filter == "" or text:find(filter, 1, true) ~= nil) then result[#result + 1] = r end
    end
    table.sort(result, function(a,b) if a.name == b.name then return a.id < b.id end return a.name < b.name end)
    return result
end
function TGGPSCourseLibrary:load(id,options)
    options=options or {}
    local record
    for _, r in ipairs(self:list(nil,options.shared)) do if r.id == id then record = clone(r); break end end
    if not record or not self.valid(record) then return false, "Trajeto indisponivel ou invalido para este mapa/fazenda" end
    local o = self.owner
    o:syncWorkingWidth()
    if options.here then
        local pose=o:getVehiclePose(o:getControlledVehicle())
        if not pose then return false,'Entre na maquina para usar a linha aqui' end
        local reference=(record.fieldCurveReference and #record.fieldCurveReference>=2) and record.fieldCurveReference or record.sourcePoints
        local first=reference[1]
        local dx,dz=pose.x-first.x,pose.z-first.z
        local moved={}
        for _,p in ipairs(reference) do moved[#moved+1]={x=p.x+dx,z=p.z+dz} end
        local curved=record.mode=='curve' or (record.fieldCurveReference and #record.fieldCurveReference>=2)
        local boundary=TGFieldBoundary.getAt(pose.x,pose.z)
        record.sourcePoints=moved
        if record.mode=='border' then
            if not boundary then return false,'Contorno indisponivel para usar bordadura aqui' end
            record.fieldBoundary=boundary
        elseif boundary then
            record.mode,record.fieldBoundary='field',boundary
            record.fieldOrigin={x=pose.x,z=pose.z}
            local heading=math.rad(record.heading);record.fieldDirection={dx=math.sin(heading),dz=math.cos(heading)}
            record.fieldCurveReference=curved and moved or {}
        else record.mode=curved and 'curve' or 'straight';record.fieldBoundary=nil;record.fieldCurveReference={} end
        record.trackOffset,record.currentLane,record.currentSection=0,0,1
    end
    local candidate = setmetatable({}, {__index = o})
    for _, key in ipairs({"mode", "width", "currentLane", "currentSection", "trackOffset", "headlandEnabled",
        "headlandDepth", "turnSpeed", "turnRadius", "turnSide", "autoLaneSelection", "sourcePoints",
        "fieldBoundary", "fieldOrigin", "fieldDirection","fieldCurveReference"}) do candidate[key] = clone(record[key]) end
    candidate.fieldBoundary = (record.mode == "field" or record.mode=="border") and record.fieldBoundary or nil
    candidate.fieldCurveReference=record.fieldCurveReference or {}
    candidate.width=o.width -- loading a route must not replace this vehicle/implement's width
    if options.onlyLine then
        for _,name in ipairs({'headlandEnabled','headlandDepth','turnSpeed','turnRadius','turnSide'}) do candidate[name]=o[name] end
        if candidate.mode~='field' then candidate.headlandEnabled=false end
    end
    if not candidate:rebuildGuidance() then return false, "Nao foi possivel reconstruir as linhas salvas" end
    local section = record.currentSection
    if candidate:getLanePath(candidate.currentLane, section) ~= nil then candidate.currentSection = section end
    o:stopAutosteer()
    for _, key in ipairs({"mode", "width", "currentLane", "currentSection", "trackOffset", "headlandEnabled",
        "headlandDepth", "turnSpeed", "turnRadius", "turnSide", "autoLaneSelection", "sourcePoints",
        "basePath", "guidanceLines", "guidanceSections", "minLane", "maxLane", "fieldBoundary", "fieldOrigin", "fieldDirection","fieldCurveReference"}) do
        o[key] = candidate[key]
    end
    -- Explicitly clear inherited metadata for a non-field route.
    if record.mode ~= "field" and record.mode~="border" then o.fieldBoundary, o.fieldOrigin, o.fieldDirection, o.minLane, o.maxLane = nil,nil,nil,nil,nil end
    o.pointA, o.isRecording, o.recordingVehicle, o.completedSections = nil, false, nil, {}
    o.recordedPoints, o.activeCourseName = {}, record.name
    if o.coverage then o.coverage:endRun() end
    return true, record
end
function TGGPSCourseLibrary:write()
    if createXMLFile == nil or setXMLFloat == nil or setXMLString == nil or setXMLInt == nil
        or saveXMLFile == nil then return false end
    if createFolder then createFolder(getUserProfileAppPath() .. TGGPS.SAVE_FOLDER) end
    local xml = createXMLFile("TGGPSLibrary", self:path(), "tgGpsLibrary")
    if xml == nil or xml == 0 then return false end
    setXMLInt(xml, "tgGpsLibrary#count", #self.records)
    setXMLInt(xml, "tgGpsLibrary#nextId", self.nextId)
    for i, r in ipairs(self.records) do
        local k = string.format("tgGpsLibrary.course(%d)", i - 1)
        setXMLInt(xml, k .. "#id", r.id)
        if r.farmId then setXMLInt(xml, k .. "#farmId", r.farmId) end
        for _, n in ipairs(STRINGS) do setXMLString(xml, k .. "#" .. n, r[n] or "") end
        for _, n in ipairs(NUMBERS) do setXMLFloat(xml, k .. "#" .. n, r[n]) end
        setXMLInt(xml, k .. "#headlandEnabled", r.headlandEnabled and 1 or 0)
        setXMLInt(xml, k .. "#autoLaneSelection", r.autoLaneSelection and 1 or 0)
        if r.mode == "field" then
            setXMLFloat(xml, k .. "#originX", r.fieldOrigin.x); setXMLFloat(xml, k .. "#originZ", r.fieldOrigin.z)
            setXMLFloat(xml, k .. "#dirX", r.fieldDirection.dx); setXMLFloat(xml, k .. "#dirZ", r.fieldDirection.dz)
        end
        for _, group in ipairs({"sourcePoints", "fieldBoundary","fieldCurveReference"}) do
            local points = r[group] or {}
            setXMLInt(xml, k .. "#" .. group .. "Count", #points)
            for j, p in ipairs(points) do
                local pk = k .. "." .. group .. string.format("(%d)", j - 1)
                setXMLFloat(xml, pk .. "#x", p.x); setXMLFloat(xml, pk .. "#z", p.z)
            end
        end
    end
    local result = saveXMLFile(xml); delete(xml)
    return result ~= false
end
function TGGPSCourseLibrary:deleteOwn(id,profile)
    if self.readError then return false,'Biblioteca invalida; arquivo preservado' end
    for index,record in ipairs(self.records) do
        if record.id==id then
            if record.profileId~=profile then return false,'Esta linha pertence a outro implemento' end
            table.remove(self.records,index)
            if not self:write() then table.insert(self.records,index,record);return false,'Nao foi possivel excluir a linha no disco' end
            return true,'Somente a linha selecionada foi excluida'
        end
    end
    return false,'Linha nao encontrada'
end
function TGGPSCourseLibrary:read()
    if fileExists == nil or not fileExists(self:path()) or loadXMLFile == nil then return end
    local xml = loadXMLFile("TGGPSLibrary", self:path())
    if xml == nil or xml == 0 then self.readError=true;return end
    local count = getXMLInt(xml, "tgGpsLibrary#count")
    if not finite(count) or count%1~=0 or count < 0 or count > 200 then self.readError=true;delete(xml); return end
    local used = {}
    for i = 0, count - 1 do
        local k, r = string.format("tgGpsLibrary.course(%d)", i), {}
        r.id, r.farmId = getXMLInt(xml, k .. "#id"), getXMLInt(xml, k .. "#farmId")
        for _, n in ipairs(STRINGS) do r[n] = getXMLString(xml, k .. "#" .. n) or "" end
        for _, n in ipairs(NUMBERS) do r[n] = getXMLFloat(xml, k .. "#" .. n) end
        r.headlandEnabled, r.autoLaneSelection = getXMLInt(xml,k.."#headlandEnabled")==1, getXMLInt(xml,k.."#autoLaneSelection")==1
        r.fieldOrigin = {x=getXMLFloat(xml,k.."#originX"),z=getXMLFloat(xml,k.."#originZ")}
        r.fieldDirection = {dx=getXMLFloat(xml,k.."#dirX"),dz=getXMLFloat(xml,k.."#dirZ")}
        local readable = true
        for _, group in ipairs({"sourcePoints", "fieldBoundary","fieldCurveReference"}) do
            r[group] = {}
            local n = getXMLInt(xml,k.."#"..group.."Count") or 0
            if n < 0 or n > 10000 then readable=false else for j=0,n-1 do
                local pk=k.."."..group..string.format("(%d)",j)
                r[group][#r[group]+1]={x=getXMLFloat(xml,pk.."#x"),z=getXMLFloat(xml,pk.."#z")}
            end end
        end
        if readable and finite(r.id) and r.id >= 1 and r.id%1==0 and not used[r.id] and self.valid(r) then
            self.records[#self.records+1]=r; used[r.id]=true; self.nextId=math.max(self.nextId,r.id+1)
        else self.readError=true end
    end
    local nextId=getXMLInt(xml,"tgGpsLibrary#nextId")
    if finite(nextId) and nextId%1==0 and nextId>=1 and nextId<1000000000 then self.nextId=math.max(self.nextId,nextId) end
    delete(xml)
end
