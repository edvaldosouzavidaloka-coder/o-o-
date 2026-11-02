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
    if DensityMapModifier==nil or DensityMapFilter==nil or DensityValueCompareType==nil
        or DensityCoordType==nil or g_fruitTypeManager==nil or g_currentMission.fruits==nil then
        return nil,"Leitura de cultura indisponivel"
    end
    for _,fruit in pairs(g_fruitTypeManager.fruitTypes or {}) do
        local name=string.upper(fruit.name or "")
        local data=g_currentMission.fruits[fruit.index]
        -- Capim/prado do mapa nao sao floresta. Todas as culturas restantes sao protegidas.
        if name~="GRASS" and name~="MEADOW" and data~=nil and data.id~=nil and data.id~=0 then
            if fruit.startStateChannel==nil or fruit.numStateChannels==nil or fruit.numGrowthStates==nil then
                return nil,"Estados da cultura nao informados pelo mapa"
            end
            local ok,reader=pcall(function()
                local modifier=DensityMapModifier.new(data.id,fruit.startStateChannel,fruit.numStateChannels,g_currentMission.terrainRootNode)
                local filter=DensityMapFilter.new(modifier)
                filter:setValueCompareParams(DensityValueCompareType.BETWEEN,1,fruit.numGrowthStates)
                local cut
                if type(fruit.cutState)=="number" then
                    cut=DensityMapFilter.new(modifier)
                    cut:setValueCompareParams(DensityValueCompareType.NOT_EQUAL,fruit.cutState+1)
                end
                return {modifier=modifier,filter=filter,cut=cut}
            end)
            if not ok then return nil,"Falha ao preparar leitura dos estados da cultura" end
            s.readers[#s.readers+1]=reader
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
        local value,area=reader.modifier:executeGet(reader.filter,reader.cut)
        local count=area~=nil and area or value
        if type(count)~="number" or count~=count then return nil,"Resposta de cultura invalida" end
        if count>0 then return false,"Cultura em pe" end
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
    return coroutine.create(function()
        local heap,best={},{}
        local count,queries=0,0
        local xmin,xmax=math.min(start.x,goal.x)-N.CONFIG.margemBusca,math.max(start.x,goal.x)+N.CONFIG.margemBusca
        local zmin,zmax=math.min(start.z,goal.z)-N.CONFIG.margemBusca,math.max(start.z,goal.z)+N.CONFIG.margemBusca
        local function heuristic(p) return norma(goal.x-p.x,goal.z-p.z) end
        local function check(p)
            queries=queries+1
            if queries>N.CONFIG.consultasPorQuadro then
                queries=1; coroutine.yield("planejando")
            end
            return sensor:livre(p)
        end
        local clear,reason=check(start)
        if not clear then return nil,reason or "Posicao inicial bloqueada" end
        start.g,start.f=0,heuristic(start)
        push(heap,start); best[key(start)]=0
        while #heap>0 and count<N.CONFIG.maxNos do
            local p=pop(heap)
            if p.g<=best[key(p)]+0.000001 then
                count=count+1
                if heuristic(p)<=N.CONFIG.tolerancia and (goal.a==nil or math.abs(angulo(goal.a-p.a))<math.rad(25)) then
                    local path={}
                    while p~=nil do table.insert(path,1,p); p=p.parent end
                    return path
                end
                for _,turn in ipairs({0,-1,1}) do
                    local q=p
                    local valid=true
                    local ds=N.CONFIG.passo/math.ceil(N.CONFIG.passo/N.CONFIG.amostra)
                    for _=1,math.ceil(N.CONFIG.passo/N.CONFIG.amostra) do
                        q=N.avancar(model,q,turn/model.radius,ds)
                        if q.x<xmin or q.x>xmax or q.z<zmin or q.z>zmax then valid=false; break end
                        local free=check(q)
                        if sensor.error~=nil then return nil,sensor.error end
                        if not free then valid=false; break end
                    end
                    if valid then
                        q.g=p.g+N.CONFIG.passo*(1+math.abs(turn)*0.08)
                        q.f=q.g+heuristic(q)*1.05
                        q.parent,q.turn=p,turn
                        local k=key(q)
                        if best[k]==nil or q.g<best[k] then best[k]=q.g; push(heap,q) end
                    end
                end
            end
        end
        return nil,"Sem rota livre de cultura e obstaculos dentro do limite de busca"
    end)
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
        if nav.search==nil then
            nav.goal=goal
            nav.search=N.criarBusca(nav.model,nav.sensor,pose,goal)
        end
        local ok,result,reason=coroutine.resume(nav.search)
        if not ok then
            nav.search=nil; nav.retry=nav.clock+N.CONFIG.tentarNovamente
            return frear(trator,dt,"Falha no planejamento; movimento interrompido")
        end
        if coroutine.status(nav.search)~="dead" then return frear(trator,dt,"Calculando rota sem pisar na cultura") end
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
