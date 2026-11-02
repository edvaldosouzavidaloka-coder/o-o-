-- Transbordo Inteligente - FS25, single-player, versao de teste 0.2.0.0.
-- A direcao usa AIVehicleUtil; transferencia de graos exclusivamente pela engine.
-- Nao contem pathfinding de obstaculos, suporte multiplayer ou salario de ajudante.
TransbordoInteligente = {}
local TI = TransbordoInteligente

TI.CONFIG = {
    chamada = 60, cheio = 99.9, vazio = 0.1,
    raioColheitadeiras = 600, raioCaminhaoSemMapa = 200, distanciaBorda = 60,
    velocidadeViagem = 15, velocidadeManobra = 5, velocidadeMaxColheita = 15,
    recuoAproximacao = 18, intervaloBusca = 1000,
    tempoSemDescarga = 30000, tempoManobra = 120000
}
TI.ESTADOS = {
    INATIVO = 1, BUSCANDO = 2, APROXIMANDO = 3, ACOMPANHANDO = 4,
    BUSCANDO_CARRETA = 5, APROXIMANDO_CARRETA = 6, DESCARREGANDO = 7,
    SAINDO = 8, PAUSADO = 9
}
local E = TI.ESTADOS
TI.reservasColheitadeiras = setmetatable({}, {__mode = "k"})
TI.reservasCarretas = setmetatable({}, {__mode = "k"})

local function valido(v)
    return v ~= nil and v.rootNode ~= nil and v.rootNode ~= 0 and not v.isDeleted
        and (entityExists == nil or entityExists(v.rootNode))
end

local function direcao(v)
    return v.getAIDirectionNode ~= nil and v:getAIDirectionNode() or v.rootNode
end

local function distancia(a, b)
    local ax, _, az = getWorldTranslation(a)
    local bx, _, bz = getWorldTranslation(b)
    return math.sqrt((ax - bx)^2 + (az - bz)^2)
end

local function velocidade(v)
    -- Vehicle:getLastSpeed() ja retorna km/h no FS25.
    return v.getLastSpeed ~= nil and math.abs(v:getLastSpeed()) or 0
end

local function mesmaFazenda(a, b)
    return a.getOwnerFarmId ~= nil and b.getOwnerFarmId ~= nil
        and a:getOwnerFarmId() == b:getOwnerFarmId()
end

function TI.getConjunto(raiz)
    local lista, vistos = {}, {}
    local function visitar(v)
        if v == nil or vistos[v] then return end
        vistos[v] = true
        lista[#lista + 1] = v
        for _, implemento in pairs(v.getAttachedImplements ~= nil and v:getAttachedImplements() or {}) do
            visitar(implemento.object)
        end
    end
    visitar(raiz)
    return lista, vistos
end

local function veiculosDaMissao()
    local lista, vistos = {}, {}
    local sistema = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, raiz in pairs(sistema ~= nil and sistema.vehicles or {}) do
        for _, v in ipairs(TI.getConjunto(raiz)) do
            if not vistos[v] then vistos[v] = true; lista[#lista + 1] = v end
        end
    end
    return lista
end

function TI.getCarga(v)
    if not valido(v) or v.getFillUnitCapacity == nil
        or v.getFillUnitFillLevel == nil or v.getFillUnitFillType == nil then return nil end
    local node
    if v.getPipeDischargeNodeIndex ~= nil and v.getDischargeNodeByIndex ~= nil then
        node = v:getDischargeNodeByIndex(v:getPipeDischargeNodeIndex())
    elseif v.getCurrentDischargeNode ~= nil then
        node = v:getCurrentDischargeNode()
    end
    local index = node ~= nil and node.fillUnitIndex or nil
    if index == nil then return nil end
    local capacidade = v:getFillUnitCapacity(index) or 0
    local nivel = v:getFillUnitFillLevel(index) or 0
    if capacidade <= 0 then return nil end
    return {veiculo = v, node = node, index = index, capacidade = capacidade,
        nivel = nivel, tipo = v:getFillUnitFillType(index), percentual = 100 * nivel / capacidade}
end

function TI.encontrarBazuca(trator)
    for _, v in ipairs(TI.getConjunto(trator)) do
        if v.spec_pipe ~= nil and v.spec_dischargeable ~= nil and v.spec_combine == nil then
            if TI.getCarga(v) ~= nil then return v end
        end
    end
    return nil
end

local function aceita(v, index, tipo)
    if tipo == nil or tipo == 0 or (FillType ~= nil and tipo == FillType.UNKNOWN) then return false end
    if v.getFillUnitFreeCapacity == nil or (v:getFillUnitFreeCapacity(index, tipo) or 0) <= 0 then return false end
    if v.getFillUnitSupportsFillType == nil or not v:getFillUnitSupportsFillType(index, tipo) then return false end
    if v.getFillUnitAllowsFillType ~= nil and not v:getFillUnitAllowsFillType(index, tipo) then return false end
    local nivel = v:getFillUnitFillLevel(index) or 0
    return nivel <= 0 or v:getFillUnitFillType(index) == tipo
end

local function pontoEnchimento(v, index)
    if v.getFillUnitExactFillRootNode == nil then return nil end
    local node = v:getFillUnitExactFillRootNode(index)
    return node ~= 0 and node or nil
end

local function abrirCano(v)
    if v.spec_pipe == nil or v.setPipeState == nil then return end
    if v.getIsPipeStateChangeAllowed ~= nil and not v:getIsPipeStateChangeAllowed(2) then return end
    if v.spec_pipe.currentState ~= 0 and v.spec_pipe.targetState ~= 2 and v.spec_pipe.currentState ~= 2 then
        v:setPipeState(2)
    end
end

local function prepararRecebimento(v, index)
    if v.aiPrepareLoading ~= nil then v:aiPrepareLoading(index) end
end

local function setDescarga(v, ativa)
    if v ~= nil and v.setDischargeState ~= nil and Dischargeable ~= nil then
        v:setDischargeState(ativa and Dischargeable.DISCHARGE_STATE_OBJECT or Dischargeable.DISCHARGE_STATE_OFF)
    end
end

local function disponivel(reservas, alvo, trator)
    local dono = reservas[alvo]
    if dono == nil or dono == trator then return true end
    local spec = dono.spec_transbordoInteligente
    if not valido(dono) or spec == nil or not spec.isAtivo then
        reservas[alvo] = nil
        return true
    end
    return false
end

local function liberarColheitadeira(trator)
    local spec = trator.spec_transbordoInteligente
    if spec.colheitadeiraAlvo ~= nil and TI.reservasColheitadeiras[spec.colheitadeiraAlvo] == trator then
        TI.reservasColheitadeiras[spec.colheitadeiraAlvo] = nil
    end
    spec.colheitadeiraAlvo = nil
end

local function liberarCarreta(trator)
    local spec = trator.spec_transbordoInteligente
    if spec.caminhaoAlvo ~= nil and TI.reservasCarretas[spec.caminhaoAlvo] == trator then
        TI.reservasCarretas[spec.caminhaoAlvo] = nil
    end
    spec.caminhaoAlvo, spec.indiceCarreta = nil, nil
    setDescarga(spec.bazuca, false)
    if spec.ligadoPeloMod and spec.bazuca ~= nil and spec.bazuca.setIsTurnedOn ~= nil then
        spec.bazuca:setIsTurnedOn(false)
    end
    spec.ligadoPeloMod = false
end

function TI.mudarEstado(trator, estado, mensagem)
    local spec = trator.spec_transbordoInteligente
    spec.estadoAtual, spec.tempoEstado = estado, 0
    spec.mensagem = mensagem
    spec.aproximacaoConcluida = false
    spec.tempoSemFluxo = 0
    spec.ultimaCarga = nil
    spec.receptorPreparado = false
    spec.buscaEm = 0
end

-- Contorno original do mapa. Sem API de talhao, usa a posicao inicial + raios.
function TI.getTalhao(v)
    if g_farmlandManager == nil or g_farmlandManager.getFarmlandAtWorldPosition == nil then return nil end
    local x, _, z = getWorldTranslation(v.rootNode)
    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
    local field = farmland ~= nil and farmland.getField ~= nil and farmland:getField() or nil
    local polygon = field ~= nil and field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    local flat = polygon ~= nil and polygon.getVerticesList ~= nil and polygon:getVerticesList() or nil
    if type(flat) ~= "table" or #flat < 6 or #flat % 2 ~= 0 then return nil end
    return {objeto = field, vertices = flat}
end

function TI.distanciaBorda(talhao, x, z)
    local minimo = math.huge
    local v = talhao.vertices
    for i = 1, #v, 2 do
        local j = i + 2 > #v and 1 or i + 2
        local ax, az, bx, bz = v[i], v[i+1], v[j], v[j+1]
        local dx, dz = bx - ax, bz - az
        local tamanho = dx*dx + dz*dz
        local t = tamanho > 0 and math.max(0, math.min(1, ((x-ax)*dx + (z-az)*dz) / tamanho)) or 0
        minimo = math.min(minimo, math.sqrt((x-ax-t*dx)^2 + (z-az-t*dz)^2))
    end
    return minimo
end

local function mesmoTalhao(trator, v)
    local spec = trator.spec_transbordoInteligente
    if spec.talhao == nil then
        return distancia(trator.rootNode, v.rootNode) <= TI.CONFIG.raioColheitadeiras
    end
    local talhao = TI.getTalhao(v)
    return talhao ~= nil and talhao.objeto == spec.talhao.objeto
end

function TI.encontrarColheitadeira(trator)
    local spec = trator.spec_transbordoInteligente
    local carga = TI.getCarga(spec.bazuca)
    if carga == nil then return nil end
    local melhor, maiorNivel, menorDistancia = nil, -1, math.huge
    for _, v in ipairs(veiculosDaMissao()) do
        if valido(v) and v.spec_combine ~= nil and mesmaFazenda(trator, v) and mesmoTalhao(trator, v)
            and disponivel(TI.reservasColheitadeiras, v, trator) then
            local grao = TI.getCarga(v)
            if grao ~= nil and grao.percentual >= TI.CONFIG.chamada and aceita(spec.bazuca, carga.index, grao.tipo) then
                local d = distancia(trator.rootNode, v.rootNode)
                if grao.percentual > maiorNivel or (grao.percentual == maiorNivel and d < menorDistancia) then
                    melhor, maiorNivel, menorDistancia = v, grao.percentual, d
                end
            end
        end
    end
    return melhor
end

function TI.encontrarCaminhao(trator)
    local spec = trator.spec_transbordoInteligente
    local carga = TI.getCarga(spec.bazuca)
    if carga == nil then return nil end
    local _, conjunto = TI.getConjunto(trator)
    local melhor, indice, menorDistancia = nil, nil, math.huge
    for _, v in ipairs(veiculosDaMissao()) do
        -- Escolhe a carreta receptora, nao o cavalo mecanico, tanque ou a propria bazuca.
        if valido(v) and not conjunto[v] and v.spec_trailer ~= nil and v.spec_combine == nil
            and v.spec_pipe == nil and mesmaFazenda(trator, v)
            and disponivel(TI.reservasCarretas, v, trator) then
            local raiz = v.getRootVehicle ~= nil and v:getRootVehicle() or v
            local x, _, z = getWorldTranslation(v.rootNode)
            local pertoBorda
            if spec.talhao ~= nil then
                pertoBorda = TI.distanciaBorda(spec.talhao, x, z) <= TI.CONFIG.distanciaBorda
            else
                pertoBorda = math.sqrt((x-spec.inicioX)^2 + (z-spec.inicioZ)^2) <= TI.CONFIG.raioCaminhaoSemMapa
            end
            if pertoBorda and velocidade(raiz) < 1 then
                for index in pairs(v.spec_fillUnit ~= nil and v.spec_fillUnit.fillUnits or {}) do
                    if aceita(v, index, carga.tipo) and pontoEnchimento(v, index) ~= nil then
                        local d = distancia(trator.rootNode, v.rootNode)
                        if d < menorDistancia then melhor, indice, menorDistancia = v, index, d end
                    end
                end
            end
        end
    end
    return melhor, indice
end

-- Conduz pelo controlador nativo; nao escreve rotatedTime nem finge um job GIANTS.
function TI.dirigir(trator, dt, x, z, velocidadeAlvo)
    local steeringNode = trator.getAISteeringNode ~= nil and trator:getAISteeringNode() or direcao(trator)
    local y = select(2, getWorldTranslation(steeringNode))
    local lx, _, lz = worldToLocal(steeringNode, x, y, z)
    AIVehicleUtil.driveToPoint(trator, dt, 1, velocidadeAlvo > 0, true, lx, lz, velocidadeAlvo)
end

local function parar(trator, dt)
    if AIVehicleUtil ~= nil and AIVehicleUtil.driveToPoint ~= nil then
        local x, _, z = localToWorld(direcao(trator), 0, 0, 5)
        TI.dirigir(trator, dt or 16, x, z, 0)
    end
end

local function pausar(trator, mensagem)
    liberarColheitadeira(trator)
    liberarCarreta(trator)
    TI.mudarEstado(trator, E.PAUSADO, mensagem .. " Desligue e reposicione antes de reativar.")
end

-- Posicao desejada do NO DE DIRECAO do trator para alinhar cano e fillRoot.
function TI.alvoReceber(trator, colheitadeira)
    local spec = trator.spec_transbordoInteligente
    local carga, grao = TI.getCarga(spec.bazuca), TI.getCarga(colheitadeira)
    if carga == nil or grao == nil or grao.node.node == nil then return nil end
    local receptor = pontoEnchimento(spec.bazuca, carga.index)
    if receptor == nil then return nil end
    local rx, _, rz = localToLocal(receptor, direcao(trator), 0, 0, 0)
    local px, _, pz = getWorldTranslation(grao.node.node)
    local dx, _, dz = localDirectionToWorld(direcao(colheitadeira), 0, 0, 1)
    local nx, _, nz = localDirectionToWorld(direcao(colheitadeira), 1, 0, 0)
    return px - nx*rx - dx*rz, pz - nz*rx - dz*rz, dx, dz, receptor
end

function TI.alvoDescarregar(trator, carreta, index)
    local spec = trator.spec_transbordoInteligente
    local carga = TI.getCarga(spec.bazuca)
    local receptor = pontoEnchimento(carreta, index)
    if carga == nil or carga.node.node == nil or receptor == nil then return nil end
    local ox, _, oz = localToLocal(carga.node.node, direcao(trator), 0, 0, 0)
    local px, _, pz = getWorldTranslation(receptor)
    local raiz = carreta.getRootVehicle ~= nil and carreta:getRootVehicle() or carreta
    local dx, _, dz = localDirectionToWorld(direcao(raiz), 0, 0, 1)
    local nx, _, nz = localDirectionToWorld(direcao(raiz), 1, 0, 0)
    return px - nx*ox - dx*oz, pz - nz*ox - dz*oz, dx, dz
end

local function erroPosicao(trator, x, z, dx, dz)
    local tx, _, tz = getWorldTranslation(direcao(trator))
    local ex, ez = x-tx, z-tz
    local hx, _, hz = localDirectionToWorld(direcao(trator), 0, 0, 1)
    return ex*dx + ez*dz, ex*dz - ez*dx, hx*dx + hz*dz
end

function TI.podeDescarregar(trator)
    local spec = trator.spec_transbordoInteligente
    local carga = TI.getCarga(spec.bazuca)
    if carga == nil or spec.bazuca.getDischargeTargetObject == nil
        or spec.bazuca.getCanDischargeToObject == nil then return false end
    local alvo, index = spec.bazuca:getDischargeTargetObject(carga.node)
    return alvo == spec.caminhaoAlvo and index == spec.indiceCarreta
        and spec.bazuca:getCanDischargeToObject(carga.node) == true
        and aceita(alvo, index, carga.tipo)
end

local function iniciarSaida(trator, proximoEstado)
    local spec = trator.spec_transbordoInteligente
    local combine = spec.colheitadeiraAlvo
    if valido(combine) then
        local cx, cy, cz = getWorldTranslation(direcao(trator))
        local lx, _, lz = worldToLocal(direcao(combine), cx, cy, cz)
        local sinal = lx >= 0 and 1 or -1
        local x, _, z = localToWorld(direcao(combine), lx + sinal*4, 0, math.min(lz-12, -18))
        spec.saidaX, spec.saidaZ, spec.depoisSaida = x, z, proximoEstado
        TI.mudarEstado(trator, E.SAINDO)
    else
        liberarColheitadeira(trator)
        TI.mudarEstado(trator, proximoEstado)
    end
end

function TI.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable, specializations)
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function TI.registerEventListeners(vehicleType)
    for _, nome in ipairs({"onLoad", "onRegisterActionEvents", "onUpdate", "onDraw", "onDelete"}) do
        SpecializationUtil.registerEventListener(vehicleType, nome, TI)
    end
end

function TI.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsActive", TI.getIsActive)
end

function TI:getIsActive(superFunc, ...)
    local spec = self.spec_transbordoInteligente
    if spec ~= nil and spec.isAtivo then return true end
    return superFunc(self, ...)
end

function TI:onLoad(savegame)
    self.spec_transbordoInteligente = {isAtivo=false, estadoAtual=E.INATIVO, actionEvents={},
        tempoEstado=0, buscaEm=0, tempoSemFluxo=0}
end

function TI:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    local spec = self.spec_transbordoInteligente
    if not self.isClient or spec == nil then return end
    self:clearActionEventsTable(spec.actionEvents)
    if not isActiveForInputIgnoreSelection or InputAction.TOGGLE_TRANSBORDO == nil then return end
    local _, id = self:addActionEvent(spec.actionEvents, InputAction.TOGGLE_TRANSBORDO,
        self, TI.actionEventToggleTransbordo, false, true, false, true)
    if id ~= nil then
        g_inputBinding:setActionEventTextVisibility(id, true)
        g_inputBinding:setActionEventText(id, "Ligar/desligar Transbordo Inteligente")
    end
end

local function avisar(trator, texto)
    trator.spec_transbordoInteligente.mensagem = texto
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, texto)
    elseif Logging ~= nil then Logging.info("[Transbordo Inteligente] " .. texto) end
end

function TI.desativar(trator)
    local spec = trator.spec_transbordoInteligente
    if spec == nil then return end
    if spec.isAtivo and trator.isServer then parar(trator, 16) end
    if spec.isAtivo then
        liberarColheitadeira(trator)
        liberarCarreta(trator)
    end
    if spec.bazuca ~= nil and spec.bazuca.spec_pipe ~= nil and spec.controleCano then
        spec.bazuca.spec_pipe.automaticDischarge = spec.descargaAutomaticaOriginal
    end
    spec.controleCano = false
    spec.isAtivo = false
    TI.mudarEstado(trator, E.INATIVO)
    if trator.setCruiseControlState ~= nil and Drivable ~= nil then
        trator:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
    end
end

function TI:actionEventToggleTransbordo(actionName, inputValue)
    if inputValue ~= nil and inputValue <= 0 then return end
    local spec = self.spec_transbordoInteligente
    if spec.isAtivo then TI.desativar(self); return end
    local info = g_currentMission ~= nil and g_currentMission.missionDynamicInfo or nil
    if not self.isServer or (info ~= nil and info.isMultiplayer) then
        avisar(self, "Esta versao suporta apenas single-player."); return
    end
    if self.getIsAIActive ~= nil and self:getIsAIActive() then
        avisar(self, "Desligue o outro piloto do trator antes de ativar."); return
    end
    if AIVehicleUtil == nil or AIVehicleUtil.driveToPoint == nil then
        avisar(self, "Controlador de direcao do FS25 indisponivel."); return
    end
    local bazuca = TI.encontrarBazuca(self)
    if bazuca == nil then avisar(self, "Acople uma bazuca com cano e compartimento de graos."); return end
    spec.bazuca, spec.isAtivo = bazuca, true
    spec.descargaAutomaticaOriginal = bazuca.spec_pipe.automaticDischarge
    spec.controleCano = true
    bazuca.spec_pipe.automaticDischarge = false
    local inicioX, _, inicioZ = getWorldTranslation(self.rootNode)
    spec.inicioX, spec.inicioZ = inicioX, inicioZ
    spec.talhao = TI.getTalhao(self)
    if spec.talhao == nil then
        local menor = TI.CONFIG.raioColheitadeiras
        for _, v in ipairs(veiculosDaMissao()) do
            if valido(v) and v.spec_combine ~= nil and mesmaFazenda(self, v) then
                local d = distancia(self.rootNode, v.rootNode)
                local talhao = TI.getTalhao(v)
                if talhao ~= nil and d < menor then spec.talhao, menor = talhao, d end
            end
        end
    end
    TI.mudarEstado(self, TI.getCarga(bazuca).percentual >= TI.CONFIG.cheio and E.BUSCANDO_CARRETA or E.BUSCANDO)
    if spec.talhao == nil then avisar(self, "Mapa sem contorno disponivel: busca limitada por raio da posicao inicial.") end
end

function TI:onUpdate(dt)
    local spec = self.spec_transbordoInteligente
    if spec == nil or not spec.isAtivo or not self.isServer then return end
    if self.raiseActive ~= nil then self:raiseActive() end
    spec.tempoEstado = spec.tempoEstado + dt
    spec.buscaEm = math.max(0, spec.buscaEm-dt)
    local _, conjunto = TI.getConjunto(self)
    if not valido(spec.bazuca) or not conjunto[spec.bazuca] then
        TI.desativar(self); avisar(self, "Transbordo desligado: bazuca desacoplada ou removida."); return
    end
    local carga = TI.getCarga(spec.bazuca)
    if carga == nil then TI.desativar(self); return end
    if self.getIsAIActive ~= nil and self:getIsAIActive() then
        TI.desativar(self); avisar(self, "Transbordo desligado: outro piloto assumiu o trator."); return
    end
    if spec.estadoAtual == E.PAUSADO then parar(self, dt); return end
    if self.startMotor ~= nil and self.getIsMotorStarted ~= nil and not self:getIsMotorStarted() then
        self:startMotor()
    end
    if spec.estadoAtual ~= E.DESCARREGANDO then setDescarga(spec.bazuca, false) end

    local estado = spec.estadoAtual
    if carga.percentual >= TI.CONFIG.cheio and (estado == E.BUSCANDO or estado == E.APROXIMANDO or estado == E.ACOMPANHANDO) then
        iniciarSaida(self, E.BUSCANDO_CARRETA)
        parar(self, dt)
        return
    end

    if estado == E.BUSCANDO then
        parar(self, dt)
        if spec.buscaEm > 0 then return end
        spec.buscaEm = TI.CONFIG.intervaloBusca
        local alvo = TI.encontrarColheitadeira(self)
        if alvo ~= nil then
            spec.colheitadeiraAlvo = alvo
            TI.reservasColheitadeiras[alvo] = self
            if spec.talhao == nil then spec.talhao = TI.getTalhao(alvo) end
            TI.mudarEstado(self, E.APROXIMANDO)
        end

    elseif estado == E.APROXIMANDO or estado == E.ACOMPANHANDO then
        local combine = spec.colheitadeiraAlvo
        local grao = TI.getCarga(combine)
        if grao == nil or not mesmaFazenda(self, combine) or not mesmoTalhao(self, combine) then
            liberarColheitadeira(self); TI.mudarEstado(self, E.BUSCANDO); parar(self, dt); return
        end
        if grao.percentual <= TI.CONFIG.vazio or not aceita(spec.bazuca, carga.index, grao.tipo) then
            iniciarSaida(self, E.BUSCANDO); parar(self, dt); return
        end
        if velocidade(combine) > TI.CONFIG.velocidadeMaxColheita then
            pausar(self, "Colheitadeira acima da velocidade de trabalho."); parar(self, dt); return
        end
        if not spec.receptorPreparado then
            prepararRecebimento(spec.bazuca, carga.index); spec.receptorPreparado = true
        end
        if distancia(self.rootNode, combine.rootNode) <= 50 then abrirCano(combine) end
        local x, z, dx, dz = TI.alvoReceber(self, combine)
        if x == nil then pausar(self, "Nao foi possivel localizar o cano ou o receptor da bazuca."); parar(self, dt); return end
        if estado == E.APROXIMANDO and not spec.aproximacaoConcluida then
            local ax, az = x-dx*TI.CONFIG.recuoAproximacao, z-dz*TI.CONFIG.recuoAproximacao
            local tx, _, tz = getWorldTranslation(direcao(self))
            if (tx-ax)^2+(tz-az)^2 < 16 then spec.aproximacaoConcluida = true
            else TI.dirigir(self, dt, ax, az, TI.CONFIG.velocidadeViagem) end
        else
            local longitudinal, lateral, alinhamento = erroPosicao(self, x, z, dx, dz)
            local base = velocidade(combine)
            local alvo = math.max(0, math.min(TI.CONFIG.velocidadeViagem, base + longitudinal*0.8))
            if alinhamento < 0.7 then alvo = math.min(alvo, TI.CONFIG.velocidadeManobra) end
            if base < 0.5 and math.abs(longitudinal) < 0.7 and math.abs(lateral) < 0.7 then alvo = 0 end
            if longitudinal < -2 then alvo = math.max(0, base-3) end
            TI.dirigir(self, dt, x+dx*6, z+dz*6, alvo)
            if estado == E.APROXIMANDO and math.abs(longitudinal) < 2 and math.abs(lateral) < 1 and alinhamento > 0.85 then
                TI.mudarEstado(self, E.ACOMPANHANDO)
            end
            if estado == E.ACOMPANHANDO then
                if spec.ultimaCarga ~= nil and carga.nivel <= spec.ultimaCarga+0.01 then
                    spec.tempoSemFluxo = spec.tempoSemFluxo + dt
                else spec.tempoSemFluxo = 0 end
                spec.ultimaCarga = carga.nivel
                if spec.tempoSemFluxo > TI.CONFIG.tempoSemDescarga then
                    pausar(self, "Sem recebimento de graos; confira o cano da colheitadeira."); parar(self, dt)
                end
            end
        end
        if estado == E.APROXIMANDO and spec.tempoEstado > TI.CONFIG.tempoManobra then
            pausar(self, "Tempo de alinhamento excedido."); parar(self, dt)
        end

    elseif estado == E.SAINDO then
        local x, _, z = getWorldTranslation(direcao(self))
        if (x-spec.saidaX)^2+(z-spec.saidaZ)^2 < 16 then
            liberarColheitadeira(self)
            TI.mudarEstado(self, spec.depoisSaida)
            parar(self, dt)
        elseif spec.tempoEstado > TI.CONFIG.tempoManobra then
            pausar(self, "Nao foi possivel sair da lateral da colheitadeira."); parar(self, dt)
        else TI.dirigir(self, dt, spec.saidaX, spec.saidaZ, TI.CONFIG.velocidadeManobra) end

    elseif estado == E.BUSCANDO_CARRETA then
        parar(self, dt)
        if carga.percentual <= TI.CONFIG.vazio then TI.mudarEstado(self, E.BUSCANDO); return end
        if spec.buscaEm > 0 then return end
        spec.buscaEm = TI.CONFIG.intervaloBusca
        local alvo, index = TI.encontrarCaminhao(self)
        if alvo ~= nil then
            spec.caminhaoAlvo, spec.indiceCarreta = alvo, index
            TI.reservasCarretas[alvo] = self
            TI.mudarEstado(self, E.APROXIMANDO_CARRETA)
        end

    elseif estado == E.APROXIMANDO_CARRETA or estado == E.DESCARREGANDO then
        local carreta = spec.caminhaoAlvo
        if carga.percentual <= TI.CONFIG.vazio then
            liberarCarreta(self); TI.mudarEstado(self, E.BUSCANDO); parar(self, dt); return
        end
        if not valido(carreta) or not mesmaFazenda(self, carreta) or not aceita(carreta, spec.indiceCarreta, carga.tipo) then
            liberarCarreta(self); TI.mudarEstado(self, E.BUSCANDO_CARRETA); parar(self, dt); return
        end
        local raiz = carreta.getRootVehicle ~= nil and carreta:getRootVehicle() or carreta
        if velocidade(raiz) >= 1 then
            liberarCarreta(self); TI.mudarEstado(self, E.BUSCANDO_CARRETA); parar(self, dt); return
        end
        abrirCano(spec.bazuca)
        if not spec.receptorPreparado then
            prepararRecebimento(carreta, spec.indiceCarreta); spec.receptorPreparado = true
        end
        local x, z, dx, dz = TI.alvoDescarregar(self, carreta, spec.indiceCarreta)
        if x == nil then pausar(self, "Geometria de descarga indisponivel."); parar(self, dt); return end
        if estado == E.APROXIMANDO_CARRETA then
            if TI.podeDescarregar(self) then
                TI.mudarEstado(self, E.DESCARREGANDO); parar(self, dt); return
            end
            if not spec.aproximacaoConcluida then
                local ax, az = x-dx*TI.CONFIG.recuoAproximacao, z-dz*TI.CONFIG.recuoAproximacao
                local tx, _, tz = getWorldTranslation(direcao(self))
                if (tx-ax)^2+(tz-az)^2 < 16 then spec.aproximacaoConcluida = true
                else TI.dirigir(self, dt, ax, az, TI.CONFIG.velocidadeViagem) end
            else
                local longitudinal, lateral = erroPosicao(self, x, z, dx, dz)
                local speed = math.min(TI.CONFIG.velocidadeManobra, math.max(0, longitudinal*0.7))
                if math.abs(longitudinal) < 0.6 and math.abs(lateral) < 0.7 then speed = 0 end
                TI.dirigir(self, dt, x+dx*5, z+dz*5, speed)
            end
            if spec.tempoEstado > TI.CONFIG.tempoManobra then
                pausar(self, "Cano nao alcancou a carreta; confira altura, lado e obstaculos."); parar(self, dt)
            end
        else
            parar(self, dt)
            if not TI.podeDescarregar(self) then
                setDescarga(spec.bazuca, false)
                TI.mudarEstado(self, E.APROXIMANDO_CARRETA)
                return
            end
            if spec.bazuca.setIsTurnedOn ~= nil and spec.bazuca.getIsTurnedOn ~= nil
                and not spec.bazuca:getIsTurnedOn() then
                spec.bazuca:setIsTurnedOn(true); spec.ligadoPeloMod = true
            end
            setDescarga(spec.bazuca, true)
            if spec.ultimaCarga ~= nil and carga.nivel >= spec.ultimaCarga-0.01 then
                spec.tempoSemFluxo = spec.tempoSemFluxo + dt
            else spec.tempoSemFluxo = 0 end
            spec.ultimaCarga = carga.nivel
            if spec.tempoSemFluxo > TI.CONFIG.tempoSemDescarga then
                pausar(self, "Descarga sem fluxo de graos.")
            end
        end
    end
end

function TI:onDraw()
    local spec = self.spec_transbordoInteligente
    if spec == nil or not spec.isAtivo or not self.isClient or not self:getIsEntered() then return end
    local textos = {
        [E.BUSCANDO]="Aguardando colheitadeira com 60% ou mais",
        [E.APROXIMANDO]="Aproximando da colheitadeira",
        [E.ACOMPANHANDO]="Recebendo graos / acompanhando colheitadeira",
        [E.BUSCANDO_CARRETA]="Aguardando carreta compativel na borda do talhao",
        [E.APROXIMANDO_CARRETA]="Alinhando o cano com a carreta",
        [E.DESCARREGANDO]="Descarregando na carreta",
        [E.SAINDO]="Saindo da lateral da colheitadeira",
        [E.PAUSADO]="Pausado: confira o conjunto"
    }
    setTextColor(1, 0.8, 0.1, 1)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    renderText(0.5, 0.85, 0.022, "TRANSBORDO: " .. (textos[spec.estadoAtual] or "Ativo"))
    if spec.mensagem ~= nil then renderText(0.5, 0.82, 0.014, spec.mensagem) end
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

function TI:onDelete()
    TI.desativar(self)
end
