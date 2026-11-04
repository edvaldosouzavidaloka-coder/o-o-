-- Pure path geometry: independent of GIANTS globals and vehicle physics.
-- X/Z world plane; heading (dx,dz) points forward. Right is (dz,-dx).
-- Positive steeringAngle and steering mean RIGHT, in radians and [-1,1].
-- These are geometric commands; the game adapter maps its steering sign.
TGGuidanceController = {}

local EPSILON = 0.000001

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function option(options, name, default, minimum, maximum)
    local value = options[name]
    if value == nil then
        return default
    end
    if not finite(value) or value < minimum or value > maximum then
        return nil
    end
    return value
end

-- pose.speed is speed magnitude in metres/second. options.direction may be
-- pinned to +1 (A -> B) or -1 (B -> A) for the lifetime of an engagement.
-- atEnd means steering must disengage; this module never controls speed/brakes.
-- Returns nil plus a stable reason code when acquisition/tracking is unsafe.
function TGGuidanceController.calculate(points, pose, options)
    if type(points) ~= "table" or #points < 2 then
        return nil, "invalid_path"
    end
    if type(pose) ~= "table" or not finite(pose.x) or not finite(pose.z)
        or not finite(pose.dx) or not finite(pose.dz)
        or (pose.speed ~= nil and not finite(pose.speed)) then
        return nil, "invalid_pose"
    end
    local headingLength = math.sqrt(pose.dx * pose.dx + pose.dz * pose.dz)
    if not finite(headingLength) or headingLength < EPSILON then
        return nil, "invalid_pose"
    end
    options = options or {}
    if type(options) ~= "table" then
        return nil, "invalid_options"
    end
    local wheelbase = option(options, "wheelbase", 3, 0.1, 30)
    local maxAngle = option(options, "maxSteeringAngle", math.rad(35), 0.01, math.rad(89))
    local lookAheadMin = option(options, "lookAheadMin", 4, 0.1, 100)
    local lookAheadTime = option(options, "lookAheadTime", 0.7, 0, 10)
    local maxDistance = option(options, "maxDistance", 8, 0.01, 1000)
    local maxHeadingAngle = option(options, "maxHeadingAngle", math.rad(75), 0, math.pi)
    local endDistance = option(options, "endDistance", 1, 0, 100)
    if wheelbase == nil or maxAngle == nil or lookAheadMin == nil
        or lookAheadTime == nil or maxDistance == nil or maxHeadingAngle == nil
        or endDistance == nil or (options.direction ~= nil
        and options.direction ~= 1 and options.direction ~= -1) then
        return nil, "invalid_options"
    end

    local hx, hz = pose.dx / headingLength, pose.dz / headingLength
    local segments = {}
    local totalLength = 0
    local nearest = nil
    for i = 1, #points do
        local point = points[i]
        if type(point) ~= "table" or not finite(point.x) or not finite(point.z) then
            return nil, "invalid_path"
        end
    end
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local dx, dz = b.x - a.x, b.z - a.z
        local lengthSquared = dx * dx + dz * dz
        if not finite(lengthSquared) then
            return nil, "invalid_path"
        end
        if lengthSquared > EPSILON * EPSILON then
            local length = math.sqrt(lengthSquared)
            local t = clamp(((pose.x - a.x) * dx + (pose.z - a.z) * dz) / lengthSquared, 0, 1)
            local x, z = a.x + t * dx, a.z + t * dz
            local ex, ez = pose.x - x, pose.z - z
            local distanceSquared = ex * ex + ez * ez
            if not finite(distanceSquared) then
                return nil, "invalid_pose"
            end
            local alignment = (hx * dx + hz * dz) / length
            -- At vertices/crossings prefer the equally close aligned segment.
            local score = options.direction and alignment * options.direction or math.abs(alignment)
            local segment = {a = a, dx = dx, dz = dz, length = length, start = totalLength}
            segments[#segments + 1] = segment
            if nearest == nil or distanceSquared < nearest.distanceSquared - EPSILON
                or (math.abs(distanceSquared - nearest.distanceSquared) <= EPSILON
                    and score > nearest.score) then
                nearest = {
                    segment = segment, distanceSquared = distanceSquared,
                    progress = totalLength + t * length, alignment = alignment,
                    score = score, x = x, z = z
                }
            end
            totalLength = totalLength + length
        end
    end
    if nearest == nil or not finite(totalLength) then
        return nil, "invalid_path"
    end

    local distance = math.sqrt(nearest.distanceSquared)
    if distance > maxDistance then
        return nil, "too_far"
    end
    local direction = options.direction or (nearest.alignment >= 0 and 1 or -1)
    local headingError = math.acos(clamp(nearest.alignment * direction, -1, 1))
    if headingError > maxHeadingAngle then
        return nil, "wrong_heading"
    end
    local remaining = direction == 1 and totalLength - nearest.progress or nearest.progress
    local atEnd = remaining <= math.min(endDistance, totalLength * 0.25) + EPSILON
    local speed = math.abs(pose.speed or 0)
    local lookAhead = lookAheadMin + speed * lookAheadTime
    if not finite(lookAhead) then
        return nil, "invalid_pose"
    end
    local targetProgress = clamp(nearest.progress + direction * lookAhead, 0, totalLength)
    local last = segments[#segments]
    local target = {x = last.a.x + last.dx, z = last.a.z + last.dz}
    for _, segment in ipairs(segments) do
        if targetProgress <= segment.start + segment.length + EPSILON then
            local t = clamp((targetProgress - segment.start) / segment.length, 0, 1)
            target = {x = segment.a.x + t * segment.dx, z = segment.a.z + t * segment.dz}
            break
        end
    end
    local tx, tz = target.x - pose.x, target.z - pose.z
    local targetDistanceSquared = tx * tx + tz * tz
    if not finite(targetDistanceSquared) then
        return nil, "invalid_pose"
    end
    local right = tx * hz - tz * hx
    local steeringAngle = 0
    if not atEnd and targetDistanceSquared > EPSILON * EPSILON then
        steeringAngle = clamp(math.atan(2 * wheelbase * right / targetDistanceSquared), -maxAngle, maxAngle)
    end
    return {
        steeringAngle = steeringAngle, steering = steeringAngle / maxAngle,
        distance = distance, atEnd = atEnd, progress = nearest.progress,
        length = totalLength, direction = direction, target = target,
        headingError = headingError, remaining = remaining,
        nearest = {x = nearest.x, z = nearest.z}
    }
end
