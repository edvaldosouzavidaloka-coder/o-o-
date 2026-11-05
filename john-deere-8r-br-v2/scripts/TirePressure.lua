-- FS25: server-authoritative simulated tire pressure. Does not change wheel physics.
TirePressure = {}
TirePressure.MOD_NAME = g_currentModName
TirePressure.SPEC_NAME = TirePressure.MOD_NAME .. ".tirePressure"
TirePressure.PRESSURE_MIN = 80
TirePressure.PRESSURE_NORMAL = 180
TirePressure.PRESSURE_MAX = 180
TirePressure.FLATE_SPEED = 0.01 -- kPa per millisecond
TirePressure.AXIS_STEP = 1.5

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function clamp(value, minimum, maximum)
    return math.min(maximum, math.max(minimum, value))
end

TirePressureEvent = {}
local TirePressureEvent_mt = Class(TirePressureEvent, Event)
InitEventClass(TirePressureEvent, "TirePressureEvent")

function TirePressureEvent.emptyNew()
    return Event.new(TirePressureEvent_mt)
end

function TirePressureEvent.new(vehicle, target, isInflating)
    local self = TirePressureEvent.emptyNew()
    self.vehicle, self.target, self.isInflating = vehicle, target, isInflating
    return self
end

function TirePressureEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.target = streamReadFloat32(streamId)
    self.isInflating = streamReadBool(streamId)
    self:run(connection)
end

function TirePressureEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteFloat32(streamId, self.target)
    streamWriteBool(streamId, self.isInflating)
end

function TirePressureEvent:run(connection)
    -- Requests only travel client -> server. The server replicates validated state
    -- through vehicle streams, including the target and the running/stopped state.
    local vehicle = self.vehicle
    if connection:getIsServer() or vehicle == nil or not vehicle.isServer
        or vehicle.spec_tirePressure == nil or not vehicle.spec_tirePressure.enabled
        or not vehicle:getIsSynchronized() or not finite(self.target) then
        return
    end
    vehicle:setInflationPressureTarget(self.target, true)
    vehicle:updateInflation(self.isInflating, true)
end

local function sendRequest(vehicle)
    if not vehicle.isServer and g_client ~= nil then
        local spec = vehicle.spec_tirePressure
        g_client:getServerConnection():sendEvent(TirePressureEvent.new(vehicle,
            spec.inflationPressureTarget, spec.isInflating))
    end
end

function TirePressure.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("TirePressure")
    schema:register(XMLValueType.FLOAT, "vehicle.tirePressure#min", "Minimum pressure (kPa)", TirePressure.PRESSURE_MIN)
    schema:register(XMLValueType.FLOAT, "vehicle.tirePressure#max", "Maximum pressure (kPa)", TirePressure.PRESSURE_MAX)
    schema:register(XMLValueType.STRING, "vehicle.tirePressure#configurationName", "Required configuration")
    schema:register(XMLValueType.STRING, "vehicle.tirePressure#configurationIndices", "Enabled configuration indices", "2")
    SoundManager.registerSampleXMLPaths(schema, "vehicle.tirePressure.sounds", "air")
    schema:setXMLSpecializationType()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT,
        "vehicles.vehicle(?)." .. TirePressure.SPEC_NAME .. "#inflationPressure", "Pressure (kPa)")
end

function TirePressure.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function TirePressure.registerFunctions(vehicleType)
    for _, name in ipairs({"updateInflation", "getInflationPressure", "setInflationPressure",
        "getInflationPressureTarget", "setInflationPressureTarget"}) do
        SpecializationUtil.registerFunction(vehicleType, name, TirePressure[name])
    end
end

function TirePressure.registerEventListeners(vehicleType)
    for _, name in ipairs({"onLoad", "onPostLoad", "onDelete", "onUpdate",
        "onReadStream", "onWriteStream", "onReadUpdateStream", "onWriteUpdateStream",
        "onRegisterActionEvents"}) do
        SpecializationUtil.registerEventListener(vehicleType, name, TirePressure)
    end
end

function TirePressure:onLoad(savegame)
    self.spec_tirePressure = self["spec_" .. TirePressure.SPEC_NAME]
    local spec = self.spec_tirePressure
    spec.actionEvents, spec.samples = {}, {}
    spec.isInflating = false
    spec.enabled = true
    local configName = self.xmlFile:getValue("vehicle.tirePressure#configurationName")
    if configName ~= nil then
        spec.enabled = false
        local indices = self.xmlFile:getValue("vehicle.tirePressure#configurationIndices", "2")
        for index in tostring(indices):gmatch("%d+") do
            if tonumber(index) == (self.configurations[configName] or 1) then
                spec.enabled = true
            end
        end
    end
    spec.pressureMin = self.xmlFile:getValue("vehicle.tirePressure#min", TirePressure.PRESSURE_MIN)
    spec.pressureMax = self.xmlFile:getValue("vehicle.tirePressure#max", TirePressure.PRESSURE_MAX)
    if not finite(spec.pressureMin) or not finite(spec.pressureMax)
        or spec.pressureMin <= 0 or spec.pressureMax < spec.pressureMin then
        Logging.xmlWarning(self.xmlFile, "Invalid tire-pressure limits. Using the default range.")
        spec.pressureMin, spec.pressureMax = TirePressure.PRESSURE_MIN, TirePressure.PRESSURE_MAX
    end
    spec.inflationPressure = clamp(TirePressure.PRESSURE_NORMAL, spec.pressureMin, spec.pressureMax)
    spec.inflationPressureTarget = spec.inflationPressure
    spec.inflationDirtyFlag = self:getNextDirtyFlag()
    if self.isClient and spec.enabled then
        spec.samples.air = g_soundManager:loadSampleFromXML(self.xmlFile,
            "vehicle.tirePressure.sounds", "air", self.baseDirectory,
            self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
    end
end

function TirePressure:onPostLoad(savegame)
    local spec = self.spec_tirePressure
    if savegame ~= nil and not savegame.resetVehicles then
        local value = savegame.xmlFile:getValue(savegame.key .. "." .. TirePressure.SPEC_NAME .. "#inflationPressure")
        if finite(value) then
            self:setInflationPressure(value)
        end
    end
    spec.inflationPressureTarget = spec.inflationPressure
end

function TirePressure:saveToXMLFile(xmlFile, key, usedModNames)
    xmlFile:setValue(key .. "#inflationPressure", self.spec_tirePressure.inflationPressure)
end

function TirePressure:onDelete()
    if self.spec_tirePressure ~= nil then
        g_soundManager:deleteSamples(self.spec_tirePressure.samples)
    end
end

local function readState(vehicle, streamId)
    local pressure = streamReadFloat32(streamId)
    local target = streamReadFloat32(streamId)
    local isInflating = streamReadBool(streamId)
    if finite(pressure) and finite(target) then
        vehicle:setInflationPressure(pressure)
        vehicle:setInflationPressureTarget(target, true)
        vehicle:updateInflation(isInflating, true)
    end
end

local function writeState(vehicle, streamId)
    local spec = vehicle.spec_tirePressure
    streamWriteFloat32(streamId, spec.inflationPressure)
    streamWriteFloat32(streamId, spec.inflationPressureTarget)
    streamWriteBool(streamId, spec.isInflating)
end

function TirePressure:onReadStream(streamId, connection)
    if connection:getIsServer() then
        readState(self, streamId)
    end
end

function TirePressure:onWriteStream(streamId, connection)
    if not connection:getIsServer() then
        writeState(self, streamId)
    end
end

function TirePressure:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        readState(self, streamId)
    end
end

function TirePressure:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local dirty = bitAND(dirtyMask, self.spec_tirePressure.inflationDirtyFlag) ~= 0
        streamWriteBool(streamId, dirty)
        if dirty then
            writeState(self, streamId)
        end
    end
end

function TirePressure:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_tirePressure
    if not spec.enabled then
        return
    end
    if self.isServer and spec.isInflating and finite(dt) and dt >= 0 then
        local diff = spec.inflationPressureTarget - spec.inflationPressure
        local step = math.min(math.abs(diff), dt * TirePressure.FLATE_SPEED)
        self:setInflationPressure(spec.inflationPressure + (diff < 0 and -step or step))
        if math.abs(spec.inflationPressureTarget - spec.inflationPressure) < 0.0001 then
            self:setInflationPressure(spec.inflationPressureTarget)
            self:updateInflation(false)
        end
    end
    if self.isClient and isActiveForInputIgnoreSelection then
        local text = g_i18n:getText("information_tirePressure", self.customEnvironment)
        local display = string.format(text, spec.inflationPressureTarget / 100, spec.inflationPressure / 100)
        if g_currentMission ~= nil and g_currentMission.addExtraPrintText ~= nil then
            g_currentMission:addExtraPrintText(display)
        elseif spec.toggleActionEventId ~= nil then
            g_inputBinding:setActionEventText(spec.toggleActionEventId, display)
        end
    end
end

function TirePressure:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end
    local spec = self.spec_tirePressure
    self:clearActionEventsTable(spec.actionEvents)
    spec.toggleActionEventId = nil
    if not spec.enabled or not isActiveForInputIgnoreSelection then
        return
    end
    local _, id = self:addActionEvent(spec.actionEvents, InputAction.TP_TOGGLE_PRESSURE,
        self, TirePressure.actionEventToggle, false, true, false, true, nil)
    spec.toggleActionEventId = id
    if id ~= nil then
        g_inputBinding:setActionEventTextPriority(id, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventText(id, g_i18n:getText("action_toggleTirePressure", self.customEnvironment))
    end
    _, id = self:addActionEvent(spec.actionEvents, InputAction.TP_AXIS_PRESSURE,
        self, TirePressure.actionEventAxis, false, false, true, true, nil)
    if id ~= nil then
        g_inputBinding:setActionEventTextVisibility(id, false)
    end
end

function TirePressure.actionEventToggle(self, actionName, inputValue, callbackState, isAnalog)
    self:updateInflation(not self.spec_tirePressure.isInflating)
end

function TirePressure.actionEventAxis(self, actionName, inputValue, callbackState, isAnalog)
    if finite(inputValue) and inputValue ~= 0 then
        local spec = self.spec_tirePressure
        self:setInflationPressureTarget(spec.inflationPressureTarget
            + (inputValue < 0 and -TirePressure.AXIS_STEP or TirePressure.AXIS_STEP))
    end
end

function TirePressure:updateInflation(isInflating, noEventSend)
    local spec = self.spec_tirePressure
    isInflating = isInflating == true and spec.enabled
    if spec.isInflating == isInflating then
        return
    end
    spec.isInflating = isInflating
    if self.isServer then
        self:raiseDirtyFlags(spec.inflationDirtyFlag)
    end
    if self.isClient and spec.samples.air ~= nil then
        if isInflating then
            g_soundManager:playSample(spec.samples.air)
        else
            g_soundManager:stopSample(spec.samples.air)
        end
    end
    if not noEventSend then
        sendRequest(self)
    end
end

function TirePressure:getInflationPressure()
    return self.spec_tirePressure.inflationPressure
end

function TirePressure:setInflationPressure(pressure)
    if not finite(pressure) then
        return
    end
    local spec = self.spec_tirePressure
    local value = clamp(pressure, spec.pressureMin, spec.pressureMax)
    if spec.inflationPressure ~= value then
        spec.inflationPressure = value
        if self.isServer then
            self:raiseDirtyFlags(spec.inflationDirtyFlag)
        end
    end
end

function TirePressure:getInflationPressureTarget()
    return self.spec_tirePressure.inflationPressureTarget
end

function TirePressure:setInflationPressureTarget(value, noEventSend)
    local spec = self.spec_tirePressure
    if not spec.enabled or not finite(value) then
        return
    end
    value = clamp(value, spec.pressureMin, spec.pressureMax)
    if spec.inflationPressureTarget ~= value then
        spec.inflationPressureTarget = value
        if self.isServer then
            self:raiseDirtyFlags(spec.inflationDirtyFlag)
        end
        if not noEventSend then
            sendRequest(self)
        end
    end
end
