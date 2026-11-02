-- Anexa a especializacao aos tipos dirigiveis, sem alterar arquivos dos veiculos.
local modName = g_currentModName

local function instalar(typeManager)
    if typeManager.typeName ~= "vehicle" or not g_modIsLoaded[modName] then return end
    local name = modName .. ".transbordoInteligente"
    local entry = g_specializationManager:getSpecializationByName(name)
    local specialization = entry ~= nil and (entry.classObject or entry) or nil
    if specialization == nil or specialization.prerequisitesPresent == nil then
        Logging.error("[Transbordo Inteligente] Especializacao nao encontrada: %s", name)
        return
    end
    for typeName, entry in pairs(typeManager.types) do
        if specialization.prerequisitesPresent(entry.specializations)
            and not SpecializationUtil.hasSpecialization(specialization, entry.specializations) then
            typeManager:addSpecialization(typeName, name)
        end
    end
end

TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, instalar)
