-- Stable material slots for the native FS25 color selectors, on both the
-- autoload and manual vehicle types. Tires, lights, glass and decals are excluded.
CottonTrailerColors = {}

function CottonTrailerColors.prerequisitesPresent(specializations)
    return true
end

function CottonTrailerColors.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("CottonTrailerColors")
    local key = "vehicle.cottonTrailerColors.surface(?)"
    schema:register(XMLValueType.NODE_INDEX, key .. "#node", "Painted shape")
    schema:register(XMLValueType.INT, key .. "#materialIndex", "Zero-based material index")
    schema:register(XMLValueType.STRING, key .. "#slotName", "Native paint material slot")
    schema:setXMLSpecializationType()
end

function CottonTrailerColors.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", CottonTrailerColors)
end

function CottonTrailerColors:onLoad(savegame)
    self.xmlFile:iterate("vehicle.cottonTrailerColors.surface", function(_, key)
        local node = self.xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
        local index = self.xmlFile:getValue(key .. "#materialIndex")
        local slot = self.xmlFile:getValue(key .. "#slotName")
        if node ~= nil and getHasClassId(node, ClassIds.SHAPE)
            and index ~= nil and index >= 0 and index < getNumOfMaterials(node) and slot ~= nil then
            setMaterialSlotName(node, index, slot)
        else
            Logging.xmlError(self.xmlFile, "Invalid cotton trailer paint surface at '%s'", key)
        end
    end)
end
