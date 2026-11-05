-- Physical LCD adapted from the supplied CurveGPSMonitorScreen.lua.
-- Keeps its pooled mesh rendering approach, but reads the TG map directly.
-- No CurveGPS globals, second coverage history, GUI dependency or steering hook.
TGGPSMonitorScreen = {}
TGGPSMonitorScreen.__index = TGGPSMonitorScreen
TGGPSMonitorScreen.STYLES = {
    "background", "field", "headland", "boundary", "lane", "selected_lane",
    "planned_turn", "tractor", "implement", "coverage", "coverage_overlap", "off", "green",
    "combine", "vehicleWheel", "vehicleCab", "panelHeader", "panelCard",
    "guidanceGround", "guidanceSky", "guidanceLane", "guidanceSelected", "guidancePaint", "guidanceOverlap"
}
TGGPSMonitorScreen.WIDTH, TGGPSMonitorScreen.HEIGHT = 0.258, 0.156
TGGPSMonitorScreen.MAX_PRIMITIVES = 650

local function valid(node) return node ~= nil and node ~= 0 and entityExists(node) end
local function drawCost(node)
    if getNumOfChildren(node)==0 then return 1 end
    local count=0
    for i=0,getNumOfChildren(node)-1 do count=count+drawCost(getChildAt(node,i)) end
    return count
end
local function clearBrightness(cache,node)
    cache[node]=nil
    for i=0,getNumOfChildren(node)-1 do clearBrightness(cache,getChildAt(node,i)) end
end
local function find(node, name, depth)
    if not valid(node) or (depth or 0) > 32 then return nil end
    if getName(node) == name then return node end
    for i = 0, getNumOfChildren(node) - 1 do
        local result = find(getChildAt(node, i), name, (depth or 0) + 1)
        if result ~= nil then return result end
    end
end

function TGGPSMonitorScreen.new(owner, modDirectory)
    return setmetatable({owner = owner, modDirectory = modDirectory,
        templates = {}, pools = {}, used = {}, count = 0, elapsed = 250}, TGGPSMonitorScreen)
end

function TGGPSMonitorScreen:attach(monitorNode, vehicle, layout)
    self:detach()
    local root = find(monitorNode, "MonitorRoot")
    local screen = find(monitorNode, "MonitorScreen")
    if not valid(root) or not valid(screen) then return false end
    local templates = loadI3DFile(self.modDirectory .. "models/tgGPSMonitorPrimitives.i3d", false, false, false)
    if not valid(templates) then return false end
    -- Only clones are visible; templates remain hidden under the loaded I3D root.
    link(root, templates)
    setVisibility(templates, false)
    local content = createTransformGroup("TGGPSMonitorScreenContent")
    if not valid(content) then delete(templates); return false end
    link(root, content)
    self.contentRoot, self.templateRoot = content, templates
    self.vehicle, self.monitorRoot = vehicle, root
    self.WIDTH,self.HEIGHT=layout.width,layout.height
    self.greenStar=TGGPSGreenStar.new(self.owner,monitorNode,vehicle,layout,self.modDirectory,content)
    if self.greenStar==nil then self:detach();return false end
    for _, style in ipairs(self.STYLES) do
        self.templates[style] = find(templates, style)
        if not valid(self.templates[style]) then self:detach(); return false end
    end
    for code = 32, 126 do
        self.templates["text_" .. code] = find(templates, "text_" .. code)
        self.templates["textWhite_" .. code] = find(templates,"textWhite_"..code)
    end
    local symbols=loadI3DFile(self.modDirectory..'models/tgGPSVehicleSymbols.i3d',false,false,false)
    if not valid(symbols) then self:detach();return false end
    self.symbolTemplateRoot=symbols
    link(root,symbols);setVisibility(symbols,false)
    self.templateCosts={}
    for _,kind in ipairs({'tractor','combine','combine_cutter'}) do
        local name='symbol_'..kind
        self.templates[name]=find(symbols,name)
        if not valid(self.templates[name]) then self:detach();return false end
        self.templateCosts[name]=drawCost(self.templates[name])
    end
    self.elapsed = 250
    self:refresh()
    return true
end

function TGGPSMonitorScreen:detach()
    if self.greenStar then self.greenStar:delete();self.greenStar=nil end
    if valid(self.contentRoot) then delete(self.contentRoot) end
    if valid(self.templateRoot) then delete(self.templateRoot) end
    if valid(self.symbolTemplateRoot) then delete(self.symbolTemplateRoot) end
    self.symbolTemplateRoot=nil
    self.contentRoot, self.templateRoot, self.monitorRoot, self.vehicle = nil, nil, nil, nil
    self.nativeNode,self.nativeShape,self.nativeKey,self.failedNativeFilename=nil,nil,nil,nil
    self.nodeBrightness={}
    self.templates, self.pools, self.used, self.count = {}, {}, {}, 0
end

function TGGPSMonitorScreen:beginFrame()
    for style in pairs(self.pools) do self.used[style] = 0 end
end

function TGGPSMonitorScreen:finishFrame()
    -- Retain a small pool to avoid allocating/deleting every LCD refresh.
    for style, pool in pairs(self.pools) do
        local used = self.used[style] or 0
        for i = #pool, used + 1, -1 do
            if i > used + 4 then
                delete(pool[i]); pool[i] = nil; self.count = self.count - ((self.templateCosts or {})[style] or 1)
            else setVisibility(pool[i], false) end
        end
    end
end

function TGGPSMonitorScreen:quad(style, x, y, w, h, rotation, layer)
    if not valid(self.templates[style]) or w <= 0 or h <= 0 then return false end
    local pool = self.pools[style] or {}
    self.pools[style] = pool
    local index = (self.used[style] or 0) + 1
    local node = pool[index]
    if not valid(node) then
        local cost=(self.templateCosts or {})[style] or 1
        if self.count+cost > self.MAX_PRIMITIVES then return false end
        node = clone(self.templates[style], false, false, false)
        if not valid(node) then return false end
        link(self.contentRoot, node)
        pool[index], self.count = node, self.count + cost
        self.nodeBrightness=self.nodeBrightness or {};clearBrightness(self.nodeBrightness,node)
    end
    self.used[style] = index
    self:applyBrightness(node)
    setVisibility(node, true)
    setTranslation(node, x, y, 0.004 + (layer or 0) * 0.00015)
    setRotation(node, 0, 0, rotation or 0)
    setScale(node, w, h, 1)
    return true
end

function TGGPSMonitorScreen:applyBrightness(node)
    if not valid(node) then return end
    local value=self.owner.monitorBrightness or 0.20
    self.nodeBrightness=self.nodeBrightness or {}
    if self.nodeBrightness[node]~=value and getHasShaderParameter and setShaderParameter then
        if getHasClassId and ClassIds and getHasClassId(node,ClassIds.SHAPE)
            and getHasShaderParameter(node,"lcdBrightness") then
            setShaderParameter(node,"lcdBrightness",value*0.25,0,0,0,false)
        end
        for i=0,getNumOfChildren(node)-1 do self:applyBrightness(getChildAt(node,i)) end
        self.nodeBrightness[node]=value
    end
end

function TGGPSMonitorScreen:text(value, x, y, size, limit, white)
    value=tostring(value) -- ASCII glyphs below; normalize complete UTF-8 sequences.
    for from,to in pairs({["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["é"]="e",["ê"]="e",["í"]="i",["ó"]="o",["ô"]="o",["õ"]="o",["ú"]="u",["ç"]="c",
        ["Á"]="A",["Ã"]="A",["É"]="E",["Ó"]="O",["Ç"]="C"}) do value=value:gsub(from,to) end
    value=value:gsub("[^\32-\126]","?"):sub(1,limit or 44)
    for i = 1, #value do
        local code = value:byte(i)
        if code ~= 32 then self:quad((white and "textWhite_" or "text_") .. code, x, y, size, size, 0, 8) end
        x = x + size * 0.64
    end
end

function TGGPSMonitorScreen:pixelText(value,x,y,size,limit,white)
    self:text(value,(x/1024-.5)*self.WIDTH,(.5-y/1024)*self.HEIGHT,size/1024*self.HEIGHT,limit,white)
end

function TGGPSMonitorScreen:pixelQuad(style,x,y,w,h,layer)
    self:quad(style,(x/1024-.5)*self.WIDTH,(.5-y/1024)*self.HEIGHT,
        w/1024*self.WIDTH,h/1024*self.HEIGHT,0,layer or 6)
end

function TGGPSMonitorScreen:drawGreenStarReadouts()
    if self.owner.cabPerspective then self:drawOrientationPanel();return end
    local context=self.owner:getMonitorContext()
    local state=self.owner.recognition and self.owner.recognition.state
    local kind=context.kind=='combine' and 'COLHEITA' or 'TRATOR'
    self:pixelText(string.format('%s | %.1f M | %s',kind,self.owner.width or 6,context.fieldName),24,310,15,55,true)
    local edge=state and state.borderDistance
    self:pixelText(edge and string.format('BORDA %.1f M%s',edge,state.nearHeadland and ' | CABECEIRA' or '')
        or 'BORDA NAO INFORMADA PELO MAPA',24,332,12,55,true)
    self:pixelText(self.owner.autosteerEnabled and 'PILOTO LIGADO' or 'DIRECAO MANUAL',180,681,14,32,true)
    local speed=self.vehicle.getLastSpeed and self.vehicle:getLastSpeed() or 0
    local motor=self.vehicle.spec_motorized
    local fuel=motor and motor.lastFuelUsageDisplay
    local rate=(self.owner.width or 6)*math.abs(speed)/10
    self.readoutFuel=(type(fuel)=='number' and rate>0.01 and self.owner.coverage and self.owner.coverage.working)
        and string.format('%.1f',fuel/rate) or '--'
    self:pixelQuad('panelCard',155,783,150,45)
    self:pixelText(self.readoutFuel,110,795,27,7)
    local cruise=self.vehicle.getCruiseControlSpeed and self.vehicle:getCruiseControlSpeed() or speed
    self:pixelQuad('panelCard',500,778,103,44)
    self:pixelText(string.format('%.1f',cruise),465,790,26,6)
    if self.owner.autosteerEnabled then
        self:pixelQuad('panelCard',432,978,150,34)
        self:pixelText('Steer ON',386,988,23,12)
    end
    local result=self.owner:calculateSteering(self.vehicle,self.owner.travelDirection)
    local pose=state and state.pose
    if result and pose then
        local signed=(pose.x-result.nearest.x)*(pose.dz or 1)-(pose.z-result.nearest.z)*(pose.dx or 0)
        local inches=signed/0.0254
        self.crossTrackMetres=signed
        self:pixelQuad('green',414,184,54,41)
        self:pixelText(string.format('%+.0f',inches),396,194,20,5)
        local marker=414+math.max(-308,math.min(266,inches*8))
        if math.abs(marker-414)>37 then self:pixelQuad('green',marker,193,12,62) end
    else self.crossTrackMetres=nil end
end

function TGGPSMonitorScreen:drawOrientationPanel()
    local o=self.owner;local context=o:getMonitorContext()
    local state=o.recognition and o.recognition.state
    local function text(s,x,y,size,limit,white) self:pixelText(s,x,y,size or 20,limit or 24,white) end
    self:pixelQuad('panelHeader',512,30,1024,60,3)
    text('Orientacao',18,43,30,30,true)
    self:pixelQuad('panelCard',112,482,206,820,3)
    self:pixelQuad('panelCard',900,482,238,820,3)
    self:pixelQuad('panelHeader',512,940,1024,168,3)
    local function card(title,value,y)
        self:pixelQuad('panelHeader',110,y-20,196,31,4)
        text(title,19,y-12,15,23,true);text(value,19,y+23,21,22)
    end
    card('Localizacao',context.farmName,106)
    text(context.fieldName,19,163,18,23)
    card('Maquina',context.kind=='combine' and 'Colheitadeira' or 'Trator',216)
    text(context.machineName,19,269,16,22)
    local speed=self.vehicle.getLastSpeed and self.vehicle:getLastSpeed() or 0
    local fuel=self.vehicle.spec_motorized and self.vehicle.spec_motorized.lastFuelUsageDisplay
    card('Velocidade',string.format('%.1f km/h',speed),317)
    card('Consumo',type(fuel)=='number' and string.format('%.1f l/h',fuel) or '-- l/h',427)
    card('Faixa Seguinte','Track '..tostring(o.currentLane or 0),537)
    card('Implemento',context.implementName,647)
    text(o.autosteerEnabled and 'AUTOTRAC LIGADO' or 'AUTOTRAC MANUAL',18,788,16,23)
    local pose=state and state.pose
    local heading=pose and (math.deg(math.atan2(pose.dx,pose.dz))+360)%360 or 0
    self:pixelQuad('panelHeader',500,97,550,70,3)
    text(string.format('N  %03.0f graus',heading),365,101,23,25,true)
    local guidance=o:calculateSteering(self.vehicle,o.travelDirection)
    local deviation=guidance and pose and ((pose.x-guidance.nearest.x)*pose.dz-(pose.z-guidance.nearest.z)*pose.dx) or nil
    self.crossTrackMetres=deviation
    text(deviation and string.format('%+.0f cm',deviation*100) or '-- cm',460,145,20,14,true)
    text(tostring(o.currentLane or 0)..'L',480,192,19,14,true)
    text('Orientacao',796,96,18,22)
    text('Ajustar Pista',798,146,21,24)
    text(string.format('%.3f m',o.width or 6),798,215,22,22)
    text('Espac. Pistas',798,247,16,24)
    text('Mudanca de Pista',790,308,17,26)
    self:pixelQuad('panelHeader',896,385,208,90,4);text('<   |   >',827,400,30,24,true)
    self:pixelQuad('panelHeader',896,505,208,90,4);text('|<     >|',813,521,30,24,true)
    text(string.format('%+.2f m',o.trackOffset or 0),800,603,23,22)
    text('Incremento 0.10 m',791,643,16,24)
    text(state and state.borderDistance and string.format('Borda %.1f m',state.borderDistance) or 'Borda --',791,722,18,24)
    text('AUTO',19,929,20,20,true);text('GRAVACAO',19,961,17,20,true)
    for i,name in ipairs({'MAPA','AUTOTRAC','TALHAO','MAQUINA','TRABALHO','TRAJETO','TOTAIS'}) do
        text(name,237+(i-1)*99,996,11,12,true)
    end
    if o.coverage then text(string.format('%.2f ha',o.coverage:getWorkedHa()),800,819,23,22) end
end

function TGGPSMonitorScreen:refresh()
    if not valid(self.contentRoot) or self.vehicle == nil then return end
    self:beginFrame()
    local motorOn = self.vehicle.getIsMotorStarted == nil or self.vehicle:getIsMotorStarted()
    if self.greenStar then
        self:applyBrightness(self.greenStar.screen)
        self:applyBrightness(self.greenStar.boot)
        self:applyBrightness(self.greenStar.overlay)
    end
    if valid(self.nativeNode) then setVisibility(self.nativeNode,false) end
    if not motorOn then self:quad('off',0,0,self.WIDTH,self.HEIGHT,0,0) end
    if motorOn and self.owner.cabPerspective then
        self:quad('panelCard',0,0,self.WIDTH,self.HEIGHT,0,-2)
        TGGPSPerspective.draw(self)
        self:drawGreenStarReadouts()
        if #self.owner.sourcePoints<2 then self:pixelText('MARQUE A/B OU GERE O TALHAO',150,430,16,32,true) end
        self:finishFrame()
        return
    end
    if motorOn then
        local options = {screenWidth = 640, screenHeight = 480, drawField = false,
            coverageBudget = 130, laneBudget = 70, boundaryBudget = 40,
            selectedBudget = 55, turnBudget = 45}
        local commands = TGGPSMap.getDrawCommands(self.owner, TGGPSGreenStar.MAP_BOX, options)
        local nativeCommand
        for _,command in ipairs(commands) do if command.type=="pda" then nativeCommand=command end end
        if nativeCommand then
            local key=nativeCommand.filename..table.concat(nativeCommand.uvs,":")
            if self.failedNativeFilename==nativeCommand.filename and self.failedNativeRecoverable then
                if TGGPSPDA.resolveCabTexture(nativeCommand.filename) then self.failedNativeFilename=nil end
            end
            if key~=self.nativeKey and nativeCommand.filename~=self.failedNativeFilename then
                local node,reason,recoverable=TGGPSPDA.createCabBackground(nativeCommand,self.contentRoot,self.WIDTH,self.HEIGHT)
                local shape=valid(node) and find(node,"NativePDA") or nil
                if valid(node) and valid(shape) then
                    if valid(self.nativeNode) then delete(self.nativeNode) end
                    self.nativeNode,self.nativeShape,self.nativeKey,self.failedNativeFilename=node,shape,key,nil
                    self.nodeBrightness[self.nativeShape]=nil
                else
                    if valid(node) then delete(node);reason='Malha do PDA nao foi carregada' end
                    self.failedNativeFilename=nativeCommand.filename
                    self.failedNativeRecoverable=recoverable
                    if Logging and Logging.warning then Logging.warning("[TG GPS PRO] "..tostring(reason)) end
                end
            end
            if valid(self.nativeNode) and self.nativeKey==key then
                setVisibility(self.nativeNode,true)
                if valid(self.nativeShape) then self:applyBrightness(self.nativeShape) end
            end
        end
        for _, command in ipairs(commands) do
            if command.type == "rect" and command.role ~= "legend_background"
                and not (command.role=="map_background" and nativeCommand and self.nativeKey==nativeCommand.filename..table.concat(nativeCommand.uvs,":")) then
                local style = command.role == "map_background" and "background" or command.role
                local layer = (style == "coverage" or style == "coverage_overlap") and 2 or 1
                self:quad(style, (command.x + command.w / 2 - 0.5) * self.WIDTH,
                    (command.y + command.h / 2 - 0.5) * self.HEIGHT,
                    command.w * self.WIDTH, command.h * self.HEIGHT, 0, layer)
            elseif command.type=='symbol' then
                self:quad('symbol_'..command.symbol,(command.cx-0.5)*self.WIDTH,(command.cy-0.5)*self.HEIGHT,
                    command.w*self.WIDTH,command.h*self.HEIGHT,command.rotation,7)
            elseif command.type == "line" then
                local x1, y1 = (command.x1 - 0.5) * self.WIDTH, (command.y1 - 0.5) * self.HEIGHT
                local x2, y2 = (command.x2 - 0.5) * self.WIDTH, (command.y2 - 0.5) * self.HEIGHT
                local dx, dy = x2 - x1, y2 - y1
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0.00001 then
                    self:quad(command.role, (x1 + x2) / 2, (y1 + y2) / 2, length,
                        math.max(0.00045, command.width * self.HEIGHT), math.atan2(dy, dx),
                        command.part~=nil and 7 or (command.role == "implement" and 6
                            or (command.role == "selected_lane" and 5 or 4)))
                end
            end
        end
        if self.failedNativeFilename then self:pixelText('PDA INDISPONIVEL',180,400,19,22,true) end
        if type(self.owner.sourcePoints) ~= "table" or #self.owner.sourcePoints < 2 then
            self:pixelText('MARQUE A/B OU GERE O TALHAO',180,452,18,28,true)
        end
        if self.owner.coverage ~= nil then
            local coverage = self.owner.coverage
            self:pixelText(string.format('%.2f HA', coverage:getWorkedHa()),190,626,17,18,true)
            self:pixelText(coverage.working and 'TRABALHANDO' or 'EM ESPERA',190,651,15,18,true)
        end
        self:drawGreenStarReadouts()
    end
    self:finishFrame()
end

function TGGPSMonitorScreen:update(dt)
    if not valid(self.contentRoot) then return end
    if self.greenStar then self.greenStar:update(dt) end
    self.elapsed = self.elapsed + math.max(0, dt or 0)
    if self.elapsed >= 250 then self.elapsed = self.elapsed % 250; self:refresh() end
end
