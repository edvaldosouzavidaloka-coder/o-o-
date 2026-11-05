-- Local compatibility fixes; pickup, ownership, mounting, unloading and network
-- state remain handled by the native FS25 BaleLoader specialization.
CottonAutoloadFix = {}

function CottonAutoloadFix.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(BaleLoader, specializations)
end

function CottonAutoloadFix.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", CottonAutoloadFix)
end

function CottonAutoloadFix.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getBaleTypeByBale", CottonAutoloadFix.getBaleTypeByBale)
end

function CottonAutoloadFix:onLoad(savegame)
    local spec = self.spec_baleLoader
    if spec == nil or spec.baleGrabber == nil or spec.baleGrabber.trigger == nil then
        Logging.xmlError(self.xmlFile, "Cotton autoload requires a valid bale pickup trigger")
        return
    end
    local trigger = spec.baleGrabber.trigger
    -- The conversion left both fields at zero. Include only the relevant flags,
    -- retaining any other flags already configured on this vehicle's trigger.
    setCollisionFilterGroup(trigger, bit32.bor(getCollisionFilterGroup(trigger), CollisionFlag.TRIGGER))
    setCollisionFilterMask(trigger, bit32.bor(getCollisionFilterMask(trigger), CollisionFlag.DYNAMIC_OBJECT))
end

function CottonAutoloadFix:getBaleTypeByBale(superFunc, bale)
    -- The vanilla size check alone does not filter the bale's crop. This trailer
    -- layout is for round cotton modules; square Case IH modules do not fit it.
    if bale == nil or bale.isRoundbale ~= true or bale.getFillType == nil
        or bale:getFillType() ~= FillType.COTTON then
        return nil
    end
    return superFunc(self, bale)
end
