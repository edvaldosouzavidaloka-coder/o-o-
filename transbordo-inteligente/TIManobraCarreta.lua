-- Estacionamento local e limitado junto da carreta. Sem rotas de viagem,
-- leitura de cultura, sensores do mapa ou coroutine.
TIManobraCarreta={}
local M=TIManobraCarreta
M.CONFIG={passo=1.5,amostra=0.5,raioLocal=22,percursoMaximo=36,maxNos=5000,
    nosPorUpdate=60,maxTrocas=4,articulacaoMaxima=math.rad(42),anguloDescarga=math.rad(50),velocidade=1.5,
    percursoTotal=150,maxRecalculos=4,maxCurvas=600,velocidadeReentrada=3}
-- So amplia a busca depois de esgotar a tentativa menor. Cada amostra continua
-- sujeita ao mesmo poligono fixo e aos mesmos limites de contato.
M.ALTERNATIVAS={
    {nome="Ajuste curto",raio=22,percurso=36,passo=1.5,trocas=4},
    {nome="Entrada alternativa",raio=36,percurso=66,passo=2,trocas=6,nos=14000},
    {nome="Reentrada pelo campo",raio=60,percurso=150,passo=2.5,trocas=8,nos=20000}
}
local function perfil(nivel)
    if nivel==1 then return {nome=M.ALTERNATIVAS[1].nome,raio=M.CONFIG.raioLocal,
        percurso=M.CONFIG.percursoMaximo,passo=M.CONFIG.passo,trocas=M.CONFIG.maxTrocas} end
    return M.ALTERNATIVAS[nivel]
end

local function angle(a,b) return math.atan2(math.sin(a-b),math.cos(a-b)) end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.faixa(trator,target,index)
    local ax,az,bx,bz=TransbordoInteligente.faixaEnchimento(target,index)
    local spec=trator.spec_transbordoInteligente
    local offset=TransbordoInteligente.config(trator,"offsetCarreta") or 0
    if ax~=nil and offset~=0 then
        local nx,_,nz=localDirectionToWorld(target.rootNode,1,0,0)
        ax,az,bx,bz=ax+nx*offset,az+nz*offset,bx+nx*offset,bz+nz*offset
    end
    if ax~=nil and spec.pontoDescargaFixo~=nil and spec.caminhaoAlvo==target and spec.indiceCarreta==index then
        local t=spec.pontoDescargaFixo
        ax,az=ax+(bx-ax)*t,az+(bz-az)*t
        bx,bz=ax,az
    end
    return ax,az,bx,bz
end
local function yaw(n)
    local x,_,z=localDirectionToWorld(n,0,0,1)
    return math.atan2(x,z)
end

-- Mapeia carroceria, faixa de carga, alcance real do cano e posicoes em que
-- TODO o conjunto cabe. A largura externa nao inventa uma abertura de carga.
function M.mapear(trator,target,index,g)
    local spec=trator.spec_transbordoInteligente
    local cargo=TransbordoInteligente.getCarga(spec.bazuca)
    if cargo==nil then return nil end
    g=g or TIProtecao.geometria(trator,target)
    local ax,az,bx,bz=M.faixa(trator,target,index)
    if ax==nil then return nil end
    local px,_,pz=getWorldTranslation(cargo.node.node)
    local wx,_,wz=getWorldTranslation(spec.bazuca.rootNode)
    local a=yaw(spec.bazuca.rootNode)
    local b=TIProtecao.medir(target)
    local own=TIProtecao.medir(spec.bazuca)
    local map={g=g,bazuca=spec.bazuca,ax=ax,az=az,bx=bx,bz=bz,vagas={},
        heading=yaw(target.rootNode),largura=b.hw*2,comprimento=b.hl*2,estimada=b.larguraEstimada,
        larguraBazuca=own.hw*2,pipeX=(px-wx)*math.cos(a)-(pz-wz)*math.sin(a),
        pipeZ=(px-wx)*math.sin(a)+(pz-wz)*math.cos(a)}
    map.alcance=math.abs(map.pipeX)
    local targetBody
    for _,body in ipairs(g.others) do if body.object==target then targetBody=body end end
    local fractions=(bx-ax)^2+(bz-az)^2>0.01 and {0.5,0.25,0.75,0,1} or {0.5}
    for _,fraction in ipairs(fractions) do
        local rx,rz=ax+(bx-ax)*fraction,az+(bz-az)*fraction
        for _,sign in ipairs({0,1}) do
            for _,offset in ipairs({0,-20,20,-40,40}) do
                local heading=map.heading+sign*math.pi+math.rad(offset)
                local q={x=0,z=0,a=heading,t=heading}
                local ox,oz,wa=TIProtecao.poseParte(g,q,spec.bazuca)
                if ox~=nil then
                    local pipeX=ox+math.cos(wa)*map.pipeX+math.sin(wa)*map.pipeZ
                    local pipeZ=oz-math.sin(wa)*map.pipeX+math.cos(wa)*map.pipeZ
                    q.x,q.z=rx-pipeX,rz-pipeZ
                    if TIProtecao.poseLivre(g,q,TIProtecao.CONFIG.margemPrecisao) then
                        local gap
                        if targetBody~=nil then
                            local x,z=TIProtecao.poseParte(g,q,spec.bazuca)
                            x,z=x+math.cos(wa)*own.cx+math.sin(wa)*own.cz,z-math.sin(wa)*own.cx+math.cos(wa)*own.cz
                            local side=(x-targetBody.x)*math.cos(targetBody.a)-(z-targetBody.z)*math.sin(targetBody.a)
                            local da=wa-targetBody.a
                            gap=math.abs(side)-targetBody.hw-own.hw*math.abs(math.cos(da))-own.hl*math.abs(math.sin(da))
                        end
                        map.vagas[#map.vagas+1]={p=q,fraction=fraction,folga=gap}
                        if gap~=nil then map.folga=math.max(map.folga or -math.huge,gap) end
                    end
                end
            end
        end
    end
    return map
end

function M.atualizarMapa(trator,target,index)
    local spec=trator.spec_transbordoInteligente
    local map=spec.mapaCarreta
    local now=spec.tempoTotal or 0
    if map==nil or map.target~=target or map.index~=index or now-(map.updatedAt or 0)>=500 then
        map=M.mapear(trator,target,index)
        if map~=nil then map.target,map.index,map.updatedAt=target,index,now end
        spec.mapaCarreta=map
    end
    return map
end
local function push(heap,n)
    local i=#heap+1
    while i>1 do
        local parent=math.floor(i/2)
        if heap[parent].f<=n.f then break end
        heap[i]=heap[parent];i=parent
    end
    heap[i]=n
end
local function pop(heap)
    local first,last=heap[1],table.remove(heap)
    if #heap>0 then
        local i=1
        while i*2<=#heap do
            local child=i*2
            if child<#heap and heap[child+1].f<heap[child].f then child=child+1 end
            if heap[child].f>=last.f then break end
            heap[i]=heap[child];i=child
        end
        heap[i]=last
    end
    return first
end

-- Curvas tangentes entre a pose atual e uma entrada alinhada antes da carga.
-- O prefixo de re abre espaco quando a frente ja aponta para a carroceria.
local function curvasTangentes(start,goal,radius)
    local theta=math.atan2(goal.z-start.z,goal.x-start.x)
    local tau=2*math.pi
    local a=(math.pi/2-start.a-theta)%tau
    local b=(math.pi/2-goal.a-theta)%tau
    local d=math.sqrt((goal.x-start.x)^2+(goal.z-start.z)^2)/radius
    local sa,sb,ca,cb=math.sin(a),math.sin(b),math.cos(a),math.cos(b)
    local cab=math.cos(a-b)
    local paths={}
    local function add(kind,p2,tmp)
        if p2<0 then return end
        local p=math.sqrt(p2)
        local t,q
        if kind=="LSL" then t,q=(-a+tmp)%tau,(b-tmp)%tau
        elseif kind=="RSR" then t,q=(a-tmp)%tau,(-b+tmp)%tau
        elseif kind=="LSR" then tmp=tmp-math.atan2(-2,p);t,q=(-a+tmp)%tau,(-b+tmp)%tau
        else tmp=tmp-math.atan2(2,p);t,q=(a-tmp)%tau,(b-tmp)%tau end
        paths[#paths+1]={kind=kind,lengths={t*radius,p*radius,q*radius}}
    end
    add("LSL",2+d*d-2*cab+2*d*(sa-sb),math.atan2(cb-ca,d+sa-sb))
    add("RSR",2+d*d-2*cab+2*d*(-sa+sb),math.atan2(ca-cb,d-sa+sb))
    add("LSR",-2+d*d+2*cab+2*d*(sa+sb),math.atan2(-ca-cb,d+sa+sb))
    add("RSL",d*d-2+2*cab-2*d*(sa+sb),math.atan2(ca+cb,d-sa-sb))
    return paths
end

function M.prepararCurvas(job)
    local choices={}
    local tail=math.max(16,job.g.drawbar*3)
    local radius=math.max(job.g.raioGiro,job.g.drawbar/math.sin(math.rad(38)))
    for _,vaga in ipairs(job.mapa.vagas) do
        local q=vaga.p
        local entry={x=q.x-math.sin(q.a)*tail,z=q.z-math.cos(q.a)*tail,a=q.a}
        if TIProtecao.poseLivre(job.g,{x=entry.x,z=entry.z,a=q.a,t=q.a},TIProtecao.CONFIG.margemPrecisao) then
            for _,back in ipairs({0,6,12,18,24,30}) do
                local start={x=job.start.x-math.sin(job.start.a)*back,z=job.start.z-math.cos(job.start.a)*back,a=job.start.a}
                for _,r in ipairs({radius,radius*1.25}) do
                    for _,curve in ipairs(curvasTangentes(start,entry,r)) do
                        local parts={{length=back,k=0,dir=-1}}
                        local length=back+tail
                        for i,v in ipairs(curve.lengths) do
                            local kind=curve.kind:sub(i,i)
                            parts[#parts+1]={length=v,k=kind=="S" and 0 or (kind=="L" and -1 or 1)/r,dir=1}
                            length=length+v
                        end
                        parts[#parts+1]={length=tail,k=0,dir=1}
                        if length<=job.limitDistance then choices[#choices+1]={parts=parts,length=length,score=length+back*0.2} end
                    end
                end
            end
        end
    end
    table.sort(choices,function(a,b) return a.score<b.score end)
    while #choices>M.CONFIG.maxCurvas do choices[#choices]=nil end
    job.curves,job.curveIndex,job.curvesChecked=choices,1,0
end

local function avancarCurvas(job,budget)
    for i=1,budget do
        local choice=job.curves[job.curveIndex]
        if choice==nil then job.curves=nil;return false end
        local run=job.curveRun
        if run==nil then
            run={p=job.start,path={},part=1,used=0,distance=0,segmentUsed=0}
            run.last={p=job.start,dir=1,changes=0,distance=0}
            job.curveRun=run
        end
        local part=choice.parts[run.part]
        while part~=nil and run.used>=part.length-0.000001 do
            run.part,run.used=run.part+1,0
            part=choice.parts[run.part]
        end
        if part==nil then
            job.curveIndex,job.curveRun=job.curveIndex+1,nil
            job.curvesChecked=job.curvesChecked+1
        else
            local ds=math.min(M.CONFIG.amostra,part.length-run.used,M.CONFIG.passo-run.segmentUsed)
            local p=TIProtecao.avancarPose(run.p,part.k,part.dir*ds,job.g.drawbar)
            local origin=job.origin or job.start
            if (p.x-origin.x)^2+(p.z-origin.z)^2>job.raio^2
                or math.abs(angle(p.a,p.t))>math.max(M.CONFIG.articulacaoMaxima,math.abs(angle(job.start.a,job.start.t)))+0.001
                or not TIProtecao.poseLivre(job.g,p,TIProtecao.CONFIG.margemPrecisao) then
                job.curveIndex,job.curveRun=job.curveIndex+1,nil
                job.curvesChecked=job.curvesChecked+1
            else
                run.p,run.used,run.distance,run.segmentUsed=p,run.used+ds,run.distance+ds,run.segmentUsed+ds
                local _,goal,t=M.avaliar(job,p)
                if goal or run.segmentUsed>=M.CONFIG.passo-0.000001 or run.used>=part.length-0.000001 then
                    local n={p=p,dir=part.dir,k=part.k,step=run.segmentUsed,distance=run.distance,parent=run.last,
                        changes=run.last.changes+(part.dir~=run.last.dir and 1 or 0)}
                    run.path[#run.path+1],run.last,run.segmentUsed=n,n,0
                    if goal then
                        job.path,job.fraction,job.status=run.path,t,"pronto"
                        job.heap,job.seen,job.curves,job.curveRun={},{},nil,nil
                        job.entradaMapeada=true
                        return true
                    end
                end
            end
        end
    end
    return true
end

function M.pontoCano(job,p)
    local x,z,a=TIProtecao.poseParte(job.g,p,job.bazuca)
    return x+math.cos(a)*job.pipeX+math.sin(a)*job.pipeZ,
        z-math.sin(a)*job.pipeX+math.cos(a)*job.pipeZ
end

function M.avaliar(job,p)
    if job.entrada~=nil then
        local q=job.entrada
        local d=math.sqrt((p.x-q.x)^2+(p.z-q.z)^2)
        local a,t=math.abs(angle(p.a,q.a)),math.abs(angle(p.t,q.a))
        return d+job.g.raioGiro*a+job.g.drawbar*t,d<0.8 and a<0.15 and t<0.25,0.5,d
    end
    local x,z=M.pontoCano(job,p)
    local wx,wz=job.bx-job.ax,job.bz-job.az
    local length=wx*wx+wz*wz
    local t=length>0.01 and clamp(((x-job.ax)*wx+(z-job.az)*wz)/length,0,1) or 0.5
    local gx,gz=job.ax+wx*t,job.az+wz*t
    local distance=math.sqrt((x-gx)^2+(z-gz)^2)
    local trailerAngle=math.min(math.abs(angle(p.t,job.heading)),math.abs(angle(p.t,job.heading+math.pi)))
    local tractorAngle=math.min(math.abs(angle(p.a,job.heading)),math.abs(angle(p.a,job.heading+math.pi)))
    local jointAngle=math.abs(angle(p.a,p.t))
    local tolerance=M.CONFIG.anguloDescarga
    local h=distance+4*math.max(0,trailerAngle-tolerance)+2*math.max(0,tractorAngle-tolerance)+jointAngle
    if job.nivel>1 and #job.mapa.vagas>0 then
        local best=math.huge
        for _,vaga in ipairs(job.mapa.vagas) do
            local q=vaga.p
            local d=math.sqrt((p.x-q.x)^2+(p.z-q.z)^2)
            local turning=job.g.raioGiro*0.6*math.abs(angle(p.a,q.a))+job.g.drawbar*0.5*math.abs(angle(p.t,q.t))
            best=math.min(best,d+turning)
        end
        h=math.max(h,best)
    end
    return h,distance<0.4 and trailerAngle<tolerance and tractorAngle<tolerance+0.1 and jointAngle<0.25,t,distance
end

local function key(job,p,dir)
    local grid=job.nivel>1 and 1.25 or 0.75
    local angular=math.rad(job.nivel>1 and 15 or 12)
    return math.floor((p.x-job.start.x)/grid+0.5)..":"..math.floor((p.z-job.start.z)/grid+0.5)
        ..":"..math.floor((p.a%(2*math.pi))/angular+0.5)
        ..":"..math.floor((p.t%(2*math.pi))/angular+0.5)..":"..dir
end

function M.iniciar(trator,target,index,dx,dz,nivel)
    local spec=trator.spec_transbordoInteligente
    local cargo=TransbordoInteligente.getCarga(spec.bazuca)
    if cargo==nil then return nil end
    local g=TIProtecao.geometria(trator,target)
    if not TIProtecao.poseLivre(g,g.pose,TIProtecao.CONFIG.margemPrecisao) then return nil end
    local map=M.mapear(trator,target,index,g)
    if map==nil then return nil end
    nivel=nivel or 1
    local profile=perfil(nivel)
    local job={g=g,start=g.pose,bazuca=spec.bazuca,target=target,index=index,
        ax=map.ax,az=map.az,bx=map.bx,bz=map.bz,heading=math.atan2(dx,dz),heap={},seen={},expanded=0,
        pipeX=map.pipeX,pipeZ=map.pipeZ,mapa=map,nivel=nivel,
        step=profile.passo,raio=profile.raio,limitDistance=profile.percurso,maxChanges=profile.trocas,
        maxNos=profile.nos,turns=nivel>1 and {-1,-0.5,0,0.5,1} or {-1,0,1},status="buscando"}
    local h,goal,t,d=M.avaliar(job,g.pose)
    local node={p=g.pose,cost=0,distance=0,changes=0,dir=1,f=1.8*h,goal=goal,fraction=t,pipeDistance=d}
    job.seen[key(job,g.pose,1)]=0
    push(job.heap,node)
    return job
end

function M.iniciarEntrada(v,target,x,z,dx,dz,nivel)
    local g=TIProtecao.geometria(v,target)
    local q={x=x,z=z,a=math.atan2(dx,dz),t=math.atan2(dx,dz)}
    if not TIProtecao.poseLivre(g,g.pose,TIProtecao.CONFIG.margemPrecisao)
        or not TIProtecao.poseLivre(g,q,TIProtecao.CONFIG.margemPrecisao) then return nil end
    nivel=nivel or 1
    local profile=perfil(nivel)
    local job={g=g,start=g.pose,entrada=q,heading=q.a,nivel=nivel,mapa={vagas={{p=q}}},
        heap={},seen={},expanded=0,step=profile.passo,raio=profile.raio,limitDistance=profile.percurso,
        maxChanges=profile.trocas,maxNos=profile.nos,turns=nivel>1 and {-1,-0.5,0,0.5,1} or {-1,0,1},status="buscando"}
    local h,goal,t,d=M.avaliar(job,g.pose)
    job.seen[key(job,g.pose,1)]=0
    push(job.heap,{p=g.pose,cost=0,distance=0,changes=0,dir=1,f=1.8*h,goal=goal,fraction=t,pipeDistance=d})
    return job
end

function M.avancar(job,budget)
    if job.status~="buscando" then return job.status end
    if job.expanded==0 and job.heap[1]~=nil and job.heap[1].goal then
        job.path,job.fraction,job.status={},job.heap[1].fraction,"pronto"
        job.heap,job.seen,job.expanded={},{},1
        return job.status
    end
    if job.nivel==3 and not job.curvesStarted then
        M.prepararCurvas(job);job.curvesStarted=true
    end
    if job.curves~=nil and avancarCurvas(job,budget or M.CONFIG.nosPorUpdate) then return job.status end
    local P=TIProtecao
    for i=1,budget or M.CONFIG.nosPorUpdate do
        if #job.heap==0 or job.expanded>=(job.maxNos or M.CONFIG.maxNos) then
            job.status,job.heap,job.seen="semEspaco",{},{};return job.status
        end
        local n=pop(job.heap)
        job.expanded=job.expanded+1
        if n.goal then
            local path={}
            local current=n
            while current.parent~=nil do table.insert(path,1,current);current=current.parent end
            job.path,job.fraction,job.status=path,n.fraction,"pronto"
            job.heap,job.seen={},{}
            return job.status
        end
        local step=job.step
        if job.nivel>1 and n.pipeDistance<8 then step=math.min(step,n.pipeDistance<4 and 0.75 or 1.5) end
        if n.distance+step<=job.limitDistance then
            for _,dir in ipairs({1,-1}) do
                local changes=n.changes+(dir~=n.dir and 1 or 0)
                if changes<=job.maxChanges then
                    for _,turn in ipairs(job.turns) do
                        local k=turn/job.g.raioGiro
                        local p=n.p
                        local safe=true
                        local samples=math.ceil(step/M.CONFIG.amostra)
                        for j=1,samples do
                            p=P.avancarPose(p,k,dir*step/samples,job.g.drawbar)
                            local articulationLimit=math.max(M.CONFIG.articulacaoMaxima,math.abs(angle(n.p.a,n.p.t)))
                            local origin=job.origin or job.start
                            if (p.x-origin.x)^2+(p.z-origin.z)^2>job.raio^2
                                or math.abs(angle(p.a,p.t))>articulationLimit+0.001
                                or not P.poseLivre(job.g,p,P.CONFIG.margemPrecisao) then safe=false;break end
                        end
                        if safe then
                            local cost=n.cost+step*(dir<0 and 1.2 or 1)+(dir~=n.dir and 2 or 0)+math.abs(turn)*0.05
                            local hash=key(job,p,dir)
                            if job.seen[hash]==nil or cost<job.seen[hash] then
                                job.seen[hash]=cost
                                local h,goal,t,d=M.avaliar(job,p)
                                push(job.heap,{p=p,cost=cost,distance=n.distance+step,step=step,
                                    changes=changes,dir=dir,k=k,parent=n,f=cost+1.8*h,goal=goal,fraction=t,pipeDistance=d})
                            end
                        end
                    end
                end
            end
        end
    end
    return job.status
end

M.erroAngular=angle

function M.distanciaCano(trator,target,index)
    local cargo=TransbordoInteligente.getCarga(trator.spec_transbordoInteligente.bazuca)
    if cargo==nil then return math.huge end
    local x,_,z=getWorldTranslation(cargo.node.node)
    local ax,az,bx,bz=M.faixa(trator,target,index)
    if ax==nil then return math.huge end
    local vx,vz=bx-ax,bz-az
    local length=vx*vx+vz*vz
    local t=length>0.01 and clamp(((x-ax)*vx+(z-az)*vz)/length,0,1) or 0.5
    return math.sqrt((x-ax-vx*t)^2+(z-az-vz*t)^2),t
end

function M.entrada(trator,target,x,z,dx,dz)
    local ref=trator.getAIDirectionNode~=nil and trator:getAIDirectionNode() or trator.rootNode
    local tx,_,tz=getWorldTranslation(ref)
    local longitudinal=(x-tx)*dx+(z-tz)*dz
    if longitudinal>=0 then
        local lead=12-longitudinal
        local ax,az=x+dx*lead,z+dz*lead
        if TIProtecao.posicaoNoTalhao(trator,ax,az,math.atan2(dx,dz)) then return ax,az end
    end
    for _,back in ipairs({TransbordoInteligente.config(trator,"recuoCarreta"),8,6,4}) do
        local ax,az=x-dx*back,z-dz*back
        if TIProtecao.posicaoLivre(trator,target,ax,az,math.atan2(dx,dz),TIProtecao.CONFIG.margemPrecisao) then return ax,az end
    end
    return nil
end

local function stopped(message) return {speed=0,message=message} end

-- Recupera a entrada quando a frente do trator esta atravessada junto da
-- plataforma. Primeiro alinha atras; receber graos continua sendo para frente.
function M.comandarEntrada(v,dt,target,x,z,dx,dz)
    local s=v.spec_transbordoInteligente
    local g=TIProtecao.geometria(v,target)
    local p=g.pose
    local c=s.manobraEntrada
    if c==nil then c={nivel=1,distance=0,progress=0,segment=1,lastX=p.x,lastZ=p.z,replans=0};s.manobraEntrada=c end
    local distance=math.sqrt((p.x-c.lastX)^2+(p.z-c.lastZ)^2)
    c.distance,c.lastX,c.lastZ=c.distance+distance,p.x,p.z
    if c.executing then c.progress=c.progress+distance end
    c.motion=(c.motion or 0)+distance
    if c.motion>=0.05 then c.noMotion,c.motion=0,0 elseif c.requesting then c.noMotion=(c.noMotion or 0)+dt end
    c.requesting=false
    local function reset()
        c.job,c.executing,c.segment,c.progress=nil,false,1,0
        c.nivel,c.replans=math.min(3,c.nivel+1),c.replans+1
        c.noMotion,c.motion=0,0
    end
    if c.distance>M.CONFIG.percursoTotal or c.replans>M.CONFIG.maxRecalculos then return stopped("Sem entrada segura neste espaco junto da plataforma") end
    if c.blocked then c.blockedTime=(c.blockedTime or 0)+dt else c.blockedTime=0 end
    if c.blockedTime>800 or (c.noMotion or 0)>3000 then
        reset();c.blocked,c.blockedTime=false,0;return stopped("Procurando outro giro atras da plataforma")
    end
    if c.job~=nil and ((c.job.entrada.x-x)^2+(c.job.entrada.z-z)^2>9
        or math.abs(angle(c.job.entrada.a,math.atan2(dx,dz)))>math.rad(8)) then
        reset();return stopped("Atualizando a entrada da colheitadeira")
    end
    if c.job==nil then
        if v.getLastSpeed~=nil and math.abs(v:getLastSpeed())>0.5 then return stopped("Parando para alinhar antes da plataforma") end
        c.job=M.iniciarEntrada(v,target,x,z,dx,dz,c.nivel)
        if c.job==nil then return stopped("Sem folga para girar junto da plataforma") end
        c.job.limitDistance=math.min(c.job.limitDistance,M.CONFIG.percursoTotal-c.distance)
    end
    local job=c.job
    if job.status=="buscando" then M.avancar(job) end
    if job.status=="buscando" then return stopped("Conferindo entrada por tras e folga da plataforma") end
    if job.status~="pronto" then
        if c.nivel<3 then reset();return stopped("Tentando outra entrada atras da colheitadeira") end
        return stopped("Nao encontrou entrada livre dentro deste talhao")
    end
    c.executing=true
    while job.path[c.segment]~=nil and c.progress>=job.path[c.segment].step-0.01 do
        c.progress=math.max(0,c.progress-job.path[c.segment].step);c.segment=c.segment+1
    end
    local part=job.path[c.segment]
    if part==nil then
        local _,goal=M.avaliar(job,p)
        if goal then return {done=true,speed=0} end
        reset();return stopped("Concluindo alinhamento atras da colheitadeira")
    end
    local expected=TIProtecao.avancarPose(part.parent.p,part.k,part.dir*c.progress,g.drawbar)
    if (p.x-expected.x)^2+(p.z-expected.z)^2>1.44 or math.abs(angle(p.a,expected.a))>0.35
        or math.abs(angle(p.t,expected.t))>0.35 then reset();return stopped("Corrigindo posicao real do engate na entrada") end
    local aim=TIProtecao.avancarPose(part.parent.p,part.k,part.dir*(c.progress+2),g.drawbar)
    c.requesting=true
    return {x=aim.x,z=aim.z,forwards=part.dir>0,
        speed=part.dir>0 and math.min(3,TransbordoInteligente.config(v,"velocidadeAlinhamento")) or TransbordoInteligente.config(v,"velocidadeRe"),
        message=string.format("Entrada segura %d/%d %s",c.segment,#job.path,part.dir>0 and "frente" or "re")}
end

function M.comandar(trator,dt,target,index,dx,dz)
    local spec=trator.spec_transbordoInteligente
    local g=TIProtecao.geometria(trator,target)
    local p=g.pose
    local control=spec.manobraCarreta
    if control==nil then
        local ax,az,bx,bz=TransbordoInteligente.faixaEnchimento(target,index)
        local origin=ax~=nil and {x=(ax+bx)/2,z=(az+bz)/2} or p
        control={distance=0,lastX=p.x,lastZ=p.z,segment=1,progress=0,replans=0,origin=origin,nivel=1}
        spec.manobraCarreta=control
    end
    local traveled=math.sqrt((p.x-control.lastX)^2+(p.z-control.lastZ)^2)
    control.distance=control.distance+traveled
    if control.executing then control.progress=control.progress+traveled end
    control.lastX,control.lastZ=p.x,p.z
    -- Soma o deslocamento entre quadros: a 60 FPS, 1,5 km/h avanca menos
    -- de um centimetro por quadro e nao pode ser confundido com imobilidade.
    control.motionDistance=(control.motionDistance or 0)+traveled
    if control.motionDistance>=0.05 then control.noMotion,control.motionDistance=0,0
    elseif control.requestingMotion then control.noMotion=(control.noMotion or 0)+dt end
    control.requestingMotion=false
    if control.distance>M.CONFIG.percursoTotal then return stopped("Tentativas de manobra esgotadas neste espaco do talhao") end
    local profile=perfil(control.nivel)
    if (p.x-control.origin.x)^2+(p.z-control.origin.z)^2>profile.raio^2 then
        if control.nivel<#M.ALTERNATIVAS then
            control.nivel=control.nivel+1
            control.job,control.executing=nil,false
            control.segment,control.progress=1,0
            return stopped("Buscando mais espaco de manobra dentro do mesmo talhao")
        end
        return stopped("Sem espaco de manobra na area interna da carreta")
    end
    local function replan(alternative)
        control.job,control.executing=nil,false
        control.segment,control.progress=1,0
        control.replans=control.replans+1
        control.noMotion,control.motionDistance=0,0
        if alternative then control.nivel=math.min(#M.ALTERNATIVAS,control.nivel+1) end
    end
    if (control.noMotion or 0)>3000 then
        if control.replans>=M.CONFIG.maxRecalculos then return stopped("Sem movimento junto da carreta; confira o espaco disponivel") end
        replan(true);return stopped("Interrompendo o ajuste para conferir a folga real")
    end
    if control.job~=nil then
        local before=control.job.g.others
        local changed=#before~=#g.others
        for i,body in ipairs(g.others) do
            local old=before[i]
            if old==nil or (old.x-body.x)^2+(old.z-body.z)^2>0.25 or math.abs(angle(old.a,body.a))>math.rad(5) then changed=true;break end
        end
        if changed then
            if control.replans>=M.CONFIG.maxRecalculos then return stopped("Caminhao mudou de posicao; pare para encostar") end
            replan();control.nivel=1
            return stopped("Atualizando a posicao real da carreta")
        end
    end
    if control.blocked then control.blockedTime=(control.blockedTime or 0)+dt else control.blockedTime=0 end
    if control.job==nil and M.distanciaCano(trator,target,index)>16 and control.blockedTime<=800 then
        local gx,gz=TransbordoInteligente.alvoDescarregar(trator,target,index)
        if gx~=nil then
            local longitudinal=(gx-p.x)*dx+(gz-p.z)*dz
            local aligned=math.sin(p.a)*dx+math.cos(p.a)*dz
            if longitudinal>0 and aligned>0.5 then
                local lead=6-longitudinal
                control.requestingMotion=true
                return {x=gx+dx*lead,z=gz+dz*lead,speed=M.CONFIG.velocidade,forwards=true,
                    message="Encostando devagar pela lateral da carreta"}
            end
        end
    end
    if control.blockedTime>800 then
        if control.replans>=M.CONFIG.maxRecalculos then return stopped("Sem folga para encostar neste espaco do talhao") end
        replan(true);control.blockedTime=0;control.blocked=false
    end
    if control.job==nil then
        local speed=trator.getLastSpeed~=nil and math.abs(trator:getLastSpeed()) or 0
        if speed>0.5 then return stopped("Parando para alinhar com movimentos curtos") end
        control.job=M.iniciar(trator,target,index,dx,dz,control.nivel)
        if control.job==nil then return stopped("Sem folga junto da carreta para iniciar o ajuste") end
        control.job.limitDistance=math.min(control.job.limitDistance,M.CONFIG.percursoTotal-control.distance)
        control.job.origin=control.origin
    end
    local job=control.job
    if job.status=="buscando" then
        M.avancar(job)
        if job.status=="buscando" then return stopped(M.ALTERNATIVAS[control.nivel].nome..": conferindo espaco dentro do talhao") end
        if job.status=="pronto" then
            spec.fracaoDescarga=spec.pontoDescargaFixo or job.fraction
            local last=job.path[#job.path]
            local a=last~=nil and last.p.t or p.t
            local hx,_,hz=localDirectionToWorld(target.rootNode,0,0,1)
            spec.sentidoDestino=math.sin(a)*hx+math.cos(a)*hz>=0 and 1 or -1
            control.executing=true
        end
    end
    if job.status~="pronto" then
        if control.nivel<#M.ALTERNATIVAS then
            control.nivel=control.nivel+1
            control.job,control.executing=nil,false
            control.segment,control.progress=1,0
            return stopped("Ajuste anterior sem passagem; buscando outra entrada dentro do campo")
        end
        return stopped("Nenhuma entrada livre encontrada neste espaco do talhao")
    end
    while job.path[control.segment]~=nil and control.progress>=job.path[control.segment].step-0.01 do
        control.progress=math.max(0,control.progress-job.path[control.segment].step)
        control.segment=control.segment+1
    end
    local segment=job.path[control.segment]
    if segment==nil then
        local distance,t=M.distanciaCano(trator,target,index)
        spec.fracaoDescarga=spec.pontoDescargaFixo or t
        if distance<0.35 then
            control.waitReceiver=(control.waitReceiver or 0)+dt
            local command=stopped("Cano na cacamba; aguardando confirmacao da descarga")
            if control.waitReceiver>TransbordoInteligente.CONFIG.tempoSemDescarga then command.retryTarget=true end
            return command
        end
        if control.replans<M.CONFIG.maxRecalculos then replan(true);return stopped("Corrigindo o ultimo trecho do cano") end
        return stopped("Ajuste curto concluido; confira o alcance do cano")
    end
    local expected=TIProtecao.avancarPose(segment.parent.p,segment.k,segment.dir*control.progress,job.g.drawbar)
    if (p.x-expected.x)^2+(p.z-expected.z)^2>1.44 or math.abs(angle(p.a,expected.a))>0.35
        or math.abs(angle(p.t,expected.t))>0.35 then
        if control.replans<M.CONFIG.maxRecalculos then replan(true);return stopped("Ajustando a manobra a posicao real da bazuca") end
        return stopped("Engate fora do ajuste previsto; reposicione para alinhar")
    end
    local aim=TIProtecao.avancarPose(segment.parent.p,segment.k,segment.dir*(control.progress+2),job.g.drawbar)
    local distance=M.distanciaCano(trator,target,index)
    control.requestingMotion=true
    local speed=job.nivel>1 and segment.dir>0 and distance>10 and M.CONFIG.velocidadeReentrada or M.CONFIG.velocidade
    if segment.dir<0 then speed=TransbordoInteligente.config(trator,"velocidadeRe")
    else speed=math.min(speed,TransbordoInteligente.config(trator,"velocidadeAlinhamento")) end
    return {x=aim.x,z=aim.z,speed=speed,forwards=segment.dir>0,
        message=string.format("%s %d/%d %s | Cano-cacamba %.1f m",M.ALTERNATIVAS[control.nivel].nome,control.segment,#job.path,
            segment.dir>0 and "frente" or "re",distance)}
end
