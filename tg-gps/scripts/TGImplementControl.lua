-- Player-style implement lift control for headland transitions.
-- FS25 usage confirmed in VCA: object:setLoweredAll(down, jointDescIndex).
-- No AI-worker activation, folding or turned-on state changes are requested.
TGImplementControl = {}

local function validJoint(value)
    return type(value) == "number" and value == value and value >= 1
        and value < math.huge and value == math.floor(value)
end

local function attachmentGraph(vehicle)
    if type(vehicle) ~= "table" then return nil, "invalid_vehicle" end
    local list, byObject, visited = {}, {}, {[vehicle] = true}
    local function visit(parent)
        local spec = parent.spec_attacherJoints
        if spec == nil then return true end
        if type(spec) ~= "table" then return false end
        local attached = spec.attachedImplements
        if attached == nil then return true end
        if type(attached) ~= "table" then return false end
        for _, descriptor in pairs(attached) do
            if type(descriptor) ~= "table" or type(descriptor.object) ~= "table" then
                return false
            end
            local object = descriptor.object
            if not visited[object] then
                visited[object] = true
                local entry = {object = object, parent = parent, jointDescIndex = descriptor.jointDescIndex}
                list[#list + 1], byObject[object] = entry, entry
                if not visit(object) then return false end
            end
        end
        return true
    end
    if not visit(vehicle) then return nil, "invalid_attachment_graph" end
    return {list = list, byObject = byObject}
end

local function query(object, method)
    if type(object[method]) ~= "function" then return nil, "unsupported_implement" end
    local ok, value = pcall(object[method], object)
    if not ok or type(value) ~= "boolean" then return nil, "state_query_failed" end
    return value
end

local function setLowered(entry, lowered)
    if type(entry.object.setLoweredAll) ~= "function" or not validJoint(entry.jointDescIndex) then
        return false
    end
    local ok, result = pcall(entry.object.setLoweredAll, entry.object, lowered, entry.jointDescIndex)
    -- Native setters normally return nil; an explicit false is a failed command.
    return ok and result ~= false
end

local function validSnapshot(snapshot)
    return type(snapshot) == "table" and snapshot.version == 1
        and type(snapshot.vehicle) == "table" and type(snapshot.entries) == "table"
        and type(snapshot.raisedGuards) == "table"
end

local function liveGraph(snapshot)
    if not validSnapshot(snapshot) then return nil, "invalid_snapshot" end
    local graph, reason = attachmentGraph(snapshot.vehicle)
    if graph == nil then return nil, reason end
    for _, collection in ipairs({snapshot.entries, snapshot.raisedGuards}) do
        for _, entry in ipairs(collection) do
            if type(entry) ~= "table" or type(entry.object) ~= "table" then
                return nil, "invalid_snapshot"
            end
            local now = graph.byObject[entry.object]
            if now == nil or now.parent ~= entry.parent or now.jointDescIndex ~= entry.jointDescIndex then
                return nil, "stale_implement"
            end
        end
    end
    return graph
end

local function entryStillAttached(snapshot, entry)
    local graph = attachmentGraph(snapshot.vehicle)
    local now = graph ~= nil and graph.byObject[entry.object] or nil
    return now ~= nil and now.parent == entry.parent and now.jointDescIndex == entry.jointDescIndex
end

-- Some native implementations may propagate a lowered-all command. These
-- guards never receive a lower command and reassert their original raised state.
local function preserveRaised(snapshot)
    local success = true
    for _, entry in ipairs(snapshot.raisedGuards) do
        local lowered
        if entryStillAttached(snapshot, entry) then lowered = query(entry.object, "getIsLowered") end
        if lowered == nil then
            success = false
        elseif lowered and not setLowered(entry, false) then
            success = false
        end
    end
    return success
end

local function rollbackRaise(snapshot, attempted)
    local graph = attachmentGraph(snapshot.vehicle)
    local success = graph ~= nil
    for index = attempted, 1, -1 do
        local entry = snapshot.entries[index]
        local now = graph ~= nil and graph.byObject[entry.object] or nil
        if now == nil or now.parent ~= entry.parent or now.jointDescIndex ~= entry.jointDescIndex then
            success = false
        else
            local lowered = query(entry.object, "getIsLowered")
            if lowered == nil or (not lowered and not setLowered(entry, true)) then
                success = false
            end
        end
    end
    if graph ~= nil and not preserveRaised(snapshot) then success = false end
    return success
end

-- Captures the complete graph and all relevant states BEFORE any mutation.
-- entries contains only implements which were originally lowered. A tractor
-- without implements returns an empty, valid snapshot.
function TGImplementControl.captureAndRaise(vehicle)
    local graph, reason = attachmentGraph(vehicle)
    if graph == nil then return nil, reason end
    local snapshot = {version = 1, vehicle = vehicle, entries = {}, raisedGuards = {}}
    for _, entry in ipairs(graph.list) do
        local object = entry.object
        local allows
        if type(object.getAllowsLowering) == "function" then
            allows, reason = query(object, "getAllowsLowering")
            if allows == nil then return nil, reason end
        end
        local lowered
        if type(object.getIsLowered) == "function" then
            lowered, reason = query(object, "getIsLowered")
            if lowered == nil then return nil, reason end
        elseif allows then
            return nil, "unsupported_implement"
        end
        if lowered then
            if not allows or type(object.setLoweredAll) ~= "function" or not validJoint(entry.jointDescIndex) then
                return nil, "unsupported_implement"
            end
            snapshot.entries[#snapshot.entries + 1] = entry
        elseif lowered == false then
            snapshot.raisedGuards[#snapshot.raisedGuards + 1] = entry
        end
    end
    for index, entry in ipairs(snapshot.entries) do
        if not setLowered(entry, false) then
            local restored = rollbackRaise(snapshot, index)
            return nil, restored and "raise_failed" or "raise_failed_rollback_incomplete"
        end
    end
    return snapshot
end

-- Only normal maneuver completion should call restore. An aborted turn leaves
-- implements raised until the player deliberately resumes or lowers them.
function TGImplementControl.restore(snapshot)
    local graph, reason = liveGraph(snapshot)
    if graph == nil then return false, reason end
    -- Validate every getter/setter before lowering even the first implement.
    for _, entry in ipairs(snapshot.entries) do
        local lowered, problem = query(entry.object, "getIsLowered")
        if lowered == nil then return false, problem end
        if type(entry.object.setLoweredAll) ~= "function" or not validJoint(entry.jointDescIndex) then
            return false, "unsupported_implement"
        end
    end
    for _, entry in ipairs(snapshot.raisedGuards) do
        local lowered, problem = query(entry.object, "getIsLowered")
        if lowered == nil then return false, problem end
        if lowered and (type(entry.object.setLoweredAll) ~= "function" or not validJoint(entry.jointDescIndex)) then
            return false, "unsupported_implement"
        end
    end
    local success = true
    for _, entry in ipairs(snapshot.entries) do
        local lowered
        if entryStillAttached(snapshot, entry) then lowered = query(entry.object, "getIsLowered") end
        if lowered == nil or (not lowered and not setLowered(entry, true)) then success = false end
    end
    if not preserveRaised(snapshot) then success = false end
    if not success then return false, "restore_failed" end
    return true
end

local function allHaveState(snapshot, expected)
    local graph, reason = liveGraph(snapshot)
    if graph == nil then return false, reason end
    for _, entry in ipairs(snapshot.entries) do
        local lowered, problem = query(entry.object, "getIsLowered")
        if lowered == nil then return false, problem end
        if lowered ~= expected then return false end
    end
    for _, entry in ipairs(snapshot.raisedGuards) do
        local lowered, problem = query(entry.object, "getIsLowered")
        if lowered == nil then return false, problem end
        if lowered then return false, "raised_implement_changed" end
    end
    return true
end

-- These are observed lowered flags, not a universal animation-completion API.
function TGImplementControl.areRaised(snapshot)
    return allHaveState(snapshot, false)
end

function TGImplementControl.areLowered(snapshot)
    return allHaveState(snapshot, true)
end
