-- Transbordo Inteligente - FS25, single-player, versao de teste 0.8.0.0.
-- A direcao usa AIVehicleUtil; transferencia de graos exclusivamente pela engine.
-- Direcao direta, sem leitura de cultura ou planejamento de rotas.
TransbordoInteligente = {}
local TI = TransbordoInteligente
TI.VERSAO="0.8.0.0"

TI.CONFIG = {
    chamada = 60, cheio = 99.9, vazio = 0.1,
    velocidadeViagem = 15, velocidadeManobra = 8, velocidadeManobraPerto = 5,
    velocidadeAlinhamento = 4, velocidadeMaxColheita = 15,
    recuoAproximacao = 50, distanciaEntradaDireta = 55, pontoMira = 8, intervaloBusca = 1000,
    tempoSemDescarga = 30000, tempoManobra = 120000,
    intervaloDestino = 250, intervaloRetentativa = 2000,
    velocidadeMinima = 1.3, velocidadeRe = 1.5, velocidadeReposicionar = 3, limiteCorrecaoRe = 8,
    toleranciaLongitudinal = 0.1, toleranciaLateral = 0.15,
    alcanceBorda = 12, folgaManobraTalhao = 8
}
TI.ESTADOS = {
    INATIVO = 1, BUSCANDO = 2, APROXIMANDO = 3, ACOMPANHANDO = 4,
    BUSCANDO_CARRETA = 5, APROXIMANDO_CARRETA = 6, DESCARREGANDO = 7,
    SAINDO = 8, PAUSADO = 9, AGUARDANDO_CARGA = 10, RETOMANDO = 11
}
local E = TI.ESTADOS
TI.reservasColheitadeiras = setmetatable({}, {__mode = "k"})
TI.reservasCarretas = setmetatable({}, {__mode = "k"})
TI.cacheCarga = setmetatable({}, {__mode = "k"})

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

-- Wheels:onUpdate consulta getBlockFoliageDestruction antes de aplicar dano.
-- O bloqueio e local ao conjunto automatico; a opcao global da partida nao muda.
local function restaurarDano(v,record)
    if rawget(v,"getBlockFoliageDestruction")==record.wrapper then
        rawset(v,"getBlockFoliageDestruction",record.originalRaw)
    end
end

function TI.atualizarBloqueioDano(trator)
    local spec=trator.spec_transbordoInteligente
    local lista,conjunto=TI.getConjunto(trator)
    spec.bloqueiosDano=spec.bloqueiosDano or {}
    for v,record in pairs(spec.bloqueiosDano) do
        if not conjunto[v] then
            restaurarDano(v,record)
            spec.bloqueiosDano[v]=nil
        end
    end
    for _,v in ipairs(lista) do
        if spec.bloqueiosDano[v]==nil then
            local original=v.getBlockFoliageDestruction
            local record={originalRaw=rawget(v,"getBlockFoliageDestruction")}
            record.wrapper=function(object,...)
                local root=object.getRootVehicle~=nil and object:getRootVehicle() or object
                if spec.isAtivo and (object==trator or root==trator) then return true end
                if original~=nil then return original(object,...) end
                return false
            end
            spec.bloqueiosDano[v]=record
            v.getBlockFoliageDestruction=record.wrapper
        end
    end
end

function TI.restaurarBloqueioDano(trator)
    local spec=trator.spec_transbordoInteligente
    for v,record in pairs(spec.bloqueiosDano or {}) do restaurarDano(v,record) end
    spec.bloqueiosDano=nil
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
        local pipeIndex=v:getPipeDischargeNodeIndex()
        if pipeIndex~=nil then node = v:getDischargeNodeByIndex(pipeIndex) end
    end
    if node==nil and v.getCurrentDischargeNode ~= nil then
        node = v:getCurrentDischargeNode()
    end
    if node==nil then node=TI.cacheCarga[v] end
    if node==nil then
        for _,candidate in pairs(v.spec_dischargeable~=nil and v.spec_dischargeable.dischargeNodes or {}) do
            if candidate.fillUnitIndex~=nil and (v:getFillUnitCapacity(candidate.fillUnitIndex) or 0)>0 then
                node=candidate;break
            end
        end
    end
    local index = node ~= nil and node.fillUnitIndex or nil
    if index == nil then return nil end
    local capacidade = v:getFillUnitCapacity(index) or 0
    local nivel = v:getFillUnitFillLevel(index) or 0
    if capacidade <= 0 then return nil end
    TI.cacheCarga[v]=node
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
    local node
    if v.getFillUnitAutoAimTargetNode~=nil then node=v:getFillUnitAutoAimTargetNode(index) end
    if node==nil or node==0 then
        if v.getFillUnitExactFillRootNode~=nil then node=v:getFillUnitExactFillRootNode(index) end
    end
    return node ~= 0 and node or nil
end

-- Centro da faixa de mira, sem mover os nos/efeitos da propria engine.
function TI.pontoEnchimento(v,index)
    local node=pontoEnchimento(v,index)
    if node==nil then return nil end
    local unit=v.spec_fillUnit~=nil and v.spec_fillUnit.fillUnits[index] or nil
    local aim=unit~=nil and unit.autoAimTarget or nil
    if aim~=nil and aim.node==node and type(aim.startZ)=="number" and type(aim.endZ)=="number"
        and aim.baseTrans~=nil and getParent~=nil then
        local parent=getParent(node)
        if parent~=nil and parent~=0 then
            local x,y,z=localToWorld(parent,aim.baseTrans[1],aim.baseTrans[2],(aim.startZ+aim.endZ)/2)
            return x,y,z,node
        end
    end
    local x,y,z=getWorldTranslation(node)
    return x,y,z,node
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
    spec.entradaPelaTraseira,spec.recebimentoConfirmado=false,false
end

local function liberarCarreta(trator)
    local spec = trator.spec_transbordoInteligente
    if spec.caminhaoAlvo ~= nil and TI.reservasCarretas[spec.caminhaoAlvo] == trator then
        TI.reservasCarretas[spec.caminhaoAlvo] = nil
    end
    spec.caminhaoAlvo, spec.indiceCarreta = nil, nil
    spec.sentidoDestino=nil
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
    spec.mensagemNavegacao=nil
    spec.ladoManobra=nil
    spec.tempoSemProgresso,spec.referenciaProgresso=0,nil
end

-- Tempo total de viagem nao e travamento. Movimento ou graos reiniciam a conta.
function TI.atualizarProgresso(trator,dt,carga)
    local spec=trator.spec_transbordoInteligente
    local x,_,z=getWorldTranslation(direcao(trator))
    local ref=spec.referenciaProgresso
    if ref==nil or (x-ref.x)^2+(z-ref.z)^2>=0.0625 or math.abs(carga.nivel-ref.nivel)>=1 then
        spec.referenciaProgresso={x=x,z=z,nivel=carga.nivel}
        spec.tempoSemProgresso=0
    else spec.tempoSemProgresso=(spec.tempoSemProgresso or 0)+dt end
end

-- Contorno original do mapa. Propriedade rural nao substitui o poligono do campo.
function TI.getTalhao(v)
    local x, _, z = getWorldTranslation(v.rootNode)
    if TITalhao==nil then return nil end
    local farmland = g_farmlandManager~=nil and g_farmlandManager.getFarmlandAtWorldPosition~=nil
        and g_farmlandManager:getFarmlandAtWorldPosition(x,z) or nil
    local field = farmland ~= nil and farmland.getField ~= nil and farmland:getField() or nil
    local polygon = field ~= nil and field.getDensityMapPolygon ~= nil and field:getDensityMapPolygon() or nil
    local flat = polygon ~= nil and polygon.getVerticesList ~= nil and polygon:getVerticesList() or nil
    local talhao=TITalhao.criar(field,flat)
    if talhao~=nil and TITalhao.contem(talhao,x,z) then return talhao end
    -- Alguns mapas informam os campos pelo FieldManager.
    for _,candidate in pairs(g_fieldManager~=nil and g_fieldManager.getFields~=nil and g_fieldManager:getFields() or {}) do
        local polygon=candidate.getDensityMapPolygon~=nil and candidate:getDensityMapPolygon() or nil
        local vertices=polygon~=nil and polygon.getVerticesList~=nil and polygon:getVerticesList() or nil
        local other=TITalhao.criar(candidate,vertices)
        if other~=nil and TITalhao.contem(other,x,z) then return other end
    end
    return nil
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
    if spec.talhao==nil or TITalhao==nil then return false end
    local x,_,z=getWorldTranslation(v.rootNode)
    return TITalhao.contem(spec.talhao,x,z)
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
    if carga == nil or spec.talhao==nil then return nil end
    local _, conjunto = TI.getConjunto(trator)
    local melhor, indice, menorDistancia,melhorClasse = nil, nil, math.huge,math.huge
    local contagem={compativeis=0,movendo=0,reservadas=0,temporarias=0}
    local sx,_,sz=getWorldTranslation(carga.node.node or trator.rootNode)
    for _, v in ipairs(veiculosDaMissao()) do
        -- Escolhe a carreta receptora, nao o cavalo mecanico, tanque ou a propria bazuca.
        if valido(v) and not conjunto[v] and (v.spec_trailer ~= nil or v.spec_fillVolume ~= nil)
            and v.spec_combine == nil and v.spec_mixerWagon == nil and v.spec_sowingMachine == nil
            and v.spec_pipe == nil and mesmaFazenda(trator, v) then
            local raiz = v.getRootVehicle ~= nil and v:getRootVehicle() or v
            for index in pairs(v.spec_fillUnit ~= nil and v.spec_fillUnit.fillUnits or {}) do
                if aceita(v, index, carga.tipo) and pontoEnchimento(v, index) ~= nil then
                    contagem.compativeis=contagem.compativeis+1
                    local fx,_,fz=TI.pontoEnchimento(v,index)
                    local d=math.sqrt((fx-sx)^2+(fz-sz)^2)
                    -- O cano pode alcancar uma caçamba na borda; as rodas ficam
                    -- dentro do campo, inclusive na posicao final de alinhamento.
                    local inside=TITalhao.contem(spec.talhao,fx,fz)
                    local nearby=inside or TITalhao.distancia(spec.talhao,fx,fz)<=TI.CONFIG.alcanceBorda
                    local classe=inside and 0 or 1
                    local ignored=spec.destinosIgnorados~=nil and spec.destinosIgnorados[v] or nil
                    if not nearby then
                        contagem.compativeis=contagem.compativeis-1
                    elseif velocidade(raiz)>=1 then contagem.movendo=contagem.movendo+1
                    elseif not disponivel(TI.reservasCarretas,v,trator) then contagem.reservadas=contagem.reservadas+1
                    elseif ignored~=nil and ignored>(spec.tempoTotal or 0) then contagem.temporarias=contagem.temporarias+1
                    elseif spec.bazuca.spec_pipe.currentState==2 and TI.alvoDescarregar(trator,v,index,true)==nil then
                        contagem.compativeis=contagem.compativeis-1
                    elseif classe<melhorClasse or (classe==melhorClasse and d<menorDistancia) then
                        melhor,indice,menorDistancia,melhorClasse=v,index,d,classe
                    end
                end
            end
        end
    end
    if melhor~=nil then spec.motivoBuscaDestino=nil
    elseif contagem.compativeis==0 then spec.motivoBuscaDestino="Nenhuma carreta compativel neste talhao; estacione na borda com espaco interno"
    elseif contagem.movendo==contagem.compativeis then spec.motivoBuscaDestino="Pare o caminhao para receber a carga"
    elseif contagem.reservadas==contagem.compativeis then spec.motivoBuscaDestino="Carretas ocupadas por outra bazuca"
    else spec.motivoBuscaDestino="Procurando receptor livre; repetindo busca automaticamente" end
    return melhor, indice
end

function TI.selecionarDestino(trator)
    local spec=trator.spec_transbordoInteligente
    local target,index=TI.encontrarCaminhao(trator)
    if target~=nil then
        if spec.caminhaoAlvo~=target or spec.indiceCarreta~=index then liberarCarreta(trator) end
        spec.caminhaoAlvo,spec.indiceCarreta=target,index
        TI.reservasCarretas[target]=trator
    end
    return target,index
end

-- Conduz pelo controlador nativo; nao escreve rotatedTime nem finge um job GIANTS.
function TI.dirigir(trator, dt, x, z, velocidadeAlvo, moveForwards,somenteFrente)
    -- Direcao direta com limite de proximidade dos conjuntos selecionados.
    -- Nao ha leitura de cultura, busca de rotas ou dependencia de coroutine.
    local spec=trator.spec_transbordoInteligente
    if velocidadeAlvo>0 and spec.talhao==nil then
        velocidadeAlvo=0;spec.mensagemNavegacao="Talhao nao reconhecido; ative dentro do campo"
    end
    moveForwards=moveForwards~=false
    local steeringNode = trator.getAISteeringNode ~= nil and trator:getAISteeringNode() or direcao(trator)
    local y = select(2, getWorldTranslation(steeringNode))
    local lx, _, lz = worldToLocal(steeringNode, x, y, z)
    -- driveToPoint nao inverte a marcha quando o alvo fica atras. Uma correcao
    -- curta e reta pode usar re; para virar, conserva um lado de esterco ate
    -- o ponto original voltar a ficar a frente. Nao ha busca de rota.
    if velocidadeAlvo>0 and moveForwards and lz < -1 then
        if not somenteFrente and math.abs(lx)<0.6 and -lz<=TI.CONFIG.limiteCorrecaoRe then
            moveForwards=false
            velocidadeAlvo=math.min(velocidadeAlvo,TI.CONFIG.velocidadeRe)
        else
            spec.ladoManobra=spec.ladoManobra or (lx<0 and -1 or 1)
            x,y,z=localToWorld(steeringNode,spec.ladoManobra*15,0,15)
            lx,lz=spec.ladoManobra*15,15
            velocidadeAlvo=math.min(velocidadeAlvo,TI.CONFIG.velocidadeManobra)
        end
    elseif lz>1 then spec.ladoManobra=nil end
    if velocidadeAlvo>TI.CONFIG.velocidadeManobraPerto and (spec.ladoManobra~=nil or spec.estadoAtual==E.SAINDO) then
        for _,key in ipairs({"colheitadeiraAlvo","caminhaoAlvo"}) do
            if valido(spec[key]) and distancia(trator.rootNode,spec[key].rootNode)<25 then
                velocidadeAlvo=math.min(velocidadeAlvo,TI.CONFIG.velocidadeManobraPerto)
            end
        end
    end
    if velocidadeAlvo>0 then
        if trator.getLastSpeed~=nil and velocidade(trator)>0.5 and trator.movingDirection~=nil
            and ((moveForwards and trator.movingDirection<0) or (not moveForwards and trator.movingDirection>0)) then
            velocidadeAlvo=0
            spec.mensagemNavegacao="Parando para corrigir o alinhamento"
        end
    end
    if velocidadeAlvo>0 then
        if TIProtecao==nil then
            velocidadeAlvo=0
            spec.mensagemNavegacao="Protecao de proximidade nao carregada"
        else
            local ok,limit,reason,kind=pcall(TIProtecao.limitar,trator,dt,x,z,velocidadeAlvo,moveForwards)
            if ok then
                if limit==0 and kind=="talhao" and moveForwards and not spec.centralizando then
                    local best,bestX,bestZ,bestLimit=-math.huge,nil,nil,nil
                    for _,side in ipairs({-1,1}) do
                        local cx,_,cz=localToWorld(steeringNode,side*12,0,12)
                        if TITalhao.contem(spec.talhao,cx,cz,2) then
                            local safe,speed=pcall(TIProtecao.limitar,trator,dt,cx,cz,math.min(velocidadeAlvo,TI.CONFIG.velocidadeManobra),true)
                            local score=TITalhao.distancia(spec.talhao,cx,cz)
                            if safe and speed>0 and score>best then best,bestX,bestZ,bestLimit=score,cx,cz,speed end
                        end
                    end
                    if bestX~=nil then
                        x,z,limit,reason=bestX,bestZ,bestLimit,"Manobrando para dentro do talhao"
                        spec.ladoManobra=nil
                    end
                end
                velocidadeAlvo=limit
                spec.mensagemNavegacao=reason
            else
                velocidadeAlvo=0
                spec.mensagemNavegacao="Nao foi possivel medir a proximidade dos veiculos"
                if Logging~=nil and Logging.warning~=nil and spec.erroProtecao~=tostring(limit) then
                    Logging.warning("[Transbordo Inteligente] Protecao de proximidade: %s",tostring(limit))
                end
                spec.erroProtecao=tostring(limit)
            end
        end
    end
    lx,_,lz=worldToLocal(steeringNode,x,y,z)
    AIVehicleUtil.driveToPoint(trator, dt, 1, velocidadeAlvo > 0, moveForwards, lx, lz, velocidadeAlvo)
    return velocidadeAlvo>0
end

local function parar(trator, dt)
    if AIVehicleUtil ~= nil and AIVehicleUtil.driveToPoint ~= nil then
        local x, _, z = localToWorld(direcao(trator), 0, 0, 5)
        TI.dirigir(trator, dt or 16, x, z, 0)
    end
end

local function retentar(trator, mensagem)
    local spec=trator.spec_transbordoInteligente
    local nextState=spec.caminhaoAlvo~=nil and E.APROXIMANDO_CARRETA or E.APROXIMANDO
    if spec.estadoAtual==E.SAINDO then nextState=E.SAINDO end
    if spec.colheitadeiraAlvo==nil and spec.caminhaoAlvo==nil then
        local cargo=TI.getCarga(spec.bazuca)
        nextState=cargo~=nil and cargo.percentual>=TI.CONFIG.cheio and E.BUSCANDO_CARRETA or E.BUSCANDO
    end
    setDescarga(spec.bazuca,false)
    TI.mudarEstado(trator,E.RETOMANDO,mensagem.." Nova tentativa automatica.")
    spec.estadoRetomar,spec.retomadaEm=nextState,TI.CONFIG.intervaloRetentativa
end

-- Posicao desejada do NO DE DIRECAO do trator para alinhar cano e fillRoot.
function TI.alvoReceber(trator, colheitadeira)
    local spec = trator.spec_transbordoInteligente
    local carga, grao = TI.getCarga(spec.bazuca), TI.getCarga(colheitadeira)
    if carga == nil or grao == nil or grao.node.node == nil then return nil end
    local fx,fy,fz,receptor=TI.pontoEnchimento(spec.bazuca,carga.index)
    if fx==nil then return nil end
    local rx, _, rz = worldToLocal(direcao(trator),fx,fy,fz)
    local px, _, pz = getWorldTranslation(grao.node.node)
    local dx, _, dz = localDirectionToWorld(direcao(colheitadeira), 0, 0, 1)
    local nx, _, nz = localDirectionToWorld(direcao(colheitadeira), 1, 0, 0)
    local canoX = select(1, localToLocal(grao.node.node, direcao(colheitadeira), 0, 0, 0))
    if math.abs(canoX) < 1 then return nil end
    local lado = canoX > 0 and 1 or -1
    -- O ponto vem dos nos reais; dimensoes genericas ou largura da plataforma
    -- nao substituem a posicao do cano e do receptor.
    spec.ladoCano = lado
    spec.alcanceCano=math.abs(canoX)
    local targetX,targetZ=px-nx*rx-dx*rz,pz-nz*rx-dz*rz
    local receiver,index
    if colheitadeira.getDischargeTargetObject~=nil then receiver,index=colheitadeira:getDischargeTargetObject(grao.node) end
    spec.recebimentoConfirmado=receiver==spec.bazuca and index==carga.index
        and colheitadeira.getCanDischargeToObject~=nil and colheitadeira:getCanDischargeToObject(grao.node)==true
    -- O primeiro raio de descarga nao e o centro da bazuca. Mantem o centro
    -- como alvo; a protecao limita a velocidade sem mudar esse alinhamento.
    return targetX,targetZ,dx,dz,receptor
end

local function erroPosicao(trator, x, z, dx, dz)
    local tx, _, tz = getWorldTranslation(direcao(trator))
    local ex, ez = x-tx, z-tz
    local hx, _, hz = localDirectionToWorld(direcao(trator), 0, 0, 1)
    return ex*dx + ez*dz, ex*dz - ez*dx, hx*dx + hz*dz
end

function TI.entradaColheitadeira(trator,dt,combine,x,z,dx,dz)
    local spec=trator.spec_transbordoInteligente
    if spec.entradaPelaTraseira then return true end
    local ax,az=x-dx*TI.CONFIG.recuoAproximacao,z-dz*TI.CONFIG.recuoAproximacao
    if TIProtecao==nil then
        parar(trator,dt);spec.mensagemNavegacao="Protecao de proximidade nao carregada";return false
    end
    local ok,bx,bz=pcall(TIProtecao.aproximacao,trator,combine,x,z,dx,dz,18)
    local okFar,farX,farZ=pcall(TIProtecao.aproximacao,trator,combine,x,z,dx,dz,TI.CONFIG.recuoAproximacao)
    if not ok or not okFar or bx==nil or farX==nil then
        parar(trator,dt);spec.mensagemNavegacao="Sem espaco dentro do talhao para entrar por tras";return false
    end
    ax,az=farX,farZ
    local tx,_,tz=getWorldTranslation(direcao(trator))
    local longitudinal,lateral,alignment=erroPosicao(trator,x,z,dx,dz)
    local limiteTraseiro=(x-bx)*dx+(z-bz)*dz
    local chegou=(tx-ax)^2+(tz-az)^2<16
    local jaAtras=longitudinal>=limiteTraseiro and math.abs(lateral)<1.5 and alignment>0.9
    if chegou or jaAtras then
        spec.entradaPelaTraseira,spec.aproximacaoConcluida=true,true
        return true
    end
    -- Se ja chegou paralelo ao lado do cano, recua em linha reta para a zona
    -- traseira. Evita tentar dar uma volta com a bazuca encostada na maquina.
    if alignment>0.995 and math.abs(lateral)<0.6 and longitudinal<limiteTraseiro
        and limiteTraseiro-longitudinal<=50 then
        local hx,_,hz=localDirectionToWorld(direcao(trator),0,0,1)
        local back=limiteTraseiro-longitudinal+0.5
        spec.mensagem="Reposicionando atras; recebimento sera para frente"
        spec.reposicionando=true
        TI.dirigir(trator,dt,tx-hx*back,tz-hz*back,TI.CONFIG.velocidadeReposicionar,false)
        return false
    end
    spec.mensagem="Entrando por tras da colheitadeira"
    -- Ao precisar dar a volta, inicia o giro para fora da colheitadeira.
    local _,_,behind=worldToLocal(direcao(trator),ax,0,az)
    if behind < -1 and spec.ladoManobra==nil then
        local cx,cy,cz=getWorldTranslation(combine.rootNode)
        local towardCombine=select(1,worldToLocal(direcao(trator),cx,cy,cz))
        spec.ladoManobra=towardCombine>0 and -1 or 1
    end
    TI.dirigir(trator,dt,ax,az,TI.CONFIG.velocidadeViagem,true,true)
    return false
end

function TI.alvoDescarregar(trator, carreta, index,somenteAvaliar)
    local spec = trator.spec_transbordoInteligente
    local carga = TI.getCarga(spec.bazuca)
    local px,_,pz=TI.pontoEnchimento(carreta,index)
    if carga == nil or carga.node.node == nil or px == nil then return nil end
    local ox, _, oz = localToLocal(carga.node.node, direcao(trator), 0, 0, 0)
    spec.alcanceCano=math.abs(ox)
    local baseX,_,baseZ=localDirectionToWorld(carreta.rootNode,0,0,1)
    local previous=not somenteAvaliar and spec.caminhaoAlvo==carreta and spec.indiceCarreta==index and spec.sentidoDestino or nil
    local sentido
    if previous~=nil and TIProtecao~=nil then
        local dx,dz=baseX*previous,baseZ*previous
        local gx,gz=px-dz*ox-dx*oz,pz+dx*ox-dz*oz
        local ok,inside=pcall(TIProtecao.posicaoNoTalhao,trator,gx,gz,math.atan2(dx,dz))
        if ok and inside then sentido=previous end
    end
    if sentido==nil then
        local tx,ty,tz=getWorldTranslation(direcao(trator))
        local hx,_,hz=localDirectionToWorld(direcao(trator),0,0,1)
        local actualSide=select(1,worldToLocal(carreta.rootNode,tx,ty,tz))
        local best=math.huge
        for _,sign in ipairs({1,-1}) do
            local dx,dz=baseX*sign,baseZ*sign
            local gx,gz=px-dz*ox-dx*oz,pz+dx*ox-dz*oz
            local side=select(1,worldToLocal(carreta.rootNode,gx,ty,gz))
            local score=math.sqrt((gx-tx)^2+(gz-tz)^2)+30*(1-hx*dx-hz*dz)
            if sign==previous then score=score-20 end
            if actualSide*side<0 and math.abs(actualSide)>1 then score=score+80 end
            local fieldSafe=TIProtecao~=nil and spec.talhao~=nil
            if TIProtecao~=nil then
                local ok,free=pcall(TIProtecao.posicaoLivre,trator,carreta,gx,gz,math.atan2(dx,dz))
                if not ok or not free then score=score+500 end
                local own=TIProtecao.geometria(trator,nil)
                local okField,inside=pcall(TIProtecao.posicaoNoTalhao,trator,gx,gz,math.atan2(dx,dz),own)
                fieldSafe=okField and inside
            end
            if fieldSafe and score<best then best=score;sentido=sign end
        end
    end
    if sentido==nil then return nil end
    if not somenteAvaliar then spec.sentidoDestino=sentido end
    local dx,dz=baseX*sentido,baseZ*sentido
    local nx,nz=dz,-dx
    return px - nx*ox - dx*oz, pz - nz*ox - dz*oz, dx, dz
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
    local combine = spec.colheitadeiraAlvo or spec.caminhaoAlvo
    if valido(combine) then
        local cx, cy, cz = getWorldTranslation(direcao(trator))
        local lx, _, lz = worldToLocal(direcao(combine), cx, cy, cz)
        local sinal = lx >= 0 and 1 or -1
        local ok,g=true,nil
        if TIProtecao~=nil then ok,g=pcall(TIProtecao.geometria,trator,combine) end
        if not ok then
            setDescarga(spec.bazuca,false);parar(trator,16)
            spec.mensagemNavegacao="Aguardando medidas validas para sair da lateral";return
        end
        spec.saidaDeRe=g~=nil and g.larguraPlataforma>0
        local fx,_,fz=localDirectionToWorld(direcao(trator),0,0,1)
        local nx,_,nz=localDirectionToWorld(direcao(combine),1,0,0)
        local x,z
        if spec.saidaDeRe then
            x,z=cx-fx*12,cz-fz*12
        else
            x,z=cx+fx*12+nx*sinal*4,cz+fz*12+nz*sinal*4
        end
        if not TITalhao.contem(spec.talhao,x,z,TI.CONFIG.folgaManobraTalhao) and not spec.saidaDeRe then
            x,z=TITalhao.pontoInterno(spec.talhao,x,z,TI.CONFIG.folgaManobraTalhao)
        end
        if x==nil then
            parar(trator,16);spec.mensagemNavegacao="Sem espaco no talhao para sair da lateral";return
        end
        spec.saidaX, spec.saidaZ, spec.depoisSaida = x, z, proximoEstado
        TI.mudarEstado(trator, E.SAINDO)
    else
        liberarColheitadeira(trator)
        if proximoEstado==E.BUSCANDO then liberarCarreta(trator) end
        TI.mudarEstado(trator, proximoEstado)
    end
end

function TI.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Drivable, specializations)
        and SpecializationUtil.hasSpecialization(Motorized, specializations)
        and SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function TI.registerEventListeners(vehicleType)
    for _, nome in ipairs({"onLoad", "onLoadFinished", "onRegisterActionEvents", "onUpdate", "onDraw", "onDelete"}) do
        SpecializationUtil.registerEventListener(vehicleType, nome, TI)
    end
end

function TI.registerOverwrittenFunctions(vehicleType)
    -- getIsActive pode ser herdada de Vehicle, fora de vehicleType.functions.
    -- Tentar sobrescrever uma funcao nao registrada pode impedir todo o tipo de carregar.
    if vehicleType.functions ~= nil and vehicleType.functions.getIsActive ~= nil then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsActive", TI.getIsActive)
    end
end

function TI:getIsActive(superFunc, ...)
    local spec = self.spec_transbordoInteligente
    if spec ~= nil and spec.isAtivo then return true end
    return superFunc(self, ...)
end

function TI:onLoad(savegame)
    self.spec_transbordoInteligente = {isAtivo=false, estadoAtual=E.INATIVO, actionEvents={},
        tempoEstado=0, buscaEm=0, tempoSemFluxo=0,tempoTotal=0,destinosIgnorados={}}
end

function TI:onLoadFinished()
    if not TI.carregamentoInformado and Logging ~= nil then
        TI.carregamentoInformado = true
        Logging.info("[Transbordo Inteligente] v0.8.0.0 carregada. Restrito ao talhao atual, alinhamento preciso e manobra ate 8 km/h. Atalhos: Ctrl+Alt+T / Ctrl+Alt+D.")
        if InputAction == nil or InputAction.TI_TOGGLE_TRANSBORDO == nil then
            Logging.warning("[Transbordo Inteligente] Acao ausente. Confira modDesc.xml e remova copias antigas do mod.")
        end
    end
end

function TI:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    local spec = self.spec_transbordoInteligente
    if not self.isClient or spec == nil then return end
    self:clearActionEventsTable(spec.actionEvents)
    if not (isActiveForInput or isActiveForInputIgnoreSelection) then return end
    local action = InputAction ~= nil and (InputAction.TI_TOGGLE_TRANSBORDO or InputAction.TOGGLE_TRANSBORDO) or nil
    if action == nil then
        if Logging ~= nil then Logging.warning("[Transbordo Inteligente] Nao foi possivel registrar o atalho: acao ausente.") end
        return
    end
    local _, id = self:addActionEvent(spec.actionEvents, action,
        self, TI.actionEventToggleTransbordo, false, true, false, true)
    if id ~= nil then
        g_inputBinding:setActionEventTextVisibility(id, true)
        g_inputBinding:setActionEventText(id, "Ligar/desligar Transbordo Inteligente")
        if GS_PRIO_HIGH ~= nil then g_inputBinding:setActionEventTextPriority(id, GS_PRIO_HIGH) end
        if not TI.atalhoInformado and g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil
            and FSBaseMission ~= nil then
            TI.atalhoInformado = true
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
                "Transbordo Inteligente 0.8.0.0: Ctrl+Alt+T automatico; Ctrl+Alt+D levar carga a carreta.")
        end
    elseif Logging ~= nil then
        Logging.warning("[Transbordo Inteligente] A engine recusou o evento de entrada no veiculo.")
    end
    local force=InputAction.TI_FORCE_UNLOAD
    if force~=nil then
        local _,forceId=self:addActionEvent(spec.actionEvents,force,self,TI.actionEventForcarDescarga,false,true,false,true)
        if forceId~=nil then
            g_inputBinding:setActionEventTextVisibility(forceId,true)
            g_inputBinding:setActionEventText(forceId,"Levar carga da bazuca ate a carreta")
        end
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
    TI.restaurarBloqueioDano(trator)
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
    TI.atualizarBloqueioDano(self)
    spec.descargaAutomaticaOriginal = bazuca.spec_pipe.automaticDischarge
    spec.controleCano = true
    bazuca.spec_pipe.automaticDischarge = false
    spec.talhao = TI.getTalhao(self)
    TI.mudarEstado(self, TI.getCarga(bazuca).percentual >= TI.CONFIG.cheio and E.BUSCANDO_CARRETA or E.BUSCANDO)
    if TI.getCarga(bazuca).percentual>=TI.CONFIG.cheio then TI.selecionarDestino(self) end
    if spec.talhao == nil then avisar(self, "Talhao nao reconhecido. Entre no campo e reative; automatico aguardando.") end
end

function TI:actionEventForcarDescarga(actionName,inputValue)
    if inputValue~=nil and inputValue<=0 then return end
    local spec=self.spec_transbordoInteligente
    if not self.isServer or spec==nil then return end
    if not spec.isAtivo then TI.actionEventToggleTransbordo(self,nil,1) end
    if not spec.isAtivo then return end
    local cargo=TI.getCarga(spec.bazuca)
    if cargo==nil or cargo.percentual<=TI.CONFIG.vazio then avisar(self,"A bazuca esta vazia; aguardando graos.");return end
    spec.destinosIgnorados={}
    TI.selecionarDestino(self)
    if valido(spec.colheitadeiraAlvo) then iniciarSaida(self,E.BUSCANDO_CARRETA)
    else TI.mudarEstado(self,E.BUSCANDO_CARRETA,"Descarga solicitada: localizando carreta compativel") end
    parar(self,16)
end

function TI:onUpdate(dt)
    local spec = self.spec_transbordoInteligente
    if spec == nil or not spec.isAtivo or not self.isServer then return end
    if self.raiseActive ~= nil then self:raiseActive() end
    spec.tempoEstado = spec.tempoEstado + dt
    spec.tempoTotal=(spec.tempoTotal or 0)+dt
    spec.buscaEm = math.max(0, spec.buscaEm-dt)
    local _, conjunto = TI.getConjunto(self)
    if not valido(spec.bazuca) or not conjunto[spec.bazuca] then
        TI.desativar(self); avisar(self, "Transbordo desligado: bazuca desacoplada ou removida."); return
    end
    TI.atualizarBloqueioDano(self)
    spec.mensagemNavegacao=nil
    if self.getIsAIActive ~= nil and self:getIsAIActive() then
        TI.desativar(self); avisar(self, "Transbordo desligado: outro piloto assumiu o trator."); return
    end
    if spec.talhao==nil then
        parar(self,dt);spec.mensagemNavegacao="Talhao nao reconhecido; entre no campo e reative";return
    end
    local carga = TI.getCarga(spec.bazuca)
    if carga == nil then
        setDescarga(spec.bazuca,false);parar(self,dt)
        spec.mensagemNavegacao="Aguardando leitura da carga da bazuca";return
    end
    spec.centralizando,spec.reposicionando=false,false
    TI.atualizarProgresso(self,dt,carga)
    if spec.estadoAtual==E.RETOMANDO then
        parar(self,dt)
        spec.retomadaEm=spec.retomadaEm-dt
        if spec.retomadaEm<=0 then TI.mudarEstado(self,spec.estadoRetomar,"Retomando alinhamento") end
        return
    end
    if spec.estadoAtual==E.PAUSADO then retentar(self,"Retomando controle automatico.");parar(self,dt);return end
    if self.startMotor ~= nil and self.getIsMotorStarted ~= nil and not self:getIsMotorStarted() then
        self:startMotor()
    end
    if spec.estadoAtual ~= E.DESCARREGANDO then setDescarga(spec.bazuca, false) end

    local estado = spec.estadoAtual
    if carga.percentual >= TI.CONFIG.cheio and (estado == E.BUSCANDO or estado == E.APROXIMANDO or estado == E.ACOMPANHANDO or estado==E.AGUARDANDO_CARGA) then
        TI.selecionarDestino(self)
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
            spec.entradaPelaTraseira=false
            TI.reservasColheitadeiras[alvo] = self
            if spec.talhao == nil then spec.talhao = TI.getTalhao(alvo) end
            TI.mudarEstado(self, E.APROXIMANDO)
        end

    elseif estado == E.APROXIMANDO or estado == E.ACOMPANHANDO or estado==E.AGUARDANDO_CARGA then
        local combine = spec.colheitadeiraAlvo
        local grao = TI.getCarga(combine)
        if grao == nil or not mesmaFazenda(self, combine) or not mesmoTalhao(self, combine) then
            liberarColheitadeira(self); TI.mudarEstado(self, E.BUSCANDO); parar(self, dt); return
        end
        if grao.percentual<=TI.CONFIG.vazio then
            if estado==E.APROXIMANDO and distancia(self.rootNode,combine.rootNode)>20 then
                liberarColheitadeira(self);TI.mudarEstado(self,E.BUSCANDO);parar(self,dt);return
            end
            if estado~=E.AGUARDANDO_CARGA then
                TI.mudarEstado(self,E.AGUARDANDO_CARGA,"Aguardando a proxima carga; automatico ligado")
                estado=E.AGUARDANDO_CARGA
            end
            if spec.buscaEm<=0 then
                spec.buscaEm=TI.CONFIG.intervaloBusca
                local other=TI.encontrarColheitadeira(self)
                if other~=nil and other~=combine then iniciarSaida(self,E.BUSCANDO);parar(self,dt);return end
            end
        elseif not aceita(spec.bazuca,carga.index,grao.tipo) then
            iniciarSaida(self,E.BUSCANDO);parar(self,dt);return
        elseif estado==E.AGUARDANDO_CARGA then
            TI.mudarEstado(self,E.APROXIMANDO,"Retomando recebimento")
            estado=E.APROXIMANDO
        end
        if velocidade(combine) > TI.CONFIG.velocidadeMaxColheita then
            retentar(self, "Colheitadeira acima da velocidade de trabalho."); parar(self, dt); return
        end
        if not spec.receptorPreparado then
            prepararRecebimento(spec.bazuca, carga.index); spec.receptorPreparado = true
        end
        abrirCano(combine)
        if combine.spec_pipe == nil or combine.spec_pipe.currentState ~= 2 then
            spec.mensagemNavegacao = "Aguardando abertura do cano da colheitadeira"
            parar(self, dt)
            if spec.tempoSemProgresso > TI.CONFIG.tempoManobra then retentar(self, "Cano da colheitadeira indisponivel.") end
            return
        end
        local x, z, dx, dz = TI.alvoReceber(self, combine)
        if x == nil then retentar(self, "Nao foi possivel localizar o cano ou o receptor da bazuca."); parar(self, dt); return end
        local longitudinal,lateral,alinhamento=erroPosicao(self,x,z,dx,dz)
        spec.erroLongitudinalReceber,spec.erroLateralReceber=longitudinal,lateral
        if estado==E.APROXIMANDO and not TI.entradaColheitadeira(self,dt,combine,x,z,dx,dz) then
            if spec.tempoSemProgresso>TI.CONFIG.tempoManobra then
                retentar(self,"Sem progresso na entrada por tras.");parar(self,dt)
            end
            return
        end
        do
            local posX, posY, posZ = getWorldTranslation(direcao(self))
            local ladoAtual = select(1, worldToLocal(direcao(combine), posX, posY, posZ))
            if spec.ladoCano*ladoAtual <= 0 then
                spec.entradaPelaTraseira=false
                TI.mudarEstado(self, E.APROXIMANDO)
                parar(self, dt)
                return
            end
            local base = velocidade(combine)
            if longitudinal < -TI.CONFIG.limiteCorrecaoRe or (base<0.5 and longitudinal < -TI.CONFIG.toleranciaLongitudinal) then
                spec.entradaPelaTraseira=false
                TI.mudarEstado(self,E.APROXIMANDO);parar(self,dt);return
            end
            local alvo = math.max(0, math.min(TI.CONFIG.velocidadeViagem, base + longitudinal*0.8))
            if alinhamento < 0.7 then alvo = math.min(alvo, TI.CONFIG.velocidadeManobra) end
            if base < 0.5 and math.abs(longitudinal) < TI.CONFIG.toleranciaLongitudinal
                and math.abs(lateral) < TI.CONFIG.toleranciaLateral then alvo = 0 end
            if base<0.5 and longitudinal>=-TI.CONFIG.toleranciaLongitudinal
                and (math.abs(longitudinal)>=TI.CONFIG.toleranciaLongitudinal or math.abs(lateral)>=TI.CONFIG.toleranciaLateral) then
                alvo=math.max(TI.CONFIG.velocidadeMinima,alvo)
            end
            if longitudinal < -2 then alvo = math.max(0, base-3) end
            if alvo>0 then alvo=math.max(TI.CONFIG.velocidadeMinima,alvo) end
            spec.centralizando=math.abs(lateral)<0.7 and alinhamento>0.97 and math.abs(longitudinal)<10
            if estado~=E.AGUARDANDO_CARGA then
                spec.mensagem=string.format("Centralizando sob o cano: longitudinal %.2f m | lateral %.2f m",longitudinal,lateral)
                if math.abs(longitudinal)<TI.CONFIG.toleranciaLongitudinal and math.abs(lateral)<TI.CONFIG.toleranciaLateral then
                    spec.mensagem=spec.recebimentoConfirmado and "Bazuca centralizada sob o cano" or "Bazuca centralizada; aguardando graos no cano"
                end
            end
            -- Segue a linha paralela pelo ponto a frente da projecao atual.
            -- Mirar sempre alem do centro final fazia cruzar a linha do cano.
            local mira=TI.CONFIG.pontoMira-longitudinal
            TI.dirigir(self, dt, x+dx*mira, z+dz*mira, alvo,true,true)
            if estado == E.APROXIMANDO and math.abs(longitudinal) < 2 and math.abs(lateral) < 1 and alinhamento > 0.85 then
                TI.mudarEstado(self, E.ACOMPANHANDO)
            end
            if estado == E.ACOMPANHANDO then
                if spec.ultimaCarga ~= nil and carga.nivel <= spec.ultimaCarga+0.01 then
                    spec.tempoSemFluxo = spec.tempoSemFluxo + dt
                else spec.tempoSemFluxo = 0 end
                spec.ultimaCarga = carga.nivel
                if spec.tempoSemFluxo > TI.CONFIG.tempoSemDescarga
                    and math.abs(longitudinal)<TI.CONFIG.toleranciaLongitudinal and math.abs(lateral)<TI.CONFIG.toleranciaLateral then
                    retentar(self, "Sem recebimento de graos; confira o cano da colheitadeira."); parar(self, dt)
                end
            end
        end
        if (estado==E.APROXIMANDO or estado==E.ACOMPANHANDO) and spec.tempoSemProgresso > TI.CONFIG.tempoManobra
            and (math.abs(longitudinal)>=TI.CONFIG.toleranciaLongitudinal or math.abs(lateral)>=TI.CONFIG.toleranciaLateral) then
            spec.entradaPelaTraseira=false
            retentar(self, "Sem progresso na centralizacao sob o cano."); parar(self, dt)
        end

    elseif estado == E.SAINDO then
        local x, _, z = getWorldTranslation(direcao(self))
        if (x-spec.saidaX)^2+(z-spec.saidaZ)^2 < 16 then
            liberarColheitadeira(self)
            if spec.depoisSaida==E.BUSCANDO then liberarCarreta(self) end
            TI.mudarEstado(self, spec.depoisSaida)
            parar(self, dt)
        elseif spec.tempoSemProgresso > TI.CONFIG.tempoManobra then
            retentar(self, "Tentando liberar a lateral do conjunto."); parar(self, dt)
        else
            TI.dirigir(self,dt,spec.saidaX,spec.saidaZ,
                spec.saidaDeRe and TI.CONFIG.velocidadeRe or TI.CONFIG.velocidadeManobra,not spec.saidaDeRe)
        end

    elseif estado == E.BUSCANDO_CARRETA then
        parar(self, dt)
        if carga.percentual <= TI.CONFIG.vazio then TI.mudarEstado(self, E.BUSCANDO); return end
        if spec.buscaEm > 0 then return end
        spec.buscaEm = TI.CONFIG.intervaloDestino
        local alvo, index = TI.selecionarDestino(self)
        if alvo ~= nil then
            spec.caminhaoAlvo, spec.indiceCarreta = alvo, index
            TI.reservasCarretas[alvo] = self
            TI.mudarEstado(self, E.APROXIMANDO_CARRETA)
        end

    elseif estado == E.APROXIMANDO_CARRETA or estado == E.DESCARREGANDO then
        local carreta = spec.caminhaoAlvo
        if carga.percentual <= TI.CONFIG.vazio then
            setDescarga(spec.bazuca,false)
            iniciarSaida(self,E.BUSCANDO)
            parar(self,dt);return
        end
        if not valido(carreta) or not mesmaFazenda(self, carreta) or not aceita(carreta, spec.indiceCarreta, carga.tipo) then
            liberarCarreta(self); TI.mudarEstado(self, E.BUSCANDO_CARRETA); parar(self, dt); return
        end
        local raiz = carreta.getRootVehicle ~= nil and carreta:getRootVehicle() or carreta
        if velocidade(raiz) >= 1 then
            liberarCarreta(self); TI.mudarEstado(self, E.BUSCANDO_CARRETA); parar(self, dt); return
        end
        abrirCano(spec.bazuca)
        if spec.bazuca.spec_pipe.currentState~=2 then
            parar(self,dt);spec.mensagemNavegacao="Aguardando abertura do cano da bazuca";return
        end
        if not spec.receptorPreparado then
            prepararRecebimento(carreta, spec.indiceCarreta); spec.receptorPreparado = true
        end
        local x, z, dx, dz = TI.alvoDescarregar(self, carreta, spec.indiceCarreta)
        if x == nil then
            spec.destinosIgnorados[carreta]=spec.tempoTotal+10000
            liberarCarreta(self);TI.mudarEstado(self,E.BUSCANDO_CARRETA,"Reposicione a carreta: alinhamento fora do talhao")
            parar(self,dt);return
        end
        if estado == E.APROXIMANDO_CARRETA then
            local longitudinal,lateral,alignment=erroPosicao(self,x,z,dx,dz)
            spec.mensagem=string.format("Alinhando com a carreta: longitudinal %.2f m | lateral %.2f m",longitudinal,lateral)
            if TI.podeDescarregar(self) and math.abs(longitudinal)<TI.CONFIG.toleranciaLongitudinal
                and math.abs(lateral)<TI.CONFIG.toleranciaLateral and alignment>0.97 then
                TI.mudarEstado(self, E.DESCARREGANDO); parar(self, dt); return
            end
            local correcaoReta=math.abs(lateral)<0.6 and alignment>0.97 and longitudinal>=-TI.CONFIG.limiteCorrecaoRe
            if math.abs(lateral)<1.5 and alignment>0.9 and longitudinal<TI.CONFIG.distanciaEntradaDireta
                and (longitudinal>=-TI.CONFIG.toleranciaLongitudinal or correcaoReta) then
                spec.aproximacaoConcluida=true
            end
            if not spec.aproximacaoConcluida then
                local ax, az = x-dx*TI.CONFIG.recuoAproximacao, z-dz*TI.CONFIG.recuoAproximacao
                if TIProtecao~=nil then
                    local ok,measuredX,measuredZ=pcall(TIProtecao.aproximacao,self,carreta,x,z,dx,dz,TI.CONFIG.recuoAproximacao)
                    if not ok or measuredX==nil then parar(self,dt);spec.mensagemNavegacao="Sem espaco no talhao para alinhar com a carreta";return end
                    ax,az=measuredX,measuredZ
                end
                local tx, _, tz = getWorldTranslation(direcao(self))
                if (tx-ax)^2+(tz-az)^2 < 16 then spec.aproximacaoConcluida = true
                else TI.dirigir(self, dt, ax, az, TI.CONFIG.velocidadeViagem) end
            else
                spec.centralizando=math.abs(lateral)<0.7 and alignment>0.97 and math.abs(longitudinal)<10
                local crawl=math.min(TI.CONFIG.velocidadeAlinhamento,math.max(TI.CONFIG.velocidadeMinima,math.abs(longitudinal)*0.7))
                if longitudinal < -TI.CONFIG.toleranciaLongitudinal and math.abs(longitudinal)<=TI.CONFIG.limiteCorrecaoRe
                    and math.abs(lateral)<0.6 and alignment>0.97 then
                    local tx,_,tz=getWorldTranslation(direcao(self))
                    local hx,_,hz=localDirectionToWorld(direcao(self),0,0,1)
                    TI.dirigir(self,dt,tx-hx*math.abs(longitudinal),tz-hz*math.abs(longitudinal),TI.CONFIG.velocidadeRe,false)
                elseif longitudinal < -TI.CONFIG.toleranciaLongitudinal then
                    spec.aproximacaoConcluida=false
                    parar(self,dt)
                else
                    if math.abs(longitudinal)<TI.CONFIG.toleranciaLongitudinal and math.abs(lateral)<TI.CONFIG.toleranciaLateral then
                        crawl=0;spec.mensagem="Alinhado; aguardando receptor da carreta sob o cano"
                    end
                    local mira=TI.CONFIG.pontoMira-longitudinal
                    TI.dirigir(self,dt,x+dx*mira,z+dz*mira,crawl)
                end
            end
            if spec.tempoSemProgresso > TI.CONFIG.tempoManobra then
                retentar(self, "Cano nao alcancou a carreta; confira altura, lado e obstaculos."); parar(self, dt)
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
                spec.destinosIgnorados[carreta]=spec.tempoTotal+10000
                liberarCarreta(self)
                TI.mudarEstado(self,E.BUSCANDO_CARRETA,"Sem fluxo: procurando outra posicao ou carreta")
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
        [E.BUSCANDO_CARRETA]="Busca forcada de carreta para descarregar",
        [E.APROXIMANDO_CARRETA]="Alinhando o cano com a carreta",
        [E.DESCARREGANDO]="Descarregando na carreta",
        [E.SAINDO]="Liberando a lateral do conjunto",
        [E.PAUSADO]="Retomando controle automatico",
        [E.AGUARDANDO_CARGA]="Automatico ligado: aguardando proxima carga",
        [E.RETOMANDO]="Automatico ligado: repetindo alinhamento"
    }
    setTextColor(1, 0.8, 0.1, 1)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    renderText(0.5, 0.85, 0.022, "TRANSBORDO "..TI.VERSAO..": " .. (textos[spec.estadoAtual] or "Ativo"))
    local mensagem = spec.mensagemNavegacao or (spec.estadoAtual==E.BUSCANDO_CARRETA and spec.motivoBuscaDestino) or spec.mensagem
    if mensagem==nil then
        local alvo=spec.caminhaoAlvo or spec.colheitadeiraAlvo
        if valido(alvo) then
            local nome=alvo.getName~=nil and alvo:getName() or "veiculo selecionado"
            local distanciaAlvo=distancia(self.rootNode,alvo.rootNode)
            mensagem=string.format("Alvo: %s | %.0f m",nome or "veiculo selecionado",distanciaAlvo)
        end
    end
    if mensagem ~= nil then renderText(0.5, 0.82, 0.014, mensagem) end
    if spec.alcanceCano~=nil then
        renderText(0.5,0.795,0.013,string.format("Plataforma %.1f m%s | Alcance lateral do cano %.1f m",
            spec.larguraPlataforma or 0,spec.larguraPlataformaEstimada and " (estimada)" or "",spec.alcanceCano))
    end
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end

function TI:onDelete()
    TI.desativar(self)
end
