-- Forward-only Dubins headland turns, independent of GIANTS globals.
-- World heading is atan2(dx,dz): zero faces +Z; positive rotation turns RIGHT.
-- The six canonical Dubins families are tried in ascending analytic length.
-- This is a bounded-curvature turn planner, not a general obstacle/path search.
TGTurnPlanner = {}

local PI, TAU = math.pi, math.pi * 2
local EPSILON = 0.0000001
local MAX_POINTS = 5000

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function atan2(y, x)
    if math.atan2 ~= nil then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and PI or -PI) end
    if y > 0 then return PI / 2 end
    if y < 0 then return -PI / 2 end
    return 0
end

local function mod2pi(value)
    local result = value % TAU
    if result < 0.0000000001 or TAU - result < 0.0000000001 then return 0 end
    return result
end

local function angleDifference(a, b)
    return (a - b + PI) % TAU - PI
end

local function poseHeading(pose)
    if type(pose) ~= "table" or not finite(pose.x) or not finite(pose.z)
        or not finite(pose.dx) or not finite(pose.dz) then return nil end
    local magnitude = math.sqrt(pose.dx * pose.dx + pose.dz * pose.dz)
    if not finite(magnitude) or magnitude <= EPSILON then return nil end
    return atan2(pose.dx / magnitude, pose.dz / magnitude)
end

local function cross(ax, az, bx, bz)
    return ax * bz - az * bx
end

local function pointSegmentDistanceSquared(point, a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    local length2 = dx * dx + dz * dz
    if length2 <= EPSILON * EPSILON then
        return (point.x - a.x)^2 + (point.z - a.z)^2
    end
    local t = clamp(((point.x - a.x) * dx + (point.z - a.z) * dz) / length2, 0, 1)
    return (point.x - a.x - t * dx)^2 + (point.z - a.z - t * dz)^2
end

local function inside(point, polygon)
    local result = false
    for i = 1, #polygon do
        local a, b = polygon[i], polygon[i % #polygon + 1]
        if pointSegmentDistanceSquared(point, a, b) <= EPSILON * EPSILON then return true end
        if (a.z > point.z) ~= (b.z > point.z) then
            local x = a.x + (point.z - a.z) * (b.x - a.x) / (b.z - a.z)
            if point.x < x then result = not result end
        end
    end
    return result
end

local function normalizeBoundary(boundary)
    if boundary == nil then return nil, true end
    if type(boundary) ~= "table" or #boundary < 3 or #boundary > 10000 then return nil, false end
    local polygon = {}
    for _, point in ipairs(boundary) do
        if type(point) ~= "table" or not finite(point.x) or not finite(point.z) then return nil, false end
        local previous = polygon[#polygon]
        if previous == nil or (point.x - previous.x)^2 + (point.z - previous.z)^2 > EPSILON * EPSILON then
            polygon[#polygon + 1] = {x = point.x, z = point.z}
        end
    end
    if #polygon > 1 and (polygon[1].x - polygon[#polygon].x)^2
        + (polygon[1].z - polygon[#polygon].z)^2 <= EPSILON * EPSILON then table.remove(polygon) end
    if #polygon < 3 then return nil, false end
    local area, origin = 0, polygon[1]
    for i = 2, #polygon - 1 do
        area = area + cross(polygon[i].x - origin.x, polygon[i].z - origin.z,
            polygon[i + 1].x - origin.x, polygon[i + 1].z - origin.z)
    end
    if not finite(area) or math.abs(area) <= EPSILON then return nil, false end
    return polygon, true
end

-- Add exact segment/edge intersection parameters. Splitting at every crossing
-- prevents a long sample chord joining two inside points across an outside gap.
local function intersections(a, b, c, d, parameters)
    local rx, rz, sx, sz = b.x - a.x, b.z - a.z, d.x - c.x, d.z - c.z
    local denominator = cross(rx, rz, sx, sz)
    local qx, qz = c.x - a.x, c.z - a.z
    if math.abs(denominator) > EPSILON then
        local t, u = cross(qx, qz, sx, sz) / denominator, cross(qx, qz, rx, rz) / denominator
        if t >= -EPSILON and t <= 1 + EPSILON and u >= -EPSILON and u <= 1 + EPSILON then
            parameters[#parameters + 1] = clamp(t, 0, 1)
            return true
        end
    elseif math.abs(cross(qx, qz, rx, rz)) <= EPSILON then
        local length2 = rx * rx + rz * rz
        if length2 > EPSILON * EPSILON then
            local t1 = (qx * rx + qz * rz) / length2
            local t2 = ((d.x - a.x) * rx + (d.z - a.z) * rz) / length2
            local low, high = math.max(0, math.min(t1, t2)), math.min(1, math.max(t1, t2))
            if low <= high + EPSILON then
                parameters[#parameters + 1], parameters[#parameters + 2] = clamp(low, 0, 1), clamp(high, 0, 1)
                return true
            end
        end
    end
    return false
end

local function pointClear(point, polygon, clearance)
    if not inside(point, polygon) then return false end
    if clearance > 0 then
        for i = 1, #polygon do
            if pointSegmentDistanceSquared(point, polygon[i], polygon[i % #polygon + 1])
                < clearance * clearance - EPSILON * EPSILON then return false end
        end
    end
    return true
end

local function chordClear(a, b, polygon, clearance)
    if not inside(a, polygon) or not inside(b, polygon) then return false end
    local parameters = {0, 1}
    local required2 = clearance * clearance
    for i = 1, #polygon do
        local c, d = polygon[i], polygon[i % #polygon + 1]
        local crosses = intersections(a, b, c, d, parameters)
        if clearance > 0 then
            if crosses then return false end
            local distance2 = math.min(pointSegmentDistanceSquared(a, c, d), pointSegmentDistanceSquared(b, c, d),
                pointSegmentDistanceSquared(c, a, b), pointSegmentDistanceSquared(d, a, b))
            if distance2 < required2 - EPSILON * EPSILON then return false end
        end
    end
    table.sort(parameters)
    for i = 1, #parameters - 1 do
        if parameters[i + 1] - parameters[i] > EPSILON then
            local t = (parameters[i] + parameters[i + 1]) / 2
            if not inside({x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t}, polygon) then return false end
        end
    end
    return true
end

-- Formula coordinates are u=z,v=x. Mathematical left increases world heading,
-- i.e. it is a physical RIGHT turn; result labels are swapped to world L/R.
local solvers = {}
function solvers.LSL(a, b, d)
    local p2 = 2 + d*d - 2*math.cos(a-b) + 2*d*(math.sin(a)-math.sin(b))
    if p2 < -EPSILON then return nil end
    local t = atan2(math.cos(b)-math.cos(a), d+math.sin(a)-math.sin(b))
    return mod2pi(-a+t), math.sqrt(math.max(0,p2)), mod2pi(b-t)
end
function solvers.RSR(a, b, d)
    local p2 = 2 + d*d - 2*math.cos(a-b) + 2*d*(math.sin(b)-math.sin(a))
    if p2 < -EPSILON then return nil end
    local t = atan2(math.cos(a)-math.cos(b), d-math.sin(a)+math.sin(b))
    return mod2pi(a-t), math.sqrt(math.max(0,p2)), mod2pi(-b+t)
end
function solvers.LSR(a, b, d)
    local p2 = -2 + d*d + 2*math.cos(a-b) + 2*d*(math.sin(a)+math.sin(b))
    if p2 < -EPSILON then return nil end
    local p = math.sqrt(math.max(0,p2))
    local t = atan2(-math.cos(a)-math.cos(b), d+math.sin(a)+math.sin(b))-atan2(-2,p)
    return mod2pi(-a+t), p, mod2pi(-b+t)
end
function solvers.RSL(a, b, d)
    local p2 = d*d - 2 + 2*math.cos(a-b) - 2*d*(math.sin(a)+math.sin(b))
    if p2 < -EPSILON then return nil end
    local p = math.sqrt(math.max(0,p2))
    local t = atan2(math.cos(a)+math.cos(b), d-math.sin(a)-math.sin(b))-atan2(2,p)
    return mod2pi(a-t), p, mod2pi(b-t)
end
function solvers.RLR(a, b, d)
    local value = (6-d*d+2*math.cos(a-b)+2*d*(math.sin(a)-math.sin(b)))/8
    if math.abs(value) > 1 + EPSILON then return nil end
    local p = mod2pi(TAU-math.acos(clamp(value,-1,1)))
    local t = mod2pi(a-atan2(math.cos(a)-math.cos(b),d-math.sin(a)+math.sin(b))+p/2)
    return t, p, mod2pi(a-b-t+p)
end
function solvers.LRL(a, b, d)
    local value = (6-d*d+2*math.cos(a-b)+2*d*(-math.sin(a)+math.sin(b)))/8
    if math.abs(value) > 1 + EPSILON then return nil end
    local p = mod2pi(TAU-math.acos(clamp(value,-1,1)))
    local t = mod2pi(-a-atan2(math.cos(a)-math.cos(b),d+math.sin(a)-math.sin(b))+p/2)
    return t, p, mod2pi(b-a-t+p)
end

local function worldKind(kind)
    return (kind:gsub("[LR]", {L="R",R="L"}))
end

local function sample(candidate, start, goal, startHeading, goalHeading, radius, spacing, polygon, clearance)
    local x, z, heading = start.x, start.z, startHeading
    local points = {{x=x,z=z,dx=math.sin(heading),dz=math.cos(heading),heading=heading,curvature=0}}
    local segments = {}
    if polygon ~= nil and not pointClear(points[1], polygon, clearance) then return nil end
    for i = 1, 3 do
        local kind = candidate.kind:sub(i,i)
        local length = candidate.parts[i] * radius
        local curvature = kind == "L" and 1/radius or (kind == "R" and -1/radius or 0)
        segments[#segments + 1] = {type=worldKind(kind),length=length,curvature=curvature}
        local steps = math.max(1, math.ceil(length / spacing))
        if length > EPSILON and #points + steps > MAX_POINTS then return nil end
        if length > EPSILON then
            local ds = length / steps
            -- Every arc lies within sagitta of its chord. Requiring that extra
            -- edge clearance makes the unsampled arc safe as well as its chord.
            local sagitta = curvature ~= 0 and radius * (1-math.cos(ds/(2*radius))) or 0
            for _ = 1, steps do
                local previous = points[#points]
                if curvature == 0 then
                    x, z = x + ds*math.sin(heading), z + ds*math.cos(heading)
                else
                    local nextHeading = heading + curvature*ds
                    x, z = x + (math.cos(heading)-math.cos(nextHeading))/curvature,
                        z + (math.sin(nextHeading)-math.sin(heading))/curvature
                    heading = nextHeading
                end
                local point = {x=x,z=z,dx=math.sin(heading),dz=math.cos(heading),heading=heading,curvature=curvature}
                if not finite(x) or not finite(z) then return nil end
                if polygon ~= nil and not chordClear(previous,point,polygon,clearance+sagitta) then return nil end
                points[#points + 1] = point
            end
        end
    end
    local error2 = (x-goal.x)^2 + (z-goal.z)^2
    if error2 > (0.00001*math.max(1,radius))^2 or math.abs(angleDifference(heading,goalHeading)) > 0.00001 then return nil end
    if #points < 2 then return nil end
    -- Clamp only verified floating-point drift, never bridge a missing segment.
    local last = points[#points]
    last.x,last.z,last.dx,last.dz,last.heading = goal.x,goal.z,math.sin(goalHeading),math.cos(goalHeading),goalHeading
    return {points=points,length=candidate.length,kind=worldKind(candidate.kind),radius=radius,
        startHeading=startHeading,endHeading=goalHeading,segments=segments}
end

-- start/goal={x,z,dx,dz}; options={radius=6,spacing=.75,boundary=nil,clearance=1}.
-- A boundary is optional for pure geometry use; game callers should supply it.
-- No fit means manual intervention is required; no straight/reverse fallback.
function TGTurnPlanner.plan(start, goal, options)
    local startHeading, goalHeading = poseHeading(start), poseHeading(goal)
    if startHeading == nil or goalHeading == nil then return nil,"invalid_pose" end
    options = options or {}
    if type(options) ~= "table" then return nil,"invalid_options" end
    local radius = options.radius == nil and 6 or options.radius
    local spacing = options.spacing == nil and 0.75 or options.spacing
    local clearance = options.clearance == nil and 1 or options.clearance
    if not finite(radius) or radius < 0.1 or radius > 1000
        or not finite(spacing) or spacing < 0.05 or spacing > 10
        or not finite(clearance) or clearance < 0 or clearance > 100 then return nil,"invalid_options" end
    local polygon, validBoundary = normalizeBoundary(options.boundary)
    if not validBoundary then return nil,"invalid_boundary" end
    local du,dv = goal.z-start.z,goal.x-start.x
    local distance = math.sqrt(du*du+dv*dv)
    if not finite(distance) then return nil,"invalid_pose" end
    if distance <= EPSILON and math.abs(angleDifference(startHeading,goalHeading)) <= EPSILON then
        return nil,"already_at_goal"
    end
    local bearing = atan2(dv,du)
    local alpha,beta,d = mod2pi(startHeading-bearing),mod2pi(goalHeading-bearing),distance/radius
    local candidates = {}
    for _, kind in ipairs({"LSL","RSR","LSR","RSL","RLR","LRL"}) do
        local t,p,q = solvers[kind](alpha,beta,d)
        if t ~= nil then
            local length = (t+p+q)*radius
            if finite(length) and length > EPSILON then
                candidates[#candidates + 1] = {kind=kind,parts={t,p,q},length=length}
            end
        end
    end
    table.sort(candidates,function(a,b) return a.length < b.length end)
    for _, candidate in ipairs(candidates) do
        local result = sample(candidate,start,goal,startHeading,goalHeading,radius,spacing,polygon,clearance)
        if result ~= nil then return result end
    end
    return nil,"no_turn_fits"
end
