-- Anexa a especializacao aos tipos dirigiveis, sem alterar arquivos dos veiculos.
local modName = g_currentModName

local function instalar(typeManager)
    if typeManager.typeName ~= "vehicle" or not g_modIsLoaded[modName] then return end
    local name = modName .. ".transbordoInteligente"
    -- O registro do manager nao e a classe Lua. O modDesc carrega a classe no
    -- ambiente deste mod; use-a para testar requisitos, como os mods FS25 fazem.
    local specialization = TransbordoInteligente
    if type(specialization) ~= "table" or type(specialization.prerequisitesPresent) ~= "function" then
        Logging.error("[Transbordo Inteligente] Classe Lua nao carregada para %s; confira scripts/TransbordoInteligente.lua no modDesc.xml.", name)
        return
    end
    local count=0
    for typeName, entry in pairs(typeManager.types) do
        if specialization.prerequisitesPresent(entry.specializations)
            and not SpecializationUtil.hasSpecialization(specialization, entry.specializations) then
            typeManager:addSpecialization(typeName, name)
            count=count+1
        end
    end
    if Logging ~= nil then
        Logging.info("[Transbordo Inteligente] Especializacao registrada em %d tipos de veiculo.",count)
    end
end

TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, instalar)
