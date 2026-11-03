-- Navegacao propria: Hybrid A* incremental, somente para frente, sensores FS25.
-- Nunca remove cultura, desliga colisao ou ignora a colheitadeira receptora.
TransbordoNavegacao = {}
local N = TransbordoNavegacao
N.CONFIG = {
    raioGiro = 10, passo = 4, amostra = 1, grade = 2, direcoes = 48,
    margem = 0.6, margemArvore = 2.5, margemBusca = 80, maxNos = 16000,
    consultasPorQuadro = 16, tolerancia = 2.5, desvioRota = 5,
    alvoMoveu = 10, tentarNovamente = 1500, desaceleracao = 2,
    larguraPadrao = 4, comprimentoPadrao = 8, alturaPadrao = 3.5
}
local PI = math.pi
local function angulo(a) return (a + PI) % (2*PI) - PI end
local function atan2(x,z) return math.atan2(x,z) end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function nodeDirecao(v)
    return v.getAIDirectionNode ~= nil and v:getAIDirectionNode() or v.rootNode
end
local function heading(v)
    local x,_,z = localDirectionToWorld(nodeDirecao(v),0,0,1)
    return atan2(x,z)
end
local function norma(x,z) return math.sqrt(x*x+z*z) end

function N.modelo(trator)
    local parts, roots, objects = {}, {}, {}
    local reference = nodeDirecao(trator)
    local a = heading(trator)
    local wagon = trator.spec_transbordoInteligente.bazuca
    for _,v in ipairs(TransbordoInteligente.getConjunto(trator)) do
        local size = v.size or {}
        local x,_,z = localToLocal(v.rootNode,reference,0,0,0)
        local width = math.max(1,size.width or N.CONFIG.larguraPadrao)
        local length = math.max(2,size.length or N.CONFIG.comprimentoPadrao)
        parts[#parts+1] = {ox=x,oz=z,da=angulo(heading(v)-a),
            cx=size.widthOffset or 0,cz=size.lengthOffset or 0,
            hw=width/2+N.CONFIG.margem,hl=length/2+N.CONFIG.margem,
            height=math.max(1,size.height or N.CONFIG.alturaPadrao),
            rebocado=v==wagon and v~=trator and z < -2}
        roots[v.rootNode],objects[v] = true,true
    end
    local radius = N.CONFIG.raioGiro
    if type(trator.maxTurningRadius) == "number" then radius=math.max(radius,trator.maxTurningRadius) end
    return {parts=parts,roots=roots,objects=objects,radius=radius,trator=trator,wagon=wagon}
end

function N.pose(model)
    local x,_,z = getWorldTranslation(nodeDirecao(model.trator))
    return {x=x,z=z,a=heading(model.trator),t=heading(model.wagon)}
end

function N.corpos(model,p)
    local bodies = {}
    for _,part in ipairs(model.parts) do
        local a = p.a+part.da
        local x = p.x+math.cos(p.a)*part.ox+math.sin(p.a)*part.oz
        local z = p.z-math.sin(p.a)*part.ox+math.cos(p.a)*part.oz
        if part.rebocado then
            a=p.t
            x=p.x+math.cos(p.a)*part.ox+math.sin(a)*part.oz
            z=p.z-math.sin(p.a)*part.ox+math.cos(a)*part.oz
        end
        bodies[#bodies+1] = {x=x+math.cos(a)*part.cx+math.sin(a)*part.cz,
            z=z-math.sin(a)*part.cx+math.cos(a)*part.cz,a=a,
            hw=part.hw,hl=part.hl,height=part.height}
    end
    return bodies
end

-- Integracao de um arco e do angulo do implemento rebocado (modelo de barra).
function N.avancar(model,p,curvatura,ds)
    local a = p.a+ds*curvatura
    local x,z
    if math.abs(curvatura)<0.000001 then
        x,z=p.x+math.sin(p.a)*ds,p.z+math.cos(p.a)*ds
    else
        x=p.x+(math.cos(p.a)-math.cos(a))/curvatura
        z=p.z+(math.sin(a)-math.sin(p.a))/curvatura
    end
    local t=p.t
    for _,part in ipairs(model.parts) do
        if part.rebocado then
            t=angulo(t+ds*math.sin(p.a-t)/math.max(2,math.abs(part.oz)))
            break
        end
    end
    return {x=x,z=z,a=angulo(a),t=t}
end

local Sensor = {}
Sensor.__index = Sensor

function Sensor:colisao(transformId)
    if transformId == g_currentMission.terrainRootNode then return true end
    if getHasClassId ~= nil and ClassIds ~= nil and ClassIds.TERRAIN_TRANSFORM_GROUP ~= nil
        and getHasClassId(transformId,ClassIds.TERRAIN_TRANSFORM_GROUP) then return true end
    local id=transformId
    local vistos={}
    for _=1,64 do
        if id==nil or id==0 or vistos[id] then break end
        vistos[id]=true
        if self.model.roots[id] then return true end
        local object=(g_currentMission.nodeToObject or {})[id]
        if self.model.objects[object] then return true end
        if object ~= nil and object.getRootVehicle ~= nil and object:getRootVehicle()==self.model.trator then return true end
        if getParent==nil then break end
        id=getParent(id)
    end
    self.blocked=true
    return true
end

function N.sensor(model)
    local s=setmetatable({model=model,readers={}},Sensor)
    if overlapBox==nil or CollisionFlag==nil or getTerrainHeightAtWorldPos==nil
        or g_currentMission==nil or g_currentMission.terrainRootNode==nil then
        return nil,"Sensor de colisao do mapa indisponivel"
    end
    s.mask=0
    for _,flag in ipairs({"DEFAULT","TREE","DYNAMIC_OBJECT","VEHICLE","BUILDING","STATIC_OBJECT"}) do
        if type(CollisionFlag[flag])~="number" then return nil,"Mascara de colisao incompleta" end
        s.mask=s.mask+CollisionFlag[flag]
    end
    if DensityMapModifier==nil or DensityMapModifier.new==nil then return nil,"API DensityMapModifier indisponivel" end
    if DensityMapFilter==nil or DensityMapFilter.new==nil then return nil,"API DensityMapFilter indisponivel" end
    if DensityValueCompareType==nil or DensityValueCompareType.BETWEEN==nil then return nil,"Comparacao de estados de cultura indisponivel" end
    if DensityCoordType==nil or DensityCoordType.POINT_POINT_POINT==nil then return nil,"Coordenadas de cultura indisponiveis" end
    if g_fruitTypeManager==nil or type(g_fruitTypeManager.fruitTypes)~="table" then
        return nil,"Cadastro de tipos de cultura indisponivel"
    end
    for _,fruit in pairs(g_fruitTypeManager.fruitTypes or {}) do
        local name=string.upper(fruit.name or "")
        -- Capim/prado do mapa nao sao floresta. Todas as culturas restantes sao protegidas.
        if name~="GRASS" and name~="MEADOW" then
            local id,first,channels
            local legacy=false
            if type(fruit.getDataPlaneInfo)=="function" then
                -- FS25: nao existe dependencia de g_currentMission.fruits.
                local ok
                ok,id,first,channels=pcall(fruit.getDataPlaneInfo,fruit)
                if not ok then return nil,"Falha em getDataPlaneInfo: "..name end
            elseif fruit.terrainDataPlaneId~=nil then
                id,first,channels=fruit.terrainDataPlaneId,fruit.startStateChannel,fruit.numStateChannels
            elseif g_currentMission.fruits~=nil and g_currentMission.fruits[fruit.index]~=nil then
                -- Compatibilidade com descritores antigos de mods; nunca e requisito.
                id=g_currentMission.fruits[fruit.index].id
                first,channels=fruit.startStateChannel,fruit.numStateChannels
                legacy=true
            else
                return nil,"Dados da cultura ausentes: "..name.." (getDataPlaneInfo)"
            end
            -- Uma cultura registrada sem layer neste mapa nao precisa ser consultada.
            if id~=nil and id~=0 then
                local maximum=fruit.numGrowthStates
                if type(id)~="number" or type(first)~="number" or type(channels)~="number"
                    or type(maximum)~="number" or maximum<1 or maximum>1024
                    or channels<1 or channels>16 or maximum>2^channels-1
                    or maximum~=math.floor(maximum) then
                    return nil,"Estados ou canais de cultura invalidos: "..name
                end
                local ok,reader=pcall(function()
                    -- Modificadores proprios: nao altera filtros compartilhados da engine.
                    local modifier=DensityMapModifier.new(id,first,channels,g_currentMission.terrainRootNode)
                    local filters={}
                    local start
                    for state=1,maximum+1 do
                        local cut=false
                        if state<=maximum then
                            if type(fruit.getIsCut)=="function" then cut=fruit:getIsCut(state)==true
                            elseif type(fruit.cutStates)=="table" then cut=fruit.cutStates[state]~=nil
                            elseif legacy and type(fruit.cutState)=="number" then cut=state==fruit.cutState+1 end
                        end
                        local protected=state<=maximum and not cut
                        if protected and start==nil then start=state end
                        if not protected and start~=nil then
                            local filter=DensityMapFilter.new(modifier)
                            filter:setValueCompareParams(DensityValueCompareType.BETWEEN,start,state-1)
                            filters[#filters+1]=filter
                            start=nil
                        end
                    end
                    if #filters==0 then error("Nenhum estado de crescimento protegido") end
                    return {modifier=modifier,filters=filters}
                end)
                if not ok then return nil,"Falha ao preparar estados de cultura: "..name end
                s.readers[#s.readers+1]=reader
            end
        end
    end
    return s
end

function Sensor:consultar(body)
    local y=getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode,body.x,0,body.z)
    if type(y)~="number" or y~=y then return nil,"Altura do terreno indisponivel" end
    self.blocked=false
    overlapBox(body.x,y+0.3+body.height/2,body.z,0,body.a,0,body.hw,body.height/2,body.hl,
        "colisao",self,self.mask,true,true,true,true)
    if self.blocked then return false,"Obstaculo" end
    -- Faixa adicional em volta das arvores: evita costurar uma rota dentro da mata.
    local m=N.CONFIG.margemArvore
    overlapBox(body.x,y+0.3+body.height/2,body.z,0,body.a,0,body.hw+m,body.height/2,body.hl+m,
        "colisao",self,CollisionFlag.TREE,true,true,true,true)
    if self.blocked then return false,"Arvore / borda de mata" end
    local nx,nz=math.cos(body.a),-math.sin(body.a)
    local dx,dz=math.sin(body.a),math.cos(body.a)
    local x1,z1=body.x-nx*body.hw-dx*body.hl,body.z-nz*body.hw-dz*body.hl
    local x2,z2=x1+nx*body.hw*2,z1+nz*body.hw*2
    local x3,z3=x1+dx*body.hl*2,z1+dz*body.hl*2
    for _,reader in ipairs(self.readers) do
        reader.modifier:setParallelogramWorldCoords(x1,z1,x2,z2,x3,z3,DensityCoordType.POINT_POINT_POINT)
        for _,filter in ipairs(reader.filters) do
            local value,area=reader.modifier:executeGet(filter)
            local count=area~=nil and area or value
            if type(count)~="number" or count~=count then return nil,"Resposta de cultura invalida" end
            if count>0 then return false,"Cultura em pe" end
        end
    end
    return true
end

function Sensor:livre(p)
    for _,body in ipairs(N.corpos(self.model,p)) do
        local ok,clear,reason=pcall(self.consultar,self,body)
        if not ok then self.error="Falha na consulta dos sensores"; return nil,self.error end
        if clear==nil then self.error=reason; return nil,reason end
        if not clear then return false,reason end
    end
    return true
end

-- Fila binaria do A*. Nenhuma dependencia de mods externos.
local function push(heap,node)
    local i=#heap+1
    while i>1 do
        local parent=math.floor(i/2)
        if heap[parent].f<=node.f then break end
        heap[i]=heap[parent]; i=parent
    end
    heap[i]=node
end
local function pop(heap)
    local first,last=heap[1],table.remove(heap)
    if #heap>0 then
        local i=1
        while i*2<=#heap do
            local child=i*2
            if child<#heap and heap[child+1].f<heap[child].f then child=child+1 end
            if heap[child].f>=last.f then break end
            heap[i]=heap[child]; i=child
        end
        heap[i]=last
    end
    return first
end
local function key(p)
    local function cell(v) return math.floor(v/N.CONFIG.grade+0.5) end
    local bins=N.CONFIG.direcoes
    return cell(p.x)..":"..cell(p.z)..":"..math.floor((p.a%(2*PI))*bins/(2*PI))
        ..":"..math.floor((p.t%(2*PI))*bins/(2*PI))
end

function N.criarBusca(model,sensor,start,goal)
    -- O ambiente Lua do FS25 pode nao expor a biblioteca coroutine.
    -- Todo o progresso (inclusive a amostra dentro de uma curva) fica nesta tabela.
    local samples=math.max(1,math.ceil(N.CONFIG.passo/N.CONFIG.amostra))
    return {model=model,sensor=sensor,start=start,goal=goal,heap={},best={},count=0,
        samples=samples,ds=N.CONFIG.passo/samples,started=false,finished=false,
        xmin=math.min(start.x,goal.x)-N.CONFIG.margemBusca,
        xmax=math.max(start.x,goal.x)+N.CONFIG.margemBusca,
        zmin=math.min(start.z,goal.z)-N.CONFIG.margemBusca,
        zmax=math.max(start.z,goal.z)+N.CONFIG.margemBusca}
end

local function terminarBusca(search,path,reason)
    search.finished,search.path,search.reason=true,path,reason
    return true,path,reason
end

local function proximaCurva(search)
    local current=search.current
    current.turn=current.turn+1
    current.q,current.sample=current.parent,0
    if current.turn>3 then search.current=nil end
end

-- Retorna terminou, caminho, motivo. Cada chamada respeita seu orcamento de
-- consultas e operacoes; nenhuma pilha de execucao fica suspensa entre quadros.
function N.atualizarBusca(search)
    if search.finished then return true,search.path,search.reason end
    local budget=math.max(1,math.floor(N.CONFIG.consultasPorQuadro))
    local queries,operations=0,0
    local function heuristic(p) return norma(search.goal.x-p.x,search.goal.z-p.z) end
    search.consultasUltimoQuadro=0
    if not search.started then
        local clear,reason=search.sensor:livre(search.start)
        queries=queries+1
        search.consultasUltimoQuadro=queries
        if not clear then return terminarBusca(search,nil,reason or "Posicao inicial bloqueada") end
        search.start.g,search.start.f=0,heuristic(search.start)
        push(search.heap,search.start)
        search.best[key(search.start)]=0
        search.started=true
    end
    while queries<budget and operations<budget*8 do
        operations=operations+1
        local current=search.current
        if current==nil then
            if #search.heap==0 or search.count>=N.CONFIG.maxNos then
                return terminarBusca(search,nil,"Sem rota livre de cultura e obstaculos dentro do limite de busca")
            end
            local p=pop(search.heap)
            if p.g<=search.best[key(p)]+0.000001 then
                search.count=search.count+1
                local goal=search.goal
                if heuristic(p)<=N.CONFIG.tolerancia and (goal.a==nil or math.abs(angulo(goal.a-p.a))<math.rad(25)) then
                    local path={}
                    while p~=nil do table.insert(path,1,p); p=p.parent end
                    return terminarBusca(search,path)
                end
                search.current={parent=p,q=p,turn=1,sample=0}
            end
        else
            local turn=current.turn==1 and 0 or (current.turn==2 and -1 or 1)
            local q=N.avancar(search.model,current.q,turn/search.model.radius,search.ds)
            if q.x<search.xmin or q.x>search.xmax or q.z<search.zmin or q.z>search.zmax then
                proximaCurva(search)
            else
                local free,reason=search.sensor:livre(q)
                queries=queries+1
                search.consultasUltimoQuadro=queries
                if search.sensor.error~=nil or free==nil then
                    return terminarBusca(search,nil,search.sensor.error or reason or "Falha na leitura do trajeto")
                end
                if not free then
                    proximaCurva(search)
                else
                    current.q,current.sample=q,current.sample+1
                    if current.sample>=search.samples then
                        local p=current.parent
                        q.g=p.g+N.CONFIG.passo*(1+math.abs(turn)*0.08)
                        q.f=q.g+heuristic(q)*1.05
                        q.parent,q.turn=p,turn
                        local k=key(q)
                        if search.best[k]==nil or q.g<search.best[k] then
                            search.best[k]=q.g; push(search.heap,q)
                        end
                        proximaCurva(search)
                    end
                end
            end
        end
    end
    return false,nil,"planejando"
end

function N.reset(trator)
    trator.spec_transbordoInteligente.navegacao=nil
    trator.spec_transbordoInteligente.mensagemNavegacao=nil
end

local function emitir(trator,dt,x,z,speed)
    local node=trator.getAISteeringNode~=nil and trator:getAISteeringNode() or nodeDirecao(trator)
    local _,y=getWorldTranslation(node)
    local lx,_,lz=worldToLocal(node,x,y,z)
    -- Esterco direto no controlador nativo; sem escrita em rotatedTime/cruise.
    AIVehicleUtil.driveToPoint(trator,dt,1,speed>0,true,lx,lz,speed)
end

local function frear(trator,dt,reason)
    local x,_,z=localToWorld(nodeDirecao(trator),0,0,5)
    emitir(trator,dt,x,z,0)
    trator.spec_transbordoInteligente.mensagemNavegacao=reason
    return false
end

function N.verificarFrente(model,sensor,p,x,z,speed)
    local dx,dz=x-p.x,z-p.z
    local right=dx*math.cos(p.a)-dz*math.sin(p.a)
    local curvature=clamp(2*right/math.max(1,dx*dx+dz*dz),-1/model.radius,1/model.radius)
    local current=model.trator.getLastSpeed~=nil and math.abs(model.trator:getLastSpeed()) or 0
    local v=math.max(speed,current)/3.6
    local horizon=math.max(3,v*0.6+v*v/(2*N.CONFIG.desaceleracao))
    local q=p
    local free,reason=sensor:livre(q)
    if not free then return false,reason end
    for _=1,math.ceil(horizon/N.CONFIG.amostra) do
        q=N.avancar(model,q,curvature,N.CONFIG.amostra)
        free,reason=sensor:livre(q)
        if not free then return false,reason end
    end
    return true
end

function N.dirigir(trator,dt,x,z,speed,modo,dx,dz)
    local spec=trator.spec_transbordoInteligente
    local nav=spec.navegacao
    if nav==nil then
        local model=N.modelo(trator)
        local ok,sensor,reason=pcall(N.sensor,model)
        if not ok or sensor==nil then return frear(trator,dt,reason or "Sensores indisponiveis") end
        nav={model=model,sensor=sensor,clock=0,retry=0}
        spec.navegacao=nav
    end
    nav.clock=nav.clock+dt
    local pose=N.pose(nav.model)
    if modo=="seguir" then
        local safe,reason=N.verificarFrente(nav.model,nav.sensor,pose,x,z,speed)
        if not safe then return frear(trator,dt,"Aguardando faixa livre: "..(reason or "sensor indisponivel")) end
        spec.mensagemNavegacao=nil
        emitir(trator,dt,x,z,speed)
        return true
    end
    local goal={x=x,z=z,a=dx~=nil and atan2(dx,dz) or nil}
    if nav.path~=nil then
        local moved=norma(nav.goal.x-x,nav.goal.z-z)>N.CONFIG.alvoMoveu
        moved=moved or (goal.a~=nil and nav.goal.a~=nil and math.abs(angulo(goal.a-nav.goal.a))>math.rad(25))
        local p=nav.path[math.min(nav.index,#nav.path)]
        local last=nav.path[math.max(1,nav.index-1)]
        -- O veiculo deve continuar perto de algum ponto do segmento atual.
        local distance=math.min(norma(pose.x-p.x,pose.z-p.z),norma(pose.x-last.x,pose.z-last.z))
        if moved or distance>N.CONFIG.desvioRota then nav.path=nil; nav.search=nil end
    end
    if nav.path==nil then
        if nav.clock<nav.retry then return frear(trator,dt,"Aguardando rota livre") end
        -- Protege tanto a criacao quanto o avanco: uma falha nao pode escapar
        -- do update, impedir a frenagem e se repetir a cada quadro no log.
        local ok,done,result,reason=pcall(function()
            if nav.search==nil then
                nav.goal=goal
                nav.search=N.criarBusca(nav.model,nav.sensor,pose,goal)
            end
            return N.atualizarBusca(nav.search)
        end)
        if not ok then
            nav.search=nil; nav.retry=nav.clock+N.CONFIG.tentarNovamente
            local message=tostring(done)
            if spec.ultimoErroPlanejador~=message and Logging~=nil and Logging.warning~=nil then
                Logging.warning("[Transbordo Inteligente] Planejamento interrompido: %s",message)
            end
            spec.ultimoErroPlanejador=message
            return frear(trator,dt,"Falha no planejamento; confira log.txt")
        end
        spec.ultimoErroPlanejador=nil
        if not done then return frear(trator,dt,"Calculando rota sem pisar na cultura") end
        nav.search=nil
        if result==nil then
            nav.retry=nav.clock+N.CONFIG.tentarNovamente
            return frear(trator,dt,reason or "Rota bloqueada")
        end
        nav.path,nav.index=result,2
    end
    while nav.index<=#nav.path and norma(pose.x-nav.path[nav.index].x,pose.z-nav.path[nav.index].z)<N.CONFIG.tolerancia do
        nav.index=nav.index+1
    end
    if nav.index>#nav.path then
        nav.path=nil
        return frear(trator,dt,nil)
    end
    local target=nav.path[nav.index]
    local bearing=atan2(target.x-pose.x,target.z-pose.z)
    local steer=math.abs(angulo(bearing-pose.a))
    local emCurva=steer>math.rad(15) or (target.turn~=nil and target.turn~=0)
    local maxSpeed=emCurva and math.min(speed,5) or speed
    if steer>math.rad(75) then
        nav.path=nil
        return frear(trator,dt,"Realinhando rota para evitar curva fechada")
    end
    local safe,reason=N.verificarFrente(nav.model,nav.sensor,pose,target.x,target.z,maxSpeed)
    if not safe and maxSpeed>5 and (trator.getLastSpeed==nil or math.abs(trator:getLastSpeed())<=5) then
        -- Em curva apertada, tenta uma previsao curta apenas depois de ja estar lento.
        maxSpeed=5
        safe,reason=N.verificarFrente(nav.model,nav.sensor,pose,target.x,target.z,maxSpeed)
    end
    if not safe then
        nav.path=nil; nav.search=nil; nav.retry=nav.clock+N.CONFIG.tentarNovamente
        return frear(trator,dt,"Freando e recalculando: "..(reason or "sensor indisponivel"))
    end
    spec.mensagemNavegacao=nil
    emitir(trator,dt,target.x,target.z,maxSpeed)
    return true
end
