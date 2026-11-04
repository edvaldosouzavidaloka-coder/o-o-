-- Player steering integration for Farming Simulator 25.
-- The route and controller live in TGGPS; this specialization owns only vehicle
-- lifecycle, input registration and the physics hook.
TGGPSVehicle = {}
TGGPSVehicle.NAMESPACE=(g_currentModName or 'FS25_TG_GPS')..'.tgGpsVehicle'

function TGGPSVehicle.initSpecialization()
    if not TGGPSVehicle.schemaRegistered and TGGPSWidthProfiles and Vehicle and Vehicle.xmlSchemaSavegame then
        TGGPSWidthProfiles.register(Vehicle.xmlSchemaSavegame,TGGPSVehicle.NAMESPACE)
        TGGPSVehicle.schemaRegistered=true
    end
end

function TGGPSVehicle:saveToXMLFile(xml,key,usedModNames)
    TGGPSWidthProfiles.save(self,xml,key)
end

function TGGPSVehicle.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable, specializations)
        and SpecializationUtil.hasSpecialization(Wheels, specializations)
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function TGGPSVehicle.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", TGGPSVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", TGGPSVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", TGGPSVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", TGGPSVehicle)
end

function TGGPSVehicle.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", TGGPSVehicle.updateVehiclePhysics)
    if vehicleType.functions ~= nil and vehicleType.functions.enterVehicleRaycastClickToSwitch ~= nil then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "enterVehicleRaycastClickToSwitch", TGGPSVehicle.enterVehicleRaycastClickToSwitch)
    end
end

function TGGPSVehicle:onLoad(savegame)
    TGGPSVehicle.initSpecialization()
    TGGPSWidthProfiles.load(self,savegame,TGGPSVehicle.NAMESPACE)
    self.tgGpsSupported = true
    self.tgGpsActionEvents = {}
end

function TGGPSVehicle:onRegisterActionEvents(isSelected, isOnActiveVehicle)
    self.tgGpsActionEvents = self.tgGpsActionEvents or {}
    self:clearActionEventsTable(self.tgGpsActionEvents)

    if self.isClient and self:getIsActiveForInput(true, true)
        and TGGPS ~= nil and TGGPS.registerInputActions ~= nil then
        local count=TGGPS:registerInputActions(self)
        if count~=self.tgGpsLastActionCount and Logging then
            if count==0 then Logging.warning("[TG GPS PRO] Nenhum atalho registrado neste veiculo")
            else Logging.info(string.format("[TG GPS PRO] %d atalhos registrados no veiculo ativo",count)) end
        end
        self.tgGpsLastActionCount=count
    end
end

local function releaseSteering(vehicle)
    if TGGPS ~= nil and TGGPS.hudVehicle == vehicle and TGGPS.closeHud ~= nil then
        TGGPS:closeHud()
    end
    if TGGPS ~= nil and TGGPS.activeVehicle == vehicle and TGGPS.stopAutosteer ~= nil then
        TGGPS:stopAutosteer("Piloto desligado: controle do veiculo encerrado")
    end
end

function TGGPSVehicle:enterVehicleRaycastClickToSwitch(superFunc, x, y, ...)
    if TGGPS ~= nil and TGGPS.hudVehicle == self and TGGPS.isMouseOverHud ~= nil
        and TGGPS:isMouseOverHud(x, y) then
        return
    end
    return superFunc(self, x, y, ...)
end

function TGGPSVehicle:onLeaveVehicle()
    releaseSteering(self)
end

function TGGPSVehicle:onDelete()
    releaseSteering(self)
    if self.tgGpsActionEvents ~= nil then
        self:clearActionEventsTable(self.tgGpsActionEvents)
    end
    self.tgGpsSupported = false
end

function TGGPSVehicle:updateVehiclePhysics(superFunc, axisForward, axisSide, doHandbrake, dt, ...)
    if TGGPS ~= nil and TGGPS.applyDriveControl ~= nil then
        axisForward, axisSide, doHandbrake = TGGPS:applyDriveControl(self, axisForward, axisSide, doHandbrake, dt)
    elseif TGGPS ~= nil and TGGPS.applySteering ~= nil then
        axisSide = TGGPS:applySteering(self, axisForward, axisSide, doHandbrake, dt)
    end

    -- Preserve throttle, braking, additional parameters and every return value.
    return superFunc(self, axisForward, axisSide, doHandbrake, dt, ...)
end

