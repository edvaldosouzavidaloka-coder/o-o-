-- Width is stored on the implement itself, not only on its tractor or model name.
TGGPSImplementProfile={}
TGGPSImplementProfile.NAMESPACE=(g_currentModName or 'FS25_TG_GPS')..'.tgGpsImplement'
function TGGPSImplementProfile.prerequisitesPresent(specs)
    return (Attachable and SpecializationUtil.hasSpecialization(Attachable,specs))
        or (WorkArea and SpecializationUtil.hasSpecialization(WorkArea,specs))
        or (Cutter and SpecializationUtil.hasSpecialization(Cutter,specs)) or false
end
function TGGPSImplementProfile.initSpecialization()
    if not TGGPSImplementProfile.schemaRegistered and Vehicle and Vehicle.xmlSchemaSavegame and XMLValueType then
        Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT,'vehicles.vehicle(?).'..TGGPSImplementProfile.NAMESPACE..'#workingWidth','TG GPS implement width')
        Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING,'vehicles.vehicle(?).'..TGGPSImplementProfile.NAMESPACE..'#profileId','TG GPS implement profile identity')
        TGGPSImplementProfile.schemaRegistered=true
    end
end
function TGGPSImplementProfile.registerEventListeners(typeEntry)
    SpecializationUtil.registerEventListener(typeEntry,'onLoad',TGGPSImplementProfile)
end
function TGGPSImplementProfile:onLoad(savegame)
    TGGPSImplementProfile.initSpecialization()
    if not savegame or savegame.resetVehicles or not savegame.xmlFile then return end
    local id=savegame.xmlFile:getValue(savegame.key..'.'..TGGPSImplementProfile.NAMESPACE..'#profileId')
    if type(id)=='string' and #id>0 and #id<=192 then self.tgGpsProfileId=id;TGGPSWidthProfiles.noteIdentity(id) end
    local value=savegame.xmlFile:getValue(savegame.key..'.'..TGGPSImplementProfile.NAMESPACE..'#workingWidth')
    if type(value)=='number' and value==value and value>=1 and value<=50 then self.tgGpsWorkingWidth=value end
end
function TGGPSImplementProfile:saveToXMLFile(xml,key)
    local value=self.tgGpsWorkingWidth
    if type(value)=='number' and value==value and value>=1 and value<=50 then xml:setValue(key..'#workingWidth',value) end
    if self.tgGpsProfileId then xml:setValue(key..'#profileId',self.tgGpsProfileId) end
end
