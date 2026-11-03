-- Painel lateral nativo. Nenhum aviso de conducao e desenhado no centro da tela.
TIHUD={buttons={},tab="controle",cursor=false}
local H=TIHUD
H.CORES={fundo={0.025,0.037,0.048,0.96},cabecalho={0.05,0.073,0.086,1},
    linha={0.11,0.15,0.17,1},texto={0.91,0.95,0.96,1},suave={0.58,0.68,0.72,1},
    verde={0.23,0.83,0.52,1},escuro={0.04,0.23,0.15,1},aviso={1,0.72,0.30,1}}
local function inside(x,y,b) return x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h end
local function menu() return g_gui~=nil and g_gui.getIsGuiVisible~=nil and g_gui:getIsGuiVisible() end
function H.cursorAtivo(v,active)
    if not active then
        if H.cursor then
            for camera,value in pairs(H.cameras or {}) do camera.isRotatable=value.value end
            if g_inputBinding~=nil and g_inputBinding.setShowMouseCursor~=nil then
                g_inputBinding:setShowMouseCursor(H.previousCursor==true)
            end
        end
        H.cursor,H.cameras,H.drag=false,nil,nil
        return
    end
    if H.cursor then H.cursorAtivo(v,false) end
    H.vehicle,H.cursor,H.cameras=v,true,{}
    H.previousCursor=g_inputBinding~=nil and g_inputBinding.getShowMouseCursor~=nil and g_inputBinding:getShowMouseCursor() or false
    for _,camera in pairs(v.spec_enterable~=nil and v.spec_enterable.cameras or {}) do
        H.cameras[camera]={value=camera.isRotatable};camera.isRotatable=false
    end
    if g_inputBinding~=nil and g_inputBinding.setShowMouseCursor~=nil then g_inputBinding:setShowMouseCursor(true) end
    TIConfiguracao.set(v,"hudAberto",true)
end
function H.toggle(v)
    local open=not TIConfiguracao.get(v,"hudAberto")
    TIConfiguracao.set(v,"hudAberto",open)
    if not open then H.cursorAtivo(v,false) end
end
local function rect(x,y,w,h,color)
    if H.renderRect~=nil then H.renderRect(x,y,w,h,color);return end
    if H.overlay==nil and Overlay~=nil then H.overlay=Overlay.new("dataS/menu/base/graph_pixel.dds",0,0,1,1) end
    if H.overlay~=nil then
        H.overlay:setPosition(x,y);H.overlay:setDimension(w,h);H.overlay:setColor(unpack(color));H.overlay:render()
    end
end
local function text(x,y,size,value,color)
    if renderText==nil then return end
    setTextColor(unpack(color or H.CORES.texto))
    renderText(x,y,size,tostring(value or ""))
end
local function name(v)
    if v==nil then return "Nenhum veiculo selecionado" end
    if v.getName~=nil then local ok,value=pcall(v.getName,v);if ok and type(value)=="string" then return value end end
    return v.spec_combine~=nil and "Colheitadeira" or "Carreta"
end
local function wrap(value,maxChars)
    local lines,line={},""
    for word in tostring(value or ""):gmatch("%S+") do
        if #line+#word+1>maxChars and line~="" then lines[#lines+1]=line;line="" end
        line=line=="" and word or line.." "..word
    end
    if line~="" then lines[#lines+1]=line end
    return lines
end
local function button(id,label,x,y,w,h,callback,selected)
    local b={id=id,x=x,y=y,w=w,h=h,callback=callback}
    H.buttons[#H.buttons+1]=b
    local hover=H.cursor and H.mouseX~=nil and inside(H.mouseX,H.mouseY,b)
    rect(x,y,w,h,selected and H.CORES.escuro or (hover and H.CORES.linha or H.CORES.cabecalho))
    if selected then rect(x,y,0.002,h,H.CORES.verde) end
    text(x+0.007,y+h/2-0.005,0.0115,label,selected and H.CORES.verde or H.CORES.texto)
end
local function fieldName(s)
    local field=s.talhao~=nil and s.talhao.objeto or nil
    if field==nil and s.mapaCampo~=nil then field=s.mapaCampo.field.objeto end
    if field~=nil and field.getId~=nil then local ok,id=pcall(field.getId,field);if ok then return "Campo "..tostring(id) end end
    return s.talhao~=nil and "Talhao fixado" or "Ative dentro do talhao"
end
local states={[1]="Desligado",[2]="Buscando colheitadeira",[3]="Entrada na colheitadeira",[4]="Recebendo graos",
    [5]="Buscando carreta",[6]="Entrada na carreta",[7]="Descarregando",[8]="Saindo da lateral",
    [9]="Aguardando",[10]="Esperando proxima carga",[11]="Repetindo alinhamento"}
local function mapLine(ax,az,bx,bz,color)
    if H.renderLine~=nil then H.renderLine(ax,az,bx,bz,color);return end
    if H.renderRect==nil and Overlay~=nil then
        if H.lineOverlay==nil then H.lineOverlay=Overlay.new("dataS/menu/base/graph_pixel.dds",0,0,1,1) end
        local aspect=g_screenAspectRatio or 16/9
        local dx,dy=(bx-ax)*aspect,bz-az
        H.lineOverlay:setPosition(ax,az)
        H.lineOverlay:setDimension(math.sqrt(dx*dx+dy*dy)/aspect,0.0012)
        H.lineOverlay:setRotation(math.atan2(dy,dx),0,0)
        H.lineOverlay:setColor(unpack(color));H.lineOverlay:render()
        return
    end
    local count=math.max(1,math.ceil(math.sqrt((bx-ax)^2+(bz-az)^2)/0.0025))
    for i=0,math.min(count,100) do
        local t=i/math.min(count,100)
        rect(ax+(bx-ax)*t,az+(bz-az)*t,0.0012,0.0017,color)
    end
end
function H.desenharMapa(v,x,y,w,h)
    local s=v.spec_transbordoInteligente
    local m=s.mapaCampo
    rect(x,y,w,h,H.CORES.cabecalho)
    if m==nil then text(x+0.01,y+h/2,0.011,"Mapeie o talhao para visualizar",H.CORES.suave);return end
    local spanX,spanZ=m.maxX-m.minX,m.maxZ-m.minZ
    local aspect=g_screenAspectRatio or 16/9
    local scale=math.min((w-0.02)*aspect/math.max(1,spanX),(h-0.02)/math.max(1,spanZ))
    local function p(wx,wz) return x+w/2+(wx-(m.minX+m.maxX)/2)*scale/aspect,y+h/2-(wz-(m.minZ+m.maxZ)/2)*scale end
    local vertices=m.field.vertices
    for i=1,#vertices,2 do
        local j=i+2>#vertices and 1 or i+2
        local ax,az=p(vertices[i],vertices[i+1]);local bx,bz=p(vertices[j],vertices[j+1])
        mapLine(ax,az,bx,bz,H.CORES.verde)
    end
    local stride=math.max(1,math.floor(math.sqrt(m.nx*m.nz/120)))
    for iz=1,m.nz,stride do for ix=1,m.nx,stride do
        local id=(iz-1)*m.nx+ix
        if m.cells[id] then local wx,wz=TIRotasCampo.ponto(m,id);local px,pz=p(wx,wz);rect(px,pz,0.0015,0.002,H.CORES.linha) end
    end end
    local job=s.navegacaoCampo
    if job~=nil and job.path~=nil then
        for i=2,#job.path do
            local a,b=job.path[i-1],job.path[i]
            local ax,az=p(a.x,a.z);local bx,bz=p(b.x,b.z);mapLine(ax,az,bx,bz,H.CORES.aviso)
        end
    end
    for _,vehicle in ipairs({v,s.colheitadeiraAlvo or false,s.caminhaoAlvo or false}) do
        if vehicle and vehicle.rootNode~=nil then
            local wx,_,wz=getWorldTranslation(vehicle.rootNode);local px,pz=p(wx,wz)
            px,pz=math.max(x+0.004,math.min(x+w-0.004,px)),math.max(y+0.006,math.min(y+h-0.006,pz))
            rect(px-0.002,pz-0.003,0.004,0.006,vehicle==v and H.CORES.texto or H.CORES.aviso)
        end
    end
end
function H.drawVehicle(v)
    local s=v.spec_transbordoInteligente
    if s==nil or menu() then H.cursorAtivo(v,false);return end
    if H.vehicle~=v then H.cursorAtivo(H.vehicle,false);H.vehicle=v end
    if RenderText~=nil then setTextAlignment(RenderText.ALIGN_LEFT);setTextBold(false) end
    H.buttons={}
    local x,y=TIConfiguracao.get(v,"hudX"),TIConfiguracao.get(v,"hudY")
    local w,h=0.245,0.68
    x,y=math.min(x,0.99-w),math.min(y,0.97-h)
    local open=TIConfiguracao.get(v,"hudAberto")
    if not open then
        H.bounds={x=x,y=y,w=w,h=0.045}
        rect(x,y,w,0.045,H.CORES.fundo);rect(x,y,0.003,0.045,H.CORES.verde)
        button("abrir","TRANSBORDO PRO  +",x+0.008,y+0.006,w-0.016,0.032,function() H.toggle(v) end)
        if setTextColor~=nil then setTextColor(1,1,1,1) end
        return
    end
    H.bounds={x=x,y=y,w=w,h=h}
    local top=y+h
    rect(x,y,w,h,H.CORES.fundo);rect(x,top-0.052,w,0.052,H.CORES.cabecalho)
    rect(x,top-0.052,0.003,0.052,H.CORES.verde)
    setTextAlignment(RenderText.ALIGN_LEFT);setTextBold(true)
    text(x+0.012,top-0.025,0.016,"TRANSBORDO PRO")
    setTextBold(false)
    text(x+0.153,top-0.023,0.0105,TransbordoInteligente.VERSAO,H.CORES.suave)
    button("fechar","-",x+w-0.027,top-0.036,0.019,0.026,function() H.toggle(v) end)
    button("drag","::",x+w-0.05,top-0.036,0.019,0.026,function() end)
    rect(x+0.012,top-0.083,0.005,0.008,s.isAtivo and H.CORES.verde or H.CORES.suave)
    text(x+0.023,top-0.084,0.013,states[s.estadoAtual] or "Aguardando")
    local message=s.mensagemNavegacao or (s.estadoAtual==5 and s.motivoBuscaDestino)
        or s.mensagem or "Pronto para trabalhar neste talhao"
    local lines=wrap(message,43)
    text(x+0.012,top-0.109,0.0115,lines[1],H.CORES.suave)
    text(x+0.012,top-0.126,0.0115,lines[2],H.CORES.suave)
    local target=s.caminhaoAlvo or s.colheitadeiraAlvo
    local targetLines=wrap("Alvo: "..name(target),40)
    text(x+0.012,top-0.151,0.012,targetLines[1])
    local distance=0
    if target~=nil then local ax,_,az=getWorldTranslation(v.rootNode);local bx,_,bz=getWorldTranslation(target.rootNode);distance=math.sqrt((ax-bx)^2+(az-bz)^2) end
    text(x+0.012,top-0.172,0.0115,fieldName(s)..string.format("  |  %.0f m",distance),H.CORES.suave)
    local wagon=s.bazuca or TransbordoInteligente.encontrarBazuca(v)
    local cargo=wagon~=nil and TransbordoInteligente.getCarga(wagon) or nil
    local percentage=cargo~=nil and cargo.percentual or 0
    rect(x+0.012,top-0.187,w-0.024,0.004,H.CORES.linha)
    rect(x+0.012,top-0.187,(w-0.024)*math.min(1,percentage/100),0.004,H.CORES.verde)
    local pages={{"controle","CONTROLE"},{"velocidades","VELOC."},{"ajustes","AJUSTES"},{"campo","CAMPO"}}
    for i,page in ipairs(pages) do
        local id=page[1]
        button("tab_"..id,page[2],x+0.009+(i-1)*(w-0.018)/4,top-0.23,(w-0.021)/4,0.029,
            function() H.tab=id end,H.tab==id)
    end
    local content=top-0.268
    if H.tab=="controle" then
        text(x+0.013,content,0.010,"OPERACAO  /  BAZUCA "..string.format("%.0f%%",percentage),H.CORES.suave)
        button("ligar",s.isAtivo and "PARAR" or "INICIAR",x+0.012,content-0.052,(w-0.03)/2,0.036,
            function() TransbordoInteligente.actionEventToggleTransbordo(v,nil,1) end,s.isAtivo)
        button("descarregar","DESCARREGAR",x+w/2+0.003,content-0.052,(w-0.03)/2,0.036,
            function() TransbordoInteligente.actionEventForcarDescarga(v,nil,1) end)
        button("buscar","BUSCAR COLHEITADEIRA 360",x+0.012,content-0.099,w-0.024,0.035,
            function() TransbordoInteligente.forcarBusca(v,false) end)
        button("proximo","PROXIMA COLHEITADEIRA",x+0.012,content-0.142,w-0.024,0.032,
            function() TransbordoInteligente.forcarBusca(v,true) end)
        text(x+0.013,content-0.183,0.010,"GEOMETRIA DO CONJUNTO",H.CORES.suave)
        local pipe=s.mapaCarreta~=nil and s.mapaCarreta.alcance or s.alcanceCano or 0
        text(x+0.013,content-0.209,0.011,string.format("Cano: %.1f m  |  Plataforma: %.1f m%s",pipe,
            s.larguraPlataforma or 0,s.larguraPlataformaEstimada and " (estimada)" or ""))
        local map=s.mapaCarreta
        if map~=nil then
            text(x+0.013,content-0.235,0.0105,string.format("Cacamba %.1f x %.1f m%s | Bazuca %.1f m",map.largura,
                map.comprimento,map.estimada and " (estimada)" or "",map.larguraBazuca))
            text(x+0.013,content-0.26,0.0105,string.format("Posicoes livres no talhao: %d",#map.vagas),H.CORES.suave)
            text(x+0.013,content-0.282,0.010,string.format("Folga lateral ate %.2f m",math.max(0,map.folga or 0)),H.CORES.suave)
        end
        button("rotas",TIConfiguracao.get(v,"usarRotas") and "ROTAS INTERNAS: LIGADAS" or "ROTAS INTERNAS: DESLIGADAS",
            x+0.012,content-0.349,w-0.024,0.033,function() TIConfiguracao.set(v,"usarRotas",not TIConfiguracao.get(v,"usarRotas")) end,
            TIConfiguracao.get(v,"usarRotas"))
    elseif H.tab=="velocidades" or H.tab=="ajustes" then
        local row=0
        for _,f in ipairs(TIConfiguracao.CAMPOS) do
            if f.page==H.tab then
                local key,step=f.key,f.step
                local yy=content-row*0.053
                text(x+0.013,yy,0.012,f.label,H.CORES.suave)
                text(x+0.013,yy-0.024,0.013,string.format("%.1f %s",TIConfiguracao.get(v,key),f.unit))
                button("menos_"..key,"-",x+w-0.086,yy-0.029,0.032,0.027,function() TIConfiguracao.set(v,key,TIConfiguracao.get(v,key)-step) end)
                button("mais_"..key,"+",x+w-0.048,yy-0.029,0.032,0.027,function() TIConfiguracao.set(v,key,TIConfiguracao.get(v,key)+step) end)
                row=row+1
            end
        end
        button("padrao","RESTAURAR AJUSTES PADRAO",x+0.012,content-0.357,w-0.024,0.031,function() TIConfiguracao.reset(v) end)
        if H.tab=="ajustes" then text(x+0.012,content-0.38,0.009,"Lateral +: direita do alvo. -: esquerda.",H.CORES.suave) end
    elseif H.tab=="campo" then
        local m=s.mapaCampo
        local status=m==nil and "Campo ainda nao mapeado" or (m.status=="pronto" and "Mapa pronto / rotas apenas neste talhao"
            or string.format("Mapeando campo... %.0f%%",math.min(100,(m.next-1)/(m.nx*m.nz)*100)))
        text(x+0.012,content,0.010,status,H.CORES.suave)
        H.desenharMapa(v,x+0.012,content-0.254,w-0.024,0.235)
        button("mapear","MAPEAR / RECALCULAR CAMPO",x+0.012,content-0.302,w-0.024,0.032,function() TIRotasCampo.iniciarMapa(v) end)
        button("usar_rotas",TIConfiguracao.get(v,"usarRotas") and "ROTAS INTERNAS: LIGADAS" or "ATIVAR ROTAS INTERNAS",
            x+0.012,content-0.347,w-0.024,0.032,function() TIConfiguracao.set(v,"usarRotas",not TIConfiguracao.get(v,"usarRotas")) end,
            TIConfiguracao.get(v,"usarRotas"))
        text(x+0.012,content-0.372,0.009,"Branco: trator | Amarelo: alvo / rota",H.CORES.suave)
    end
    rect(x,y+0.018,w,0.001,H.CORES.linha)
    text(x+0.012,y+0.005,0.009,"Ctrl+Alt+H painel | Ctrl+Alt+M mouse",H.CORES.suave)
    setTextColor(1,1,1,1);setTextBold(false);setTextAlignment(RenderText.ALIGN_LEFT)
end
function H:mouseEvent(x,y,isDown,isUp,buttonId)
    H.mouseX,H.mouseY=x,y
    local v=H.vehicle
    if not H.cursor or v==nil or menu() or v.getIsEntered==nil or not v:getIsEntered() then return false end
    local left=Input~=nil and Input.MOUSE_BUTTON_LEFT or 1
    if H.drag~=nil then
        if isUp then H.drag=nil;return true end
        TIConfiguracao.set(v,"hudX",x-H.drag.x);TIConfiguracao.set(v,"hudY",y-H.drag.y)
        return true
    end
    if isDown and buttonId==left then
        for i=#H.buttons,1,-1 do
            local b=H.buttons[i]
            if inside(x,y,b) then
                if b.id=="drag" then H.drag={x=x-H.bounds.x,y=y-H.bounds.y} else b.callback() end
                return true
            end
        end
    end
    return H.bounds~=nil and inside(x,y,H.bounds)
end
function H:update(dt)
    local v=H.vehicle
    if H.cursor and (v==nil or v.isDeleted or v.getIsEntered==nil or not v:getIsEntered() or menu()) then H.cursorAtivo(v,false) end
end
function H:keyEvent(unicode,sym,mod,isDown)
    if isDown and Input~=nil and sym==Input.KEY_esc and H.cursor then H.cursorAtivo(H.vehicle,false) end
end
function H:deleteMap()
    H.cursorAtivo(H.vehicle,false)
    if H.overlay~=nil then H.overlay:delete();H.overlay=nil end
    if H.lineOverlay~=nil then H.lineOverlay:delete();H.lineOverlay=nil end
    H.vehicle,H.buttons=nil,{}
end
if addModEventListener~=nil then addModEventListener(H) end
