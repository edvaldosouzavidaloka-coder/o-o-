-- Automatic headland sequence. Forward-only; geometry and implement commands
-- are isolated in the dedicated helpers. The driver can cancel at any time.
TGHeadlandControl = {}

local function speed(vehicle)
    return vehicle.getLastSpeed ~= nil and math.abs(vehicle:getLastSpeed()) or 0
end

local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2)
end

local function key(lane, section)
    return tostring(lane) .. ":" .. tostring(section)
end

local function plan(owner, pose, goal)
    return TGTurnPlanner.plan(pose, goal, {
        radius = owner.turnRadius, spacing = 0.6,
        boundary = owner.fieldBoundary, clearance = math.max(1.5, math.min(owner.width / 2, 3))
    })
end

local function stopping(owner, vehicle, message, snapshot)
    owner.turnState = {phase = "stopping", timer = 0, implements = snapshot, reason = message}
    owner:notify(message .. " - parando; solte o acelerador para assumir")
end

function TGHeadlandControl.begin(owner, vehicle, result)
    local pose = owner:getVehiclePose(vehicle)
    if pose == nil or owner.mode ~= "field" or owner.fieldBoundary == nil then return false end
    local current = owner:getLanePath(owner.currentLane, owner.currentSection)
    if current == nil then return false end
    local cruise = vehicle.spec_drivable and vehicle.spec_drivable.cruiseControl
    local cruiseState = cruise and cruise.state or 0
    if cruiseState > 0 then
        if type(vehicle.setCruiseControlState) ~= "function" then
            owner:stopAutosteer("Desligue o controle de cruzeiro para usar a cabeceira")
            return true
        end
        local ok = pcall(vehicle.setCruiseControlState, vehicle, Drivable.CRUISECONTROL_STATE_OFF or 0)
        if not ok or cruise.state > 0 then
            owner:stopAutosteer("Nao foi possivel suspender o cruzeiro; assuma o controle")
            return true
        end
    end
    owner.completedSections = owner.completedSections or {}
    owner.completedSections[key(owner.currentLane, owner.currentSection)] = true
    local exit = result.direction == 1 and current[#current] or current[1]
    local choices = {}
    for lane, sections in pairs(owner.guidanceSections) do
        for section, points in ipairs(sections) do
            if not owner.completedSections[key(lane, section)] then
                local entryIndex = distance(exit, points[1]) <= distance(exit, points[#points]) and 1 or #points
                local entry, other = points[entryIndex], points[entryIndex == 1 and #points or 1]
                local length = distance(entry, other)
                if length >= 3 then
                    local preferred = (lane - owner.currentLane) * owner.turnSide > 0
                    choices[#choices + 1] = {
                        lane = lane, section = section, direction = entryIndex == 1 and 1 or -1,
                        goal = {x = entry.x, z = entry.z, dx = (other.x - entry.x) / length, dz = (other.z - entry.z) / length},
                        cost = distance(exit, entry) + (preferred and 0 or 100000)
                    }
                end
            end
        end
    end
    table.sort(choices, function(a, b) return a.cost < b.cost end)
    local chosen, planned
    -- Bound work in a physics callback; the nearest candidate on either side
    -- gets a chance even if many rows lie on the preferred side.
    local attempts, triedOther = 0, false
    for index, candidate in ipairs(choices) do
        local otherSide = candidate.cost >= 100000
        if attempts < 10 or (otherSide and not triedOther) then
            attempts = attempts + 1
            triedOther = triedOther or otherSide
            local candidatePlan = plan(owner, pose, candidate.goal)
            if candidatePlan ~= nil then chosen, planned = candidate, candidatePlan; break end
        elseif index > 10 and triedOther then
            break
        end
    end
    local snapshot, implementError = TGImplementControl.captureAndRaise(vehicle)
    if snapshot == nil then
        stopping(owner, vehicle, "Implemento incompativel com levantamento automatico")
        return true
    end
    if chosen == nil then
        stopping(owner, vehicle, #choices == 0 and "Sequencia de passadas terminada" or "Curva nao cabe neste contorno; assuma a direcao", snapshot)
        return true
    end
    owner.turnState = {
        phase = "lifting", timer = 0, implements = snapshot,
        path = planned.points, goal = chosen.goal,
        cruiseState = cruiseState,
        nextLane = chosen.lane, nextSection = chosen.section, nextDirection = chosen.direction
    }
    owner:notify("Cabeceira: levantando implemento e preparando a curva")
    return true
end

function TGHeadlandControl.step(owner, vehicle, pose, dt)
    local state = owner.turnState
    if state == nil then return 0 end
    state.timer = state.timer + math.max(0, math.min(dt or 0, 250))
    if state.phase == "stopping" then
        if speed(vehicle) <= 0.3 then
            local reason = state.reason
            owner:stopAutosteer(reason .. " - controle manual; solte o acelerador")
            owner.headlandBrakeHoldVehicle = vehicle
        end
        return 0
    end
    if not TGHeadlandGeometry.contains(owner.fieldBoundary, pose, 0.5) then
        stopping(owner, vehicle, "Manobra interrompida: limite do talhao", state.implements)
        return 0
    end
    if state.phase == "lifting" then
        if state.timer > 12000 then
            stopping(owner, vehicle, "O implemento nao confirmou levantamento", state.implements)
        elseif state.timer >= 800 and speed(vehicle) <= 1 and TGImplementControl.areRaised(state.implements) then
            local recalculated = plan(owner, pose, state.goal)
            if recalculated == nil then
                stopping(owner, vehicle, "Curva indisponivel na posicao atual", state.implements)
            else
                state.path, state.phase, state.timer = recalculated.points, "turning", 0
                owner:notify("Cabeceira: curva automatica - volante ou freio cancela")
            end
        end
        return 0
    end
    if state.phase == "lowering" then
        if state.timer > 12000 then
            stopping(owner, vehicle, "O implemento nao confirmou descida", state.implements)
            return 0
        end
        if not state.restoreStarted and speed(vehicle) <= 1 then
            local restored = TGImplementControl.restore(state.implements)
            if not restored then
                stopping(owner, vehicle, "Nao foi possivel baixar o implemento", state.implements)
                return 0
            end
            state.restoreStarted, state.timer = true, 0
        elseif state.restoreStarted and state.timer >= 800 and TGImplementControl.areLowered(state.implements) then
            if state.cruiseState ~= nil and state.cruiseState > 0 then
                local ok = pcall(vehicle.setCruiseControlState, vehicle, state.cruiseState)
                if not ok then
                    stopping(owner, vehicle, "Nao foi possivel retomar o cruzeiro", state.implements)
                    return 0
                end
            end
            owner.currentLane, owner.currentSection = state.nextLane, state.nextSection
            owner.travelDirection = state.nextDirection
            owner.turnState, owner.steeringCommand = nil, 0
            owner:notify("Manobra concluida - seguindo a proxima passada")
        end
        return 0
    end
    local result, reason = TGGuidanceController.calculate(state.path, pose, {
        wheelbase = 3, maxSteeringAngle = math.rad(35), lookAheadMin = 2.5, lookAheadTime = 0.4,
        maxDistance = 5, maxHeadingAngle = math.rad(85), direction = 1, endDistance = 0.5
    })
    if result == nil then
        stopping(owner, vehicle, "Manobra interrompida: trator fora da curva", state.implements)
        return 0
    end
    if result.atEnd then
        local goal = state.goal
        local alignment = pose.dx * goal.dx + pose.dz * goal.dz
        local headingLength = math.sqrt(pose.dx * pose.dx + pose.dz * pose.dz)
        if distance(pose, goal) <= 2 and alignment / headingLength >= math.cos(math.rad(18)) then
            state.phase, state.timer = "lowering", 0
            owner:notify("Cabeceira: alinhado, preparando descida do implemento")
            return 0
        end
        stopping(owner, vehicle, "Alinhamento final insuficiente; assuma a direcao", state.implements)
        return 0
    end
    return -result.steering
end

-- Throttle/brake override applies ONLY during the automatic maneuver. A manual
-- brake or steering input is handled by TGGPS before reaching this function.
function TGHeadlandControl.drive(owner, vehicle, axisForward, doHandbrake)
    local state = owner.turnState
    if state == nil then return axisForward, doHandbrake end
    local cruise = vehicle.spec_drivable and vehicle.spec_drivable.cruiseControl
    if cruise ~= nil and (cruise.state or 0) > 0 and type(vehicle.setCruiseControlState) == "function" then
        vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF or 0)
    end
    local kmh = speed(vehicle)
    if state.phase ~= "turning" then
        return kmh > 0.3 and -1 or 0, true
    end
    if kmh > owner.turnSpeed + 0.4 then return -0.5, doHandbrake end
    if kmh > owner.turnSpeed + 0.1 then return 0, doHandbrake end
    return math.min(0.65, math.max(0.12, (owner.turnSpeed - kmh) * 0.3)), doHandbrake
end
