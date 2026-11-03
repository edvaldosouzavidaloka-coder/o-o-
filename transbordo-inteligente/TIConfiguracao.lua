-- Ajustes por trator. Nao altera a configuracao global nem desliga protecoes.
TIConfiguracao={}
local C=TIConfiguracao
C.CAMPOS={
    {key="velocidadeChegadaColheitadeira",label="Chegada na colheitadeira",value=25,min=5,max=40,step=1,unit="km/h",page="velocidades"},
    {key="velocidadeViagem",label="Viagem ate a carreta",value=15,min=5,max=30,step=1,unit="km/h",page="velocidades"},
    {key="velocidadeManobra",label="Manobra em area livre",value=8,min=2,max=12,step=1,unit="km/h",page="velocidades"},
    {key="velocidadeAlinhamento",label="Entrada e alinhamento",value=4,min=1.3,max=6,step=0.5,unit="km/h",page="velocidades"},
    {key="velocidadeRe",label="Re perto das maquinas",value=1.5,min=1.3,max=3,step=0.2,unit="km/h",page="velocidades"},
    {key="velocidadeReposicionar",label="Reposicionar por tras",value=3,min=1.3,max=5,step=0.5,unit="km/h",page="velocidades"},
    {key="offsetColheitadeira",label="Lateral da colheitadeira",value=0,min=-1.5,max=1.5,step=0.1,unit="m",page="ajustes"},
    {key="offsetCarreta",label="Lateral da carreta",value=0,min=-1,max=1,step=0.1,unit="m",page="ajustes"},
    {key="offsetLongitudinal",label="Avanco sob o cano",value=0,min=-2,max=2,step=0.1,unit="m",page="ajustes"},
    {key="recuoAproximacao",label="Entrada por tras / colheita",value=50,min=18,max=70,step=2,unit="m",page="ajustes"},
    {key="recuoCarreta",label="Entrada lateral / carreta",value=10,min=4,max=20,step=1,unit="m",page="ajustes"},
    {key="chamada",label="Chamar com tanque em",value=60,min=10,max=95,step=5,unit="%",page="ajustes"},
    {key="usarRotas",label="Rotas dentro do talhao",value=false},
    {key="hudAberto",label="Painel aberto",value=true},
    {key="hudX",label="Posicao horizontal",value=0.74,min=0.01,max=0.80,step=0.01},
    {key="hudY",label="Posicao vertical",value=0.20,min=0.04,max=0.35,step=0.01}
}
C.INDICE={}
for _,f in ipairs(C.CAMPOS) do C.INDICE[f.key]=f end

local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
function C.validar(key,value)
    local f=C.INDICE[key]
    if f==nil then return nil end
    if type(f.value)=="boolean" then
        if type(value)=="boolean" then return value end
        return f.value
    end
    if not finite(value) then return f.value end
    return math.max(f.min,math.min(f.max,value))
end
function C.nova()
    local result={}
    for _,f in ipairs(C.CAMPOS) do result[f.key]=f.value end
    return result
end
function C.get(v,key)
    local s=v.spec_transbordoInteligente
    local a=s~=nil and s.ajustes or nil
    if C.INDICE[key]~=nil then
        if a~=nil then return C.validar(key,a[key]) end
        return C.INDICE[key].value
    end
    return TransbordoInteligente.CONFIG[key]
end
function C.set(v,key,value)
    local f=C.INDICE[key]
    if f==nil then return false end
    local s=v.spec_transbordoInteligente
    if s==nil then return false end
    s.ajustes=s.ajustes or C.nova()
    s.ajustes[key]=C.validar(key,value)
    if key~="hudX" and key~="hudY" and key~="hudAberto" then
        s.manobraCarreta,s.mapaCarreta,s.navegacaoCampo,s.manobraEntrada=nil,nil,nil,nil
        s.entradaPelaTraseira=false
        s.aproximacaoConcluida,s.alinhandoEntrada=false,false
        if TransbordoInteligente.ajusteMudou~=nil then TransbordoInteligente.ajusteMudou(v,key) end
    end
    return true
end
function C.reset(v)
    for _,f in ipairs(C.CAMPOS) do if f.page~=nil then C.set(v,f.key,f.value) end end
end
function C.register(schema,base)
    if schema==nil or XMLValueType==nil then return end
    for _,f in ipairs(C.CAMPOS) do
        schema:register(type(f.value)=="boolean" and XMLValueType.BOOL or XMLValueType.FLOAT,base.."#"..f.key,f.label,f.value)
    end
end
function C.load(v,savegame,namespace)
    local s=v.spec_transbordoInteligente
    s.ajustes=C.nova()
    if savegame==nil or savegame.resetVehicles or savegame.xmlFile==nil then return end
    local key=savegame.key.."."..namespace
    for _,f in ipairs(C.CAMPOS) do s.ajustes[f.key]=C.validar(f.key,savegame.xmlFile:getValue(key.."#"..f.key,f.value)) end
end
function C.save(v,xml,key)
    for _,f in ipairs(C.CAMPOS) do xml:setValue(key.."#"..f.key,C.get(v,f.key)) end
end
