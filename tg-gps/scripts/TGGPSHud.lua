-- Clickable in-game GPS monitor. Cursor and vehicle-camera ownership stay in
-- TGGPS; this class owns layout, drawing, pointer capture and configuration.
TGGPSHud = {}
TGGPSHud.__index = TGGPSHud

local WIDTH, HEIGHT = 720, 690
local MIN_SCALE, MAX_SCALE = 0.75, 1.25
local DEFAULT_X, DEFAULT_Y = 0.55, 0.18
local MARGIN = 0.01
local COLORS = {
    shadow = {0, 0, 0, 0.48}, frame = {0.035, 0.055, 0.065, 0.98},
    background = {0.055, 0.080, 0.092, 0.98}, header = {0.080, 0.118, 0.135, 1},
    card = {0.085, 0.125, 0.143, 1}, border = {0.17, 0.23, 0.26, 1},
    white = {0.94, 0.97, 0.98, 1}, muted = {0.59, 0.69, 0.73, 1},
    green = {0.20, 0.88, 0.62, 1}, red = {1, 0.36, 0.40, 1},
    blue = {0.27, 0.75, 0.96, 1}, amber = {1, 0.77, 0.30, 1},
    button = {0.11, 0.17, 0.20, 1}, hover = {0.16, 0.25, 0.29, 1},
    pressed = {0.20, 0.33, 0.37, 1}, active = {0.10, 0.27, 0.23, 1},
    danger = {0.29, 0.11, 0.13, 1}, disabled = {0.08, 0.105, 0.115, 1}
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
    local owner, buttons = self.owner, {}
    local hasRoute = type(owner.sourcePoints) == "table" and #owner.sourcePoints >= 2
    local function button(id, label, x, y, w, h, action, enabled, active, tone)
        local rect = self:_rect(x, y, w, h)
        rect.id, rect.label, rect.action = id, label, action
        rect.enabled, rect.active, rect.tone = enabled ~= false, active == true, tone
        buttons[#buttons + 1] = rect
    end
    button("close", "X", 666, 13, 34, 30, "close")
    button("tab_map", "MAPA", 20, 136, 166, 36, "map", true, self.page == "map")
    button("tab_guide", "GUIA", 194, 136, 166, 36, "guide", true, self.page == "guide")
    button("tab_headland", "CABECEIRA", 368, 136, 166, 36, "headland", true, self.page == "headland")
    button("tab_settings", "AJUSTES", 542, 136, 158, 36, "settings", true, self.page == "settings")
    if self.page == "map" then
        local zoom = TGGPSMap ~= nil and TGGPSMap.getZoom(owner) or (owner.mapZoom or 1)
        button("map_fit", "TUDO", 536, 192, 62, 26, "map_fit")
        button("map_zoom_out", "-", 606, 192, 40, 26, "map_zoom_out", zoom > 1.001)
        button("map_zoom_in", "+", 654, 192, 36, 26, "map_zoom_in", zoom < 3.999)
        button("enable", "LIGAR PILOTO", 20, 500, 218, 36, "onEnableAutosteer", not owner.autosteerEnabled, owner.autosteerEnabled, "green")
        button("disable", "DESLIGAR", 250, 500, 218, 36, "onDisableAutosteer", owner.autosteerEnabled, false, "red")
        button("generate_field", "GERAR TALHAO", 480, 500, 220, 36, "onGenerateField", true, false, "blue")
    elseif self.page == "guide" then
        button("enable", "LIGAR PILOTO", 20, 264, 218, 44, "onEnableAutosteer", not owner.autosteerEnabled, owner.autosteerEnabled, "green")
        button("disable", "DESLIGAR", 250, 264, 218, 44, "onDisableAutosteer", owner.autosteerEnabled, false, "red")
        button("generate_field", "GERAR TALHAO", 480, 264, 220, 44, "onGenerateField", true, false, "blue")
        button("mark_ab", owner.pointA ~= nil and "MARCAR PONTO B" or "MARCAR A/B", 20, 320, 218, 44, "onMarkAB")
        button("record_curve", owner.isRecording and "FINALIZAR CURVA" or "GRAVAR CURVA", 250, 320, 218, 44, "onRecordCurve", true, owner.isRecording)
        button("toggle_lines", owner.showLines and "LINHAS: VISIVEIS" or "LINHAS: OCULTAS", 480, 320, 220, 44, "onToggleLines", true, owner.showLines)
        button("lane_prev", "< PASSADA", 20, 376, 218, 44, "onLanePrevious", hasRoute)
        button("auto_lane", owner.autoLaneSelection and "SELECAO: AUTO" or "SELECAO: MANUAL", 250, 376, 218, 44, "onToggleAutoLane", true, owner.autoLaneSelection)
        button("lane_next", "PASSADA >", 480, 376, 220, 44, "onLaneNext", hasRoute)
        button("width_down", "- LARGURA", 20, 432, 218, 44, "onWidthDown", (owner.width or 6) > (owner.MIN_WIDTH or 1))
        button("detect_width", "DETECTAR LARGURA", 250, 432, 218, 44, "onDetectWidth")
        button("width_up", "LARGURA +", 480, 432, 220, 44, "onWidthUp", (owner.width or 6) < (owner.MAX_WIDTH or 50))
        button("save", "SALVAR TRAJETO", 20, 488, 334, 40, "onSave", hasRoute)
        button("clear", "LIMPAR DA TELA", 366, 488, 334, 40, "onClear", hasRoute or owner.pointA ~= nil or owner.isRecording, false, "red")
    elseif self.page == "headland" then
        button("headland_toggle", owner.headlandEnabled and "CABECEIRA AUTOMATICA: LIGADA" or "CABECEIRA AUTOMATICA: DESLIGADA", 20, 194, 680, 40, "onToggleHeadland", true, owner.headlandEnabled, "blue")
        button("headland_depth_down", "-", 516, 254, 74, 42, "onHeadlandDepthDown")
        button("headland_depth_up", "+", 602, 254, 74, 42, "onHeadlandDepthUp")
        button("headland_speed_down", "-", 516, 324, 74, 42, "onTurnSpeedDown")
        button("headland_speed_up", "+", 602, 324, 74, 42, "onTurnSpeedUp")
        button("headland_radius_down", "-", 516, 394, 74, 42, "onTurnRadiusDown")
        button("headland_radius_up", "+", 602, 394, 74, 42, "onTurnRadiusUp")
        button("headland_direction", (owner.turnSide or 1) > 0 and "PROXIMA PASSADA +" or "PROXIMA PASSADA -", 448, 464, 228, 42, "onToggleTurnDirection")
    else
        button("scale_down", "-", 516, 238, 74, 42, "scale_down", self.scale > MIN_SCALE + 0.001)
        button("scale_up", "+", 602, 238, 74, 42, "scale_up", self.scale < MAX_SCALE - 0.001)
        button("reset_position", "RESTAURAR POSICAO", 448, 332, 228, 42, "reset_position")
        button("auto_lane", owner.autoLaneSelection and "AUTOMATICA" or "MANUAL", 448, 426, 228, 42, "onToggleAutoLane", true, owner.autoLaneSelection)
        button("reset_coverage", "ZERAR PINTURA", 448, 500, 228, 32, "onResetCoverage", owner.coverage ~= nil, false, "red")
    end
    return buttons
end

function TGGPSHud:_run(button)
    local action = button.action
    if action == "close" then
        if type(self.owner.closeHud) == "function" then self.owner:closeHud() else self:setOpen(false) end
    elseif action == "map" or action == "guide" or action == "headland" or action == "settings" then
        self.page = action
    elseif action == "scale_down" or action == "scale_up" then
        self.scale = clamp(self.scale + (action == "scale_up" and 0.1 or -0.1), MIN_SCALE, MAX_SCALE)
        self:_layout()
        self:_saveSettings()
    elseif action == "reset_position" then
        self:resetPosition()
    elseif action == "map_fit" then
        self.owner.mapZoom = 1
    elseif action == "map_zoom_in" or action == "map_zoom_out" then
        local zoom = TGGPSMap ~= nil and TGGPSMap.getZoom(self.owner) or (self.owner.mapZoom or 1)
        self.owner.mapZoom = clamp(zoom + (action == "map_zoom_in" and 0.5 or -0.5), 1, 4)
    elseif type(self.owner[action]) == "function" then
        self.owner[action](self.owner, nil, 1)
    end
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
    local owner, commands = self.owner, {}
    local function rect(x, y, w, h, color)
        local entry = self:_rect(x, y, w, h)
        entry.type, entry.color = "rect", color
        commands[#commands + 1] = entry
    end
    local function text(value, x, y, size, color, bold, align)
        commands[#commands + 1] = {type = "text", text = tostring(value),
            x = self.x + x * self.unitX, y = self.y + (HEIGHT - y) * self.unitY,
            size = size * self.unitY, color = color or COLORS.white,
            bold = bold == true, align = align or "left"}
    end
    rect(6, 6, WIDTH, HEIGHT, COLORS.shadow)
    rect(0, 0, WIDTH, HEIGHT, COLORS.frame)
    rect(3, 3, WIDTH - 6, HEIGHT - 6, COLORS.background)
    rect(3, 3, WIDTH - 6, 51, COLORS.header)
    rect(20, 19, 5, 23, COLORS.green)
    text("TG GPS PRO", 36, 38, 25, COLORS.white, true)
    text("MONITOR DE ORIENTACAO", 236, 36, 12, COLORS.muted)

    rect(20, 66, 680, 58, COLORS.card)
    rect(20, 66, 5, 58, owner.autosteerEnabled and COLORS.green or COLORS.muted)
    text(owner.autosteerEnabled and "PILOTO LIGADO" or "PILOTO DESLIGADO", 39, 91, 18,
        owner.autosteerEnabled and COLORS.green or COLORS.white, true)
    local mode = owner.mode == "field" and "TALHAO INTEIRO" or (owner.mode == "curve" and "CURVA GRAVADA" or (owner.mode == "straight" and "RETA A/B" or "SEM TRAJETO"))
    local phases = {tracking = "SEGUINDO LINHA", approach = "APROXIMANDO", planning = "CALCULANDO CURVA", braking = "REDUZINDO",
        lifting = "LEVANTANDO IMPLEMENTO", turning = "FAZENDO CURVA", aligning = "ALINHANDO", lowering = "BAIXANDO IMPLEMENTO",
        stopped = "PARADO", stopping = "PARANDO", error = "CONTROLE MANUAL"}
    local phase = owner.turnState and phases[owner.turnState.phase] or nil
    local subtitle = mode .. (owner.isRecording and "  /  GRAVANDO" or "")
    if phase ~= nil then subtitle = subtitle .. "  /  " .. phase end
    text(subtitle, 39, 113, 12, owner.isRecording and COLORS.amber or COLORS.muted)
    text("Ctrl+Alt+M abre / fecha", 681, 92, 12, COLORS.muted, false, "right")

    if self.page == "map" then
        if TGGPSMap ~= nil and type(TGGPSMap.getDrawCommands) == "function" then
            for _, command in ipairs(TGGPSMap.getDrawCommands(owner, self:_rect(20, 184, 680, 280))) do
                commands[#commands + 1] = command
            end
        else
            rect(20, 184, 680, 280, COLORS.card)
            text("MAPA INDISPONIVEL", 360, 330, 16, COLORS.muted, true, "center")
        end
        local coverage = owner.coverage
        text(string.format("TRABALHADO %.2f ha | SOBREPOSICAO %.2f ha",
            coverage and coverage:getWorkedHa() or 0, coverage and coverage:getOverlapHa() or 0),
            24, 486, 13, COLORS.white, true)
        text(coverage and coverage.working and (coverage.estimated and "ESTIMADO" or "TRABALHANDO") or "SEM TRABALHO",
            696, 486, 12, coverage and coverage.working and COLORS.green or COLORS.muted, false, "right")
    elseif self.page == "guide" then
        rect(20, 184, 334, 68, COLORS.card)
        rect(366, 184, 334, 68, COLORS.card)
        text("LARGURA DO IMPLEMENTO", 36, 207, 11, COLORS.muted)
        text(string.format("%.1f m", owner.width or 6), 36, 238, 27, COLORS.white, true)
        text("PASSADA ATUAL", 382, 207, 11, COLORS.muted)
        text(tostring(owner.currentLane or 0), 382, 238, 27, COLORS.white, true)
        text(owner.autoLaneSelection and "AUTOMATICA" or "MANUAL", 682, 236, 12,
            owner.autoLaneSelection and COLORS.green or COLORS.amber, false, "right")
    elseif self.page == "headland" then
        local rows = {
            {y = 244, label = "MARGEM DE CABECEIRA", value = string.format("%.1f m", owner.headlandDepth or 18)},
            {y = 314, label = "VELOCIDADE NA CURVA", value = string.format("%.1f km/h", owner.turnSpeed or 6)},
            {y = 384, label = "RAIO MINIMO DA CURVA", value = string.format("%.1f m", owner.turnRadius or 6)}
        }
        for _, row in ipairs(rows) do
            rect(20, row.y, 680, 60, COLORS.card)
            text(row.label, 36, row.y + 21, 11, COLORS.muted)
            text(row.value, 36, row.y + 49, 23, COLORS.white, true)
        end
        rect(20, 454, 680, 60, COLORS.card)
        text("LADO DA PROXIMA PASSADA", 36, 476, 11, COLORS.muted)
        text((owner.turnSide or 1) > 0 and "Sentido positivo das linhas" or "Sentido negativo das linhas", 36, 500, 12, COLORS.white)
        text("A curva e calculada antes de levantar o implemento.", 24, 535, 12, COLORS.muted)
    else
        text("PREFERENCIAS DO MONITOR", 24, 205, 16, COLORS.white, true)
        rect(20, 220, 680, 82, COLORS.card)
        text("TAMANHO DO PAINEL", 36, 246, 12, COLORS.muted)
        text(string.format("%d%%", math.floor(self.scale * 100 + 0.5)), 36, 280, 27, COLORS.white, true)
        rect(20, 314, 680, 82, COLORS.card)
        text("POSICAO NA TELA", 36, 340, 12, COLORS.muted)
        text("Arraste a barra superior com o mouse.", 36, 368, 13, COLORS.white)
        rect(20, 408, 680, 82, COLORS.card)
        text("ESCOLHA DA PASSADA", 36, 434, 12, COLORS.muted)
        text("Automatica usa a linha mais proxima.", 36, 461, 13, COLORS.white)
        text("Shift direito+M: ajustar monitor na cabine.", 24, 518, 12, COLORS.muted)
    end

    for _, button in ipairs(self:getButtons()) do
        local color = button.active and COLORS.active or COLORS.button
        if button.tone == "red" then color = COLORS.danger end
        if button.enabled and inside(button, self.pointerX, self.pointerY) then
            color = self.pressedId == button.id and COLORS.pressed or COLORS.hover
        end
        if not button.enabled then color = COLORS.disabled end
        commands[#commands + 1] = {type = "rect", x = button.x, y = button.y, w = button.w, h = button.h, color = COLORS.border}
        commands[#commands + 1] = {type = "rect", x = button.x + self.unitX, y = button.y + self.unitY,
            w = button.w - 2 * self.unitX, h = button.h - 2 * self.unitY, color = color}
        if button.active then
            commands[#commands + 1] = {type = "rect", x = button.x + self.unitX, y = button.y + self.unitY,
                w = 3 * self.unitX, h = button.h - 2 * self.unitY, color = COLORS.green}
        end
        local foreground = button.enabled and (COLORS[button.tone] or COLORS.white) or COLORS.muted
        commands[#commands + 1] = {type = "text", text = button.label,
            x = button.x + button.w / 2, y = button.y + button.h / 2 - 5 * self.unitY,
            size = 14 * self.unitY, color = foreground, bold = true, align = "center"}
    end

    rect(20, 546, 680, 96, COLORS.card)
    text("MENSAGEM DO GPS", 36, 568, 11, COLORS.muted)
    local lines = wrapText(owner.status or "Gere o talhao e alinhe o trator para ligar o piloto.", 76, 3)
    for index, line in ipairs(lines) do
        text(line, 36, 589 + (index - 1) * 18, 13, COLORS.white)
    end
    text("Use DESLIGAR ou mova o volante para assumir o controle.", 20, 668, 11, COLORS.muted)
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
    self:setOpen(false)
    if self.overlay ~= nil and type(self.overlay.delete) == "function" then self.overlay:delete() end
    self.overlay = nil
    if self.lineOverlayId ~= nil and self.lineOverlayId ~= 0 and delete ~= nil then delete(self.lineOverlayId) end
    self.lineOverlayId = nil
end
