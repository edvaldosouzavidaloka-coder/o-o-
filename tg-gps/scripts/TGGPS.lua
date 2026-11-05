-- TG GPS PRO - FS25
-- Guias A/B e curvas com direcao automatica pelo TGGuidanceController.
-- A velocidade permanece sob controle do jogador. Uso single-player.

TGGPS = {}
TGGPS.MOD_NAME = g_currentModName
TGGPS.MOD_DIRECTORY = g_currentModDirectory

TGGPS.VERSION = "0.9.3.0"
TGGPS.DEFAULT_WIDTH = 6.0
TGGPS.MIN_WIDTH = 1.0
TGGPS.MAX_WIDTH = 50.0
TGGPS.WIDTH_STEP = 0.5
TGGPS.RECORD_DISTANCE = 2.0
TGGPS.SPLINE_SPACING = 1.25
TGGPS.MAX_LANE = 5
TGGPS.MAX_DYNAMIC_LANE = 1000
TGGPS.DRAW_LANE_RADIUS = 5
TGGPS.SAVE_FOLDER = "modSettings/FS25_TG_GPS"
TGGPS.MAX_AUTOSTEER_SPEED = 25 -- km/h
TGGPS.MANUAL_STEERING_THRESHOLD = 0 -- any nonzero manual steering input releases GPS
TGGPS.MAX_CAPTURE_DISTANCE = 8 -- metros
TGGPS.MAX_CAPTURE_ANGLE = math.rad(60)

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function fieldError(reason)
    local messages = {
        too_many_lanes = "mais de 1000 passadas; aumente a largura",
        invalid_polygon = "contorno invalido no mapa",
        invalid_position = "posicao do trator invalida",
        invalid_direction = "direcao do trator invalida",
        invalid_width = "largura do implemento invalida",
        no_lanes = "nao ha trechos de pelo menos 2 metros",
        field_api_unavailable = "o mapa nao disponibiliza o contorno",
        field_api_failed = "falha ao ler os dados do mapa",
        polygon_unavailable = "contorno indisponivel",
        no_field = "nenhum talhao identificado neste ponto"
    }
    return messages[reason] or "nao foi possivel ler o contorno"
end

local function distance2D(a, b)
    local dx = b.x - a.x
    local dz = b.z - a.z
    return math.sqrt(dx * dx + dz * dz)
end

local function getVehiclePosition(vehicle)
    if vehicle == nil then
        return nil
    end

    local node = vehicle.rootNode
    if node == nil and vehicle.components ~= nil and vehicle.components[1] ~= nil then
        node = vehicle.components[1].node
    end
    if node == nil then
        return nil
    end

    local x, y, z = getWorldTranslation(node)
    return {x = x, y = y, z = z}
end

local function catmullRom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    local function value(a, b, c, d)
        return 0.5 * ((2 * b) + (-a + c) * t + (2*a - 5*b + 4*c - d) * t2 + (-a + 3*b - 3*c + d) * t3)
    end
    return {
        x = value(p0.x, p1.x, p2.x, p3.x),
        z = value(p0.z, p1.z, p2.z, p3.z)
    }
end

function TGGPS:smoothPath(points, spacing)
    if points == nil or #points < 3 then
        local copy = {}
        for i, p in ipairs(points or {}) do
            copy[i] = {x = p.x, z = p.z}
        end
        return copy
    end

    local result = {}
    spacing = spacing or TGGPS.SPLINE_SPACING

    for i = 1, #points - 1 do
        local p0 = points[math.max(1, i - 1)]
        local p1 = points[i]
        local p2 = points[i + 1]
        local p3 = points[math.min(#points, i + 2)]
        local segmentLength = distance2D(p1, p2)
        local steps = math.max(1, math.ceil(segmentLength / spacing))

        for step = 0, steps - 1 do
            local t = step / steps
            result[#result + 1] = catmullRom(p0, p1, p2, p3, t)
        end
    end

    local last = points[#points]
    result[#result + 1] = {x = last.x, z = last.z}
    return result
end

function TGGPS:offsetPath(points, offset)
    local result = {}
    local count = #points
    if count < 2 then
        return result
    end

    for i = 1, count do
        local previous = points[math.max(1, i - 1)]
        local following = points[math.min(count, i + 1)]
        local dx = following.x - previous.x
        local dz = following.z - previous.z
        local length = math.sqrt(dx * dx + dz * dz)

        if length < 0.0001 then
            result[i] = {x = points[i].x, z = points[i].z}
        else
            -- Normal perpendicular to the local tangent.
            local normalX = -dz / length
            local normalZ = dx / length
            result[i] = {
                x = points[i].x + normalX * offset,
                z = points[i].z + normalZ * offset
            }
        end
    end

    return result
end

function TGGPS:makeStraightPath(pointA, pointB)
    local length = distance2D(pointA, pointB)
    if length < 2 then
        return nil
    end

    local steps = math.max(2, math.ceil(length / TGGPS.SPLINE_SPACING))
    local points = {}
    for i = 0, steps do
        local t = i / steps
        points[#points + 1] = {
            x = pointA.x + (pointB.x - pointA.x) * t,
            z = pointA.z + (pointB.z - pointA.z) * t
        }
    end
    return points
end

function TGGPS:loadMap()
    if self.monitor ~= nil then self.monitor:delete() end
    if self.audio ~= nil then self.audio:delete() end
    if self.hud ~= nil then
        self:closeHud()
        self.hud:delete()
        self.hud = nil
    end
    self.width = TGGPS.DEFAULT_WIDTH
    self.trackOffset, self.activeCourseName, self.libraryFilter, self.libraryPage = 0, nil, "", 1
    self.mapZoom, self.contextTimer, self.monitorContext, self.dialogBusy = 1, 0, nil, false
    self.monitorBrightness=0.20
    self.monitorSounds=true
    self.mapVehicleUp,self.mapViewport,self.mapTime=true,nil,nil
    self.activeImplementId,self.activeSessionKey,self.activeWorkAreaId,self.implementSessions,self.coverageSessions=nil,nil,nil,{},{}
    self.currentLane = 0
    self.showLines = true
    self.isRecording = false
    self.recordedPoints = {}
    self.sourcePoints = {}
    self.basePath = {}
    self.guidanceLines = {}
    self.guidanceSections = {}
    self.fieldBoundary = nil
    self.fieldOrigin = nil
    self.fieldDirection = nil
    self.curveReference,self.fieldCurveReference=nil,nil
    self.autoLaneSelection = true
    self.currentSection = 1
    self.selectionTimer = 0
    self.minLane, self.maxLane = nil, nil
    self.pointA = nil
    self.mode = "none"
    self.status = "Ctrl+Alt+F gera o talhao | Ctrl+Alt+P liga o piloto"
    self.actionEventIds = {}
    self.autosteerEnabled = false
    self.activeVehicle = nil
    self.travelDirection = nil
    self.steeringCommand = 0
    self.recordingVehicle = nil
    self.headlandEnabled = false
    self.headlandDepth, self.turnSpeed, self.turnRadius, self.turnSide = 18, 6, 6, 1
    self.turnState, self.headlandBrakeHoldVehicle = nil, nil
    self.completedSections = {}
    self.hudVehicle = nil
    self.hudSavedCameras = nil
    self.hudSavedCursor = nil

    self.coverage = TGGPSHUDMonitor.new(self)
    self.widthProfiles = TGGPSWidthProfiles.new(self)
    self.audio = TGGPSAudio.new(self, TGGPS.MOD_DIRECTORY)
    self.recognition = TGGPSRecognition.new(self)
    self.monitor = TGGPSMonitorManager.new(self, TGGPS.MOD_DIRECTORY)

    self:loadCourse()
    self.library = TGGPSCourseLibrary.new(self)
    if TGGPSHud ~= nil then
        self.hud = TGGPSHud.new(self)
        self:loadHudSettings()
    end
    Logging.info(string.format("[TG GPS PRO] v%s carregado", TGGPS.VERSION))
end

function TGGPS:registerOneAction(vehicle, actionName, callback, textKey)
    if g_inputBinding == nil then
        return
    end

    local action = InputAction ~= nil and InputAction[actionName] or actionName
    if action == nil then
        Logging.warning("[TG GPS PRO] Acao nao encontrada: " .. actionName)
        return
    end
    local _, eventId = vehicle:addActionEvent(
        vehicle.tgGpsActionEvents, action, self, callback, false, true, false, true
    )
    if eventId ~= nil then
        vehicle.tgGpsRegisteredActions=vehicle.tgGpsRegisteredActions or {}
        vehicle.tgGpsRegisteredActions[actionName]=eventId
        if textKey ~= nil and g_i18n ~= nil then
            g_inputBinding:setActionEventText(eventId, g_i18n:getText(textKey))
        end
        if GS_PRIO_HIGH ~= nil then
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_HIGH)
        end
    end
end

function TGGPS:registerInputActions(vehicle)
    vehicle.tgGpsRegisteredActions={}
    self:registerOneAction(vehicle,"TG_GPS_MONITOR_SETTINGS",TGGPS.onOpenMonitorSettings,"input_TG_GPS_MONITOR_SETTINGS")
    self:registerOneAction(vehicle,"TG_GPS_ZOOM_IN",TGGPS.onZoomIn,"input_TG_GPS_ZOOM_IN")
    self:registerOneAction(vehicle,"TG_GPS_ZOOM_OUT",TGGPS.onZoomOut,"input_TG_GPS_ZOOM_OUT")
    self:registerOneAction(vehicle, "TG_GPS_MONITOR_EDIT", TGGPS.onEditMonitor, "input_TG_GPS_MONITOR_EDIT")
    self:registerOneAction(vehicle, "TG_GPS_HUD", TGGPS.onToggleHud, "input_TG_GPS_HUD")
    self:registerOneAction(vehicle, "TG_GPS_ENABLE", TGGPS.onEnableAutosteer, "input_TG_GPS_ENABLE")
    self:registerOneAction(vehicle, "TG_GPS_DISABLE", TGGPS.onDisableAutosteer, "input_TG_GPS_DISABLE")
    self:registerOneAction(vehicle, "TG_GPS_AUTO_LANE_ENABLE", TGGPS.onEnableAutoLane, "input_TG_GPS_AUTO_LANE_ENABLE")
    self:registerOneAction(vehicle, "TG_GPS_FIELD", TGGPS.onGenerateField, "input_TG_GPS_FIELD")
    self:registerOneAction(vehicle, "TG_GPS_AUTO_LANE", TGGPS.onToggleAutoLane, "input_TG_GPS_AUTO_LANE")
    self:registerOneAction(vehicle, "TG_GPS_AUTOSTEER", TGGPS.onToggleAutosteer, "input_TG_GPS_AUTOSTEER")
    self:registerOneAction(vehicle, "TG_GPS_MARK_AB", TGGPS.onMarkAB, "input_TG_GPS_MARK_AB")
    self:registerOneAction(vehicle, "TG_GPS_RECORD_CURVE", TGGPS.onRecordCurve, "input_TG_GPS_RECORD_CURVE")
    self:registerOneAction(vehicle, "TG_GPS_TOGGLE_LINES", TGGPS.onToggleLines, "input_TG_GPS_TOGGLE_LINES")
    self:registerOneAction(vehicle, "TG_GPS_LANE_PREV", TGGPS.onLanePrevious, "input_TG_GPS_LANE_PREV")
    self:registerOneAction(vehicle, "TG_GPS_LANE_NEXT", TGGPS.onLaneNext, "input_TG_GPS_LANE_NEXT")
    self:registerOneAction(vehicle, "TG_GPS_WIDTH_DOWN", TGGPS.onWidthDown, "input_TG_GPS_WIDTH_DOWN")
    self:registerOneAction(vehicle, "TG_GPS_WIDTH_UP", TGGPS.onWidthUp, "input_TG_GPS_WIDTH_UP")
    self:registerOneAction(vehicle, "TG_GPS_DETECT_WIDTH", TGGPS.onDetectWidth, "input_TG_GPS_DETECT_WIDTH")
    self:registerOneAction(vehicle, "TG_GPS_SAVE", TGGPS.onSave, "input_TG_GPS_SAVE")
    self:registerOneAction(vehicle, "TG_GPS_CLEAR", TGGPS.onClear, "input_TG_GPS_CLEAR")
    local count=0 for _ in pairs(vehicle.tgGpsRegisteredActions) do count=count+1 end
    return count
end

function TGGPS:getControlledVehicle()
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil then
        return g_localPlayer:getCurrentVehicle()
    end
    if g_currentMission == nil then
        return nil
    end
    return g_currentMission.controlledVehicle
end

function TGGPS:getCurrentPosition()
    return getVehiclePosition(self:getControlledVehicle())
end

function TGGPS:notify(message)
    self.status = message
    if Logging ~= nil then
        Logging.info("[TG GPS PRO] " .. tostring(message))
    end
end

function TGGPS:getMonitorContext()
    local vehicle = self:getControlledVehicle()
    if self.monitorContext == nil or self.monitorContext.vehicle ~= vehicle then
        self.monitorContext = TGGPSContext.read(self)
    end
    return self.monitorContext
end

function TGGPS:syncWorkingWidth()
    if self.widthProfiles then return self.widthProfiles:select(self:getControlledVehicle()) end
    return false
end
local IMPLEMENT_STATE={"mode","sourcePoints","basePath","guidanceLines","guidanceSections","fieldBoundary","fieldOrigin",
    "fieldDirection","minLane","maxLane","currentLane","currentSection","autoLaneSelection","trackOffset","headlandEnabled",
    "headlandDepth","turnSpeed","turnRadius","turnSide","activeCourseName","pointA","curveReference","fieldCurveReference"}
function TGGPS:selectImplementSession(id)
    local context=self:getMonitorContext()
    local field=context.fieldId~='' and context.fieldId or (self.activeImplementId==id and self.activeWorkAreaId or 'unknown')
    local key=id..'|'..tostring(field)
    if self.activeSessionKey==key then return false end
    self:stopAutosteer()
    if self.activeSessionKey then
        local state={}
        for _,name in ipairs(IMPLEMENT_STATE) do state[name]=self[name] end
        self.implementSessions[self.activeSessionKey]=state
        if self.coverage then self.coverage:endRun() end
        if self.activeImplementId==id and self.activeWorkAreaId=='unknown' and field~='unknown' then
            self.implementSessions[key]=state
            self.coverageSessions[key]=self.coverage
        end
    else
        -- Preserve the legacy quick route only for the first implement entered.
        local first={}
        for _,name in ipairs(IMPLEMENT_STATE) do first[name]=self[name] end
        self.implementSessions[key]=first
    end
    local state=self.implementSessions[key] or {mode='none',sourcePoints={},basePath={},guidanceLines={},guidanceSections={},
        currentLane=0,currentSection=1,autoLaneSelection=true,trackOffset=0,headlandEnabled=false,
        headlandDepth=18,turnSpeed=6,turnRadius=6,turnSide=1}
    for _,name in ipairs(IMPLEMENT_STATE) do self[name]=state[name] end
    self.activeImplementId,self.activeSessionKey,self.activeWorkAreaId=id,key,field
    self.isRecording,self.recordingVehicle,self.recordedPoints=false,nil,{}
    self.libraryFilter,self.libraryPage,self.libraryShowAll='',1,false
    self.coverageSessions[key]=self.coverageSessions[key] or TGGPSHUDMonitor.new(self)
    self.coverage=self.coverageSessions[key]
    self.workedAreaHa=self.coverage:getWorkedHa()
    return true
end

function TGGPS:requestText(title, default, callback)
    if self.dialogBusy then return end
    if g_gui == nil or g_gui.showTextInputDialog == nil then
        self:notify("A entrada de texto do jogo esta indisponivel")
        return
    end
    self:stopAutosteer()
    self.dialogBusy = true
    self:closeHud()
    g_gui:showTextInputDialog({title=title, text=title, defaultText=default or "", maxCharacters=48,
        target=self, callback=function(target,text,ok)
            target.dialogBusy=false
            if ok and type(text)=="string" then callback(text) end
            target.pendingHudOpen=true
        end})
end

function TGGPS:onSaveNamedCourse()
    self:syncWorkingWidth()
    if self.library == nil or #self.sourcePoints < 2 then self:notify("Crie uma linha antes de salvar"); return end
    local context = self:getMonitorContext()
    local snapshot = self.library:snapshot(self.activeCourseName or context.fieldName)
    self:requestText("Nome do trajeto (ex.: Talhao 3 - Norte)", snapshot.name, function(name)
        local ok, result = self.library:saveSnapshot(snapshot, name)
        if ok then
            self.activeCourseName=result.name
            self:saveCourse()
            self:notify("Trajeto salvo: " .. result.name)
        else self:notify(result) end
    end)
end

function TGGPS:onSearchCourses()
    self:requestText("Buscar nome, talhao ou orientacao", self.libraryFilter, function(text)
        self.libraryFilter, self.libraryPage = text, 1
        if self.hud then self.hud.page="library" end
    end)
end

function TGGPS:loadNamedCourse(id,here)
    local ok, result = self.library:load(id,{onlyLine=true,here=here==true,shared=self.libraryShowAll==true})
    if ok then
        self:notify(string.format("Carregado: %s | %.1f graus | largura deste conjunto %.1f m. Alinhe e ligue o piloto.", result.name, result.heading, self.width))
        if self.hud then self.hud.page="map" end
    else self:notify(result) end
end

function TGGPS:changeTrackOffset(delta)
    if #self.sourcePoints < 2 then self:notify("Crie ou carregue uma linha primeiro"); return false end
    self:stopAutosteer()
    local old = self.trackOffset or 0
    self.trackOffset=math.max(-1000,math.min(1000,old+delta))
    if not self:rebuildGuidance() then self.trackOffset=old;self:rebuildGuidance();return false end
    self.autoLaneSelection, self.completedSections = false, {}
    self:notify(string.format("Linha deslocada %.2f m | piloto desligado; confira o alinhamento", self.trackOffset))
    return true
end
function TGGPS:onNudgeLineLeft() self:changeTrackOffset(-0.10) end
function TGGPS:onNudgeLineRight() self:changeTrackOffset(0.10) end
function TGGPS:onResetTrackOffset() self:changeTrackOffset(-(self.trackOffset or 0)) end
function TGGPS:onSnapLine()
    local path=self:getLanePath(self.currentLane,self.currentSection)
    local pose=self:getVehiclePose(self:getControlledVehicle())
    if path==nil or pose==nil then self:notify("Selecione uma linha e entre na maquina");return end
    local distance, offset=math.huge,0
    for i=1,#path-1 do
        local a,b=path[i],path[i+1]
        local dx,dz=b.x-a.x,b.z-a.z
        local length=math.sqrt(dx*dx+dz*dz)
        if length>0.00001 then
            local t=math.max(0,math.min(1,((pose.x-a.x)*dx+(pose.z-a.z)*dz)/(length*length)))
            local ex,ez=pose.x-a.x-dx*t,pose.z-a.z-dz*t
            local squared=ex*ex+ez*ez
            if squared<distance then distance,offset=squared,(-dz*ex+dx*ez)/length end
        end
    end
    self:changeTrackOffset(offset)
end

function TGGPS:onZoomIn() self.mapZoom=math.min(12,TGGPSMap.getZoom(self)+0.5);self:saveHudSettings() end
function TGGPS:onZoomOut() self.mapZoom=math.max(1,TGGPSMap.getZoom(self)-0.5);self:saveHudSettings() end
function TGGPS:onZoomFit() self.mapZoom=1;self:saveHudSettings() end
function TGGPS:onToggleMapOrientation()
    self.mapVehicleUp=not self.mapVehicleUp
    self.mapViewport=nil
    self:saveHudSettings()
end
function TGGPS:onOpenMonitorSettings()
    if self.hud then self.hud.page="settings" end
    self:openHud()
end
function TGGPS:onBrightnessDown()
    self.monitorBrightness=math.max(0.05,(self.monitorBrightness or 0.20)-0.05)
    self:saveHudSettings()
end
function TGGPS:onBrightnessUp()
    self.monitorBrightness=math.min(1,(self.monitorBrightness or 0.20)+0.05)
    self:saveHudSettings()
end

function TGGPS:onToggleMonitorSounds()
    self.monitorSounds=self.monitorSounds==false
    self:saveHudSettings()
    if self.monitorSounds and self.audio then self.audio:play('connect') end
end

local function isGameMenuVisible()
    return g_gui ~= nil and g_gui.getIsGuiVisible ~= nil and g_gui:getIsGuiVisible()
end

function TGGPS:openHud()
    if self.hud == nil or isGameMenuVisible() then
        return false
    end
    if self.monitor and self.monitor.editing then self.monitor:finishEditing(true) end
    if self.hud.isOpen then
        return true
    end
    local vehicle = self:getControlledVehicle()
    if vehicle == nil or not vehicle.tgGpsSupported then
        self:notify("Entre em um trator para abrir o monitor GPS")
        return false
    end
    if g_inputBinding == nil or g_inputBinding.getShowMouseCursor == nil or g_inputBinding.setShowMouseCursor == nil then
        self:notify("Nao foi possivel ativar o cursor do monitor")
        return false
    end
    self.hudVehicle = vehicle
    self.hudSavedCursor = g_inputBinding:getShowMouseCursor()
    self.hudSavedCameras = {}
    local cameras = vehicle.spec_enterable and vehicle.spec_enterable.cameras or {}
    for _, camera in pairs(cameras) do
        self.hudSavedCameras[#self.hudSavedCameras + 1] = {camera = camera, value = camera.isRotatable}
        camera.isRotatable = false
    end
    g_inputBinding:setShowMouseCursor(true)
    self.hud:setOpen(true)
    return true
end

function TGGPS:closeHud(preserveMenuCursor)
    local wasOpen = self.hud ~= nil and self.hud.isOpen
    if self.hud ~= nil then
        self.hud:setOpen(false)
    end
    for _, entry in ipairs(self.hudSavedCameras or {}) do
        entry.camera.isRotatable = entry.value
    end
    if self.hudSavedCursor ~= nil and not preserveMenuCursor and not isGameMenuVisible()
        and g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        g_inputBinding:setShowMouseCursor(self.hudSavedCursor)
    end
    self.hudSavedCameras, self.hudSavedCursor, self.hudVehicle = nil, nil, nil
    if wasOpen then
        self:saveHudSettings()
    end
end

function TGGPS:onToggleHud()
    if self.hud ~= nil and self.hud.isOpen then
        self:closeHud()
    else
        self:openHud()
    end
end

function TGGPS:onEditMonitor()
    if self.monitor ~= nil then self.monitor:toggleEditMode() end
end

function TGGPS:onResetCoverage()
    if self.coverage == nil then return end
    local selected=self.coverage
    if g_gui ~= nil and g_gui.showYesNoDialog ~= nil then
        g_gui:showYesNoDialog({text = "Zerar pintura e hectares somente deste implemento nesta sessao?",
            target = self, callback = function(target, yes)
                if yes then selected:reset() end
            end})
    end
end
function TGGPS:deleteNamedCourse(id)
    local profile=self.activeImplementId
    if g_gui and g_gui.showYesNoDialog then
        g_gui:showYesNoDialog({text='Excluir somente esta linha salva deste implemento?',target=self,
            callback=function(target,yes)
                if yes then local ok,message=target.library:deleteOwn(id,profile);target:notify(message) end
            end})
    end
end

function TGGPS:isMouseOverHud(x, y)
    if self.hud == nil or not self.hud.isOpen or isGameMenuVisible()
        or self:getControlledVehicle() ~= self.hudVehicle then
        return false
    end
    local bounds = self.hud:getBounds()
    return x >= bounds.x and x <= bounds.x + bounds.w and y >= bounds.y and y <= bounds.y + bounds.h
end

function TGGPS:mouseEvent(posX, posY, isDown, isUp, button)
    if self.hud ~= nil and self.hud.isOpen then
        if self:getControlledVehicle() ~= self.hudVehicle or isGameMenuVisible() then
            self:closeHud(isGameMenuVisible())
            return false
        end
        return self.hud:mouseEvent(posX, posY, isDown, isUp, button)
    end
    return false
end

function TGGPS:keyEvent(unicode, sym, modifier, isDown)
    if self.monitor ~= nil and self.monitor:keyEvent(unicode, sym, modifier, isDown) then return end
    local escape = Input ~= nil and Input.KEY_esc or nil
    if isDown and escape ~= nil and sym == escape and self.hud ~= nil and self.hud.isOpen then
        self:closeHud(isGameMenuVisible())
    end
end

function TGGPS:saveHudSettings()
    if self.hud == nil or createXMLFile == nil or setXMLFloat == nil or saveXMLFile == nil or delete == nil then
        return false
    end
    local folder = getUserProfileAppPath() .. TGGPS.SAVE_FOLDER
    if createFolder ~= nil then createFolder(folder) end
    local xml = createXMLFile("TGGPSHudSettings", folder .. "/hud.xml", "tgGpsHud")
    if xml == nil or xml == 0 then return false end
    local settings = self.hud:getSettings()
    setXMLFloat(xml, "tgGpsHud#x", settings.x)
    setXMLFloat(xml, "tgGpsHud#y", settings.y)
    setXMLFloat(xml, "tgGpsHud#scale", settings.scale)
    setXMLFloat(xml, "tgGpsHud#zoom", self.mapZoom or 1)
    setXMLFloat(xml,"tgGpsHud#brightness",self.monitorBrightness or 0.20)
    setXMLInt(xml,"tgGpsHud#vehicleUp",self.mapVehicleUp~=false and 1 or 0)
    setXMLInt(xml,"tgGpsHud#monitorSounds",self.monitorSounds~=false and 1 or 0)
    saveXMLFile(xml)
    delete(xml)
    return true
end

function TGGPS:loadHudSettings()
    if self.hud == nil or loadXMLFile == nil or getXMLFloat == nil or delete == nil then return false end
    local path = getUserProfileAppPath() .. TGGPS.SAVE_FOLDER .. "/hud.xml"
    if fileExists ~= nil and not fileExists(path) then return false end
    local xml = loadXMLFile("TGGPSHudSettings", path)
    if xml == nil or xml == 0 then return false end
    self.hud:applySettings({
        x = getXMLFloat(xml, "tgGpsHud#x"), y = getXMLFloat(xml, "tgGpsHud#y"),
        scale = getXMLFloat(xml, "tgGpsHud#scale")
    })
    local zoom=getXMLFloat(xml,"tgGpsHud#zoom")
    self.mapZoom=finite(zoom) and math.max(1,math.min(12,zoom)) or 1
    local brightness=getXMLFloat(xml,"tgGpsHud#brightness")
    self.monitorBrightness=finite(brightness) and math.max(0.05,math.min(1,brightness)) or 0.20
    self.mapVehicleUp=getXMLInt(xml,'tgGpsHud#vehicleUp')~=0
    self.monitorSounds=getXMLInt(xml,'tgGpsHud#monitorSounds')~=0
    self.mapViewport=nil
    delete(xml)
    return true
end

function TGGPS:rebuildGuidance()
    self.guidanceLines = {}
    self.guidanceSections = {}
    self.basePath = {}

    if self.mode=='field' and self.fieldBoundary and self.fieldCurveReference and #self.fieldCurveReference>=2 then
        local data,reason=TGFieldCurves.generate(self,self.fieldBoundary,self.fieldCurveReference,self.width,self.trackOffset or 0,
            self.headlandEnabled and self.headlandDepth or 0)
        if not data then self:notify('Nao foi possivel gerar curvas: '..tostring(reason));return false end
        self.guidanceSections,self.minLane,self.maxLane=data.lanes,data.minLane,data.maxLane
        self.basePath,self.sourcePoints=data.basePath,self.fieldCurveReference
        for lane,paths in pairs(data.lanes) do self.guidanceLines[lane]=paths[1] end
        if self.guidanceLines[self.currentLane]==nil then self.currentLane=next(self.guidanceLines) end
        self.currentSection=1
        return true
    end
    if self.mode == "field" and self.fieldBoundary ~= nil then
        local d, origin = self.fieldDirection, self.fieldOrigin
        if d==nil or origin==nil or not finite(d.dx) or not finite(d.dz)
            or d.dx*d.dx+d.dz*d.dz<0.000001 then
            self:notify("Direcao de talhao invalida"); return false
        end
        local length=math.sqrt(d.dx*d.dx+d.dz*d.dz)
        local shifted={x=origin.x-d.dz/length*(self.trackOffset or 0),z=origin.z+d.dx/length*(self.trackOffset or 0)}
        local data, reason = TGFieldBoundary.generateLanes(self.fieldBoundary, shifted, d, self.width)
        if data == nil then
            self:notify("Nao foi possivel gerar as passadas: " .. fieldError(reason))
            return false
        end
        local work = data
        if self.headlandEnabled then
            work, reason = TGHeadlandGeometry.trimLanes(data.lanes, self.fieldBoundary, self.headlandDepth)
            if work == nil then
                self:notify("Nao ha area util com esta margem de cabeceira; reduza a margem")
                return false
            end
        end
        self.guidanceSections = work.lanes
        self.minLane, self.maxLane = work.minLane, work.maxLane
        self.basePath = data.basePath
        self.sourcePoints = data.basePath
        for lane, paths in pairs(work.lanes) do
            self.guidanceLines[lane] = paths[1]
        end
        if self.guidanceLines[self.currentLane] == nil then
            self.currentLane = next(self.guidanceLines)
        end
        self.currentSection = 1
        return true
    end

    if self.sourcePoints == nil or #self.sourcePoints < 2 then
        self:notify("Marque pelo menos dois pontos para criar as linhas")
        return false
    end

    if self.mode == "curve" then
        self.basePath = self:smoothPath(self.sourcePoints, TGGPS.SPLINE_SPACING)
    else
        self.basePath = self.sourcePoints
    end

    for lane = -TGGPS.MAX_LANE, TGGPS.MAX_LANE do
        self.guidanceLines[lane] = self:offsetPath(self.basePath, lane * self.width + (self.trackOffset or 0))
    end

    self.minLane, self.maxLane = nil, nil
    self.currentLane = math.max(-TGGPS.MAX_DYNAMIC_LANE, math.min(TGGPS.MAX_DYNAMIC_LANE, self.currentLane or 0))
    self:ensureLane(self.currentLane)
    self.currentSection = 1
    return true
end

function TGGPS:onToggleHeadland()
    if self.mode ~= "field" or self.fieldBoundary == nil then
        self:notify("Gere o talhao antes de ativar a cabeceira automatica")
        return
    end
    self:stopAutosteer()
    self.headlandEnabled = not self.headlandEnabled
    if not self:rebuildGuidance() then
        self.headlandEnabled = false
        self:rebuildGuidance()
        self:notify("Margem grande demais para este talhao; cabeceira desativada")
        return
    end
    self:refreshSelection(self:getControlledVehicle())
    self:notify(self.headlandEnabled and "Cabeceira automatica ligada: volante ou freio cancela a manobra"
        or "Cabeceira automatica desligada")
end

function TGGPS:changeHeadlandSetting(name, delta, minimum, maximum)
    self:stopAutosteer()
    local old = self[name]
    self[name] = math.max(minimum, math.min(maximum, old + delta))
    if self.headlandEnabled and name == "headlandDepth" and not self:rebuildGuidance() then
        self[name] = old
        self:rebuildGuidance()
        self:notify("Margem recusada: nao sobra area de trabalho neste talhao")
        return
    end
    self:notify(string.format("Cabeceira: margem %.0f m | curva %.0f km/h | raio %.0f m", self.headlandDepth, self.turnSpeed, self.turnRadius))
end

function TGGPS:onHeadlandDepthDown() self:changeHeadlandSetting("headlandDepth", -2, 6, 50) end
function TGGPS:onHeadlandDepthUp() self:changeHeadlandSetting("headlandDepth", 2, 6, 50) end
function TGGPS:onTurnSpeedDown() self:changeHeadlandSetting("turnSpeed", -1, 2, 8) end
function TGGPS:onTurnSpeedUp() self:changeHeadlandSetting("turnSpeed", 1, 2, 8) end
function TGGPS:onTurnRadiusDown() self:changeHeadlandSetting("turnRadius", -1, 5, 15) end
function TGGPS:onTurnRadiusUp() self:changeHeadlandSetting("turnRadius", 1, 5, 15) end
function TGGPS:onToggleTurnDirection()
    self:stopAutosteer()
    self.turnSide = -self.turnSide
    self:notify(self.turnSide == 1 and "Proxima passada: indices maiores" or "Proxima passada: indices menores")
end

-- Recorded guides grow on demand instead of stopping at five neighboring lanes.
function TGGPS:ensureLane(lane)
    if self.guidanceLines[lane] ~= nil then
        return self.guidanceLines[lane]
    end
    if self.mode == "field" or #self.basePath < 2 or math.abs(lane) > TGGPS.MAX_DYNAMIC_LANE then
        return nil
    end
    self.guidanceLines[lane] = self:offsetPath(self.basePath, lane * self.width + (self.trackOffset or 0))
    return self.guidanceLines[lane]
end

function TGGPS:getLaneSections(lane)
    if self.guidanceSections[lane] ~= nil then
        return self.guidanceSections[lane]
    end
    local path = self:ensureLane(lane)
    return path ~= nil and {path} or {}
end

function TGGPS:getLanePath(lane, section)
    return self:getLaneSections(lane)[section or 1]
end

function TGGPS:onMarkAB(actionName, inputValue)
    self:syncWorkingWidth()
    local position = self:getCurrentPosition()
    if position == nil then
        self:notify("Entre em um trator para marcar A/B")
        return
    end

    self:stopAutosteer()
    self.isRecording = false
    self.recordingVehicle = nil
    self.recordedPoints = {}

    if self.pointA == nil then
        self.pointA = {x = position.x, z = position.z}
        self:notify("Ponto A marcado. Dirija ate o ponto B e pressione a tecla novamente")
        return
    end

    local pointB = {x = position.x, z = position.z}
    local path = self:makeStraightPath(self.pointA, pointB)
    if path == nil then
        self:notify("Pontos muito proximos. Marque A e B com pelo menos 2 metros")
        return
    end

    self.sourcePoints = path
    self.trackOffset, self.activeCourseName = 0, nil
    self.headlandEnabled = false
    self.fieldBoundary = nil
    self.mode = "straight"
    self.pointA = nil
    self.currentLane = 0
    self.autoLaneSelection = true
    self:rebuildGuidance()
    self:notify(string.format("Linha reta criada | largura %.1f m", self.width))
end

function TGGPS:onRecordCurve(actionName, inputValue)
    self:stopAutosteer()
    if not self.isRecording then
        local position = self:getCurrentPosition()
        if position == nil then
            self:notify("Entre em um trator para gravar a curva")
            return
        end

        self.isRecording = true
        self.recordingVehicle = self:getControlledVehicle()
        self.recordedPoints = {{x = position.x, z = position.z}}
        self.pointA = nil
        self:notify("GRAVANDO curva - siga o contorno do terreno e pressione novamente para finalizar")
        return
    end

    if self:getControlledVehicle() ~= self.recordingVehicle then
        self.isRecording = false
        self.recordingVehicle = nil
        self.recordedPoints = {}
        self:notify("Gravacao cancelada: veiculo alterado")
        return
    end
    local position = self:getCurrentPosition()
    if position ~= nil then
        local last = self.recordedPoints[#self.recordedPoints]
        if last == nil or distance2D(last, position) >= 0.5 then
            self.recordedPoints[#self.recordedPoints + 1] = {x = position.x, z = position.z}
        end
    end

    self.isRecording = false
    self.recordingVehicle = nil
    if #self.recordedPoints < 2 then
        self:notify("Curva muito curta. Grave novamente com mais distancia")
        self.recordedPoints = {}
        return
    end

    self.sourcePoints = self.recordedPoints
    self.curveReference=self.sourcePoints
    self.fieldCurveReference=nil
    self.trackOffset, self.activeCourseName = 0, nil
    self.recordedPoints = {}
    self.mode = "curve"
    self.headlandEnabled = false
    self.fieldBoundary = nil
    self.currentLane = 0
    self.autoLaneSelection = true
    self:rebuildGuidance()
    self:notify(string.format("Curva finalizada: %d pontos | largura %.1f m", #self.sourcePoints, self.width))
end

function TGGPS:onToggleLines(actionName, inputValue)
    self.showLines = not self.showLines
    self:notify(self.showLines and "Linhas do GPS visiveis" or "Linhas do GPS ocultas")
end

function TGGPS:onLanePrevious(actionName, inputValue)
    self:stopAutosteer()
    self:selectManualLane(-1)
end

function TGGPS:onLaneNext(actionName, inputValue)
    self:stopAutosteer()
    self:selectManualLane(1)
end

function TGGPS:selectManualLane(step)
    self.autoLaneSelection = false
    local lane = self.currentLane + step
    local minimum, maximum = self.minLane or -TGGPS.MAX_DYNAMIC_LANE, self.maxLane or TGGPS.MAX_DYNAMIC_LANE
    while lane >= minimum and lane <= maximum do
        if self:ensureLane(lane) ~= nil then
            self.currentLane, self.currentSection = lane, 1
            break
        end
        lane = lane + step
    end
    self:notify(string.format("Passada %d manual | Ctrl+Alt+L volta para automatica", self.currentLane))
end

function TGGPS:onToggleAutoLane()
    self:stopAutosteer()
    self.autoLaneSelection = not self.autoLaneSelection
    if self.autoLaneSelection then
        self:refreshSelection(self:getControlledVehicle())
    end
    self:notify(self.autoLaneSelection and "Passada automatica: use Ctrl+Alt+P para seguir a mais proxima"
        or "Passada manual: selecione com Ctrl+Alt+setas")
end

-- Separate commands let a remote dashboard send repeated taps without
-- accidentally toggling the current state back. They do not provide telemetry.
function TGGPS:onEnableAutoLane(actionName, inputValue)
    if self.autoLaneSelection then
        return
    end
    self:stopAutosteer()
    self.autoLaneSelection = true
    self:refreshSelection(self:getControlledVehicle())
    self:notify("Passada automatica: use Ligar piloto para seguir a mais proxima")
end

function TGGPS:onGenerateField()
    if self.isRecording then self:notify('Finalize a gravacao da curva antes de gerar o talhao');return end
    if self.mode=='curve' or (self.fieldCurveReference and #self.fieldCurveReference>=2) then return self:onGenerateFieldCurve() end
    return self:onGenerateFieldStraight()
end
function TGGPS:onGenerateFieldCurve()
    self:syncWorkingWidth();self:stopAutosteer()
    local reference
    if self.mode=='curve' then reference=self.sourcePoints
    elseif self.fieldCurveReference and #self.fieldCurveReference>=2 then reference=self.fieldCurveReference
    else reference=self.curveReference end
    if not reference or #reference<2 then self:notify('Grave ou carregue uma curva primeiro');return end
    local pose=self:getVehiclePose(self:getControlledVehicle())
    local boundary,reason=pose and TGFieldBoundary.getAt(pose.x,pose.z)
    if not boundary then self:notify('Entre no talhao para gerar curvas: '..tostring(reason));return end
    local old={} for _,name in ipairs(IMPLEMENT_STATE) do old[name]=self[name] end
    self.mode,self.fieldBoundary,self.fieldCurveReference='field',boundary,reference
    self.curveReference,self.sourcePoints=reference,reference
    self.fieldOrigin={x=reference[1].x,z=reference[1].z}
    local angle=math.rad(TGGPSContext.heading(reference));self.fieldDirection={dx=math.sin(angle),dz=math.cos(angle)}
    self.trackOffset,self.currentLane,self.currentSection,self.activeCourseName=0,0,1,nil
    if not self:rebuildGuidance() then for _,name in ipairs(IMPLEMENT_STATE) do self[name]=old[name] end;return end
    self:refreshSelection(self:getControlledVehicle())
    self:notify('Curvas paralelas geradas no talhao; referencia curva preservada')
end
function TGGPS:onGenerateFieldStraight()
    self:syncWorkingWidth()
    self:stopAutosteer()
    local vehicle = self:getControlledVehicle()
    local pose = vehicle ~= nil and self:getVehiclePose(vehicle) or nil
    if pose == nil then
        self:notify("Entre em um trator dentro do talhao e alinhe na direcao desejada")
        return
    end
    local vertices, fieldId = TGFieldBoundary.getAt(pose.x, pose.z)
    if vertices == nil then
        self:notify("Talhao: " .. fieldError(fieldId) .. ". Entre no talhao ou marque A/B")
        return
    end
    local data, reason = TGFieldBoundary.generateLanes(vertices, {x = pose.x, z = pose.z}, {dx = pose.dx, dz = pose.dz}, self.width)
    if data == nil then
        self:notify("Nao foi possivel gerar linhas: " .. fieldError(reason))
        return
    end
    if self.headlandEnabled then
        local work = TGHeadlandGeometry.trimLanes(data.lanes, vertices, self.headlandDepth)
        if work == nil then
            self:notify("Este talhao nao comporta a margem atual; reduza a cabeceira e tente novamente")
            return
        end
    end
    self.isRecording, self.recordingVehicle = false, nil
    self.recordedPoints, self.pointA = {}, nil
    self.fieldBoundary = vertices
    self.fieldCurveReference=nil
    self.trackOffset, self.activeCourseName = 0, nil
    self.fieldOrigin = {x = pose.x, z = pose.z}
    self.fieldDirection = {dx = pose.dx, dz = pose.dz}
    self.mode, self.currentLane, self.currentSection = "field", 0, 1
    self.autoLaneSelection = true
    self:rebuildGuidance()
    self:refreshSelection(vehicle)
    self:notify(string.format("Talhao: %d passadas geradas | Ctrl+Alt+P segue a mais proxima", data.laneCount))
end

function TGGPS:onWidthDown(actionName, inputValue)
    self:syncWorkingWidth()
    self:stopAutosteer()
    self.width = math.max(TGGPS.MIN_WIDTH, self.width - TGGPS.WIDTH_STEP)
    self.widthProfiles:remember(self.width)
    self:rebuildGuidance()
    self:notify(string.format("Largura do implemento: %.1f m", self.width))
end
function TGGPS:onResetImplementWidth()
    self:syncWorkingWidth()
    self:stopAutosteer()
    self.widthProfiles:resetCurrent()
    self:notify(string.format("Largura restaurada so deste implemento: %.2f m",self.width))
end

function TGGPS:onWidthUp(actionName, inputValue)
    self:syncWorkingWidth()
    self:stopAutosteer()
    self.width = math.min(TGGPS.MAX_WIDTH, self.width + TGGPS.WIDTH_STEP)
    self.widthProfiles:remember(self.width)
    self:rebuildGuidance()
    self:notify(string.format("Largura do implemento: %.1f m", self.width))
end

function TGGPS:onDetectWidth(actionName, inputValue)
    self:syncWorkingWidth()
    self:stopAutosteer()
    local vehicle = self:getControlledVehicle()
    if vehicle ~= nil then
        local detectedWidth = TGGPSWidthProfiles.detect(vehicle)
        if finite(detectedWidth) and detectedWidth > 0.5 then
            self.width = math.max(TGGPS.MIN_WIDTH, math.min(TGGPS.MAX_WIDTH, detectedWidth))
            self.widthProfiles:remember(self.width)
            self:rebuildGuidance()
            self:notify(string.format("Largura detectada: %.2f m", self.width))
            return
        end
    end
    self:notify("Nao foi possivel detectar. Ajuste a largura manualmente pelas setas")
end

function TGGPS:onSave(actionName, inputValue)
    self:onSaveNamedCourse()
end

function TGGPS:onClear(actionName, inputValue)
    self.trackOffset, self.activeCourseName = 0, nil
    self:stopAutosteer()
    self.isRecording = false
    self.recordingVehicle = nil
    self.recordedPoints = {}
    self.sourcePoints = {}
    self.basePath = {}
    self.guidanceLines = {}
    self.guidanceSections = {}
    self.fieldBoundary, self.fieldOrigin, self.fieldDirection = nil, nil, nil
    self.fieldCurveReference=nil
    self.minLane, self.maxLane = nil, nil
    self.currentSection = 1
    self.autoLaneSelection = true
    self.pointA = nil
    self.currentLane = 0
    self.mode = "none"
    self.headlandEnabled = false
    self:notify("Trajeto removido da tela. O arquivo salvo anteriormente foi mantido")
end

function TGGPS:stopAutosteer(message)
    local wasEnabled=self.autosteerEnabled==true
    local hadRaised = self.turnState ~= nil and self.turnState.implements ~= nil
        and #self.turnState.implements.entries > 0 and TGImplementControl ~= nil
        and TGImplementControl.areRaised(self.turnState.implements)
    self.turnState, self.headlandBrakeHoldVehicle = nil, nil
    self.autosteerEnabled = false
    self.activeVehicle = nil
    self.travelDirection = nil
    self.steeringCommand = 0
    if wasEnabled and self.audio then self.audio:play('disconnect') end
    if message ~= nil then
        if hadRaised then message = message .. " | implemento permanece levantado" end
        self:notify(message)
    end
end

-- Does not change speed, cruise control, brakes or the saved route.
function TGGPS:getAutosteerProblem(vehicle)
    if vehicle == nil or vehicle ~= self:getControlledVehicle() or not vehicle.tgGpsSupported then
        return "Entre em um trator compativel para usar o piloto"
    end
    local mission = g_currentMission
    if mission ~= nil and mission.missionDynamicInfo ~= nil and mission.missionDynamicInfo.isMultiplayer then
        return "Piloto disponivel apenas no single-player"
    end
    if self.isRecording then
        return "Finalize a gravacao antes de ligar o piloto"
    end
    local cruise = vehicle.spec_drivable and vehicle.spec_drivable.cruiseControl
    if self.headlandEnabled and cruise ~= nil and (cruise.state or 0) > 0
        and type(vehicle.setCruiseControlState) ~= "function" then
        return "Desligue o controle de cruzeiro para usar a cabeceira"
    end
    if vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
        return "Desligue o ajudante antes de ligar o piloto"
    end
    if vehicle.getIsMotorStarted ~= nil and not vehicle:getIsMotorStarted() then
        return "Ligue o motor para usar o piloto"
    end
    if vehicle.getIsActiveForInput ~= nil and not vehicle:getIsActiveForInput(true, true) then
        return "Piloto desligado: controle do veiculo indisponivel"
    end
    if vehicle.spec_reverseDriving ~= nil and vehicle.spec_reverseDriving.isReverseDriving then
        return "Piloto indisponivel com posto de conducao invertido"
    end
    local motor = vehicle.spec_motorized and vehicle.spec_motorized.motor
    local speed = vehicle.getLastSpeed ~= nil and math.abs(vehicle:getLastSpeed()) or 0
    if (motor ~= nil and motor.currentDirection ~= nil and motor.currentDirection < 0)
        or (speed > 0.5 and (vehicle.movingDirection or 1) < 0)
        or (vehicle.spec_drivable ~= nil and (vehicle.spec_drivable.reverserDirection or 1) < 0) then
        return "Piloto desligado: marcha a re"
    end
    if speed ~= speed or speed > TGGPS.MAX_AUTOSTEER_SPEED then
        return "Piloto desligado: reduza para ate 25 km/h"
    end
    return nil
end

function TGGPS:getVehiclePose(vehicle)
    if vehicle == nil then
        return nil, "Entre em um trator"
    end
    local node = vehicle.getAIRootNode ~= nil and vehicle:getAIRootNode() or nil
    if node == nil or node == 0 then
        node = vehicle.steeringAxleNode
    end
    if node == nil or node == 0 then
        node = vehicle.rootNode
    end
    if node == nil or node == 0 then
        return nil, "Nao foi possivel obter a posicao do trator"
    end
    local x, _, z = getWorldTranslation(node)
    local dx, _, dz = localDirectionToWorld(node, 0, 0, 1)
    local speed = vehicle.getLastSpeed ~= nil and math.abs(vehicle:getLastSpeed()) / 3.6 or 0
    return {
        x = x, z = z, dx = dx, dz = dz, speed = speed
    }
end

function TGGPS:calculateSteering(vehicle, direction, lane, section)
    local path = self:getLanePath(lane or self.currentLane, section or self.currentSection)
    if path == nil or #path < 2 then
        return nil, "Gere o talhao com Ctrl+Alt+F ou crie uma linha A/B"
    end
    local pose, problem = self:getVehiclePose(vehicle)
    if pose == nil then
        return nil, problem
    end
    local result, reason = TGGuidanceController.calculate(path, pose, {
        wheelbase = 3, maxSteeringAngle = math.rad(35),
        maxDistance = TGGPS.MAX_CAPTURE_DISTANCE,
        maxHeadingAngle = TGGPS.MAX_CAPTURE_ANGLE,
        direction = direction
    })
    if result == nil then
        local reasons = {
            too_far = "Aproxime o trator da passada selecionada (ate 8 m)",
            wrong_heading = "Alinhe o trator com a passada selecionada",
            invalid_path = "Trajeto invalido: marque ou grave novamente",
            invalid_pose = "Posicao ou direcao do trator invalida"
        }
        return nil, reasons[reason] or "Nao foi possivel calcular a direcao"
    end
    return result
end

function TGGPS:refreshSelection(vehicle)
    if vehicle == nil or self.autosteerEnabled or #self.basePath < 2 then
        return false, "Gere as linhas do talhao ou grave uma referencia primeiro"
    end
    local pose, problem = self:getVehiclePose(vehicle)
    if pose == nil then
        return false, problem
    end
    local candidates = {}
    if self.mode == "field" then
        for lane in pairs(self.guidanceSections) do
            candidates[lane] = true
        end
    else
        -- Estimate signed offset using the SAME left normal as offsetPath.
        local closest, offset
        for i = 1, #self.basePath - 1 do
            local a, b = self.basePath[i], self.basePath[i + 1]
            local dx, dz = b.x - a.x, b.z - a.z
            local length2 = dx * dx + dz * dz
            if length2 > 0.000001 then
                local t = math.max(0, math.min(1, ((pose.x - a.x) * dx + (pose.z - a.z) * dz) / length2))
                local ex, ez = pose.x - a.x - t * dx, pose.z - a.z - t * dz
                local distance2 = ex * ex + ez * ez
                if closest == nil or distance2 < closest then
                    closest = distance2
                    offset = (-ex * dz + ez * dx) / math.sqrt(length2)
                end
            end
        end
        if offset == nil then
            return false, "Trajeto de referencia invalido"
        end
        local estimated = math.floor(offset / self.width + 0.5)
        for lane = estimated - 2, estimated + 2 do
            if math.abs(lane) <= TGGPS.MAX_DYNAMIC_LANE then
                candidates[lane] = true
            end
        end
        candidates[self.currentLane] = true
    end
    local best, bestLane, bestSection
    for lane in pairs(candidates) do
        for section in ipairs(self:getLaneSections(lane)) do
            local result = self:calculateSteering(vehicle, nil, lane, section)
            if result ~= nil and not result.atEnd then
                local closer = best == nil or result.distance < best.distance - 0.05
                local tiedCurrent = best ~= nil and math.abs(result.distance - best.distance) <= 0.05
                    and lane == self.currentLane and section == self.currentSection
                if closer or tiedCurrent then
                    best, bestLane, bestSection = result, lane, section
                end
            end
        end
    end
    if best == nil then
        return false, "Alinhe o trator e aproxime de uma passada (ate 8 m)"
    end
    self.currentLane, self.currentSection = bestLane, bestSection
    return true
end

function TGGPS:onEnableAutosteer(actionName, inputValue)
    if not self.autosteerEnabled then
        self:onToggleAutosteer(actionName, inputValue)
    end
end

function TGGPS:onDisableAutosteer(actionName, inputValue)
    self:stopAutosteer("Piloto desligado - direcao manual")
end

function TGGPS:onToggleAutosteer(actionName, inputValue)
    if self.autosteerEnabled then
        self:stopAutosteer("Piloto desligado - direcao manual")
        return
    end
    self:syncWorkingWidth()
    local vehicle = self:getControlledVehicle()
    local problem = self:getAutosteerProblem(vehicle)
    if problem ~= nil then
        self:notify(problem)
        return
    end
    if self.autoLaneSelection then
        local selected, reason = self:refreshSelection(vehicle)
        if not selected then
            self:notify(reason)
            return
        end
    elseif self.mode == "field" then
        -- Manual mode fixes the lane, but must still acquire the nearest
        -- disconnected section of that lane in a concave field.
        local best, bestSection
        for section in ipairs(self:getLaneSections(self.currentLane)) do
            local result = self:calculateSteering(vehicle, nil, self.currentLane, section)
            if result ~= nil and not result.atEnd and (best == nil or result.distance < best.distance) then
                best, bestSection = result, section
            end
        end
        if bestSection ~= nil then
            self.currentSection = bestSection
        end
    end
    local result, reason = self:calculateSteering(vehicle)
    if result == nil or result.atEnd then
        self:notify(reason or "Fim do trajeto: selecione outra passada e alinhe o trator")
        return
    end
    self.activeVehicle = vehicle
    self.travelDirection = result.direction
    self.steeringCommand = 0
    self.autosteerEnabled = true
    if self.audio then self.audio:play('connect') end
    self.completedSections = {}
    self.headlandBrakeHoldVehicle = nil
    self:notify("Piloto ligado - controle a velocidade; vire o volante para desligar")
end

-- Called by the vehicle specialization immediately before GIANTS physics.
-- FS25 axisSide is positive LEFT; the controller is positive RIGHT.
function TGGPS:applySteering(vehicle, axisForward, axisSide, doHandbrake, dt)
    if not self.autosteerEnabled or vehicle ~= self.activeVehicle then
        return axisSide
    end
    local rawInputs = vehicle.spec_drivable and vehicle.spec_drivable.lastInputValues
    local manual = rawInputs and rawInputs.axisSteer or 0
    if math.abs(manual)>0 or math.abs(axisSide or 0)>0 then
        self:stopAutosteer("Piloto desligado: direcao manual")
        return axisSide
    end
    local problem = self:getAutosteerProblem(vehicle)
    if self.turnState ~= nil and (axisForward or 0) < -0.15 then
        problem = "Piloto desligado: freio manual"
    end
    if problem ~= nil then
        self:stopAutosteer(problem)
        return axisSide
    end
    if self.turnState ~= nil then
        local pose = self:getVehiclePose(vehicle)
        if pose == nil then self:stopAutosteer("Posicao indisponivel na manobra"); return axisSide end
        self.steeringCommand = TGHeadlandControl.step(self, vehicle, pose, dt)
        return self.steeringCommand
    end
    local result, reason = self:calculateSteering(vehicle, self.travelDirection)
    if result ~= nil and self.headlandEnabled and self.mode == "field" then
        local pose = self:getVehiclePose(vehicle)
        local trigger = math.max(2, math.min(6, (pose.speed or 0) * 0.8 + 1))
        if result.remaining <= trigger then
            TGHeadlandControl.begin(self, vehicle, result)
            self.steeringCommand = 0
            return 0
        end
    end
    if result == nil or result.atEnd then
        self:stopAutosteer(reason or "Fim do trajeto - assuma a direcao e controle a velocidade")
        return axisSide
    end
    local target = -result.steering
    local maxChange = 2 * math.max(0, math.min(dt or 0, 100)) / 1000
    self.steeringCommand = self.steeringCommand + math.max(-maxChange, math.min(maxChange, target - self.steeringCommand))
    return self.steeringCommand
end

function TGGPS:applyDriveControl(vehicle, axisForward, axisSide, doHandbrake, dt)
    if vehicle==self:getControlledVehicle() then self:syncWorkingWidth() end
    if self.monitor ~= nil and self.monitor.editing and self.monitor.vehicle == vehicle then
        return 0, 0, true
    end
    local steering = self:applySteering(vehicle, axisForward, axisSide, doHandbrake, dt)
    if self.headlandBrakeHoldVehicle == vehicle then
        local inputs = vehicle.spec_drivable and vehicle.spec_drivable.lastInputValues
        local manualSteer = inputs and inputs.axisSteer or 0
        if self:getControlledVehicle() ~= vehicle or math.abs(manualSteer) > TGGPS.MANUAL_STEERING_THRESHOLD
            or math.abs(axisSide or 0)>0
            or (axisForward or 0) < -0.15 then
            self.headlandBrakeHoldVehicle = nil
        else
            if math.abs(axisForward or 0) <= 0.05 then self.headlandBrakeHoldVehicle = nil end
            return 0, steering, true
        end
    end
    if self.autosteerEnabled and self.activeVehicle == vehicle and self.turnState ~= nil then
        local throttle, brake = TGHeadlandControl.drive(self, vehicle, axisForward, doHandbrake)
        return throttle, steering, brake
    end
    return axisForward, steering, doHandbrake
end

function TGGPS:update(dt)
    self.mapTime=(self.mapTime or 0)+math.max(0,dt or 0)
    self:syncWorkingWidth()
    self.contextTimer=(self.contextTimer or 0)+math.max(0,dt or 0)
    if self.contextTimer>=500 then self.monitorContext=nil;self.contextTimer=0 end
    if self.pendingHudOpen and not isGameMenuVisible() then self.pendingHudOpen=false;self:openHud() end
    if self.coverage ~= nil then self.coverage:update(dt) end
    if self.audio ~= nil then self.audio:update(dt) end
    if self.recognition ~= nil then self.recognition:update(dt) end
    if self.monitor ~= nil then self.monitor:update(dt) end
    if self.hud ~= nil and self.hud.isOpen and (self:getControlledVehicle() ~= self.hudVehicle or isGameMenuVisible()) then
        self:closeHud(isGameMenuVisible())
    end
    if self.autosteerEnabled and self:getControlledVehicle() ~= self.activeVehicle then
        self:stopAutosteer("Piloto desligado: veiculo alterado")
    end
    if not self.autosteerEnabled and not self.isRecording and self.autoLaneSelection then
        self.selectionTimer = (self.selectionTimer or 0) + (dt or 0)
        if self.selectionTimer >= 300 then
            self.selectionTimer = 0
            self:refreshSelection(self:getControlledVehicle())
            if self.mode ~= "field" then
                -- Keep a bounded cache of nearby recorded parallels.
                for lane in pairs(self.guidanceLines) do
                    if math.abs(lane - self.currentLane) > TGGPS.DRAW_LANE_RADIUS + 2 then
                        self.guidanceLines[lane] = nil
                    end
                end
            end
        end
    end
    if self.isRecording then
        if self:getControlledVehicle() ~= self.recordingVehicle then
            self.isRecording = false
            self.recordedPoints = {}
            self.recordingVehicle = nil
            self:notify("Gravacao cancelada: veiculo alterado")
            return
        end
        local position = self:getCurrentPosition()
        if position ~= nil then
            local last = self.recordedPoints[#self.recordedPoints]
            if last == nil or distance2D(last, position) >= TGGPS.RECORD_DISTANCE then
                self.recordedPoints[#self.recordedPoints + 1] = {x = position.x, z = position.z}
            end
        end
    end
end

function TGGPS:getSavePath()
    local mapName = "defaultMap"
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        mapName = tostring(g_currentMission.missionInfo.mapId or g_currentMission.missionInfo.mapTitle or mapName)
    end
    mapName = string.gsub(mapName, "[^%w_%-]", "_")
    return getUserProfileAppPath() .. TGGPS.SAVE_FOLDER .. "/" .. mapName .. ".xml"
end

function TGGPS:saveCourse()
    if self.sourcePoints == nil or #self.sourcePoints < 2 then
        self:notify("Nao existe trajeto para salvar")
        return false
    end

    local folderPath = getUserProfileAppPath() .. TGGPS.SAVE_FOLDER
    if createFolder ~= nil then
        createFolder(folderPath)
    end

    local filePath = self:getSavePath()
    local xmlFile = createXMLFile("TGGPSCourse", filePath, "tgGps")
    if xmlFile == nil or xmlFile == 0 then
        self:notify("ERRO: nao foi possivel criar o arquivo XML do trajeto")
        return false
    end

    setXMLString(xmlFile, "tgGps#mode", self.mode or "curve")
    setXMLFloat(xmlFile, "tgGps#width", self.width or TGGPS.DEFAULT_WIDTH)
    setXMLInt(xmlFile, "tgGps#currentLane", self.currentLane or 0)
    setXMLInt(xmlFile, "tgGps#pointCount", #self.sourcePoints)
    setXMLInt(xmlFile, "tgGps#autoLane", self.autoLaneSelection and 1 or 0)
    setXMLInt(xmlFile, "tgGps#currentSection", self.currentSection or 1)
    setXMLInt(xmlFile, "tgGps#headlandEnabled", self.headlandEnabled and 1 or 0)
    setXMLFloat(xmlFile, "tgGps#headlandDepth", self.headlandDepth or 18)
    setXMLFloat(xmlFile, "tgGps#turnSpeed", self.turnSpeed or 6)
    setXMLFloat(xmlFile, "tgGps#turnRadius", self.turnRadius or 6)
    setXMLFloat(xmlFile, "tgGps#trackOffset", self.trackOffset or 0)
    setXMLInt(xmlFile, "tgGps#turnSide", self.turnSide or 1)
    local boundary = self.mode == "field" and self.fieldBoundary or nil
    setXMLInt(xmlFile, "tgGps#boundaryCount", boundary ~= nil and #boundary or 0)
    if boundary ~= nil then
        setXMLFloat(xmlFile, "tgGps#originX", self.fieldOrigin.x)
        setXMLFloat(xmlFile, "tgGps#originZ", self.fieldOrigin.z)
        setXMLFloat(xmlFile, "tgGps#dirX", self.fieldDirection.dx)
        setXMLFloat(xmlFile, "tgGps#dirZ", self.fieldDirection.dz)
        for i, point in ipairs(boundary) do
            local key = string.format("tgGps.boundary(%d)", i - 1)
            setXMLFloat(xmlFile, key .. "#x", point.x)
            setXMLFloat(xmlFile, key .. "#z", point.z)
        end
    end

    for i, point in ipairs(self.sourcePoints) do
        local key = string.format("tgGps.point(%d)", i - 1)
        setXMLFloat(xmlFile, key .. "#x", point.x)
        setXMLFloat(xmlFile, key .. "#z", point.z)
    end
    local curve=self.mode=='field' and self.fieldCurveReference or {}
    setXMLInt(xmlFile,'tgGps#fieldCurveCount',curve and #curve or 0)
    for i,p in ipairs(curve or {}) do
        local k=string.format('tgGps.fieldCurve(%d)',i-1)
        setXMLFloat(xmlFile,k..'#x',p.x);setXMLFloat(xmlFile,k..'#z',p.z)
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
    self:notify("Trajeto salvo no modSettings/FS25_TG_GPS")
    return true
end

function TGGPS:loadCourse()
    local filePath = self:getSavePath()
    if fileExists ~= nil and not fileExists(filePath) then
        return
    end
    local xmlFile = loadXMLFile("TGGPSCourse", filePath)
    if xmlFile == nil or xmlFile == 0 then
        return
    end

    local pointCount = getXMLInt(xmlFile, "tgGps#pointCount") or 0
    local offset=getXMLFloat(xmlFile,"tgGps#trackOffset")
    self.trackOffset=finite(offset) and math.max(-1000,math.min(1000,offset)) or 0
    if pointCount >= 2 and pointCount <= 10000 then
        self.mode = getXMLString(xmlFile, "tgGps#mode") or "curve"
        if self.mode ~= "field" and self.mode ~= "straight" and self.mode ~= "curve" then
            self.mode = "curve"
        end
        self.headlandEnabled = self.mode == "field" and getXMLInt(xmlFile, "tgGps#headlandEnabled") == 1
        local depth = getXMLFloat(xmlFile, "tgGps#headlandDepth")
        local turnSpeed = getXMLFloat(xmlFile, "tgGps#turnSpeed")
        local turnRadius = getXMLFloat(xmlFile, "tgGps#turnRadius")
        self.headlandDepth = finite(depth) and math.max(6, math.min(50, depth)) or 18
        self.turnSpeed = finite(turnSpeed) and math.max(2, math.min(8, turnSpeed)) or 6
        self.turnRadius = finite(turnRadius) and math.max(5, math.min(15, turnRadius)) or 6
        self.turnSide = getXMLInt(xmlFile, "tgGps#turnSide") == -1 and -1 or 1
        local width = getXMLFloat(xmlFile, "tgGps#width")
        self.width = finite(width) and math.max(TGGPS.MIN_WIDTH, math.min(TGGPS.MAX_WIDTH, width)) or TGGPS.DEFAULT_WIDTH
        local lane = getXMLInt(xmlFile, "tgGps#currentLane")
        self.currentLane = finite(lane) and math.max(-TGGPS.MAX_DYNAMIC_LANE, math.min(TGGPS.MAX_DYNAMIC_LANE, lane)) or 0
        self.autoLaneSelection = getXMLInt(xmlFile, "tgGps#autoLane") ~= 0
        local section = getXMLInt(xmlFile, "tgGps#currentSection") or 1
        self.sourcePoints = {}
        self.fieldCurveReference=nil
        local curveCount=getXMLInt(xmlFile,'tgGps#fieldCurveCount') or 0
        if self.mode=='field' and curveCount>=2 and curveCount<=10000 then
            local curve={}
            for i=0,curveCount-1 do
                local k=string.format('tgGps.fieldCurve(%d)',i)
                local x,z=getXMLFloat(xmlFile,k..'#x'),getXMLFloat(xmlFile,k..'#z')
                if finite(x) and finite(z) then curve[#curve+1]={x=x,z=z} end
            end
            if #curve==curveCount then self.fieldCurveReference=curve;self.curveReference=curve end
        end

        for i = 0, pointCount - 1 do
            local key = string.format("tgGps.point(%d)", i)
            local x = getXMLFloat(xmlFile, key .. "#x")
            local z = getXMLFloat(xmlFile, key .. "#z")
            if finite(x) and finite(z) then
                self.sourcePoints[#self.sourcePoints + 1] = {x = x, z = z}
            end
        end

        if self.mode == "field" then
            local count = getXMLInt(xmlFile, "tgGps#boundaryCount") or 0
            local boundary = {}
            if count >= 3 and count <= 10000 then
                for i = 0, count - 1 do
                    local key = string.format("tgGps.boundary(%d)", i)
                    boundary[#boundary + 1] = {x = getXMLFloat(xmlFile, key .. "#x"), z = getXMLFloat(xmlFile, key .. "#z")}
                end
            end
            local origin = {x = getXMLFloat(xmlFile, "tgGps#originX"), z = getXMLFloat(xmlFile, "tgGps#originZ")}
            local direction = {dx = getXMLFloat(xmlFile, "tgGps#dirX"), dz = getXMLFloat(xmlFile, "tgGps#dirZ")}
            local valid = TGFieldBoundary.generateLanes(boundary, origin, direction, self.width)
            if valid == nil then
                self:onClear()
                self:notify("Talhao salvo invalido: gere novamente com Ctrl+Alt+F")
                delete(xmlFile)
                return
            end
            self.fieldBoundary, self.fieldOrigin, self.fieldDirection = boundary, origin, direction
        end
        if self:rebuildGuidance() then
            if finite(section) and self:getLanePath(self.currentLane, section) ~= nil then
                self.currentSection = section
            end
            self:notify(self.mode == "field" and "Linhas do talhao carregadas | Ctrl+Alt+P liga o piloto"
                or string.format("Trajeto carregado automaticamente (%d pontos)", #self.sourcePoints))
        end
    end

    delete(xmlFile)
end

local function getDrawHeight(x, z)
    local terrainNode = g_currentMission ~= nil and g_currentMission.terrainRootNode or g_terrainNode
    if terrainNode ~= nil and terrainNode ~= 0 and getTerrainHeightAtWorldPos ~= nil then
        return getTerrainHeightAtWorldPos(terrainNode, x, 0, z) + 0.35
    end
    return 0.35
end

local function drawGuidePath(points, r, g, b, budget)
    if #points < 2 then return end
    if #points == 2 then
        local a, p = points[1], points[2]
        local steps = math.max(1, math.min(budget, math.ceil(distance2D(a, p) / 8)))
        for step = 0, steps - 1 do
            local t, nt = step / steps, (step + 1) / steps
            local x, z = a.x + (p.x - a.x) * t, a.z + (p.z - a.z) * t
            local nx, nz = a.x + (p.x - a.x) * nt, a.z + (p.z - a.z) * nt
            drawDebugLine(x, getDrawHeight(x, z), z, r, g, b,
                nx, getDrawHeight(nx, nz), nz, r, g, b)
        end
    else
        local stride = math.max(1, math.ceil((#points - 1) / budget))
        local i = 1
        while i < #points do
            local nextIndex = math.min(i + stride, #points)
            local a, p = points[i], points[nextIndex]
            drawDebugLine(a.x, getDrawHeight(a.x, a.z), a.z, r, g, b,
                p.x, getDrawHeight(p.x, p.z), p.z, r, g, b)
            i = nextIndex
        end
    end
end

function TGGPS:draw()
    if g_currentMission == nil then return end
    if self.showLines and drawDebugLine ~= nil then
        if self.isRecording then
            drawGuidePath(self.recordedPoints, 1, 0.75, 0.1, 200)
        else
            local minimum = self.mode == "field" and self.minLane or self.currentLane - TGGPS.DRAW_LANE_RADIUS
            local maximum = self.mode == "field" and self.maxLane or self.currentLane + TGGPS.DRAW_LANE_RADIUS
            if minimum ~= nil and maximum ~= nil then
                local perPathBudget = self.mode == "field" and math.max(2, math.min(100, math.floor(4000 / (maximum - minimum + 1)))) or 100
                for lane = minimum, maximum do
                    for section, points in ipairs(self:getLaneSections(lane)) do
                        local r, g, b = 0.15, 0.8, 0.35
                        if lane == self.currentLane and section == self.currentSection then
                            r, g, b = 1, 0.72, 0.08
                        end
                        drawGuidePath(points, r, g, b, perPathBudget)
                    end
                end
            end
        end
    end

    if self.hud ~= nil and self.hud.isOpen and not isGameMenuVisible() then
        self.hud:draw()
    elseif renderText ~= nil and setTextColor ~= nil and not isGameMenuVisible() then
        if setTextAlignment ~= nil and RenderText ~= nil then
            setTextAlignment(RenderText.ALIGN_LEFT)
        end
        if setTextVerticalAlignment ~= nil and RenderText ~= nil then
            setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
        end
        if setTextBold ~= nil then setTextBold(false) end
        local modeText = self.mode == "field" and "TALHAO INTEIRO" or (self.mode == "curve" and "CURVA" or (self.mode == "straight" and "RETA A/B" or "SEM LINHAS"))
        local pilot = self.autosteerEnabled and "LIGADO" or "DESLIGADO"
        local selection = self.autoLaneSelection and "AUTOMATICA" or "MANUAL"
        local rows = {
            string.format("TG GPS %s | %s | PILOTO %s", TGGPS.VERSION, modeText, pilot),
            string.format("Largura %.1f m | Passada %d | Selecao %s%s", self.width, self.currentLane, selection, self.isRecording and " | GRAVANDO" or ""),
            self.status or "Ctrl+Alt+F gera o talhao | Ctrl+Alt+P liga o piloto"
        }
        -- Lower center keeps the panel clear of the top-left F1 help menu.
        for i, text in ipairs(rows) do
            local y = 0.145 - (i - 1) * 0.022
            setTextColor(0, 0, 0, 0.9)
            renderText(0.3007, y - 0.0007, 0.013, text)
            setTextColor(1, 1, 1, 1)
            renderText(0.30, y, 0.013, text)
        end
    end
end

function TGGPS:deleteMap()
    self.mapViewport,self.mapTime=nil,nil
    if self.monitor ~= nil then self.monitor:delete(); self.monitor = nil end
    self.coverage = nil
    self:closeHud()
    if self.hud ~= nil then
        self.hud:delete()
        self.hud = nil
    end
    self:stopAutosteer()
    if self.audio ~= nil then self.audio:delete();self.audio=nil end
    self.recognition=nil
    if g_inputBinding ~= nil and self.actionEventIds ~= nil then
        for _, eventId in ipairs(self.actionEventIds) do
            g_inputBinding:removeActionEvent(eventId)
        end
    end
    self.actionEventIds = {}
end

addModEventListener(TGGPS)

-- Install from an extraSourceFile: this hook must exist before type finalization.
function TGGPS.installSpecialization(typeManager)
    if typeManager.typeName ~= "vehicle" or not g_modIsLoaded[TGGPS.MOD_NAME] then
        return
    end
    for typeName, typeEntry in pairs(typeManager.types) do
        if TGGPSImplementProfile and TGGPSImplementProfile.prerequisitesPresent(typeEntry.specializations)
            and not SpecializationUtil.hasSpecialization(TGGPSImplementProfile,typeEntry.specializations) then
            typeManager:addSpecialization(typeName,TGGPS.MOD_NAME..'.tgGpsImplement')
        end
        if TGGPSVehicle.prerequisitesPresent(typeEntry.specializations)
            and not SpecializationUtil.hasSpecialization(TGGPSVehicle, typeEntry.specializations) then
            typeManager:addSpecialization(typeName, TGGPS.MOD_NAME .. ".tgGpsVehicle")
        end
    end
end

TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, TGGPS.installSpecialization)
