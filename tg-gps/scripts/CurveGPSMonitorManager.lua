-- TG adapter for the user-supplied CurveGPSMonitorManager.lua and monitor I3D.
-- Preserves stable cab anchoring and delayed vehicle-switch attachment.
-- Position editing/configuration live here, with no CurveGPS shop configuration.
TGGPSMonitorManager = {}
TGGPSMonitorManager.__index = TGGPSMonitorManager

local function valid(node) return node ~= nil and node ~= 0 and entityExists(node) end
local function copy(value)
    local result = {}
    for k, v in pairs(value) do result[k] = v end
    return result
end
local FIELDS = {"positionX", "positionY", "positionZ", "rotationX", "rotationY", "rotationZ", "scale"}
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function TGGPSMonitorManager.new(owner, modDirectory)
    local self = setmetatable({owner = owner, modDirectory = modDirectory or "", clock = 0,
        settings = {}, editing = false, pendingSince = 0, lastToggleTime = -10000}, TGGPSMonitorManager)
    self.screenRenderer = TGGPSMonitorScreen.new(owner, self.modDirectory)
    self:loadConfig()
    return self
end

function TGGPSMonitorManager:getConfigPath()
    if getUserProfileAppPath == nil then return nil end
    return getUserProfileAppPath() .. TGGPS.SAVE_FOLDER .. "/monitors.xml"
end

function TGGPSMonitorManager:loadConfig()
    local path = self:getConfigPath()
    if path == nil or fileExists == nil or not fileExists(path)
        or loadXMLFile == nil or getXMLInt == nil or getXMLFloat == nil or getXMLString == nil then return end
    local xml = loadXMLFile("TGGPSMonitors", path)
    if not valid(xml) then return end
    local count = math.max(0, math.min(500, getXMLInt(xml, "tgGpsMonitors#count") or 0))
    for i = 0, count - 1 do
        local key, entry = string.format("tgGpsMonitors.monitor(%d)", i), {}
        local name = getXMLString(xml, key .. "#vehicle")
        local usable = type(name) == "string" and name ~= ""
        for _, field in ipairs(FIELDS) do
            local value = getXMLFloat(xml, key .. "#" .. field)
            if not finite(value) then usable = false else
                local limit = field == "scale" and 3 or (field:sub(1, 8) == "rotation" and 360 or 10)
                entry[field] = math.max(field == "scale" and 0.25 or -limit, math.min(limit, value))
            end
        end
        if usable then self.settings[name] = entry end
    end
    delete(xml)
end

function TGGPSMonitorManager:saveConfig()
    local path = self:getConfigPath()
    if path == nil or createXMLFile == nil or setXMLFloat == nil or setXMLInt == nil
        or setXMLString == nil or saveXMLFile == nil then return false end
    if createFolder ~= nil then createFolder(getUserProfileAppPath() .. TGGPS.SAVE_FOLDER) end
    local xml = createXMLFile("TGGPSMonitors", path, "tgGpsMonitors")
    if not valid(xml) then return false end
    local names = {}
    for name in pairs(self.settings) do names[#names + 1] = name end
    table.sort(names)
    setXMLInt(xml, "tgGpsMonitors#count", #names)
    for i, name in ipairs(names) do
        local key = string.format("tgGpsMonitors.monitor(%d)", i - 1)
        setXMLString(xml, key .. "#vehicle", name)
        for _, field in ipairs(FIELDS) do setXMLFloat(xml, key .. "#" .. field, self.settings[name][field]) end
    end
    local result = saveXMLFile(xml)
    delete(xml)
    return result ~= false
end

function TGGPSMonitorManager:createDefaultPlacement(parentNode, reference, vehicle)
    local x, y, z = -0.35, 1.80, 0.65
    if valid(reference) and localToLocal then
        x, y, z = localToLocal(reference,parentNode,0,0,0)
        if TGGPSContext.machineKind(vehicle)=='combine' then
            x,y,z=x-0.42,y-0.30,z+0.75
        else x, y, z = x - 0.35, y - 0.25, z + 0.65 end
    end
    return {positionX = x, positionY = y, positionZ = z,
        rotationX = -10, rotationY = 180, rotationZ = 0, scale = 1}
end

function TGGPSMonitorManager:applyPlacement()
    local p = self.placement
    if p == nil or not valid(self.monitorNode) then return end
    setTranslation(self.monitorNode, p.positionX, p.positionY, p.positionZ)
    setRotation(self.monitorNode, math.rad(p.rotationX), math.rad(p.rotationY), math.rad(p.rotationZ))
    setScale(self.monitorNode, p.scale, p.scale, p.scale)
end

function TGGPSMonitorManager:attachMonitor(vehicle)
    if vehicle == nil or not vehicle.tgGpsSupported then return false end
    local parent, reference = self:findStableParent(vehicle)
    if not valid(parent) then return false end
    local model = loadI3DFile(self.modDirectory .. "models/curveGPSMonitor.i3d", false, false, false)
    if not valid(model) then return false end
    local layout=TGGPSGreenStar.prepare(model)
    if layout==nil then delete(model);return false end
    link(parent, model)
    self.monitorNode, self.parentNode = model, parent
    self.vehicleKey = tostring(vehicle.configFileName or vehicle.typeName or "vehicle")
    self.defaultPlacement = self:createDefaultPlacement(parent, reference, vehicle)
    self.placement = copy(self.settings[self.vehicleKey] or self.defaultPlacement)
    self:applyPlacement()
    if not self.screenRenderer:attach(model, vehicle, layout) then
        self:removeMonitor()
        return false
    end
    return true
end

function TGGPSMonitorManager:removeMonitor()
    self.editing = false
    self.screenRenderer:detach()
    if valid(self.monitorNode) then delete(self.monitorNode) end
    self.monitorNode, self.parentNode, self.placement = nil, nil, nil
end

function TGGPSMonitorManager:onVehicleDeleted(vehicle)
    if self.vehicle==vehicle or self.screenRenderer.vehicle==vehicle then
        self:removeMonitor()
        self.vehicle=nil
    end
    if self.pendingVehicle==vehicle then self.pendingVehicle=nil end
end

function TGGPSMonitorManager:update(dt)
    self.clock = self.clock + math.max(0, dt or 0)
    local vehicle = self.owner:getControlledVehicle()
    if vehicle ~= nil and not vehicle.tgGpsSupported then vehicle = nil end
    if vehicle ~= self.vehicle then
        if valid(self.monitorNode) then self:removeMonitor(); self.vehicle = nil end
        if vehicle ~= self.pendingVehicle then
            self.pendingVehicle, self.pendingSince = vehicle, self.clock
        end
        if vehicle == nil or self.clock - self.pendingSince >= 450 then
            self.vehicle, self.pendingVehicle = vehicle, nil
            if vehicle ~= nil and not self:attachMonitor(vehicle) then
                self.owner:notify("Monitor da cabine indisponivel: confira os arquivos do mod")
            end
        end
    else self.pendingVehicle = nil end
    if self.editing and g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then
        self:finishEditing(false)
    end
    self.screenRenderer:update(dt)
end

function TGGPSMonitorManager:toggleEditMode()
    if self.clock - self.lastToggleTime < 180 then return end
    self.lastToggleTime = self.clock
    if self.editing then self:finishEditing(true); return end
    if not valid(self.monitorNode) or self.vehicle == nil then
        self.owner:notify("Entre no trator e aguarde o monitor aparecer")
        return
    end
    local speed = self.vehicle.getLastSpeed ~= nil and self.vehicle:getLastSpeed()
        or math.abs(self.vehicle.lastSpeedReal or 0) * 3600
    if math.abs(speed) > 0.5 then self.owner:notify("Pare o trator antes de ajustar o monitor"); return end
    if g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible() then return end
    self.owner:stopAutosteer()
    if self.owner.hud ~= nil and self.owner.hud.isOpen then self.owner:closeHud() end
    self.beforeEdit, self.editing = copy(self.placement), true
    self.owner:notify("MONITOR: setas movem | PgUp/PgDn altura | Q/E giro | +/- tamanho | Enter salva | Esc cancela")
end

function TGGPSMonitorManager:finishEditing(save)
    if not self.editing then return end
    self.editing = false
    if save then
        self.settings[self.vehicleKey] = copy(self.placement)
        self.owner:notify(self:saveConfig() and "Posicao do monitor salva para este modelo"
            or "Posicao aplicada nesta sessao; nao foi possivel salvar no disco")
    else
        self.placement = copy(self.beforeEdit)
        self:applyPlacement()
        self.owner:notify("Ajuste do monitor cancelado")
    end
    self.beforeEdit = nil
end

function TGGPSMonitorManager:keyEvent(unicode, sym, modifier, isDown)
    if not self.editing or not isDown or Input == nil then return false end
    if Input.isKeyPressed then
        local ctrl=(Input.KEY_lctrl and Input.isKeyPressed(Input.KEY_lctrl)) or (Input.KEY_rctrl and Input.isKeyPressed(Input.KEY_rctrl))
        local alt=(Input.KEY_lalt and Input.isKeyPressed(Input.KEY_lalt)) or (Input.KEY_ralt and Input.isKeyPressed(Input.KEY_ralt))
        if ctrl and alt then return false end -- reserved for native monitor shortcuts
    end
    local function key(...)
        for _, name in ipairs({...}) do if Input[name] ~= nil and sym == Input[name] then return true end end
        return false
    end
    local p = self.placement
    if key("KEY_return", "KEY_KP_enter") then self:finishEditing(true); return true end
    if key("KEY_esc") then self:finishEditing(false); return true end
    if key("KEY_left") then p.positionX = p.positionX + 0.02
    elseif key("KEY_right") then p.positionX = p.positionX - 0.02
    elseif key("KEY_up") then p.positionZ = p.positionZ + 0.02
    elseif key("KEY_down") then p.positionZ = p.positionZ - 0.02
    elseif key("KEY_pageup") then p.positionY = p.positionY + 0.02
    elseif key("KEY_pagedown") then p.positionY = p.positionY - 0.02
    elseif key("KEY_q") then p.rotationY = p.rotationY + 2
    elseif key("KEY_e") then p.rotationY = p.rotationY - 2
    elseif key("KEY_r") then p.rotationX = p.rotationX + 2
    elseif key("KEY_f") then p.rotationX = p.rotationX - 2
    elseif key("KEY_plus", "KEY_equals", "KEY_KP_plus") then p.scale = math.min(3, p.scale + 0.05)
    elseif key("KEY_minus", "KEY_KP_minus") then p.scale = math.max(0.25, p.scale - 0.05)
    elseif key("KEY_home") then self.placement = copy(self.defaultPlacement)
    else return false end
    self:applyPlacement()
    return true
end

function TGGPSMonitorManager:delete()
    self:removeMonitor()
    self.vehicle, self.pendingVehicle = nil, nil
end

-- Stable anchoring from the supplied manager.
function TGGPSMonitorManager:isNodePartOfVehicle(node, vehicle)
    if not valid(node) or vehicle == nil then return false end

    local componentNodes = {}
    for _, component in ipairs(vehicle.components or {}) do
        if valid(component.node) then componentNodes[component.node] = true end
    end
    if valid(vehicle.rootNode) then componentNodes[vehicle.rootNode] = true end

    local current = node
    local depth = 0
    while valid(current) and depth < 64 do
        if componentNodes[current] then return true end
        current = getParent(current)
        depth = depth + 1
    end
    return false
end

function TGGPSMonitorManager:findStableParent(vehicle)
    local enterable = vehicle ~= nil and vehicle.spec_enterable or nil
    if enterable ~= nil and enterable.cameras ~= nil then
        for _, camera in ipairs(enterable.cameras) do
            if camera ~= nil and camera.isInside == true then
                -- cameraPositionNode e o node que marca a posicao original da
                -- camera. O monitor usa apenas o PAI dele, que permanece preso
                -- a cabine e nao recebe a rotacao do olhar do jogador.
                local reference = camera.cameraPositionNode
                if not valid(reference) then reference = camera.rotateNode end
                if not valid(reference) then reference = camera.cameraNode end
                if valid(reference) then
                    local parent = getParent(reference)
                    if valid(parent) and self:isNodePartOfVehicle(parent, vehicle) then
                        return parent, reference, "inside-camera-parent"
                    end
                end
            end
        end
    end

    if vehicle ~= nil and vehicle.components ~= nil
        and vehicle.components[1] ~= nil
        and valid(vehicle.components[1].node) then
        return vehicle.components[1].node, nil, "first-component"
    end

    if vehicle ~= nil and valid(vehicle.rootNode) then
        return vehicle.rootNode, nil, "vehicle-root"
    end
    return nil, nil, nil
end

