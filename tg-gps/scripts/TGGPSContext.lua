-- Read-only vehicle/farm/land metadata. Missing map APIs remain explicitly unknown.
TGGPSContext = {}
local function call(object, method, ...)
    if object == nil or type(object[method]) ~= "function" then return nil end
    local ok, value = pcall(object[method], object, ...)
    if ok then return value end
end
local function label(value)
    if type(value) == "string" and value ~= "" then return value end
end
function TGGPSContext.mapId()
    local info = g_currentMission and g_currentMission.missionInfo
    return tostring(info and (info.mapId or info.mapTitle) or "defaultMap")
end
function TGGPSContext.name(object)
    return label(call(object, "getName")) or label(object and object.name)
        or (object and object.configFileName and object.configFileName:match("([^/\\]+)%.xml$"))
        or "Nao informado"
end
function TGGPSContext.machineKind(vehicle)
    return vehicle ~= nil and (vehicle.spec_combine ~= nil or vehicle.spec_forageHarvester ~= nil)
        and "combine" or "tractor"
end
function TGGPSContext.implement(vehicle)
    local visited, found = {}, nil
    local function scan(object)
        if object == nil or visited[object] then return end
        visited[object] = true
        if object ~= vehicle and (object.spec_cutter ~= nil or object.spec_workArea ~= nil
            or object.spec_sowingMachine ~= nil or object.spec_sprayer ~= nil) then
            if found == nil or object.spec_cutter ~= nil then found = object end
        end
        for _, entry in pairs(call(object, "getAttachedImplements") or {}) do scan(entry.object) end
    end
    scan(vehicle)
    return found
end
function TGGPSContext.read(owner)
    local vehicle = owner:getControlledVehicle()
    local pose = vehicle and owner:getVehiclePose(vehicle)
    local farmId = call(vehicle, "getOwnerFarmId") or (g_localPlayer and call(g_localPlayer, "getFarmId"))
    local farm = call(g_farmManager, "getFarmById", farmId)
    local land = pose and call(g_farmlandManager, "getFarmlandAtWorldPosition", pose.x, pose.z)
    local field = call(land, "getField")
    local fieldId = call(field, "getId") or (field and field.fieldId)
    local landFarmId = land and (land.farmId or call(g_farmlandManager, "getFarmlandOwner", land.id))
    local landFarm = landFarmId and call(g_farmManager, "getFarmById", landFarmId)
    local tool = TGGPSContext.implement(vehicle)
    local kind = TGGPSContext.machineKind(vehicle)
    return {vehicle = vehicle, kind = kind, machineName = TGGPSContext.name(vehicle),
        operation = kind == "combine" and "COLHEITA" or "TRABALHO DE CAMPO",
        farmId = farmId, farmName = farm and label(farm.name) or "Nao informado",
        ownerName = landFarm and label(landFarm.name) or "Nao informado",
        fieldId = fieldId and tostring(fieldId) or "",
        fieldName = label(field and field.name) or (fieldId and "Talhao " .. tostring(fieldId)) or "Nao informado",
        implement = tool, implementName = tool and TGGPSContext.name(tool) or "Sem implemento",
        implementKind = tool and (tool.spec_cutter and "PLATAFORMA" or tool.spec_sowingMachine and "SEMEADORA"
            or tool.spec_sprayer and "PULVERIZADOR" or "IMPLEMENTO") or "SEM IMPLEMENTO"}
end
function TGGPSContext.heading(points)
    if type(points) ~= "table" or #points < 2 then return 0 end
    local a = points[1]
    for i=2,#points do
        local b=points[i]
        if (b.x-a.x)^2+(b.z-a.z)^2>0.000001 then
            return (math.deg(math.atan2(b.x-a.x,b.z-a.z))+360)%360
        end
    end
    return 0
end
