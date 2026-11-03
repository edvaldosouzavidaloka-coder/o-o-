-- Mapa e rotas opcionais somente dentro do poligono fixado. Sem coroutine.
-- A rota guia a viagem; a protecao articulada continua autorizando cada comando.
TIRotasCampo={CONFIG={celula=6,ladoMaximo=60,celulasPorUpdate=80,nosPorUpdate=32}}
local R=TIRotasCampo
local function index(m,x,z) return (z-1)*m.nx+x end
local function point(m,i)
    return m.minX+((i-1)%m.nx+0.5)*m.step,m.minZ+(math.floor((i-1)/m.nx)+0.5)*m.step
end
R.ponto=point
local function ref(v) return v.getAIDirectionNode~=nil and v:getAIDirectionNode() or v.rootNode end
function R.iniciarMapa(v)
    local s=v.spec_transbordoInteligente
    local field=s.isAtivo and s.talhao or TransbordoInteligente.getTalhao(v)
    if field==nil then s.mensagem="Entre no talhao para mapear o campo";return nil end
    s.bazuca=s.bazuca or TransbordoInteligente.encontrarBazuca(v)
    if s.bazuca==nil then s.mensagem="Acople a bazuca antes de mapear";return nil end
    local minX,minZ,maxX,maxZ=math.huge,math.huge,-math.huge,-math.huge
    for i=1,#field.vertices,2 do
        minX,minZ=math.min(minX,field.vertices[i]),math.min(minZ,field.vertices[i+1])
        maxX,maxZ=math.max(maxX,field.vertices[i]),math.max(maxZ,field.vertices[i+1])
    end
    local radius,width=2,2
    for _,part in ipairs(TIProtecao.geometria(v,nil).own) do
        radius=math.max(radius,math.sqrt(part.ox^2+part.oz^2)+math.sqrt(part.bounds.hw^2+part.bounds.hl^2))
        width=math.max(width,part.bounds.hw)
    end
    local step=math.max(R.CONFIG.celula,math.max(maxX-minX,maxZ-minZ)/R.CONFIG.ladoMaximo)
    local m={field=field,minX=minX,minZ=minZ,maxX=maxX,maxZ=maxZ,step=step,
        nx=math.max(1,math.ceil((maxX-minX)/step)),nz=math.max(1,math.ceil((maxZ-minZ)/step)),
        radius=radius+TIProtecao.CONFIG.margemTalhao,width=width+TIProtecao.CONFIG.margem,
        cells={},next=1,livres=0,status="mapeando"}
    s.mapaCampo,s.navegacaoCampo=m,nil
    return m
end
function R.atualizarMapa(m,budget)
    if m==nil or m.status~="mapeando" then return end
    for n=1,budget or R.CONFIG.celulasPorUpdate do
        if m.next>m.nx*m.nz then m.status="pronto";return end
        local x,z=point(m,m.next)
        local free=TITalhao.contem(m.field,x,z,m.radius)
        m.cells[m.next]=free
        if free then m.livres=m.livres+1 end
        m.next=m.next+1
    end
end
local function outside(m,others,x,z)
    for _,b in ipairs(others) do
        local dx,dz=x-b.x,z-b.z
        local a=math.max(0,math.abs(dx*math.cos(b.a)-dz*math.sin(b.a))-b.hw)
        local c=math.max(0,math.abs(dx*math.sin(b.a)+dz*math.cos(b.a))-b.hl)
        if a*a+c*c<m.width^2 then return false end
    end
    return true
end
local function segment(m,others,ax,az,bx,bz,margin)
    if not TITalhao.segmentoDentro(m.field,ax,az,bx,bz,margin) then return false end
    local n=math.max(1,math.ceil(math.sqrt((ax-bx)^2+(az-bz)^2)/2))
    for i=0,n do if not outside(m,others,ax+(bx-ax)*i/n,az+(bz-az)*i/n) then return false end end
    return true
end
local function nearest(m,others,x,z)
    local best,which=math.huge,nil
    for i,free in pairs(m.cells) do
        if free then
            local px,pz=point(m,i)
            local d=(px-x)^2+(pz-z)^2
            if d<best and outside(m,others,px,pz)
                and segment(m,others,x,z,px,pz,TIProtecao.CONFIG.margemTalhao) then best,which=d,i end
        end
    end
    return which
end
local function push(heap,n)
    local i=#heap+1
    while i>1 do local j=math.floor(i/2);if heap[j].f<=n.f then break end;heap[i]=heap[j];i=j end
    heap[i]=n
end
local function pop(heap)
    local first,last=heap[1],table.remove(heap)
    if #heap>0 then
        local i=1
        while i*2<=#heap do
            local j=i*2;if j<#heap and heap[j+1].f<heap[j].f then j=j+1 end
            if heap[j].f>=last.f then break end;heap[i]=heap[j];i=j
        end
        heap[i]=last
    end
    return first
end
function R.iniciarRota(v,gx,gz,target)
    local s=v.spec_transbordoInteligente
    local m=s.mapaCampo
    if m==nil or m.status~="pronto" then return nil end
    local x,_,z=getWorldTranslation(ref(v))
    local g=TIProtecao.geometria(v,target)
    local job={map=m,others=g.others,gx=gx,gz=gz,target=target,heap={},seen={},expanded=0,status="buscando",segment=1}
    local start,goal=nearest(m,g.others,x,z),nearest(m,g.others,gx,gz)
    if start==nil or goal==nil then job.status="semRota";return job end
    job.goal=goal
    local px,pz=point(m,start)
    job.seen[start]=0;push(job.heap,{i=start,cost=0,f=math.sqrt((px-gx)^2+(pz-gz)^2)})
    return job
end
function R.avancar(job,budget)
    if job.status~="buscando" then return job.status end
    local m=job.map
    for n=1,budget or R.CONFIG.nosPorUpdate do
        if #job.heap==0 or job.expanded>=m.nx*m.nz*4 then
            job.status,job.heap,job.seen="semRota",{},{};return job.status
        end
        local current=pop(job.heap)
        job.expanded=job.expanded+1
        if current.i==job.goal then
            local path={};local node=current
            while node~=nil do local x,z=point(m,node.i);table.insert(path,1,{x=x,z=z});node=node.parent end
            job.path,job.status,job.heap,job.seen=path,"pronto",{},{}
            return job.status
        end
        if current.cost<=job.seen[current.i] then
            local cx,cz=(current.i-1)%m.nx+1,math.floor((current.i-1)/m.nx)+1
            local ax,az=point(m,current.i)
            for dx=-1,1 do for dz=-1,1 do
                if dx~=0 or dz~=0 then
                    local nx,nz=cx+dx,cz+dz
                    if nx>=1 and nx<=m.nx and nz>=1 and nz<=m.nz then
                        local i=index(m,nx,nz)
                        local x,z=point(m,i)
                        local cost=current.cost+m.step*math.sqrt(dx*dx+dz*dz)
                        if m.cells[i] and (job.seen[i]==nil or cost<job.seen[i])
                            and segment(m,job.others,ax,az,x,z,m.radius) then
                            job.seen[i]=cost
                            push(job.heap,{i=i,cost=cost,f=cost+math.sqrt((x-job.gx)^2+(z-job.gz)^2),parent=current})
                        end
                    end
                end
            end end
        end
    end
    return job.status
end
function R.guia(v,gx,gz,target)
    local s=v.spec_transbordoInteligente
    if not TIConfiguracao.get(v,"usarRotas") then return nil end
    local x,_,z=getWorldTranslation(ref(v))
    if (x-gx)^2+(z-gz)^2<18^2 then s.navegacaoCampo=nil;return nil end
    local m=s.mapaCampo
    if m==nil or m.field~=s.talhao then m=R.iniciarMapa(v) end
    if m==nil then return {speed=0,message="Sem contorno valido para calcular a rota"} end
    if m.status~="pronto" then return {speed=0,message="Mapeando area interna do talhao"} end
    local job=s.navegacaoCampo
    if job==nil or job.target~=target or (job.gx-gx)^2+(job.gz-gz)^2>15^2 then
        job=R.iniciarRota(v,gx,gz,target);s.navegacaoCampo=job
    end
    if job==nil then return {speed=0,message="Aguardando mapa do campo"} end
    if job.status=="buscando" then R.avancar(job) end
    if job.status=="buscando" then return {speed=0,message="Calculando passagem dentro do talhao"} end
    if job.status~="pronto" then return {speed=0,message="Rota interna indisponivel; confira a posicao de entrada"} end
    local path=job.path
    while path[job.segment]~=nil and (path[job.segment].x-x)^2+(path[job.segment].z-z)^2<math.max(3,m.step*0.4)^2 do
        job.segment=job.segment+1
    end
    if path[job.segment]==nil then return nil end
    local nextPoint=path[job.segment]
    -- Mira adiante apenas quando o atalho conserva toda a folga do conjunto.
    for i=math.min(#path,job.segment+3),job.segment+1,-1 do
        if segment(m,job.others,x,z,path[i].x,path[i].z,m.radius) then
            nextPoint=path[i];job.segment=i;break
        end
    end
    return {x=nextPoint.x,z=nextPoint.z,message="Seguindo rota interna do talhao"}
end
