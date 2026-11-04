-- Physical LCD adapted from the supplied CurveGPSMonitorScreen.lua.
-- Keeps its pooled mesh rendering approach, but reads the TG map directly.
-- No CurveGPS globals, second coverage history, GUI dependency or steering hook.
TGGPSMonitorScreen = {}
TGGPSMonitorScreen.__index = TGGPSMonitorScreen
TGGPSMonitorScreen.STYLES = {
    "background", "field", "headland", "boundary", "lane", "selected_lane",
    "planned_turn", "tractor", "implement", "coverage", "coverage_overlap", "off", "green"
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

function TGGPSMonitorScreen:text(value, x, y, size)
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
    self:quad(motorOn and "background" or "off", 0, 0, self.WIDTH, self.HEIGHT, 0, 0)
    if motorOn then
        self:text("TG GPS", -0.118, 0.059, 0.012)
        self:text(self.owner.autosteerEnabled and "PILOTO" or "MANUAL", 0.061, 0.059, 0.010)
        local options = {screenWidth = 480, screenHeight = 290, drawField = false,
            coverageBudget = 130, laneBudget = 70, boundaryBudget = 40,
            selectedBudget = 55, turnBudget = 45}
        local commands = TGGPSMap.getDrawCommands(self.owner, {x = 0.015, y = 0.13, w = 0.97, h = 0.73}, options)
        for _, command in ipairs(commands) do
            if command.type == "rect" and command.role ~= "legend_background" then
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
                        command.role == "tractor" and 7 or (command.role == "implement" and 6
                            or (command.role == "selected_lane" and 5 or 4)))
                end
            end
        end
        if type(self.owner.sourcePoints) ~= "table" or #self.owner.sourcePoints < 2 then
            self:text("GERE TALHAO OU MARQUE A/B", -0.112, 0, 0.014)
        end
        if self.owner.coverage ~= nil then
            local coverage = self.owner.coverage
            self:text(string.format("%.2f HA", coverage:getWorkedHa()), -0.118, -0.069, 0.010)
            self:text(coverage.working and "TRABALHANDO" or "EM ESPERA", 0.036, -0.069, 0.009)
        end
    end
    self:finishFrame()
end

function TGGPSMonitorScreen:update(dt)
    if not valid(self.contentRoot) then return end
    self.elapsed = self.elapsed + math.max(0, dt or 0)
    if self.elapsed >= 250 then self.elapsed = self.elapsed % 250; self:refresh() end
end
