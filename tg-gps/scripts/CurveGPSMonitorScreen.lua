-- Physical LCD adapted from the supplied CurveGPSMonitorScreen.lua.
-- Keeps its pooled mesh rendering approach, but reads the TG map directly.
-- No CurveGPS globals, second coverage history, GUI dependency or steering hook.
TGGPSMonitorScreen = {}
TGGPSMonitorScreen.__index = TGGPSMonitorScreen
TGGPSMonitorScreen.STYLES = {
    "background", "field", "headland", "boundary", "lane", "selected_lane",
    "planned_turn", "tractor", "implement", "coverage", "coverage_overlap", "off", "green",
    "combine", "vehicleWheel", "vehicleCab", "panelHeader", "panelCard"
}
TGGPSMonitorScreen.WIDTH, TGGPSMonitorScreen.HEIGHT = 0.254, 0.150
TGGPSMonitorScreen.MAX_PRIMITIVES = 650

local function valid(node) return node ~= nil and node ~= 0 end
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

function TGGPSMonitorScreen:attach(monitorNode, vehicle)
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
    for _, style in ipairs(self.STYLES) do
        self.templates[style] = find(templates, style)
        if not valid(self.templates[style]) then self:detach(); return false end
    end
    for code = 32, 126 do
        self.templates["text_" .. code] = find(templates, "text_" .. code)
    end
    self.elapsed = 250
    self:refresh()
    return true
end

function TGGPSMonitorScreen:detach()
    if valid(self.contentRoot) then delete(self.contentRoot) end
    if valid(self.templateRoot) then delete(self.templateRoot) end
    self.contentRoot, self.templateRoot, self.monitorRoot, self.vehicle = nil, nil, nil, nil
    self.nativeNode,self.nativeKey,self.failedNativeKey,self.viewport,self.viewportElapsed=nil,nil,nil,nil,1000
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
                delete(pool[i]); pool[i] = nil; self.count = self.count - 1
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
        if self.count >= self.MAX_PRIMITIVES then return false end
        node = clone(self.templates[style], false, false, false)
        if not valid(node) then return false end
        link(self.contentRoot, node)
        pool[index], self.count = node, self.count + 1
    end
    self.used[style] = index
    setVisibility(node, true)
    setTranslation(node, x, y, 0.004 + (layer or 0) * 0.00004)
    setRotation(node, 0, 0, rotation or 0)
    setScale(node, w, h, 1)
    return true
end

function TGGPSMonitorScreen:text(value, x, y, size, limit)
    value=tostring(value) -- ASCII glyphs below; normalize complete UTF-8 sequences.
    for from,to in pairs({["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["é"]="e",["ê"]="e",["í"]="i",["ó"]="o",["ô"]="o",["õ"]="o",["ú"]="u",["ç"]="c",
        ["Á"]="A",["Ã"]="A",["É"]="E",["Ó"]="O",["Ç"]="C"}) do value=value:gsub(from,to) end
    value=value:gsub("[^\32-\126]","?"):sub(1,limit or 44)
    for i = 1, #value do
        local code = value:byte(i)
        if code ~= 32 then self:quad("text_" .. code, x, y, size, size, 0, 8) end
        x = x + size * 0.64
    end
end

function TGGPSMonitorScreen:refresh()
    if not valid(self.contentRoot) or self.vehicle == nil then return end
    self:beginFrame()
    local motorOn = self.vehicle.getIsMotorStarted == nil or self.vehicle:getIsMotorStarted()
    if valid(self.nativeNode) then setVisibility(self.nativeNode,false) end
    self:quad(motorOn and "background" or "off", 0, 0, self.WIDTH, self.HEIGHT, 0, 0)
    if motorOn then
        local context=self.owner:getMonitorContext()
        self:quad("panelHeader",0,0.066,self.WIDTH,0.018,0,3)
        self:text(context.kind=="combine" and "TG GPS | COLHEITA" or "TG GPS | TRATOR",-0.121,0.061,0.008)
        self:text(self.owner.autosteerEnabled and "PILOTO" or "MANUAL",0.082,0.061,0.007)
        self:quad("panelCard",-0.095,-0.003,0.060,0.112,0,3)
        self:quad("panelCard",0.103,-0.003,0.042,0.112,0,3)
        self:text("FAZENDA",-0.122,0.043,0.0045)
        self:text(context.farmName,-0.122,0.034,0.0055,16)
        self:text("PROPRIETARIO",-0.122,0.019,0.0045)
        self:text(context.ownerName,-0.122,0.010,0.0055,16)
        self:text("TALHAO",-0.122,-0.006,0.0045)
        self:text(context.fieldName,-0.122,-0.015,0.0055,16)
        self:text(context.machineName,-0.122,-0.034,0.005,17)
        self:text(context.implementName,-0.122,-0.046,0.0045,19)
        self:text("PASSADA",0.085,0.043,0.0045)
        self:text(tostring(self.owner.currentLane or 0),0.085,0.031,0.008)
        self:text("DESLOC.",0.085,0.015,0.0045)
        self:text(string.format("%+.2fm",self.owner.trackOffset or 0),0.085,0.004,0.0055)
        self:text(string.format("ZOOM %.1fx",TGGPSMap.getZoom(self.owner)),0.085,-0.015,0.0045)
        self:text("CABECEIRA",0.085,-0.032,0.0045)
        self:text(self.owner.headlandEnabled and "LIGADA" or "MANUAL",0.085,-0.043,0.0055)
        local options = {screenWidth = 480, screenHeight = 290, drawField = false,
            coverageBudget = 130, laneBudget = 70, boundaryBudget = 40,
            selectedBudget = 55, turnBudget = 45}
        local zoom=TGGPSMap.getZoom(self.owner)
        if self.vehicle~=nil then
            if self.viewport==nil or self.viewport.zoom~=zoom or (self.viewportElapsed or 1000)>=1000 then
                local pose=self.owner:getVehiclePose(self.vehicle)
                if pose then self.viewport={x=pose.x,z=pose.z,zoom=zoom};self.viewportElapsed=0 end
            end
            if self.viewport then options.centerX,options.centerZ=self.viewport.x,self.viewport.z end
        else self.viewport=nil end
        local commands = TGGPSMap.getDrawCommands(self.owner, {x = 0.255, y = 0.15, w = 0.56, h = 0.70}, options)
        local nativeCommand
        for _,command in ipairs(commands) do if command.type=="pda" then nativeCommand=command end end
        if nativeCommand then
            local key=nativeCommand.filename..table.concat(nativeCommand.uvs,":")
            if key~=self.nativeKey and key~=self.failedNativeKey then
                local node=TGGPSPDA.createCabBackground(nativeCommand,self.contentRoot,self.WIDTH,self.HEIGHT)
                if valid(node) then
                    if valid(self.nativeNode) then delete(self.nativeNode) end
                    self.nativeNode,self.nativeKey,self.failedNativeKey=node,key,nil
                else self.failedNativeKey=key end
            end
            if valid(self.nativeNode) and self.nativeKey==key then setVisibility(self.nativeNode,true) end
        end
        for _, command in ipairs(commands) do
            if command.type == "rect" and command.role ~= "legend_background"
                and not (command.role=="map_background" and nativeCommand and self.nativeKey~=nil) then
                local style = command.role == "map_background" and "background" or command.role
                local layer = (style == "coverage" or style == "coverage_overlap") and 2 or 1
                self:quad(style, (command.x + command.w / 2 - 0.5) * self.WIDTH,
                    (command.y + command.h / 2 - 0.5) * self.HEIGHT,
                    command.w * self.WIDTH, command.h * self.HEIGHT, 0, layer)
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
        if type(self.owner.sourcePoints) ~= "table" or #self.owner.sourcePoints < 2 then
            self:text("MARQUE A/B",-0.042,0,0.008)
        end
        if self.owner.coverage ~= nil then
            local coverage = self.owner.coverage
            self:text(string.format("%.2f HA", coverage:getWorkedHa()), -0.118, -0.069, 0.010)
            self:text(coverage.working and "TRABALHANDO" or "EM ESPERA", 0.036, -0.069, 0.008)
        end
    end
    self:finishFrame()
end

function TGGPSMonitorScreen:update(dt)
    if not valid(self.contentRoot) then return end
    self.elapsed = self.elapsed + math.max(0, dt or 0)
    self.viewportElapsed=(self.viewportElapsed or 0)+math.max(0,dt or 0)
    if self.elapsed >= 250 then self.elapsed = self.elapsed % 250; self:refresh() end
end
