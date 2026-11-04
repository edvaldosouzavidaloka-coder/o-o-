-- Shared field view for the panel and physical monitor, including implement coverage.
TGGPSMap = {}

local MAX_COMMANDS = 4000
local COLORS = {
    background = {0.055, 0.070, 0.060, 1},
    field = {0.12, 0.19, 0.12, 1}, headland = {0.48, 0.20, 0.12, 1},
    boundary = {0.94, 0.40, 0.32, 1}, lane = {0.58, 0.79, 0.87, 0.8},
    selected = {1, 0.84, 0.25, 1}, turn = {1, 1, 1, 1},
    tractor = {0.20, 1, 0.61, 1}, text = {0.82, 0.92, 0.95, 1}
}
COLORS.coverage = {0.20, 0.82, 0.30, 0.46}
COLORS.overlap = {1, 0.67, 0.10, 0.58}
COLORS.implement = {0.25, 0.92, 0.45, 1}
COLORS.combine = {0.29, 0.88, 0.36, 1}
COLORS.vehicleWheel = {0.025, 0.03, 0.03, 1}
COLORS.vehicleCab = {0.40, 0.85, 0.96, 1}
local cache = setmetatable({}, {__mode = "k"})

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validPoint(point)
    return type(point) == "table" and finite(point.x) and finite(point.z)
end

function TGGPSMap.getZoom(owner)
    if finite(owner.mapZoom) then return math.max(1, math.min(12, owner.mapZoom)) end
    return owner.turnState ~= nil and 2.5 or 1
end

local function distanceToEdges(boundary, point)
    local minimum = math.huge
    for i, a in ipairs(boundary) do
        local b = boundary[i % #boundary + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local squared = dx * dx + dz * dz
        local t = squared > 0 and math.max(0, math.min(1, ((point.x - a.x) * dx + (point.z - a.z) * dz) / squared)) or 0
        local ex, ez = point.x - a.x - t * dx, point.z - a.z - t * dz
        minimum = math.min(minimum, math.sqrt(ex * ex + ez * ez))
    end
    return minimum
end

local function fieldRaster(owner, boundary, extent)
    local margin = owner.headlandEnabled and math.max(0, owner.headlandDepth or 0) or 0
    local old = cache[owner]
    if old ~= nil and old.boundary == boundary and old.margin == margin then return old.cells end
    local cells = {}
    local rows, columns = 34, 52
    local rowHeight = (extent.maxZ - extent.minZ) / rows
    local columnWidth = (extent.maxX - extent.minX) / columns
    for row = 0, rows - 1 do
        local z = extent.minZ + (row + 0.5) * rowHeight
        local crossings = {}
        for i, a in ipairs(boundary) do
            local b = boundary[i % #boundary + 1]
            if (a.z <= z and b.z > z) or (b.z <= z and a.z > z) then
                crossings[#crossings + 1] = a.x + (z - a.z) * (b.x - a.x) / (b.z - a.z)
            end
        end
        table.sort(crossings)
        for index = 1, #crossings - 1, 2 do
            local left, right = crossings[index], crossings[index + 1]
            local count = math.max(1, math.ceil((right - left) / columnWidth))
            local step = (right - left) / count
            local active, start
            for column = 0, count do
                local role
                if column < count then
                    local point = {x = left + (column + 0.5) * step, z = z}
                    role = margin > 0 and distanceToEdges(boundary, point) < margin and "headland" or "field"
                end
                if role ~= active then
                    if active ~= nil then
                        cells[#cells + 1] = {x = start, z = z - rowHeight / 2,
                            w = left + column * step - start, h = rowHeight, role = active}
                    end
                    active, start = role, left + column * step
                end
            end
        end
    end
    cache[owner] = {boundary = boundary, margin = margin, cells = cells}
    return cells
end

-- Clip normalized screen-space line segments to the map, never the outer HUD.
local function clip(x1, y1, x2, y2, box)
    local dx, dy, low, high = x2 - x1, y2 - y1, 0, 1
    local p = {-dx, dx, -dy, dy}
    local q = {x1 - box.x, box.x + box.w - x1, y1 - box.y, box.y + box.h - y1}
    for i = 1, 4 do
        if math.abs(p[i]) < 0.0000001 then
            if q[i] < -0.000000001 then return nil end
        else
            local r = q[i] / p[i]
            if p[i] < 0 then low = math.max(low, r) else high = math.min(high, r) end
            if low > high + 0.000000001 then return nil end
        end
    end
    return x1 + low * dx, y1 + low * dy, x1 + high * dx, y1 + high * dy
end

local function pathsOf(owner)
    local paths = {}
    if type(owner.guidanceSections) == "table" and next(owner.guidanceSections) ~= nil then
        for lane, sections in pairs(owner.guidanceSections) do
            for section, points in ipairs(sections) do
                paths[#paths + 1] = {lane = lane, section = section, points = points}
            end
        end
    elseif type(owner.guidanceLines) == "table" then
        for lane, points in pairs(owner.guidanceLines) do
            paths[#paths + 1] = {lane = lane, section = 1, points = points}
        end
    end
    table.sort(paths, function(a, b)
        local da,db=math.abs(a.lane-(owner.currentLane or 0)),math.abs(b.lane-(owner.currentLane or 0))
        if da~=db then return da<db end
        if a.lane == b.lane then return a.section < b.section end
        return a.lane < b.lane
    end)
    return paths
end

function TGGPSMap.getDrawCommands(owner, bounds, options)
    options = options or {}
    if type(owner) ~= "table" or type(bounds) ~= "table" or not finite(bounds.x) or not finite(bounds.y)
        or not finite(bounds.w) or not finite(bounds.h) or bounds.w <= 0 or bounds.h <= 0 then return {} end
    local sw = options.screenWidth or (finite(g_screenWidth) and math.max(1, g_screenWidth) or 1920)
    local sh = options.screenHeight or (finite(g_screenHeight) and math.max(1, g_screenHeight) or 1080)
    local commands = {{type = "rect", x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h,
        color = COLORS.background, role = "map_background"}}
    local box = {x = bounds.x + bounds.w * 0.025, y = bounds.y + bounds.h * 0.11,
        w = bounds.w * 0.95, h = bounds.h * 0.76}
    local paths = pathsOf(owner)
    local boundary = type(owner.fieldBoundary) == "table" and #owner.fieldBoundary >= 3 and owner.fieldBoundary or nil
    local extent = {minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge}
    local function include(point)
        if validPoint(point) then
            extent.minX, extent.maxX = math.min(extent.minX, point.x), math.max(extent.maxX, point.x)
            extent.minZ, extent.maxZ = math.min(extent.minZ, point.z), math.max(extent.maxZ, point.z)
        end
    end
    if boundary ~= nil then
        for _, point in ipairs(boundary) do
            if not validPoint(point) then boundary = nil break end
            include(point)
        end
    end
    if boundary == nil then
        for _, item in ipairs(paths) do for _, point in ipairs(item.points) do include(point) end end
        if #paths == 0 then for _, point in ipairs(owner.basePath or {}) do include(point) end end
    end
    local pose
    if type(owner.getControlledVehicle)=="function" and type(owner.getVehiclePose)=="function" then
        local vehicle=owner:getControlledVehicle()
        if vehicle then local ok,p=pcall(owner.getVehiclePose,owner,vehicle);if ok and validPoint(p) then pose=p end end
    end
    if extent.minX==math.huge and pose then
        include({x=pose.x-100,z=pose.z-100});include({x=pose.x+100,z=pose.z+100})
    end
    local function label(value, role)
        commands[#commands + 1] = {type = "rect", x = bounds.x, y = bounds.y,
            w = bounds.w, h = bounds.h * 0.085, color = COLORS.background, role = "legend_background"}
        commands[#commands + 1] = {type = "text", x = bounds.x + bounds.w / 2,
            y = bounds.y + bounds.h * 0.045, text = value, size = math.min(bounds.h * 0.034, 13 / 1080),
            color = COLORS.text, align = "center", bold = false, role = role or "map_label"}
    end
    if extent.minX == math.huge then
        label("GERE O TALHAO OU GRAVE UMA LINHA PARA VER O MAPA", "empty_map")
        return commands
    end
    -- The PDA is a local moving window, never a fit of the entire field/map.
    local localSpan=math.max(80,math.min(180,(owner.width or 6)*14))
    local spanX, spanZ = localSpan,localSpan
    local zoom = TGGPSMap.getZoom(owner)
    local pixelsPerMetre = math.min(box.w * sw / spanX, box.h * sh / spanZ) * zoom
    local centerX, centerZ = (extent.minX + extent.maxX) / 2, (extent.minZ + extent.maxZ) / 2
    if pose ~= nil then centerX, centerZ = pose.x, pose.z end
    if options.centerX~=nil then centerX,centerZ=options.centerX,options.centerZ end
    local nativeMap,filename=TGGPSPDA.get()
    if nativeMap then
        local halfX,halfZ=box.w*sw/(2*pixelsPerMetre),box.h*sh/(2*pixelsPerMetre)
        commands[#commands+1]=TGGPSPDA.command(nativeMap,filename,box,centerX-halfX,centerZ-halfZ,centerX+halfX,centerZ+halfZ)
    end
    local function project(point)
        return box.x + box.w / 2 + (point.x - centerX) * pixelsPerMetre / sw,
            box.y + box.h / 2 + (point.z - centerZ) * pixelsPerMetre / sh
    end
    local function line(a, b, color, role, width, lane, section)
        if #commands >= MAX_COMMANDS - 2 or not validPoint(a) or not validPoint(b) then return end
        local x1, y1 = project(a)
        local x2, y2 = project(b)
        x1, y1, x2, y2 = clip(x1, y1, x2, y2, box)
        if x1 ~= nil then
            commands[#commands + 1] = {type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                color = color, role = role, width = (width or 1.2) / sh, lane = lane, section = section}
        end
    end
    if boundary ~= nil and options.drawField ~= false and nativeMap==nil then
        for _, cell in ipairs(fieldRaster(owner, boundary, extent)) do
            if #commands >= 1000 then break end
            local x, y = project({x = cell.x, z = cell.z})
            local right = math.min(box.x + box.w, x + cell.w * pixelsPerMetre / sw)
            local top = math.min(box.y + box.h, y + cell.h * pixelsPerMetre / sh)
            x, y = math.max(box.x, x), math.max(box.y, y)
            if right > x and top > y then
                commands[#commands + 1] = {type = "rect", x = x, y = y, w = right - x, h = top - y,
                    color = COLORS[cell.role], role = cell.role}
            end
        end
    end
    if owner.coverage ~= nil then
        local halfX, halfZ = box.w * sw / (2 * pixelsPerMetre), box.h * sh / (2 * pixelsPerMetre)
        local cells = owner.coverage:getMapCells(centerX - halfX, centerZ - halfZ,
            centerX + halfX, centerZ + halfZ, options.coverageBudget)
        for _, cell in ipairs(cells) do
            local x, y = project(cell)
            local right = math.min(box.x + box.w, x + cell.w * pixelsPerMetre / sw)
            local top = math.min(box.y + box.h, y + cell.h * pixelsPerMetre / sh)
            x, y = math.max(box.x, x), math.max(box.y, y)
            if right > x and top > y then
                commands[#commands + 1] = {type = "rect", x = x, y = y, w = right - x, h = top - y,
                    color = cell.overlap and COLORS.overlap or COLORS.coverage,
                    role = cell.overlap and "coverage_overlap" or "coverage"}
            end
        end
    end
    local selected
    -- Reserve room for the selected route, turn, implement and vehicle marker.
    local laneBudget = math.max(0, math.min(options.laneBudget or 1400, MAX_COMMANDS - #commands - 550))
    local pathLimit=math.min(12,#paths)
    local backgroundSegments = 0
    for pathIndex, item in ipairs(paths) do
        if item.lane == owner.currentLane and item.section == (owner.currentSection or 1) then
            selected = item
        elseif pathIndex<=pathLimit and #commands < 3000 and backgroundSegments < laneBudget then
            local points = item.points
            local stride = math.max(1, math.floor(2/math.max(0.01,pixelsPerMetre)))
            for i = 1, #points - 1, stride do
                if backgroundSegments >= laneBudget then break end
                local before=#commands
                line(points[i], points[math.min(#points, i + stride)], COLORS.lane, "lane", 1.1, item.lane, item.section)
                if #commands>before then backgroundSegments = backgroundSegments + 1 end
            end
        end
    end
    if boundary ~= nil then
        local stride = math.max(1, math.ceil(#boundary / (options.boundaryBudget or 200)))
        for i = 1, #boundary, stride do
            line(boundary[i], boundary[(math.min(#boundary, i + stride - 1) % #boundary) + 1], COLORS.boundary, "boundary", 1.8)
        end
    end
    if selected ~= nil then
        local points = selected.points
        local stride = math.max(1, math.ceil((#points - 1) / (options.selectedBudget or 128)))
        for i = 1, #points - 1, stride do
            line(points[i], points[math.min(#points, i + stride)], COLORS.selected, "selected_lane", 2.4, selected.lane, selected.section)
        end
    end
    local turn = owner.turnState and owner.turnState.path or owner.plannedTurn
    if type(turn) == "table" and type(turn.points) == "table" then turn = turn.points end
    if type(turn) == "table" then
        local stride = math.max(1, math.ceil((#turn - 1) / (options.turnBudget or 160)))
        for i = 1, #turn - 1, stride do line(turn[i], turn[math.min(#turn, i + stride)], COLORS.turn, "planned_turn", 2.5) end
    end
    local outside = false
    local context = owner.getMonitorContext and owner:getMonitorContext() or {kind="tractor"}
    local footprint = owner.coverage ~= nil and owner.coverage.footprint or nil
    if footprint ~= nil then
        local points = {}
        for _, corner in ipairs({{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}) do
            points[#points + 1] = {
                x = footprint.x + corner[1] * footprint.rx * footprint.width / 2
                    + corner[2] * footprint.fx * footprint.length / 2,
                z = footprint.z + corner[1] * footprint.rz * footprint.width / 2
                    + corner[2] * footprint.fz * footprint.length / 2
            }
        end
        for i = 1, 4 do line(points[i], points[i % 4 + 1], COLORS.implement, "implement", 2) end
        if pose ~= nil then line(pose, footprint, COLORS.implement, "implement", 1) end
    end
    if pose ~= nil then
        local x, y = project(pose)
        outside = x < box.x or x > box.x + box.w or y < box.y or y > box.y + box.h
        local dx, dz = pose.dx or 0, pose.dz or 1
        local length = math.sqrt(dx * dx + dz * dz)
        if not outside and finite(length) and length > 0.000001 then
            dx, dz = dx / length, dz / length
            local unit = 15 / pixelsPerMetre
            local function part(ax, az, bx, bz, role, width, name)
                local a={x=pose.x+(dz*ax+dx*az)*unit,z=pose.z+(-dx*ax+dz*az)*unit}
                local b={x=pose.x+(dz*bx+dx*bz)*unit,z=pose.z+(-dx*bx+dz*bz)*unit}
                local before=#commands
                line(a,b,COLORS[role],role,width)
                if #commands>before then
                    commands[#commands].machineType=context.kind
                    commands[#commands].part=name
                end
            end
            if context.kind=="combine" then
                part(0,-0.65,0,0.65,"combine",15,"body")
                part(-0.65,-0.45,-0.65,-0.12,"vehicleWheel",5,"rearWheel")
                part(0.65,-0.45,0.65,-0.12,"vehicleWheel",5,"rearWheel")
                part(-0.70,0.22,-0.70,0.67,"vehicleWheel",6,"frontWheel")
                part(0.70,0.22,0.70,0.67,"vehicleWheel",6,"frontWheel")
                part(0,0.25,0,0.65,"vehicleCab",8,"cab")
                if context.implement and context.implement.spec_cutter then
                    part(-1.1,0.95,1.1,0.95,"implement",5,"header")
                    part(0,0.67,0,0.95,"implement",3,"feeder")
                end
            else
                part(0,-0.6,0,0.65,"tractor",9,"body")
                part(-0.50,-0.55,-0.50,-0.13,"vehicleWheel",6,"rearWheel")
                part(0.50,-0.55,0.50,-0.13,"vehicleWheel",6,"rearWheel")
                part(-0.43,0.45,-0.43,0.70,"vehicleWheel",4,"frontWheel")
                part(0.43,0.45,0.43,0.70,"vehicleWheel",4,"frontWheel")
                part(0,-0.18,0,0.20,"vehicleCab",8,"cab")
            end
        end
    end
    label(outside and "MAQUINA FORA DO MAPA" or (nativeMap and "PDA DO JOGO | VERDE: TRABALHADO | AMARELO: SOBREPOSICAO"
        or "PDA INDISPONIVEL | VERDE: TRABALHADO | AMARELO: SOBREPOSICAO"))
    return commands
end
