-- Clickable in-game GPS monitor. Cursor and vehicle-camera ownership stay in
-- TGGPS; this class owns layout, drawing, pointer capture and configuration.
TGGPSHud = {}
TGGPSHud.__index = TGGPSHud

local WIDTH, HEIGHT = 1040, 660
local MIN_SCALE, MAX_SCALE = 0.75, 1.25
local DEFAULT_X, DEFAULT_Y = 0.42, 0.18
local MARGIN = 0.01
local COLORS = {
    shadow={0,0,0,0.48},frame={0.025,0.06,0.04,1},background={0.89,0.90,0.85,1},
    header={0.025,0.36,0.16,1},card={0.97,0.97,0.93,1},border={0.66,0.70,0.62,1},
    ink={0.06,0.11,0.08,1},white={1,1,1,1},muted={0.34,0.40,0.35,1},
    green={0.02,0.42,0.18,1},red={0.65,0.08,0.07,1},blue={0.1,0.34,0.5,1},
    button={0.88,0.90,0.84,1},hover={0.72,0.83,0.67,1},pressed={0.55,0.74,0.50,1},
    active={0.65,0.82,0.54,1},danger={0.95,0.75,0.69,1},disabled={0.82,0.83,0.79,1}
}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function inside(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function guiVisible()
    return g_gui ~= nil and type(g_gui.getIsGuiVisible) == "function" and g_gui:getIsGuiVisible()
end

local function characterCount(value)
    local stripped = tostring(value):gsub("[\128-\191]", "")
    return #stripped
end

local function wrapText(value, maxCharacters, maxLines)
    local lines, current = {}, ""
    for word in tostring(value or ""):gmatch("%S+") do
        local nextLine = current == "" and word or current .. " " .. word
        if current ~= "" and characterCount(nextLine) > maxCharacters then
            lines[#lines + 1] = current
            if #lines >= maxLines then
                lines[maxLines] = lines[maxLines] .. "..."
                return lines
            end
            current = word
        else
            current = nextLine
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    return lines
end

function TGGPSHud.new(owner)
    local self = setmetatable({}, TGGPSHud)
    self.owner = owner
    self.isOpen = false
    self.x, self.y, self.scale = DEFAULT_X, DEFAULT_Y, 1
    self.page = "map"
    self.pointerX, self.pointerY = -1, -1
    self.pressedId, self.drag = nil, nil
    self.overlay = nil
    self.lineOverlayId = nil
    self:_layout()
    return self
end

function TGGPSHud:_layout()
    local sw = finite(g_screenWidth) and math.max(1, g_screenWidth) or 1920
    local sh = finite(g_screenHeight) and math.max(1, g_screenHeight) or 1080
    local pixels = math.min(sw / 1920, sh / 1080) * self.scale
    self.unitX, self.unitY = pixels / sw, pixels / sh
    local w, h = WIDTH * self.unitX, HEIGHT * self.unitY
    self.x = clamp(self.x, MARGIN, math.max(MARGIN, 1 - MARGIN - w))
    self.y = clamp(self.y, MARGIN, math.max(MARGIN, 1 - MARGIN - h))
    self.bounds = {x = self.x, y = self.y, w = w, h = h}
end

function TGGPSHud:getBounds()
    self:_layout()
    return {x = self.bounds.x, y = self.bounds.y, w = self.bounds.w, h = self.bounds.h}
end

function TGGPSHud:_rect(x, y, w, h)
    return {x = self.x + x * self.unitX, y = self.y + (HEIGHT - y - h) * self.unitY,
        w = w * self.unitX, h = h * self.unitY}
end

function TGGPSHud:getSettings()
    self:_layout()
    return {x = self.x, y = self.y, scale = self.scale}
end

function TGGPSHud:applySettings(settings)
    settings = type(settings) == "table" and settings or {}
    if finite(settings.scale) then self.scale = clamp(settings.scale, MIN_SCALE, MAX_SCALE) end
    if finite(settings.x) then self.x = settings.x end
    if finite(settings.y) then self.y = settings.y end
    self:_layout()
end

function TGGPSHud:_saveSettings()
    if self.owner ~= nil and type(self.owner.saveHudSettings) == "function" then
        self.owner:saveHudSettings()
    end
end

function TGGPSHud:resetPosition()
    self.x, self.y = DEFAULT_X, DEFAULT_Y
    self:_layout()
    self:_saveSettings()
end

function TGGPSHud:setOpen(open)
    self.isOpen = open == true
    self.pressedId, self.drag = nil, nil
    self.pointerX, self.pointerY = -1, -1
    self:_layout()
end

function TGGPSHud:_available()
    if not self.isOpen or self.owner == nil or guiVisible() then return false end
    if type(self.owner.getControlledVehicle) ~= "function" then return false end
    local vehicle = self.owner:getControlledVehicle()
    if vehicle == nil then return false end
    if type(vehicle.getIsActiveForInput) == "function" and not vehicle:getIsActiveForInput(true, true) then
        return false
    end
    return true
end

function TGGPSHud:getButtons()
    if not self:_available() then return {} end
    self:_layout()
    local o, buttons = self.owner, {}
    local route = type(o.sourcePoints)=="table" and #o.sourcePoints>=2
    local function b(id,label,x,y,w,h,action,enabled,active,tone)
        local v=self:_rect(x,y,w,h)
        v.id,v.label,v.action,v.enabled,v.active,v.tone=id,label,action,enabled~=false,active==true,tone
        buttons[#buttons+1]=v
    end
    b("close","X",1000,10,26,26,"close")
    for i,item in ipairs({{"map","MAPA"},{"guide","LINHAS"},{"headland","CABECEIRA"},{"library","TRAJETOS"},{"settings","MONITOR"}}) do
        b("tab_"..item[1],item[2],20+(i-1)*204,546,196,36,item[1],true,self.page==item[1])
    end
    if self.page=="map" then
        b("lane_prev","< PASSADA",820,110,94,32,"onLanePrevious",route)
        b("lane_next","PASSADA >",922,110,90,32,"onLaneNext",route)
        b("nudge_left","- 10 cm",820,187,94,32,"onNudgeLineLeft",route)
        b("nudge_right","+ 10 cm",922,187,90,32,"onNudgeLineRight",route)
        b("snap_line","PUXAR ATE A MAQUINA",820,229,192,34,"onSnapLine",route)
        b("reset_shift","ZERAR DESLOCAMENTO",820,273,192,30,"onResetTrackOffset",route)
        b("map_zoom_out","-",820,345,52,32,"onZoomOut",TGGPSMap.getZoom(o)>1)
        b("map_fit","PADRAO",880,345,72,32,"onZoomFit")
        b("map_zoom_in","+",960,345,52,32,"onZoomIn",TGGPSMap.getZoom(o)<12)
        b("headland_toggle",o.headlandEnabled and "CABECEIRA: LIGADA" or "CABECEIRA: DESLIGADA",820,402,192,34,"onToggleHeadland",o.mode=="field",o.headlandEnabled)
        b("save","SALVAR LINHA",820,446,192,32,"onSaveNamedCourse",route)
        b("load","BUSCAR TRAJETO",820,488,192,32,"library")
        b("enable","LIGAR PILOTO",214,486,184,36,"onEnableAutosteer",route and not o.autosteerEnabled,o.autosteerEnabled,"green")
        b("disable","DESLIGAR",408,486,184,36,"onDisableAutosteer",o.autosteerEnabled,false,"red")
        b("generate_field","GERAR TALHAO",602,486,197,36,"onGenerateField",true,false,"blue")
    elseif self.page=="guide" then
        for i,v in ipairs({{"mark_ab",o.pointA and "MARCAR PONTO B" or "MARCAR A/B","onMarkAB"},
            {"record_curve",o.isRecording and "FINALIZAR CURVA" or "GRAVAR CURVA","onRecordCurve"},
            {"toggle_lines",o.showLines and "LINHAS VISIVEIS" or "LINHAS OCULTAS","onToggleLines"}}) do
            b(v[1],v[2],214+(i-1)*274,174,258,40,v[3])
        end
        b("width_down","- LARGURA",214,236,190,38,"onWidthDown",o.width>1)
        b("detect_width","DETECTAR IMPLEMENTO",418,236,398,38,"onDetectWidth")
        b("width_up","LARGURA +",830,236,190,38,"onWidthUp",o.width<50)
        b("lane_prev","< PASSADA",214,298,258,38,"onLanePrevious",route)
        b("auto_lane",o.autoLaneSelection and "SELECAO AUTOMATICA" or "SELECAO MANUAL",488,298,258,38,"onToggleAutoLane",true,o.autoLaneSelection)
        b("lane_next","PASSADA >",762,298,258,38,"onLaneNext",route)
        b("nudge_left","LINHA - 10 cm",214,360,258,38,"onNudgeLineLeft",route)
        b("snap_line","PUXAR ATE A MAQUINA",488,360,258,38,"onSnapLine",route)
        b("nudge_right","LINHA + 10 cm",762,360,258,38,"onNudgeLineRight",route)
        b("save","SALVAR COM NOME",214,432,392,40,"onSaveNamedCourse",route)
        b("clear","LIMPAR TRAJETO DA TELA",622,432,398,40,"onClear",route or o.pointA~=nil,false,"red")
    elseif self.page=="headland" then
        b("headland_toggle",o.headlandEnabled and "CABECEIRA AUTOMATICA LIGADA" or "ATIVAR CABECEIRA AUTOMATICA",214,120,806,40,"onToggleHeadland",o.mode=="field",o.headlandEnabled)
        for i,v in ipairs({{"headland_depth","onHeadlandDepthDown","onHeadlandDepthUp"},{"headland_speed","onTurnSpeedDown","onTurnSpeedUp"},{"headland_radius","onTurnRadiusDown","onTurnRadiusUp"}}) do
            b(v[1].."_down","-",814,190+(i-1)*82,90,44,v[2])
            b(v[1].."_up","+",918,190+(i-1)*82,90,44,v[3])
        end
        b("headland_direction","INVERTER LADO DA PROXIMA PASSADA",214,454,806,40,"onToggleTurnDirection")
    elseif self.page=="library" then
        b("save_named","SALVAR ATUAL",214,76,252,34,"onSaveNamedCourse",route)
        b("search_courses","BUSCAR NOME / TALHAO",480,76,330,34,"onSearchCourses")
        b("clear_search","VER TODOS",824,76,196,34,"clear_search")
        local records=o.library:list(o.libraryFilter)
        local pages=math.max(1,math.ceil(#records/4))
        o.libraryPage=math.max(1,math.min(pages,o.libraryPage or 1))
        for row=1,4 do
            local r=records[(o.libraryPage-1)*4+row]
            if r then b("load_course_"..r.id,"CARREGAR",874,142+(row-1)*82,134,36,"load_course:"..r.id) end
        end
        b("library_prev","< ANTERIOR",214,488,190,34,"library_prev",o.libraryPage>1)
        b("library_next","PROXIMA >",830,488,190,34,"library_next",o.libraryPage<pages)
    else
        b("scale_down","-",814,120,90,42,"scale_down",self.scale>MIN_SCALE+0.001)
        b("scale_up","+",918,120,90,42,"scale_up",self.scale<MAX_SCALE-0.001)
        b("reset_position","CENTRALIZAR PAINEL",714,200,294,42,"reset_position")
        b("edit_cab","AJUSTAR POSICAO DO MONITOR NA CABINE",214,298,806,44,"onEditMonitor")
        b("map_zoom_out","ZOOM -",214,378,252,38,"onZoomOut",TGGPSMap.getZoom(o)>1)
        b("map_fit","ZOOM PADRAO / SEGUIR MAQUINA",480,378,330,38,"onZoomFit")
        b("map_zoom_in","ZOOM +",824,378,196,38,"onZoomIn",TGGPSMap.getZoom(o)<12)
        b("reset_coverage","ZERAR PINTURA DESTA SESSAO",214,468,806,40,"onResetCoverage",true,false,"red")
    end
    return buttons
end

function TGGPSHud:_run(button)
    local a=button.action
    if a=="close" then self.owner:closeHud()
    elseif a=="map" or a=="guide" or a=="headland" or a=="library" or a=="settings" then self.page=a
    elseif a=="scale_down" or a=="scale_up" then
        self.scale=clamp(self.scale+(a=="scale_up" and 0.1 or -0.1),MIN_SCALE,MAX_SCALE)
        self:_layout();self:_saveSettings()
    elseif a=="reset_position" then self:resetPosition()
    elseif a=="clear_search" then self.owner.libraryFilter,self.owner.libraryPage="",1
    elseif a=="library_prev" then self.owner.libraryPage=math.max(1,self.owner.libraryPage-1)
    elseif a=="library_next" then self.owner.libraryPage=self.owner.libraryPage+1
    elseif a:match("^load_course:%d+$") then self.owner:loadNamedCourse(tonumber(a:match("(%d+)$")))
    elseif type(self.owner[a])=="function" then self.owner[a](self.owner,nil,1) end
end

function TGGPSHud:mouseEvent(posX, posY, isDown, isUp, button)
    if not self:_available() then
        self.pressedId, self.drag = nil, nil
        return false
    end
    if not finite(posX) or not finite(posY) then return false end
    self.pointerX, self.pointerY = posX, posY
    self:_layout()
    local left = Input ~= nil and Input.MOUSE_BUTTON_LEFT or 1
    if (isDown or isUp) and button ~= left then return false end

    if self.drag ~= nil then
        self.x, self.y = posX - self.drag.x, posY - self.drag.y
        self:_layout()
        if isUp then
            self.drag = nil
            self:_saveSettings()
        end
        return true
    end

    local underPointer
    for _, candidate in ipairs(self:getButtons()) do
        if inside(candidate, posX, posY) then underPointer = candidate break end
    end
    if isDown then
        self.pressedId = nil
        if underPointer ~= nil then
            if underPointer.enabled then self.pressedId = underPointer.id end
            return true
        end
        if inside(self:_rect(0, 0, WIDTH, 54), posX, posY) then
            self.drag = {x = posX - self.x, y = posY - self.y}
            return true
        end
        return inside(self.bounds, posX, posY)
    end
    if isUp then
        local pressed = self.pressedId
        self.pressedId = nil
        if pressed ~= nil and underPointer ~= nil and pressed == underPointer.id and underPointer.enabled then
            self:_run(underPointer)
            return true
        end
        return pressed ~= nil or inside(self.bounds, posX, posY)
    end
    return inside(self.bounds, posX, posY)
end

-- Draw commands are the actual monitor primitives, also usable by an offline
-- renderer to inspect the layout without substituting a mock app screenshot.
function TGGPSHud:getDrawCommands()
    if not self:_available() then return {} end
    self:_layout()
    local o,c,commands=self.owner,self.owner:getMonitorContext(),{}
    local function rect(x,y,w,h,color)
        local e=self:_rect(x,y,w,h);e.type,e.color="rect",color;commands[#commands+1]=e
    end
    local function short(value,n)
        local chars={}
        for ch in tostring(value or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=ch end
        if #chars>(n or 30) then return table.concat(chars,"",1,(n or 30)-3).."..." end
        return table.concat(chars)
    end
    local function text(value,x,y,size,color,bold)
        commands[#commands+1]={type="text",text=tostring(value),x=self.x+x*self.unitX,
            y=self.y+(HEIGHT-y)*self.unitY,size=size*self.unitY,color=color or COLORS.ink,bold=bold==true,align="left"}
    end
    rect(6,6,WIDTH,HEIGHT,COLORS.shadow);rect(0,0,WIDTH,HEIGHT,COLORS.frame)
    rect(3,3,WIDTH-6,HEIGHT-6,COLORS.background);rect(3,3,WIDTH-6,43,COLORS.header)
    text("TG GPS PRO  |  "..c.operation,20,31,19,{1,1,1,1},true)
    text(o.autosteerEnabled and "PILOTO LIGADO" or "DIRECAO MANUAL",740,30,14,{1,1,1,1},true)
    rect(20,64,180,462,COLORS.card)
    local rows={{"FAZENDA",c.farmName},{"PROPRIETARIO",c.ownerName},{"TALHAO",c.fieldName},
        {c.kind=="combine" and "COLHEITADEIRA" or "TRATOR",c.machineName},{c.implementKind,c.implementName}}
    for i,v in ipairs(rows) do
        local y=88+(i-1)*65
        text(v[1],32,y,10,COLORS.muted,true);text(short(v[2],21),32,y+23,13,COLORS.ink,true)
        rect(32,y+37,156,1,COLORS.border)
    end
    text("AREA DA SESSAO",32,431,10,COLORS.muted,true)
    text(string.format("%.2f ha",o.coverage:getWorkedHa()),32,459,24,COLORS.green,true)
    text(string.format("Repetida %.2f ha",o.coverage:getOverlapHa()),32,484,11,COLORS.muted)
    text(o.coverage.working and "TRABALHANDO" or "EM ESPERA",32,510,12,o.coverage.working and COLORS.green or COLORS.muted,true)
    if self.page=="map" then
        for _,command in ipairs(TGGPSMap.getDrawCommands(o,self:_rect(214,64,585,400))) do commands[#commands+1]=command end
        rect(812,64,208,462,COLORS.card)
        text("PASSADA "..tostring(o.currentLane or 0),824,93,15,COLORS.ink,true)
        text(string.format("DESLOCAMENTO %+.2f m",o.trackOffset or 0),824,170,12,COLORS.ink,true)
        text(string.format("ZOOM %.1fx",TGGPSMap.getZoom(o)),824,329,13,COLORS.ink,true)
        text(short(o.activeCourseName or "Linha sem nome",43),220,477,11,COLORS.muted)
    elseif self.page=="guide" then
        text("ORIENTACAO E CONTROLE DE LINHA",214,88,19,COLORS.ink,true)
        text(string.format("Largura %.2f m   |   Orientacao %.1f graus   |   Deslocamento %+.2f m",
            o.width,TGGPSContext.heading(o.basePath),o.trackOffset or 0),214,136,17,COLORS.green,true)
        text("Ajustar ou puxar a linha desliga o piloto. Confira o alinhamento antes de religar.",214,510,12,COLORS.muted)
    elseif self.page=="headland" then
        text("CONTROLE DE CABECEIRA",214,90,19,COLORS.ink,true)
        for i,v in ipairs({{"MARGEM",o.headlandDepth,"m"},{"VELOCIDADE DA CURVA",o.turnSpeed,"km/h"},{"RAIO MINIMO",o.turnRadius,"m"}}) do
            local y=182+(i-1)*82
            rect(214,y,806,66,COLORS.card);text(v[1],230,y+22,12,COLORS.muted,true)
            text(string.format("%.1f %s",v[2],v[3]),230,y+51,23,COLORS.ink,true)
        end
        text(o.mode=="field" and "Passadas do talhao: levantar, virar e baixar implementos compativeis."
            or "Gere o talhao para usar a cabeceira automatica. A/B e curvas usam retorno manual.",214,520,12,COLORS.muted)
    elseif self.page=="library" then
        local records=o.library:list(o.libraryFilter)
        for row=1,4 do
            local r=records[((o.libraryPage or 1)-1)*4+row]
            if r then
                local y=124+(row-1)*82
                rect(214,y,806,70,COLORS.card)
                text(short(r.name,55),228,y+25,17,COLORS.ink,true)
                text(string.format("%s | %.1f graus | %.1f m | %s",short(r.fieldName,20),r.heading,r.width,r.mode),228,y+51,12,COLORS.muted)
            end
        end
        if #records==0 then text("Nenhum trajeto encontrado. Salve uma linha ou altere a busca.",228,170,16,COLORS.muted) end
        text(string.format("%d trajetos | Pagina %d/%d | Busca: %s",#records,o.libraryPage or 1,
            math.max(1,math.ceil(#records/4)),short(o.libraryFilter~="" and o.libraryFilter or "todos",24)),424,510,11,COLORS.muted)
    else
        text("PAINEL E MONITOR NA CABINE",214,88,19,COLORS.ink,true)
        rect(214,104,806,70,COLORS.card)
        text(string.format("Tamanho do painel: %d%%",math.floor(self.scale*100+0.5)),230,147,20,COLORS.ink,true)
        text("Arraste a barra verde para mover o painel.",230,225,16,COLORS.ink)
        text("Monitor fisico: ajuste parado, por modelo de maquina.",214,277,14,COLORS.muted)
        text("O zoom e compartilhado entre o painel e a tela da cabine.",214,362,14,COLORS.muted)
        text("A pintura e os hectares valem para a sessao atual.",214,448,14,COLORS.muted)
    end
    for _,b in ipairs(self:getButtons()) do
        local color=b.active and COLORS.active or COLORS.button
        if b.tone=="red" then color=COLORS.danger end
        if b.enabled and inside(b,self.pointerX,self.pointerY) then color=self.pressedId==b.id and COLORS.pressed or COLORS.hover end
        if not b.enabled then color=COLORS.disabled end
        commands[#commands+1]={type="rect",x=b.x,y=b.y,w=b.w,h=b.h,color=COLORS.border}
        commands[#commands+1]={type="rect",x=b.x+self.unitX,y=b.y+self.unitY,w=b.w-2*self.unitX,h=b.h-2*self.unitY,color=color}
        commands[#commands+1]={type="text",text=b.label,x=b.x+b.w/2,y=b.y+b.h/2-5*self.unitY,size=12*self.unitY,
            color=b.enabled and COLORS.ink or COLORS.muted,bold=true,align="center"}
    end
    rect(20,596,1000,46,COLORS.card)
    text(short(o.status or "",133),32,624,13,COLORS.ink)
    return commands
end

local function atan2(y, x)
    if math.atan2 ~= nil then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

function TGGPSHud:_drawLine(command)
    if createImageOverlay == nil or setOverlayColor == nil or setOverlayRotation == nil or renderOverlay == nil then return end
    if self.lineOverlayId == nil then
        self.lineOverlayId = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    if self.lineOverlayId == nil or self.lineOverlayId == 0 then return end
    local aspect = finite(g_screenAspectRatio) and g_screenAspectRatio > 0 and g_screenAspectRatio
        or ((g_screenWidth or 1920) / (g_screenHeight or 1080))
    local dx, dy = command.x2 - command.x1, (command.y2 - command.y1) / aspect
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.000001 then return end
    setOverlayColor(self.lineOverlayId, unpack(command.color))
    setOverlayRotation(self.lineOverlayId, -atan2(dy, dx), 0, 0)
    renderOverlay(self.lineOverlayId, command.x1, command.y1, length, command.width or 1 / (g_screenHeight or 1080))
    setOverlayRotation(self.lineOverlayId, 0, 0, 0)
end

function TGGPSHud:draw()
    local commands = self:getDrawCommands()
    if #commands == 0 then return end
    if self.overlay == nil and Overlay ~= nil and type(Overlay.new) == "function" then
        self.overlay = Overlay.new("dataS/menu/base/graph_pixel.dds", 0, 0, 1, 1)
    end
    for _, command in ipairs(commands) do
        if command.type == "rect" and self.overlay ~= nil then
            self.overlay:setPosition(command.x, command.y)
            self.overlay:setDimension(command.w, command.h)
            self.overlay:setColor(unpack(command.color))
            self.overlay:render()
        elseif command.type == "pda" and Overlay ~= nil then
            if self.nativeFilename ~= command.filename then
                if self.nativeOverlay ~= nil then self.nativeOverlay:delete() end
                self.nativeOverlay=Overlay.new(command.filename,0,0,1,1)
                self.nativeFilename=command.filename
            end
            if self.nativeOverlay ~= nil then
                self.nativeOverlay:setPosition(command.x,command.y)
                self.nativeOverlay:setDimension(command.w,command.h)
                self.nativeOverlay:setColor(1,1,1,1)
                self.nativeOverlay:setUVs(command.uvs)
                self.nativeOverlay:render()
            end
        elseif command.type == "line" then
            self:_drawLine(command)
        elseif command.type == "text" and renderText ~= nil and setTextColor ~= nil then
            setTextColor(unpack(command.color))
            if setTextBold ~= nil then setTextBold(command.bold) end
            if RenderText ~= nil and setTextAlignment ~= nil then
                local align = command.align == "center" and RenderText.ALIGN_CENTER
                    or (command.align == "right" and RenderText.ALIGN_RIGHT or RenderText.ALIGN_LEFT)
                setTextAlignment(align)
            end
            if RenderText ~= nil and setTextVerticalAlignment ~= nil then
                setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
            end
            renderText(command.x, command.y, command.size, command.text)
        end
    end
    if setTextBold ~= nil then setTextBold(false) end
    if setTextColor ~= nil then setTextColor(1, 1, 1, 1) end
    if RenderText ~= nil and setTextAlignment ~= nil then setTextAlignment(RenderText.ALIGN_LEFT) end
    if RenderText ~= nil and setTextVerticalAlignment ~= nil then setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE) end
end

function TGGPSHud:delete()
    if self.nativeOverlay~=nil then self.nativeOverlay:delete();self.nativeOverlay=nil end
    self.nativeFilename=nil
    self:setOpen(false)
    if self.overlay ~= nil and type(self.overlay.delete) == "function" then self.overlay:delete() end
    self.overlay = nil
    if self.lineOverlayId ~= nil and self.lineOverlayId ~= 0 and delete ~= nil then delete(self.lineOverlayId) end
    self.lineOverlayId = nil
end
