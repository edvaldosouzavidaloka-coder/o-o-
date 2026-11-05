-- Physical LCD adapted from the supplied CurveGPSMonitorScreen.lua.
-- Keeps its pooled mesh rendering approach, but reads the TG map directly.
-- No CurveGPS globals, second coverage history, GUI dependency or steering hook.
TGGPSMonitorScreen = {}
TGGPSMonitorScreen.__index = TGGPSMonitorScreen
TGGPSMonitorScreen.STYLES = {
    "background", "field", "headland", "boundary", "lane", "selected_lane",
    "planned_turn", "tractor", "implement", "coverage", "coverage_overlap", "off", "green",
    "combine", "vehicleWheel", "vehicleCab", "panelHeader", "panelCard",
    "guidanceGround", "guidanceSky", "guidanceLane", "guidanceSelected", "guidancePaint", "guidanceOverlap", "guidanceGrid",
    "paintBlueL", "paintBlueR", "paintOverlapL", "paintOverlapR"
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
    for _,code in ipairs({176,193,195,201,211,199,225,224,227,226,233,234,237,243,244,245,250,231}) do
        self.templates['text_'..code]=find(templates,'text_'..code)
        self.templates['textWhite_'..code]=find(templates,'textWhite_'..code)
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

function TGGPSMonitorScreen:text(value,x,y,size,limit,white,xScale)
    local count=0;xScale=xScale or 1
    for char in tostring(value):gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        count=count+1;if count>(limit or 44) then break end
        local code=char:byte()
        if #char==2 then code=(code-192)*64+char:byte(2)-128
        elseif #char==3 then code=(code-224)*4096+(char:byte(2)-128)*64+char:byte(3)-128
        elseif #char>3 then code=63 end
        local style=(white and 'textWhite_' or 'text_')..code
        if self.templates[style]==nil then style=(white and 'textWhite_' or 'text_')..63 end
        if code~=32 then self:quad(style,x,y,size*xScale,size,0,8) end
        x=x+size*xScale*((TGGPSGlyphs and TGGPSGlyphs[code]) or .64)
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
    local o=self.owner;local c=o:getMonitorContext();local state=o.recognition and o.recognition.state
    local function t(value,x,y,size,limit,white)
        self:pixelText(value,x/440*1024,y/330*1024,size/330*1024,limit,white)
    end
    local speed=self.vehicle.getLastSpeed and self.vehicle:getLastSpeed() or 0
    local fuel=self.vehicle.spec_motorized and self.vehicle.spec_motorized.lastFuelUsageDisplay
    local area=o.coverage and o.coverage:getWorkedHa() or 0
    t(string.format('%.2f',area),14,60,13,7)
    t(string.format('%.1f',speed),14,105,13,7)
    t(o.activeCourseName or ('Track '..tostring(o.currentLane or 0)),8,150,10,14)
    t(type(fuel)=='number' and string.format('%.1f',fuel) or '--',14,232,13,7)
    t(c.machineName,6,270,8,16)
    t(c.fieldName,6,285,8,16)
    t(c.farmName,358,52,9,14);t(c.fieldName,358,65,9,14)
    t(string.format('%.2f m',o.width or 6),360,143,10,12)
    t(string.format('%.1f cm',math.abs(o.trackOffset or 0)*100),359,270,11,12)
    local day=g_currentMission and g_currentMission.environment and g_currentMission.environment.dayTime or 0
    t(string.format('%02d:%02d  GPS',math.floor(day/3600000)%24,math.floor(day/60000)%60),275,18,8,16,true)
    local pose=state and state.pose
    local heading=pose and (math.deg(math.atan2(pose.dx,pose.dz))+360)%360 or 0
    local direction=({'N','NE','E','SE','S','SO','O','NO'})[math.floor((heading+22.5)%360/45)+1]
    t(direction,214,47,12,3,true);t(string.format('%03.0f°',heading),204,64,13,7,true)
    local guidance=o:calculateSteering(self.vehicle,o.travelDirection)
    local deviation=guidance and pose and ((pose.x-guidance.nearest.x)*pose.dz-(pose.z-guidance.nearest.z)*pose.dx) or nil
    self.crossTrackMetres=deviation
    self:pixelQuad('green',222/440*1024,76/330*1024,45/440*1024,14/330*1024,4)
    t(deviation and string.format('%+.0f cm',deviation*100) or '-- cm',204,81,9,8)
    self:pixelQuad('panelHeader',222/440*1024,99/330*1024,27/440*1024,19/330*1024,4)
    t(tostring(o.currentLane or 0)..'N',213,104,11,4,true)
    t(c.fieldName,93,102,9,18,true)
    local realWidth=o.coverage and o.coverage.footprint and o.coverage.footprint.width or TGGPSWidthProfiles.detect(self.vehicle)
    t(realWidth and string.format('Real %.2f m',realWidth) or 'Real --',359,154,7,15)
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
        self:quad('guidanceGround',0,0,self.WIDTH,self.HEIGHT,0,-2)
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
