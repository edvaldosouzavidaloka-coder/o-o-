-- Pure X/Z geometry for reserving a headland inside a static field polygon.
-- Work lines are clipped analytically: polygon interior minus the capsules of
-- radius `margin` around every polygon edge. No unsafe sampling gaps are used.
TGHeadlandGeometry = {}

local EPSILON = 0.000001
local PARALLEL_EPSILON = 0.000000000001
local MAX_VERTICES = 10000
local MAX_LANES = 1000
local MAX_EDGE_WORK = 200000
local MIN_SECTION_LENGTH = 2

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function validPoint(point)
    return type(point) == "table" and finite(point.x) and finite(point.z)
end

local function samePoint(a, b)
    return math.abs(a.x - b.x) <= EPSILON and math.abs(a.z - b.z) <= EPSILON
end

local function prepare(boundary)
    if type(boundary) ~= "table" or #boundary < 3 or #boundary > MAX_VERTICES then
        return nil
    end
    local vertices = {}
    for _, point in ipairs(boundary) do
        if not validPoint(point) then return nil end
        if #vertices == 0 or not samePoint(vertices[#vertices], point) then
            vertices[#vertices + 1] = point
        end
    end
    if #vertices > 1 and samePoint(vertices[1], vertices[#vertices]) then
        vertices[#vertices] = nil
    end
    if #vertices < 3 then return nil end

    local area, edges = 0, {}
    local origin = vertices[1]
    for index = 2, #vertices - 1 do
        local a, b = vertices[index], vertices[index + 1]
        area = area + (a.x - origin.x) * (b.z - origin.z)
            - (b.x - origin.x) * (a.z - origin.z)
    end
    if not finite(area) or math.abs(area) < EPSILON then return nil end
    for index, a in ipairs(vertices) do
        local b = vertices[index % #vertices + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local lengthSquared = dx * dx + dz * dz
        if not finite(lengthSquared) then return nil end
        if lengthSquared > EPSILON * EPSILON then
            local length = math.sqrt(lengthSquared)
            edges[#edges + 1] = {a = a, b = b, dx = dx, dz = dz,
                lengthSquared = lengthSquared, length = length,
                ux = dx / length, uz = dz / length}
        end
    end
    if #edges < 3 then return nil end
    return edges
end

local function distanceSquaredToEdge(edge, point)
    local x, z = point.x - edge.a.x, point.z - edge.a.z
    local t = math.max(0, math.min(1, (x * edge.dx + z * edge.dz) / edge.lengthSquared))
    local ex, ez = x - t * edge.dx, z - t * edge.dz
    return ex * ex + ez * ez
end

local function distanceToEdges(edges, point)
    local minimum = math.huge
    for _, edge in ipairs(edges) do
        minimum = math.min(minimum, distanceSquaredToEdge(edge, point))
    end
    return finite(minimum) and math.sqrt(minimum) or nil
end

function TGHeadlandGeometry.distanceToBoundary(boundary, point)
    if not validPoint(point) then return nil end
    local edges = prepare(boundary)
    if edges == nil then return nil end
    return distanceToEdges(edges, point)
end

function TGHeadlandGeometry.contains(boundary, point, clearance)
    clearance = clearance == nil and 0 or clearance
    if not validPoint(point) or not finite(clearance) or clearance < 0 then return false end
    local edges = prepare(boundary)
    if edges == nil then return false end
    local distance = distanceToEdges(edges, point)
    if distance == nil or distance + EPSILON < clearance then return false end
    if distance <= EPSILON then return clearance <= EPSILON end
    local inside = false
    for _, edge in ipairs(edges) do
        local a, b = edge.a, edge.b
        if (a.z > point.z) ~= (b.z > point.z) then
            local crossing = a.x + (point.z - a.z) * edge.dx / edge.dz
            if point.x < crossing then inside = not inside end
        end
    end
    return inside
end

local function mergeIntervals(intervals)
    table.sort(intervals, function(a, b)
        return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
    end)
    local result = {}
    for _, interval in ipairs(intervals) do
        local previous = result[#result]
        if previous ~= nil and interval[1] <= previous[2] + EPSILON then
            previous[2] = math.max(previous[2], interval[2])
        else
            result[#result + 1] = {interval[1], interval[2]}
        end
    end
    return result
end

local function addClipped(intervals, low, high, length)
    low, high = math.max(0, low), math.min(length, high)
    if high - low > EPSILON then intervals[#intervals + 1] = {low, high} end
end

-- The interval on the work line where a projected coordinate lies in a band.
local function bandInterval(base, slope, low, high)
    if math.abs(slope) <= PARALLEL_EPSILON then
        if base < low - EPSILON or base > high + EPSILON then return nil end
        return -math.huge, math.huge
    end
    local a, b = (low - base) / slope, (high - base) / slope
    return math.min(a, b), math.max(a, b)
end

local function addDisk(intervals, center, start, ux, uz, length, radius)
    local x, z = start.x - center.x, start.z - center.z
    local along = x * ux + z * uz
    -- Perpendicular distance avoids subtracting two large nearly equal squares.
    local perpendicular = x * uz - z * ux
    local discriminant = radius * radius - perpendicular * perpendicular
    if discriminant <= EPSILON * EPSILON then return end -- mere tangency
    local half = math.sqrt(discriminant)
    addClipped(intervals, -along - half, -along + half, length)
end

local function addCapsule(intervals, edge, start, ux, uz, length, radius)
    addDisk(intervals, edge.a, start, ux, uz, length, radius)
    addDisk(intervals, edge.b, start, ux, uz, length, radius)
    local x, z = start.x - edge.a.x, start.z - edge.a.z
    local pBase, pSlope = x * edge.ux + z * edge.uz, ux * edge.ux + uz * edge.uz
    local qBase, qSlope = edge.ux * z - edge.uz * x, edge.ux * uz - edge.uz * ux
    -- A parallel line at exactly the requested margin remains usable.
    if math.abs(qSlope) <= PARALLEL_EPSILON and math.abs(qBase) >= radius - EPSILON then return end
    local pLow, pHigh = bandInterval(pBase, pSlope, 0, edge.length)
    if pLow == nil then return end
    local qLow, qHigh = bandInterval(qBase, qSlope, -radius, radius)
    if qLow == nil then return end
    addClipped(intervals, math.max(pLow, qLow), math.min(pHigh, qHigh), length)
end

local function clipSection(edges, start, finish, margin, work)
    local dx, dz = finish.x - start.x, finish.z - start.z
    local length = math.sqrt(dx * dx + dz * dz)
    if not finite(length) then return nil, "invalid_lanes" end
    if length < MIN_SECTION_LENGTH - EPSILON then return {} end
    local ux, uz = dx / length, dz / length
    local crossings, insideIntervals, forbidden = {}, {}, {}
    for _, edge in ipairs(edges) do
        work.used = work.used + 1
        if work.used > MAX_EDGE_WORK then return nil, "geometry_too_complex" end
        local ax, az = edge.a.x - start.x, edge.a.z - start.z
        local bx, bz = edge.b.x - start.x, edge.b.z - start.z
        local aS, bS = ax * ux + az * uz, bx * ux + bz * uz
        local aQ, bQ = ux * az - uz * ax, ux * bz - uz * bx
        if math.abs(aQ) <= EPSILON then aQ = 0 end
        if math.abs(bQ) <= EPSILON then bQ = 0 end
        if math.abs(aQ) <= EPSILON and math.abs(bQ) <= EPSILON then
            addClipped(insideIntervals, math.min(aS, bS), math.max(aS, bS), length)
        elseif (aQ <= 0 and bQ > 0) or (bQ <= 0 and aQ > 0) then
            crossings[#crossings + 1] = aS - aQ * (bS - aS) / (bQ - aQ)
        end
        if margin > EPSILON then
            addCapsule(forbidden, edge, start, ux, uz, length, margin)
        end
    end
    table.sort(crossings)
    if #crossings % 2 ~= 0 then return nil, "invalid_polygon" end
    for index = 1, #crossings, 2 do
        addClipped(insideIntervals, crossings[index], crossings[index + 1], length)
    end
    insideIntervals, forbidden = mergeIntervals(insideIntervals), mergeIntervals(forbidden)
    local allowed = {}
    for _, interval in ipairs(insideIntervals) do
        local cursor = interval[1]
        for _, cut in ipairs(forbidden) do
            if cut[1] >= interval[2] then break end
            if cut[2] > cursor then
                if cut[1] > cursor + EPSILON then
                    allowed[#allowed + 1] = {cursor, math.min(cut[1], interval[2])}
                end
                cursor = math.max(cursor, cut[2])
                if cursor >= interval[2] then break end
            end
        end
        if cursor < interval[2] - EPSILON then allowed[#allowed + 1] = {cursor, interval[2]} end
    end
    local result = {}
    for _, interval in ipairs(allowed) do
        if interval[2] - interval[1] >= MIN_SECTION_LENGTH - EPSILON then
            result[#result + 1] = {
                {x = start.x + ux * interval[1], z = start.z + uz * interval[1]},
                {x = start.x + ux * interval[2], z = start.z + uz * interval[2]}
            }
        end
    end
    return result
end

-- Input and output paths have two endpoints and retain the original direction.
-- A polygon's erosion can split one source section into several work sections.
function TGHeadlandGeometry.trimLanes(lanes, boundary, margin)
    local edges = prepare(boundary)
    if edges == nil then return nil, "invalid_polygon" end
    if not finite(margin) or margin < 0 then return nil, "invalid_margin" end
    if type(lanes) ~= "table" then return nil, "invalid_lanes" end
    local indices = {}
    for lane, sections in pairs(lanes) do
        if not finite(lane) or lane % 1 ~= 0 or type(sections) ~= "table" then
            return nil, "invalid_lanes"
        end
        indices[#indices + 1] = lane
        if #indices > MAX_LANES then return nil, "geometry_too_complex" end
    end
    table.sort(indices)
    local result = {lanes = {}, minLane = nil, maxLane = nil, laneCount = 0, sectionCount = 0}
    local work = {used = 0}
    for _, lane in ipairs(indices) do
        local paths = {}
        for _, path in ipairs(lanes[lane]) do
            if type(path) ~= "table" or #path ~= 2 or not validPoint(path[1]) or not validPoint(path[2]) then
                return nil, "invalid_lanes"
            end
            local clipped, reason = clipSection(edges, path[1], path[2], margin, work)
            if clipped == nil then return nil, reason end
            for _, section in ipairs(clipped) do paths[#paths + 1] = section end
        end
        if #paths > 0 then
            result.lanes[lane] = paths
            result.minLane = result.minLane or lane
            result.maxLane = lane
            result.laneCount = result.laneCount + 1
            result.sectionCount = result.sectionCount + #paths
        end
    end
    if result.laneCount == 0 then return nil, "no_work_area" end
    return result
end
