-- FS25 conversion support scoped to this mod's JD_8R vehicle type.
-- No global Vehicle functions or other vehicles are modified.
JD8RCompatibility = {}

function JD8RCompatibility.prerequisitesPresent(specializations)
    return true
end

function JD8RCompatibility.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("JD8RCompatibility")
    schema:register(XMLValueType.NODE_INDEX, "vehicle.jd8rCompatibility.paintSurface(?)#node", "Painted shape")
    schema:register(XMLValueType.INT, "vehicle.jd8rCompatibility.paintSurface(?)#materialIndex", "Zero-based paint material index")
    schema:setXMLSpecializationType()
end

function JD8RCompatibility.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", JD8RCompatibility)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", JD8RCompatibility)
end

local function childPath(root, path)
    local node = root
    for _, index in ipairs(path) do
        if node == nil or node == 0 or index >= getNumOfChildren(node) then
            return nil
        end
        node = getChildAt(node, index)
    end
    return node
end

local function repairZeroFilter(node, group, mask)
    if node ~= nil and node ~= 0 then
        -- Retain any already configured filter; only restore the broken zero fields.
        if getCollisionFilterGroup(node) == 0 then
            setCollisionFilterGroup(node, group)
        end
        if getCollisionFilterMask(node) == 0 then
            setCollisionFilterMask(node, mask)
        end
    end
end

function JD8RCompatibility:onPreLoad(savegame)
    local originalCallback = self.i3dFileLoaded
    -- onPreLoad runs before I3D loading. Fix the converted zero filters before
    -- Vehicle.loadComponentFromXML checks the VEHICLE bits or inserts physics.
    -- Wrapping this instance's callback avoids a global loading hook.
    self.i3dFileLoaded = function(vehicle, i3dNode, ...)
        if i3dNode ~= nil and i3dNode ~= 0 then
            local group = bit32.bor(CollisionFlag.VEHICLE, CollisionFlag.CAMERA_BLOCKING, CollisionFlag.AI_BLOCKING)
            local mask = bit32.bor(CollisionFlag.VEHICLE, CollisionFlag.TERRAIN,
                CollisionFlag.STATIC_OBJECT, CollisionFlag.DYNAMIC_OBJECT,
                CollisionFlag.TREE, CollisionFlag.PLAYER, CollisionFlag.ANIMAL,
                CollisionFlag.TRIGGER)
            repairZeroFilter(childPath(i3dNode, {0}), group, mask)
            repairZeroFilter(childPath(i3dNode, {0, 0, 13, 0}), group, mask)
            repairZeroFilter(childPath(i3dNode, {0, 0, 16}), CollisionFlag.TRIGGER, CollisionFlag.PLAYER)
        end
        return originalCallback(vehicle, i3dNode, ...)
    end
end

function JD8RCompatibility:onLoad(savegame)
    -- The native FS25 color configuration runs during configuration onPostLoad,
    -- after specialization onLoad. Establish stable slot names first.
    self.xmlFile:iterate("vehicle.jd8rCompatibility.paintSurface", function(_, key)
        local node = self.xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
        local index = self.xmlFile:getValue(key .. "#materialIndex")
        if node ~= nil and getHasClassId(node, ClassIds.SHAPE)
            and index ~= nil and index >= 0 and index < getNumOfMaterials(node) then
            setMaterialSlotName(node, index, "JD8R_BODY_PAINT")
        else
            Logging.xmlWarning(self.xmlFile, "Invalid paint surface or material index at '%s'", key)
        end
    end)
end
