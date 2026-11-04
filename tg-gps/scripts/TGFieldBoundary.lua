-- Static FS25 map boundaries plus independent planar line/polygon geometry.
-- Does not scan altered terrain, merged fields, or islands within a field.
TGFieldBoundary = {}

local EPSILON = 0.000001
local MAX_VERTICES = 10000
local MAX_LANES = 1000
local MIN_SECTION_LENGTH = 2

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function samePoint(a, b)
    return math.abs(a.x - b.x) <= EPSILON and math.abs(a.z - b.z) <= EPSILON
end

local function normalizeVertices(vertices)
    if type(vertices) ~= "table" or #vertices < 3 or #vertices > MAX_VERTICES then
        return nil
    end
    local result = {}
    for _, point in ipairs(vertices) do
        if type(point) ~= "table" or not finite(point.x) or not finite(point.z) then
            return nil
        end
        if #result == 0 or not samePoint(result[#result], point) then
            result[#result + 1] = {x = point.x, z = point.z}
        end
    end
    if #result > 1 and samePoint(result[1], result[#result]) then
        table.remove(result)
    end
    if #result < 3 then
        return nil
    end
    local area = 0
    local origin = result[1]
    for i = 2, #result - 1 do
        local a, b = result[i], result[i + 1]
        area = area + (a.x - origin.x) * (b.z - origin.z)
            - (b.x - origin.x) * (a.z - origin.z)
    end
    if not finite(area) or math.abs(area) < EPSILON then
        return nil
    end
    return result
end

-- Confirmed FS25 API: farmland:getField():getDensityMapPolygon():getVerticesList().
-- The list is a flat x,z sequence, not transform IDs or field dimensions.
-- Returns a copied { {x,z}, ... } polygon and optional field ID, or nil, reason.
function TGFieldBoundary.getAt(x, z)
    if not finite(x) or not finite(z) then
        return nil, "invalid_position"
    end
    if g_farmlandManager == nil or type(g_farmlandManager.getFarmlandAtWorldPosition) ~= "function" then
        return nil, "field_api_unavailable"
    end
    local ok, farmland = pcall(g_farmlandManager.getFarmlandAtWorldPosition, g_farmlandManager, x, z)
    if not ok then
        return nil, "field_api_failed"
    end
    if farmland == nil then
        return nil, "no_field"
    end
    if type(farmland.getField) ~= "function" then
        return nil, "field_api_unavailable"
    end
    local field
    ok, field = pcall(farmland.getField, farmland)
    if not ok then
        return nil, "field_api_failed"
    end
    if field == nil then
        return nil, "no_field"
    end
    if type(field.getDensityMapPolygon) ~= "function" then
        return nil, "polygon_unavailable"
    end
    local polygon
    ok, polygon = pcall(field.getDensityMapPolygon, field)
    if not ok or polygon == nil or type(polygon.getVerticesList) ~= "function" then
        return nil, "polygon_unavailable"
    end
    local flat
    ok, flat = pcall(polygon.getVerticesList, polygon)
    if not ok or type(flat) ~= "table" or #flat % 2 ~= 0 or #flat > MAX_VERTICES * 2 then
        return nil, "invalid_polygon"
    end
    local vertices = {}
    for i = 1, #flat, 2 do
        vertices[#vertices + 1] = {x = flat[i], z = flat[i + 1]}
    end
    vertices = normalizeVertices(vertices)
    if vertices == nil then
        return nil, "invalid_polygon"
    end
    local fieldId
    if type(field.getId) == "function" then
        local gotId, value = pcall(field.getId, field)
        if gotId and (type(value) == "number" or type(value) == "string") then
            fieldId = value
        end
    end
    return vertices, fieldId
end

local function sortedIntervals(projected, offset)
    local intersections, intervals = {}, {}
    for i = 1, #projected do
        local a, b = projected[i], projected[i % #projected + 1]
        local sa = math.abs(a.s - offset) <= EPSILON and offset or a.s
        local sb = math.abs(b.s - offset) <= EPSILON and offset or b.s
        if sa == offset and sb == offset then
            intervals[#intervals + 1] = {math.min(a.t, b.t), math.max(a.t, b.t)}
        elseif (sa <= offset and sb > offset) or (sb <= offset and sa > offset) then
            local t = a.t + (offset - sa) * (b.t - a.t) / (sb - sa)
            intersections[#intersections + 1] = t
        end
    end
    table.sort(intersections)
    -- Half-open edge crossings retain coincident hits: two equal hits cancel
    -- parity naturally, instead of accidentally connecting an outside gap.
    if #intersections % 2 ~= 0 then
        return nil
    end
    for i = 1, #intersections, 2 do
        intervals[#intervals + 1] = {intersections[i], intersections[i + 1]}
    end
    table.sort(intervals, function(a, b) return a[1] < b[1] end)
    local merged = {}
    for _, interval in ipairs(intervals) do
        local previous = merged[#merged]
        if previous ~= nil and interval[1] <= previous[2] + EPSILON then
            previous[2] = math.max(previous[2], interval[2])
        else
            merged[#merged + 1] = {interval[1], interval[2]}
        end
    end
    return merged
end

-- Each lane is an integer width offset along normal (-dz,dx). A concave field
-- can produce several disconnected sections on one lane. They remain separate;
-- consumers must never draw or steer across the outside-field gap between them.
function TGFieldBoundary.generateLanes(vertices, origin, direction, width)
    vertices = normalizeVertices(vertices)
    if vertices == nil then
        return nil, "invalid_polygon"
    end
    if type(origin) ~= "table" or not finite(origin.x) or not finite(origin.z)
        or type(direction) ~= "table" or not finite(direction.dx) or not finite(direction.dz) then
        return nil, "invalid_position"
    end
    if not finite(width) or width <= 0 then
        return nil, "invalid_width"
    end
    local length = math.sqrt(direction.dx * direction.dx + direction.dz * direction.dz)
    if not finite(length) or length < EPSILON then
        return nil, "invalid_direction"
    end
    local dx, dz = direction.dx / length, direction.dz / length
    local nx, nz = -dz, dx
    local minT, maxT, minS, maxS = math.huge, -math.huge, math.huge, -math.huge
    local projected = {}
    for _, point in ipairs(vertices) do
        local px, pz = point.x - origin.x, point.z - origin.z
        local t, s = px * dx + pz * dz, px * nx + pz * nz
        if not finite(t) or not finite(s) then
            return nil, "invalid_position"
        end
        projected[#projected + 1] = {t = t, s = s}
        minT, maxT = math.min(minT, t), math.max(maxT, t)
        minS, maxS = math.min(minS, s), math.max(maxS, s)
    end
    local minLane = math.ceil((minS - EPSILON) / width)
    local maxLane = math.floor((maxS + EPSILON) / width)
    if not finite(minLane) or not finite(maxLane) or maxLane - minLane + 1 > MAX_LANES then
        return nil, "too_many_lanes"
    end
    local function world(t, offset)
        return {x = origin.x + dx * t + nx * offset, z = origin.z + dz * t + nz * offset}
    end
    local result = {
        lanes = {}, basePath = {world(minT, 0), world(maxT, 0)},
        minLane = nil, maxLane = nil, laneCount = 0, sectionCount = 0
    }
    for lane = minLane, maxLane do
        local offset = lane * width
        local intervals = sortedIntervals(projected, offset)
        if intervals == nil then
            return nil, "invalid_polygon"
        end
        local sections = {}
        for _, interval in ipairs(intervals) do
            if interval[2] - interval[1] >= MIN_SECTION_LENGTH - EPSILON then
                sections[#sections + 1] = {world(interval[1], offset), world(interval[2], offset)}
            end
        end
        if #sections > 0 then
            result.lanes[lane] = sections
            result.minLane = result.minLane or lane
            result.maxLane = lane
            result.laneCount = result.laneCount + 1
            result.sectionCount = result.sectionCount + #sections
        end
    end
    if result.laneCount == 0 then
        return nil, "no_lanes"
    end
    return result
end
