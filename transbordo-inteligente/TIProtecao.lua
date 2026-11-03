-- Protecao local entre os conjuntos selecionados; nao e um planejador de rotas.
-- Usa dimensoes, workAreas e marcadores atuais. Nao le cultura nem usa coroutine.
TIProtecao = {}
local P=TIProtecao
P.CONFIG={margem=0.75,margemPrecisao=0.2,velocidadeRelativaPrecisao=3,reacao=0.7,desaceleracao=2,amostra=0.5,
    margemTalhao=0.35,antecipacaoGiroTalhao=12,raioGiro=10,velocidadePerto=5,velocidadePrecisao=2,
    larguraPadrao=4,comprimentoPadrao=8,larguraPlataformaPadrao=12,
    comprimentoPlataformaPadrao=3}

local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function nodeOk(n) return n~=nil and n~=0 and (entityExists==nil or entityExists(n)) end
local function direction(v) return v.getAIDirectionNode~=nil and v:getAIDirectionNode() or v.rootNode end
local function yaw(n)
    local dx,_,dz=localDirectionToWorld(n,0,0,1)
    return math.atan2(dx,dz)
end
local function speed(v) return v.getLastSpeed~=nil and math.abs(v:getLastSpeed()) or 0 end
local function root(v) return v.getRootVehicle~=nil and v:getRootVehicle() or v end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

-- Cada componente conserva seu proprio retangulo e orientacao. A plataforma
-- nao e incorporada num retangulo gigante que bloquearia a lateral inteira.
function P.medir(v)
    local cutter=v.spec_cutter~=nil
    local size=v.size or {}
    local width=finite(size.width) and size.width>0 and size.width
        or (cutter and P.CONFIG.larguraPlataformaPadrao or P.CONFIG.larguraPadrao)
    local length=finite(size.length) and size.length>0 and size.length
        or (cutter and P.CONFIG.comprimentoPlataformaPadrao or P.CONFIG.comprimentoPadrao)
    local cx=finite(size.widthOffset) and size.widthOffset or 0
    local cz=finite(size.lengthOffset) and size.lengthOffset or 0
    local bounds={xmin=cx-width/2,xmax=cx+width/2,zmin=cz-length/2,zmax=cz+length/2,
        object=v,plataforma=cutter}
    if cutter and not (finite(size.width) and size.width>0) then
        bounds.xmin,bounds.xmax=math.huge,-math.huge
    end
    local function addNode(n)
        if not nodeOk(n) then return end
        local x,_,z=localToLocal(n,v.rootNode,0,0,0)
        if not finite(x) or not finite(z) then error("Marcador de dimensao invalido") end
        bounds.xmin,bounds.xmax=math.min(bounds.xmin,x),math.max(bounds.xmax,x)
        bounds.zmin,bounds.zmax=math.min(bounds.zmin,z),math.max(bounds.zmax,z)
    end
    if cutter then
        for _,area in pairs(v.spec_workArea~=nil and v.spec_workArea.workAreas or {}) do
            if nodeOk(area.start) and nodeOk(area.width) and nodeOk(area.height) then
                addNode(area.start);addNode(area.width);addNode(area.height)
                local ax,_,az=localToLocal(area.start,v.rootNode,0,0,0)
                local bx,_,bz=localToLocal(area.width,v.rootNode,0,0,0)
                local hx,_,hz=localToLocal(area.height,v.rootNode,0,0,0)
                bounds.xmin,bounds.xmax=math.min(bounds.xmin,bx+hx-ax),math.max(bounds.xmax,bx+hx-ax)
                bounds.zmin,bounds.zmax=math.min(bounds.zmin,bz+hz-az),math.max(bounds.zmax,bz+hz-az)
            end
        end
        if v.getAIMarkers~=nil then
            local left,right,back=v:getAIMarkers()
            addNode(left);addNode(right);addNode(back)
        end
    end
    bounds.larguraEstimada=not (finite(size.width) and size.width>0)
    if cutter and finite(bounds.xmin) and finite(bounds.xmax) and bounds.xmax-bounds.xmin>=0.1 then
        bounds.larguraEstimada=false
    end
    if not finite(bounds.xmin) or not finite(bounds.xmax) or bounds.xmax-bounds.xmin<0.1 then
        bounds.xmin,bounds.xmax=cx-width/2,cx+width/2
    end
    bounds.cx,bounds.cz=(bounds.xmin+bounds.xmax)/2,(bounds.zmin+bounds.zmax)/2
    bounds.hw,bounds.hl=(bounds.xmax-bounds.xmin)/2,(bounds.zmax-bounds.zmin)/2
    return bounds
end

local function rectangle(bounds,x,z,a)
    return {x=x+math.cos(a)*bounds.cx+math.sin(a)*bounds.cz,
        z=z-math.sin(a)*bounds.cx+math.cos(a)*bounds.cz,
        a=a,hw=bounds.hw,hl=bounds.hl,object=bounds.object,plataforma=bounds.plataforma}
end

function P.sobrepoe(a,b,margin)
    local arx,arz,afx,afz=math.cos(a.a),-math.sin(a.a),math.sin(a.a),math.cos(a.a)
    local brx,brz,bfx,bfz=math.cos(b.a),-math.sin(b.a),math.sin(b.a),math.cos(b.a)
    for _,axis in ipairs({{arx,arz},{afx,afz},{brx,brz},{bfx,bfz}}) do
        local x,z=axis[1],axis[2]
        local ra=a.hw*math.abs(arx*x+arz*z)+a.hl*math.abs(afx*x+afz*z)
        local rb=b.hw*math.abs(brx*x+brz*z)+b.hl*math.abs(bfx*x+bfz*z)
        if math.abs((b.x-a.x)*x+(b.z-a.z)*z)>ra+rb+margin then return false end
    end
    return true
end

local function partes(v,reference,wagon)
    local result={}
    local a=yaw(reference)
    for _,object in ipairs(TransbordoInteligente.getConjunto(v)) do
        if nodeOk(object.rootNode) then
            local ox,_,oz=localToLocal(object.rootNode,reference,0,0,0)
            local heading=yaw(object.rootNode)
            local drawbar=math.max(2,math.sqrt(ox*ox+oz*oz))
            result[#result+1]={bounds=P.medir(object),ox=ox,oz=oz,da=heading-a,
                heading=heading,tow=object==wagon and object~=v and oz < -2,
                drawbar=drawbar,hitchX=ox+math.sin(heading-a)*drawbar,
                hitchZ=oz+math.cos(heading-a)*drawbar}
        end
    end
    return result
end

local function corpo(part,p,rigid)
    local a=p.a+part.da
    local x=p.x+math.cos(p.a)*part.ox+math.sin(p.a)*part.oz
    local z=p.z-math.sin(p.a)*part.ox+math.cos(p.a)*part.oz
    if part.tow and not rigid then
        a=p.t
        x=p.x+math.cos(p.a)*part.hitchX+math.sin(p.a)*part.hitchZ-math.sin(a)*part.drawbar
        z=p.z-math.sin(p.a)*part.hitchX+math.cos(p.a)*part.hitchZ-math.cos(a)*part.drawbar
    end
    return rectangle(part.bounds,x,z,a)
end

local function avancar(p,curvature,ds,drawbar)
    local a=p.a+curvature*ds
    local x,z
    if math.abs(curvature)<0.000001 then x,z=p.x+math.sin(p.a)*ds,p.z+math.cos(p.a)*ds
    else
        x=p.x+(math.cos(p.a)-math.cos(a))/curvature
        z=p.z+(math.sin(a)-math.sin(p.a))/curvature
    end
    return {x=x,z=z,a=a,t=p.t+ds*math.sin(p.a-p.t)/drawbar}
end

function P.geometria(trator,target)
    local reference=direction(trator)
    local x,_,z=getWorldTranslation(reference)
    local spec=trator.spec_transbordoInteligente
    local own=partes(trator,reference,spec.bazuca)
    local targetRoot=target~=nil and root(target) or trator
    local others={}
    local _,ownSet=TransbordoInteligente.getConjunto(trator)
    local headerWidth,estimated=0,false
    local combineRef=direction(targetRoot)
    local left,right=math.huge,-math.huge
    for _,object in ipairs(TransbordoInteligente.getConjunto(targetRoot)) do
        if not ownSet[object] and nodeOk(object.rootNode) then
            local bounds=P.medir(object)
            local px,_,pz=getWorldTranslation(object.rootNode)
            others[#others+1]=rectangle(bounds,px,pz,yaw(object.rootNode))
            if bounds.plataforma then
                estimated=estimated or bounds.larguraEstimada
                for _,lx in ipairs({bounds.xmin,bounds.xmax}) do
                    for _,lz in ipairs({bounds.zmin,bounds.zmax}) do
                        local ax=select(1,localToLocal(object.rootNode,combineRef,lx,0,lz))
                        left,right=math.min(left,ax),math.max(right,ax)
                    end
                end
                headerWidth=right-left
            end
        end
    end
    local targetSpeed=target~=nil and speed(targetRoot)/3.6 or 0
    local tx,_,tz=localDirectionToWorld(combineRef,0,0,1)
    local sign=targetRoot.movingDirection~=nil and targetRoot.movingDirection<0 and -1 or 1
    local heading=yaw(reference)
    local drawbar=8
    for _,part in ipairs(own) do if part.tow then drawbar=part.drawbar end end
    return {own=own,others=others,pose={x=x,z=z,a=heading,t=yaw(spec.bazuca.rootNode)},
        vx=tx*targetSpeed*sign,vz=tz*targetSpeed*sign,velocidadeAlvo=targetSpeed*3.6,drawbar=drawbar,
        larguraPlataforma=headerWidth,larguraEstimada=estimated,talhao=spec.talhao}
end

local function livre(g,p,time,margin)
    for _,part in ipairs(g.own) do
        local body=corpo(part,p)
        if g.talhao~=nil and (TITalhao==nil or not TITalhao.retanguloDentro(g.talhao,body,P.CONFIG.margemTalhao)
            or (part.tow and not TITalhao.retanguloDentro(g.talhao,corpo(part,p,true),P.CONFIG.margemTalhao))) then
            return false,"talhao"
        end
        for _,other in ipairs(g.others) do
            local future={x=other.x+g.vx*time,z=other.z+g.vz*time,a=other.a,hw=other.hw,hl=other.hl}
            if P.sobrepoe(body,future,margin or P.CONFIG.margem) then
                return false,other.plataforma and "plataforma" or "veiculo"
            end
        end
    end
    return true
end

local function dentroDoTalhao(g,p)
    if g.talhao==nil then return true end
    for _,part in ipairs(g.own) do
        if not TITalhao.retanguloDentro(g.talhao,corpo(part,p),P.CONFIG.margemTalhao) then return false end
        if part.tow and not TITalhao.retanguloDentro(g.talhao,corpo(part,p,true),P.CONFIG.margemTalhao) then return false end
    end
    return true
end

function P.posicaoLivre(trator,target,x,z,a,margin)
    local g=P.geometria(trator,target)
    return livre(g,{x=x,z=z,a=a or g.pose.a,t=a or g.pose.t},0,margin)
end

function P.posicaoNoTalhao(trator,x,z,a,g)
    g=g or P.geometria(trator,nil)
    if g.talhao==nil or TITalhao==nil then return false end
    local pose={x=x,z=z,a=a or g.pose.a,t=a or g.pose.t}
    for _,part in ipairs(g.own) do
        if not TITalhao.retanguloDentro(g.talhao,corpo(part,pose),P.CONFIG.margemTalhao) then return false end
    end
    return true
end

local function prever(g,x,z,requested,current,dt,moveForwards,margin)
    local p=g.pose
    local dx,dz=x-p.x,z-p.z
    local lateral=dx*math.cos(p.a)-dz*math.sin(p.a)
    local curvature=clamp(2*lateral/math.max(1,dx*dx+dz*dz),-1/P.CONFIG.raioGiro,1/P.CONFIG.raioGiro)
    local v=math.max(current,requested)/3.6
    local horizon=v*(P.CONFIG.reacao+math.min(0.25,dt/1000))+v*v/(2*P.CONFIG.desaceleracao)
    local safe,reason=livre(g,p,0,margin)
    if not safe then return false,reason end
    local steps=math.max(1,math.ceil(horizon/P.CONFIG.amostra))
    local step=horizon/steps
    local ds=moveForwards==false and -step or step
    for i=1,steps do
        p=avancar(p,curvature,ds,g.drawbar)
        safe,reason=livre(g,p,v>0 and i*step/v or 0,margin)
        if not safe then return false,reason end
    end
    -- Frear a tempo nao basta para dar a volta: olha um pouco alem, somente
    -- para a borda, e permite escolher um giro interno antes de ficar sem raio.
    if moveForwards~=false and g.talhao~=nil and dx*dx+dz*dz>100 then
        local reach=0
        for _,part in ipairs(g.own) do
            reach=math.max(reach,math.sqrt(part.ox^2+part.oz^2)+math.sqrt(part.bounds.hw^2+part.bounds.hl^2))
        end
        local extra=P.CONFIG.antecipacaoGiroTalhao-horizon
        if extra>0 and TITalhao.distancia(g.talhao,g.pose.x,g.pose.z)<P.CONFIG.antecipacaoGiroTalhao+reach+P.CONFIG.margemTalhao then
            local n=math.ceil(extra/P.CONFIG.amostra)
            for i=1,n do
                p=avancar(p,curvature,extra/n,g.drawbar)
                if not dentroDoTalhao(g,p) then return false,"talhao" end
            end
        end
    end
    return true
end

function P.limitar(trator,dt,x,z,requested,moveForwards)
    local spec=trator.spec_transbordoInteligente
    local geometries,seen={},{}
    spec.larguraPlataforma,spec.larguraPlataformaEstimada=0,false
    -- O destino pode ser reservado enquanto a bazuca ainda sai da colheitadeira.
    -- Ambos continuam protegidos durante essa transicao.
    for _,key in ipairs({"colheitadeiraAlvo","caminhaoAlvo"}) do
        local target=spec[key]
        if target~=nil and nodeOk(target.rootNode) and not seen[root(target)] then
            seen[root(target)]=true
            local g=P.geometria(trator,target)
            geometries[#geometries+1]=g
            spec.larguraPlataforma=math.max(spec.larguraPlataforma,g.larguraPlataforma)
            spec.larguraPlataformaEstimada=spec.larguraPlataformaEstimada or g.larguraEstimada
        end
    end
    if #geometries==0 then geometries[1]=P.geometria(trator,nil) end
    local current=speed(trator)
    local reason
    local precision=spec.centralizando or spec.reposicionando
    local matching=precision and spec.colheitadeiraAlvo~=nil and speed(root(spec.colheitadeiraAlvo)) or 0
    local relativeLimit=math.min(requested,matching+P.CONFIG.velocidadeRelativaPrecisao)
    local limits={requested,math.min(requested,P.CONFIG.velocidadePerto),math.min(requested,P.CONFIG.velocidadePrecisao)}
    if precision then table.insert(limits,2,relativeLimit) end
    for _,limit in ipairs(limits) do
        local safe,why=true,nil
        for _,g in ipairs(geometries) do
            -- Na faixa paralela, o que importa e a velocidade de aproximacao.
            -- Uma colheitadeira a 8 km/h pode ser acompanhada a 8 km/h; aproximar
            -- a 15 km/h de uma maquina parada conserva a margem de viagem.
            local margin=P.CONFIG.margem
            if precision
                and math.abs(current-g.velocidadeAlvo)<=P.CONFIG.velocidadeRelativaPrecisao
                and math.abs(limit-g.velocidadeAlvo)<=P.CONFIG.velocidadeRelativaPrecisao then margin=P.CONFIG.margemPrecisao end
            safe,why=prever(g,x,z,limit,current,dt,moveForwards,margin)
            if not safe then break end
        end
        if safe then
            return limit,limit<requested and "Aproximacao reduzida: distancia de seguranca" or nil
        end
        reason=why
    end
    if reason=="talhao" then return 0,"Freando: limite do talhao","talhao" end
    return 0,reason=="plataforma" and "Freando: limite da plataforma" or "Freando: distancia do veiculo",reason
end

-- Apenas desloca o ponto de aproximacao para tras do conjunto medido.
-- Nao calcula desvios em volta da lavoura nem cria uma fila de busca.
function P.aproximacao(trator,target,x,z,dx,dz,recuo)
    local minAlong=math.huge
    for _,object in ipairs(TransbordoInteligente.getConjunto(root(target))) do
        local b=P.medir(object)
        for _,lx in ipairs({b.xmin,b.xmax}) do
            for _,lz in ipairs({b.zmin,b.zmax}) do
                local px,_,pz=localToWorld(object.rootNode,lx,0,lz)
                minAlong=math.min(minAlong,(px-x)*dx+(pz-z)*dz)
            end
        end
    end
    local ownFront=0
    for _,object in ipairs(TransbordoInteligente.getConjunto(trator)) do
        local b=P.medir(object)
        for _,lx in ipairs({b.xmin,b.xmax}) do
            for _,lz in ipairs({b.zmin,b.zmax}) do
                local _,_,pz=localToLocal(object.rootNode,direction(trator),lx,0,lz)
                ownFront=math.max(ownFront,pz)
            end
        end
    end
    local behind=math.min(-recuo,minAlong-ownFront-P.CONFIG.margem-2)
    local talhao=trator.spec_transbordoInteligente.talhao
    if talhao==nil then return nil end
    local minimum=math.min(-18,minAlong-ownFront-P.CONFIG.margem-2)
    while behind<=minimum+0.01 do
        local ax,az=x+dx*behind,z+dz*behind
        if P.posicaoLivre(trator,target,ax,az,math.atan2(dx,dz)) then return ax,az end
        behind=behind+2
    end
    local ax,az=x+dx*minimum,z+dz*minimum
    if P.posicaoLivre(trator,target,ax,az,math.atan2(dx,dz)) then return ax,az end
    return nil
end
