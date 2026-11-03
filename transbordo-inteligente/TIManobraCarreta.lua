-- Estacionamento local e limitado junto da carreta. Sem rotas de viagem,
-- leitura de cultura, sensores do mapa ou coroutine.
TIManobraCarreta={}
local M=TIManobraCarreta
M.CONFIG={passo=1.5,amostra=0.5,raioLocal=22,percursoMaximo=36,maxNos=5000,
    nosPorUpdate=60,maxTrocas=4,articulacaoMaxima=math.rad(42),anguloDescarga=math.rad(50),velocidade=1.5}

local function angle(a,b) return math.atan2(math.sin(a-b),math.cos(a-b)) end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.faixa(trator,target,index)
    local ax,az,bx,bz=TransbordoInteligente.faixaEnchimento(target,index)
    local spec=trator.spec_transbordoInteligente
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

function M.pontoCano(job,p)
    local x,z,a=TIProtecao.poseParte(job.g,p,job.bazuca)
    return x+math.cos(a)*job.pipeX+math.sin(a)*job.pipeZ,
        z-math.sin(a)*job.pipeX+math.cos(a)*job.pipeZ
end

function M.avaliar(job,p)
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
    return distance+4*math.max(0,trailerAngle-tolerance)+2*math.max(0,tractorAngle-tolerance)+jointAngle,
        distance<0.4 and trailerAngle<tolerance and tractorAngle<tolerance+0.1 and jointAngle<0.25,t
end

local function key(job,p,dir)
    return math.floor((p.x-job.start.x)/0.75+0.5)..":"..math.floor((p.z-job.start.z)/0.75+0.5)
        ..":"..math.floor((p.a%(2*math.pi))/math.rad(12)+0.5)
        ..":"..math.floor((p.t%(2*math.pi))/math.rad(12)+0.5)..":"..dir
end

function M.iniciar(trator,target,index,dx,dz)
    local spec=trator.spec_transbordoInteligente
    local cargo=TransbordoInteligente.getCarga(spec.bazuca)
    if cargo==nil then return nil end
    local g=TIProtecao.geometria(trator,target)
    if not TIProtecao.poseLivre(g,g.pose,TIProtecao.CONFIG.margemPrecisao) then return nil end
    local px,_,pz=getWorldTranslation(cargo.node.node)
    local wx,_,wz=getWorldTranslation(spec.bazuca.rootNode)
    local a=yaw(spec.bazuca.rootNode)
    local ax,az,bx,bz
    if TransbordoInteligente.faixaEnchimento~=nil then ax,az,bx,bz=M.faixa(trator,target,index) end
    if ax==nil then
        local x,_,z=TransbordoInteligente.pontoEnchimento(target,index)
        ax,az,bx,bz=x,z,x,z
    end
    if ax==nil then return nil end
    local job={g=g,start=g.pose,bazuca=spec.bazuca,target=target,index=index,
        ax=ax,az=az,bx=bx,bz=bz,heading=math.atan2(dx,dz),heap={},seen={},expanded=0,
        pipeX=(px-wx)*math.cos(a)-(pz-wz)*math.sin(a),
        pipeZ=(px-wx)*math.sin(a)+(pz-wz)*math.cos(a),status="buscando"}
    local h,goal,t=M.avaliar(job,g.pose)
    local node={p=g.pose,cost=0,distance=0,changes=0,dir=1,f=1.8*h,goal=goal,fraction=t}
    job.seen[key(job,g.pose,1)]=0
    push(job.heap,node)
    return job
end

function M.avancar(job,budget)
    if job.status~="buscando" then return job.status end
    local P=TIProtecao
    for i=1,budget or M.CONFIG.nosPorUpdate do
        if #job.heap==0 or job.expanded>=M.CONFIG.maxNos then
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
        if n.distance+M.CONFIG.passo<=(job.limitDistance or M.CONFIG.percursoMaximo) then
            for _,dir in ipairs({1,-1}) do
                local changes=n.changes+(dir~=n.dir and 1 or 0)
                if changes<=M.CONFIG.maxTrocas then
                    for _,turn in ipairs({-1,0,1}) do
                        local k=turn/job.g.raioGiro
                        local p=n.p
                        local safe=true
                        local samples=math.ceil(M.CONFIG.passo/M.CONFIG.amostra)
                        for j=1,samples do
                            p=P.avancarPose(p,k,dir*M.CONFIG.passo/samples,job.g.drawbar)
                            local articulationLimit=math.max(M.CONFIG.articulacaoMaxima,math.abs(angle(n.p.a,n.p.t)))
                            local origin=job.origin or job.start
                            if (p.x-origin.x)^2+(p.z-origin.z)^2>M.CONFIG.raioLocal^2
                                or math.abs(angle(p.a,p.t))>articulationLimit+0.001
                                or not P.poseLivre(job.g,p,P.CONFIG.margemPrecisao) then safe=false;break end
                        end
                        if safe then
                            local cost=n.cost+M.CONFIG.passo*(dir<0 and 1.2 or 1)+(dir~=n.dir and 2 or 0)+math.abs(turn)*0.05
                            local hash=key(job,p,dir)
                            if job.seen[hash]==nil or cost<job.seen[hash] then
                                job.seen[hash]=cost
                                local h,goal,t=M.avaliar(job,p)
                                push(job.heap,{p=p,cost=cost,distance=n.distance+M.CONFIG.passo,
                                    changes=changes,dir=dir,k=k,parent=n,f=cost+1.8*h,goal=goal,fraction=t})
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
    for _,back in ipairs({TransbordoInteligente.CONFIG.recuoCarreta,8,6,4}) do
        local ax,az=x-dx*back,z-dz*back
        if TIProtecao.posicaoLivre(trator,target,ax,az,math.atan2(dx,dz),TIProtecao.CONFIG.margemPrecisao) then return ax,az end
    end
    return nil
end

local function stopped(message) return {speed=0,message=message} end

function M.comandar(trator,dt,target,index,dx,dz)
    local spec=trator.spec_transbordoInteligente
    local g=TIProtecao.geometria(trator,target)
    local p=g.pose
    local control=spec.manobraCarreta
    if control==nil then
        local ax,az,bx,bz=TransbordoInteligente.faixaEnchimento(target,index)
        local origin=ax~=nil and {x=(ax+bx)/2,z=(az+bz)/2} or p
        control={distance=0,lastX=p.x,lastZ=p.z,segment=1,progress=0,replans=0,origin=origin}
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
    if control.distance>M.CONFIG.percursoMaximo then return stopped("Limite do ajuste curto: reposicione a carreta com mais espaco") end
    if (p.x-control.origin.x)^2+(p.z-control.origin.z)^2>M.CONFIG.raioLocal^2 then
        return stopped("Limite da area de ajuste: reposicione a carreta")
    end
    local function replan()
        control.job,control.executing=nil,false
        control.segment,control.progress=1,0
        control.replans=control.replans+1
        control.noMotion,control.motionDistance=0,0
    end
    if (control.noMotion or 0)>3000 then
        if control.replans>=2 then return stopped("Sem movimento junto da carreta; reposicione o conjunto") end
        replan();return stopped("Interrompendo o ajuste para conferir a folga real")
    end
    if control.job~=nil then
        local before=control.job.g.others
        local changed=#before~=#g.others
        for i,body in ipairs(g.others) do
            local old=before[i]
            if old==nil or (old.x-body.x)^2+(old.z-body.z)^2>0.25 or math.abs(angle(old.a,body.a))>math.rad(5) then changed=true;break end
        end
        if changed then
            if control.replans>=2 then return stopped("Caminhao mudou de posicao; pare para encostar") end
            replan();return stopped("Atualizando a posicao real da carreta")
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
        if control.replans>=2 then return stopped("Sem folga para encostar; reposicione o conjunto") end
        replan();control.blockedTime=0;control.blocked=false
    end
    if control.job==nil then
        local speed=trator.getLastSpeed~=nil and math.abs(trator:getLastSpeed()) or 0
        if speed>0.5 then return stopped("Parando para alinhar com movimentos curtos") end
        control.job=M.iniciar(trator,target,index,dx,dz)
        if control.job==nil then return stopped("Sem folga junto da carreta para iniciar o ajuste") end
        control.job.limitDistance=M.CONFIG.percursoMaximo-control.distance
        control.job.origin=control.origin
    end
    local job=control.job
    if job.status=="buscando" then
        M.avancar(job)
        if job.status=="buscando" then return stopped("Preparando ajuste local junto da carreta") end
        if job.status=="pronto" then
            spec.fracaoDescarga=spec.pontoDescargaFixo or job.fraction
            local last=job.path[#job.path]
            local a=last~=nil and last.p.t or p.t
            local hx,_,hz=localDirectionToWorld(target.rootNode,0,0,1)
            spec.sentidoDestino=math.sin(a)*hx+math.cos(a)*hz>=0 and 1 or -1
            control.executing=true
        end
    end
    if job.status~="pronto" then return stopped("Sem manobra curta livre dentro do talhao; reposicione a carreta") end
    while job.path[control.segment]~=nil and control.progress>=M.CONFIG.passo-0.01 do
        control.progress=math.max(0,control.progress-M.CONFIG.passo)
        control.segment=control.segment+1
    end
    local segment=job.path[control.segment]
    if segment==nil then
        local distance,t=M.distanciaCano(trator,target,index)
        spec.fracaoDescarga=spec.pontoDescargaFixo or t
        if distance<0.45 then
            control.waitReceiver=(control.waitReceiver or 0)+dt
            local command=stopped("Cano na cacamba; aguardando confirmacao da descarga")
            if control.waitReceiver>TransbordoInteligente.CONFIG.tempoSemDescarga then command.retryTarget=true end
            return command
        end
        if control.replans<2 then replan();return stopped("Corrigindo o ultimo trecho do cano") end
        return stopped("Ajuste curto concluido; confira o alcance do cano")
    end
    local expected=TIProtecao.avancarPose(segment.parent.p,segment.k,segment.dir*control.progress,job.g.drawbar)
    if (p.x-expected.x)^2+(p.z-expected.z)^2>1.44 or math.abs(angle(p.a,expected.a))>0.35
        or math.abs(angle(p.t,expected.t))>0.35 then
        if control.replans<2 then replan();return stopped("Ajustando a manobra a posicao real da bazuca") end
        return stopped("Engate fora do ajuste previsto; reposicione para alinhar")
    end
    local aim=TIProtecao.avancarPose(segment.parent.p,segment.k,segment.dir*(control.progress+2),job.g.drawbar)
    local distance=M.distanciaCano(trator,target,index)
    control.requestingMotion=true
    return {x=aim.x,z=aim.z,speed=M.CONFIG.velocidade,forwards=segment.dir>0,
        message=string.format("Ajuste curto %d/%d %s | Cano-cacamba %.1f m",control.segment,#job.path,
            segment.dir>0 and "frente" or "re",distance)}
end
