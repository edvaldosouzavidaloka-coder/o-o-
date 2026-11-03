-- Contorno fixo do talhao atual. Nao consulta cultura nem procura caminhos em ruas.
TITalhao={}
local T=TITalhao
local EPS=0.000001
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end

local function nearest(x,z,ax,az,bx,bz)
    local dx,dz=bx-ax,bz-az
    local d=dx*dx+dz*dz
    local t=d>EPS and math.max(0,math.min(1,((x-ax)*dx+(z-az)*dz)/d)) or 0
    local px,pz=ax+t*dx,az+t*dz
    return math.sqrt((px-x)^2+(pz-z)^2),px,pz
end

function T.criar(objeto,flat)
    if type(flat)~="table" or #flat<6 or #flat%2~=0 then return nil end
    local v={}
    for i=1,#flat,2 do
        local x,z=flat[i],flat[i+1]
        if not finite(x) or not finite(z) then return nil end
        if #v==0 or math.abs(x-v[#v-1])+math.abs(z-v[#v])>EPS then v[#v+1]=x;v[#v+1]=z end
    end
    if #v>=8 and math.abs(v[1]-v[#v-1])+math.abs(v[2]-v[#v])<EPS then v[#v]=nil;v[#v]=nil end
    local area=0
    for i=1,#v,2 do
        local j=i+2>#v and 1 or i+2
        area=area+v[i]*v[j+1]-v[j]*v[i+1]
    end
    if #v<6 or math.abs(area)<1 then return nil end
    return {objeto=objeto,vertices=v}
end

function T.distancia(t,x,z)
    local best,px,pz=math.huge,nil,nil
    local v=t.vertices
    for i=1,#v,2 do
        local j=i+2>#v and 1 or i+2
        local d,nx,nz=nearest(x,z,v[i],v[i+1],v[j],v[j+1])
        if d<best then best,px,pz=d,nx,nz end
    end
    return best,px,pz
end

function T.contem(t,x,z,margin)
    if t==nil or not finite(x) or not finite(z) then return false end
    local v,inside=t.vertices,false
    for i=1,#v,2 do
        local j=i+2>#v and 1 or i+2
        local ax,az,bx,bz=v[i],v[i+1],v[j],v[j+1]
        if (az>z)~=(bz>z) and x<(bx-ax)*(z-az)/(bz-az)+ax then inside=not inside end
    end
    local distance=T.distancia(t,x,z)
    return (inside or distance<EPS) and distance+EPS>=(margin or 0),distance
end

local function cross(ax,az,bx,bz) return ax*bz-az*bx end
local function intersect(ax,az,bx,bz,cx,cz,dx,dz)
    local ux,uz,vx,vz=bx-ax,bz-az,dx-cx,dz-cz
    local denom=cross(ux,uz,vx,vz)
    if math.abs(denom)>EPS then
        local a=cross(cx-ax,cz-az,vx,vz)/denom
        local b=cross(cx-ax,cz-az,ux,uz)/denom
        return a>=-EPS and a<=1+EPS and b>=-EPS and b<=1+EPS
    end
    return nearest(ax,az,cx,cz,dx,dz)<EPS or nearest(bx,bz,cx,cz,dx,dz)<EPS
        or nearest(cx,cz,ax,az,bx,bz)<EPS or nearest(dx,dz,ax,az,bx,bz)<EPS
end

function T.segmentoDentro(t,ax,az,bx,bz,margin)
    margin=margin or 0
    if not T.contem(t,ax,az,margin) or not T.contem(t,bx,bz,margin) then return false end
    local v=t.vertices
    for i=1,#v,2 do
        local j=i+2>#v and 1 or i+2
        local cx,cz,dx,dz=v[i],v[i+1],v[j],v[j+1]
        if intersect(ax,az,bx,bz,cx,cz,dx,dz) then return false end
        local gap=math.min((nearest(ax,az,cx,cz,dx,dz)),(nearest(bx,bz,cx,cz,dx,dz)),
            (nearest(cx,cz,ax,az,bx,bz)),(nearest(dx,dz,ax,az,bx,bz)))
        if gap+EPS<margin then return false end
    end
    return true
end

function T.retanguloDentro(t,body,margin)
    local inside,distance=T.contem(t,body.x,body.z)
    if not inside then return false end
    -- Em espaco aberto, o circulo que contem a carroceria basta. As arestas
    -- completas ficam para a proximidade da borda e para recortes concavos.
    if distance>=math.sqrt(body.hw^2+body.hl^2)+(margin or 0)+EPS then return true end
    local vertices={}
    for _,p in ipairs({{-body.hw,-body.hl},{body.hw,-body.hl},{body.hw,body.hl},{-body.hw,body.hl}}) do
        vertices[#vertices+1]={x=body.x+math.cos(body.a)*p[1]+math.sin(body.a)*p[2],
            z=body.z-math.sin(body.a)*p[1]+math.cos(body.a)*p[2]}
    end
    for i,p in ipairs(vertices) do
        local q=vertices[i%4+1]
        if not T.segmentoDentro(t,p.x,p.z,q.x,q.z,margin) then return false end
    end
    return true
end

-- Projeta somente pontos de manobra para o lado interno. A frenagem ainda
-- verifica toda a trajetoria proxima; nao transforma isso em uma rota garantida.
function T.pontoInterno(t,x,z,margin)
    if T.contem(t,x,z,margin) then return x,z end
    local best,bx,bz=math.huge,nil,nil
    local v=t.vertices
    for i=1,#v,2 do
        local j=i+2>#v and 1 or i+2
        local _,px,pz=nearest(x,z,v[i],v[i+1],v[j],v[j+1])
        local dx,dz=v[j]-v[i],v[j+1]-v[i+1]
        local length=math.sqrt(dx*dx+dz*dz)
        if length>EPS then
            for _,sign in ipairs({-1,1}) do
                local cx,cz=px-sign*dz/length*(margin+0.1),pz+sign*dx/length*(margin+0.1)
                local d=(cx-x)^2+(cz-z)^2
                if d<best and T.contem(t,cx,cz,margin) then best,bx,bz=d,cx,cz end
            end
        end
    end
    return bx,bz
end
