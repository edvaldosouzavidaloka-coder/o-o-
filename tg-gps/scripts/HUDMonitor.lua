-- TG GPS PRO: coverage engine adapted from the user-supplied HUDMonitor.lua.
-- Isolated from CurveGPS globals, controls, UI, storage and event listeners.
-- Shared by the TG panel and the physical cab monitor; never controls steering.
TGGPSHUDMonitor = {}
TGGPSHUDMonitor.__index = TGGPSHUDMonitor

local function hudClamp(v, a, b) return math.max(a, math.min(b, v)) end
local HUD_WORK_AREA_SKIP = {
    processRidgeMarkerArea = true,
    processCombineSwathArea = true,
    processCombineChopperArea = true
}

function TGGPSHUDMonitor.new(owner)
    local self = setmetatable({owner = owner}, TGGPSHUDMonitor)
    self:reset()
    return self
end

function TGGPSHUDMonitor:reset()
    self.coverageRuns, self.coverageGrid = {}, {}
    self.coverageDisplayGrid, self.coverageDisplayList, self.coverageDisplayBuckets = {}, {}, {}
    self.coverageOverlapList = {}
    self.coverageCellSize, self.coverageDisplayCellSize, self.coverageDisplayBucketCells = 0.75, 0.75, 20
    self.coverageGeometryPruned,self.visualCache=false,nil
    self.coverageUniqueCells, self.coverageOverlapCells = 0, 0
    self.coveragePointCount, self.coverageRunSerial, self.coverageSegmentSerial = 0, 0, 0
    self.coverageMaxPoints, self.coverageSameRunReentryGap = 3500, 6
    self.coverageBaseWorkedHa, self.useCoverageWorkedArea = 0, true
    self.coverageAreaDirty, self.coveragePersistenceDirty = false, false
    self.lastVehicle, self.lastImplement = nil, nil
    self.footprint, self.estimated, self.implementName = nil, false, nil
    self.elapsed, self.working = 100, false
    self.mapCache, self.revision = nil, (self.revision or 0) + 1
    self:endRun()
    if self.owner ~= nil and (self.owner.coverage==nil or self.owner.coverage==self) then self.owner.workedAreaHa = 0 end
end

function TGGPSHUDMonitor:endRun()
    self.currentCoverageRun, self.currentCoverageRunId, self.coverageLastPoint = nil, nil, nil
end

-- Invoked by the existing TG listener. Work is sampled at 10 Hz, even with the
-- 2D panel closed and with manual steering. Changing vehicles never bridges paint.
function TGGPSHUDMonitor:update(dt)
    local owner = self.owner
    local vehicle = owner:getControlledVehicle()
    local routeReady = type(owner.sourcePoints) == "table" and #owner.sourcePoints >= 2
    if not routeReady or vehicle == nil or not vehicle.tgGpsSupported then
        self:endRun()
        self.lastVehicle, self.lastImplement, self.working, self.footprint = nil, nil, false, nil
        self.elapsed = 100
        return
    end
    if vehicle ~= self.lastVehicle then
        self:endRun()
        self.lastVehicle, self.lastImplement = vehicle, nil
        self.elapsed = 100
    end
    self.elapsed = self.elapsed + math.max(0, dt or 0)
    if self.elapsed < 100 then return end
    self.elapsed = self.elapsed % 100
    local working, implement, name, footprint = self:getCoverageWorkingState(vehicle)
    if not working or implement ~= self.lastImplement then self:endRun() end
    self.working, self.lastImplement, self.implementName = working == true, implement, name
    self.footprint = working and footprint or nil
    self.estimated = working and footprint == nil
    if working then self:recordCoveragePoint(owner, vehicle, footprint) end
end

function TGGPSHUDMonitor:getWorkedHa()
    return (self.coverageUniqueCells or 0) * self.coverageCellSize ^ 2 / 10000
end

function TGGPSHUDMonitor:getOverlapHa()
    return (self.coverageOverlapCells or 0) * self.coverageCellSize ^ 2 / 10000
end

-- Aggregate world-anchored display cells into a bounded map raster. Coarsen rather
-- than discard passes when viewing a large field. The measurement grid is intact.
function TGGPSHUDMonitor:getMapCells(minX, minZ, maxX, maxZ, budget)
    budget = math.max(4, budget or 1200)
    local old = self.mapCache
    if old ~= nil and old.revision == self.revision and old.minX == minX and old.minZ == minZ
        and old.maxX == maxX and old.maxZ == maxZ and old.budget == budget then return old.cells end
    local cellSize, bucketCells = self.coverageDisplayCellSize, self.coverageDisplayBucketCells
    local bucketSize = cellSize * bucketCells
    local columns = math.max(1, math.min(384, math.ceil((maxX - minX) / cellSize)))
    local rows = math.max(1, math.min(192, math.ceil((maxZ - minZ) / cellSize)))
    local result
    repeat
        local grid = {}
        local dx, dz = (maxX - minX) / columns, (maxZ - minZ) / rows
        for bz = math.floor(minZ / bucketSize), math.floor(maxZ / bucketSize) do
            for bx = math.floor(minX / bucketSize), math.floor(maxX / bucketSize) do
                local bucket = self.coverageDisplayBuckets[tostring(bx) .. ":" .. tostring(bz)]
                for _, cell in ipairs(bucket or {}) do
                    local x, z = cell.ix * cellSize, cell.iz * cellSize
                    if x < maxX and x + cellSize > minX and z < maxZ and z + cellSize > minZ then
                        local c1 = math.max(0, math.floor((x - minX) / dx))
                        local c2 = math.min(columns - 1, math.ceil((x + cellSize - minX) / dx) - 1)
                        local r1 = math.max(0, math.floor((z - minZ) / dz))
                        local r2 = math.min(rows - 1, math.ceil((z + cellSize - minZ) / dz) - 1)
                        for r = r1, r2 do
                            grid[r] = grid[r] or {}
                            for c = c1, c2 do
                                grid[r][c] = math.max(grid[r][c] or 0, cell.overlap and 2 or 1)
                            end
                        end
                    end
                end
            end
        end
        result=TGGPSMapFrame.mergeGrid(grid,columns,rows)
        for _,rect in ipairs(result) do
            rect.x,rect.z=minX+rect.x*(maxX-minX),minZ+rect.y*(maxZ-minZ)
            rect.w,rect.h=rect.w*(maxX-minX),rect.h*(maxZ-minZ)
            rect.overlap=rect.value==2
        end
        columns, rows = math.max(1, math.floor(columns / 2)), math.max(1, math.floor(rows / 2))
    until #result <= budget
    self.mapCache = {revision = self.revision, minX = minX, minZ = minZ,
        maxX = maxX, maxZ = maxZ, budget = budget, cells = result}
    return result
end

-- Recent passes are drawn from their continuous work-area edges, rather than
-- enlarging measurement cells when zooming in. Yellow overlap and archived
-- history keep using the measurement display; hectares are never modified.
function TGGPSHUDMonitor:getMapVisuals(minX,minZ,maxX,maxZ)
    local cells=self:getMapCells(minX,minZ,maxX,maxZ,2400)
    local old=self.visualCache
    if old and old.cells==cells and old.serial==self.coverageSegmentSerial
        and old.count==self.coveragePointCount then return old.shapes end
    local shapes={}
    local hasRuns=#self.coverageRuns>0
    for _,cell in ipairs(cells) do
        if cell.overlap or not hasRuns or self.coverageGeometryPruned then shapes[#shapes+1]=cell end
    end
    local function add(a,b,c)
        if math.max(a.x,b.x,c.x)>=minX and math.min(a.x,b.x,c.x)<=maxX
            and math.max(a.z,b.z,c.z)>=minZ and math.min(a.z,b.z,c.z)<=maxZ then
            shapes[#shapes+1]={points={a,b,c}}
        end
    end
    for _,run in ipairs(self.coverageRuns) do
        for i=2,#run do
            local a,b=run[i-1],run[i]
            local arx,arz=a.rx or 1,a.rz or 0
            local brx,brz=b.rx or arx,b.rz or arz
            local ah,bh=(a.width or 6)/2,(b.width or 6)/2
            local al={x=a.x-arx*ah,z=a.z-arz*ah};local ar={x=a.x+arx*ah,z=a.z+arz*ah}
            local bl={x=b.x-brx*bh,z=b.z-brz*bh};local br={x=b.x+brx*bh,z=b.z+brz*bh}
            add(al,ar,br);add(al,br,bl)
        end
    end
    self.visualCache={cells=cells,serial=self.coverageSegmentSerial,count=self.coveragePointCount,shapes=shapes}
    return shapes
end

function TGGPSHUDMonitor:getCoverageCellKey(ix,iz)
    return tostring(ix)..":"..tostring(iz)
end

function TGGPSHUDMonitor:syncCoverageWorkedArea(owner)
    if owner==nil or self.useCoverageWorkedArea~=true then return end
    if self.coverageBaseWorkedHa==nil then
        self.coverageBaseWorkedHa=tonumber(owner.workedAreaHa) or 0
    end
    local cellSize=math.max(0.50,self.coverageCellSize or 0.75)
    local uniqueHa=(self.coverageUniqueCells or 0)*(cellSize*cellSize)/10000
    owner.workedAreaHa=(self.coverageBaseWorkedHa or 0)+uniqueHa
    local profile=owner.fieldProfiles~=nil and owner.activeFieldProfileId~=nil and owner.fieldProfiles[owner.activeFieldProfileId] or nil
    if profile~=nil then profile.workedAreaHa=owner.workedAreaHa end
    self.coverageAreaDirty=false
end

function TGGPSHUDMonitor:getCoverageDisplayKey(ix,iz)
    return tostring(ix)..":"..tostring(iz)
end

function TGGPSHUDMonitor:indexCoverageDisplayCell(cell)
    if cell==nil then return end
    self.coverageDisplayBuckets=self.coverageDisplayBuckets or {}
    local bucketCells=math.max(4,math.floor(self.coverageDisplayBucketCells or 16))
    local bx=math.floor(cell.ix/bucketCells)
    local bz=math.floor(cell.iz/bucketCells)
    local key=tostring(bx)..":"..tostring(bz)
    local bucket=self.coverageDisplayBuckets[key]
    if bucket==nil then
        bucket={}
        self.coverageDisplayBuckets[key]=bucket
    end
    table.insert(bucket,cell)
end

function TGGPSHUDMonitor:markCoverageDisplayWorld(wx,wz,isOverlap)
    local cellSize=math.max(0.75,self.coverageDisplayCellSize or 1.25)
    local ix=math.floor(wx/cellSize)
    local iz=math.floor(wz/cellSize)
    local key=self:getCoverageDisplayKey(ix,iz)
    self.coverageDisplayGrid=self.coverageDisplayGrid or {}
    local cell=self.coverageDisplayGrid[key]
    if cell==nil then
        cell={ix=ix,iz=iz,overlap=isOverlap==true}
        self.coverageDisplayGrid[key]=cell
        self.coverageDisplayList=self.coverageDisplayList or {}
        table.insert(self.coverageDisplayList,cell)
        self:indexCoverageDisplayCell(cell)
    elseif isOverlap==true then
        cell.overlap=true
    end
    self.revision = (self.revision or 0) + 1
    return cell
end

function TGGPSHUDMonitor:markCoverageCell(ix,iz,runId,segmentId,touched)
    local key=self:getCoverageCellKey(ix,iz)
    if touched[key] then return end
    touched[key]=true

    local cell=self.coverageGrid[key]
    if cell==nil then
        cell={ix=ix,iz=iz,lastRun=runId,lastSegment=segmentId,overlap=false}
        self.coverageGrid[key]=cell
        self.coverageUniqueCells=(self.coverageUniqueCells or 0)+1
        self.coverageAreaDirty=true
        local fineSize=math.max(0.50,self.coverageCellSize or 0.75)
        self:markCoverageDisplayWorld((ix+0.5)*fineSize,(iz+0.5)*fineSize,false)
        return
    end

    -- A cell only becomes real overlap when it is reached in a NEW work run.
    -- Adjacent stamps from the same physical pass can touch the same grid cells
    -- many times, especially on curves; counting those as overlap created the
    -- dark jagged strip seen in the monitor even during a single pass.
    local separatedRun=(cell.lastRun~=runId)
    local lastSegment=tonumber(cell.lastSegment) or segmentId
    -- Also detect a genuine re-pass during the same lowered/turned-on cycle.
    -- Consecutive raster segments overlap naturally along their seam, so only
    -- segments separated by several recording steps count as a new pass here.
    local separatedSameRun=(cell.lastRun==runId and math.abs(segmentId-lastSegment)>=(self.coverageSameRunReentryGap or 6))
    if (separatedRun or separatedSameRun) and not cell.overlap then
        cell.overlap=true
        self.coverageOverlapCells=(self.coverageOverlapCells or 0)+1
        table.insert(self.coverageOverlapList,cell)
        local fineSize=math.max(0.50,self.coverageCellSize or 0.75)
        self:markCoverageDisplayWorld((ix+0.5)*fineSize,(iz+0.5)*fineSize,true)
    end

    cell.lastRun=runId
    cell.lastSegment=segmentId
end


function TGGPSHUDMonitor:rasterizeCoverageSegment(a,b,runId,owner)
    if a==nil or b==nil then return end

    local cellSize=math.max(0.50,self.coverageCellSize or 1.00)
    local dx=b.x-a.x
    local dz=b.z-a.z
    local dist=math.sqrt(dx*dx+dz*dz)
    if dist<0.03 then return end

    self.coverageSegmentSerial=(self.coverageSegmentSerial or 0)+1
    local segmentId=self.coverageSegmentSerial
    local touched={}

    -- Sample the swept implement strip densely enough to avoid holes in curves,
    -- while staying independent from the frame rate.
    local alongStep=cellSize*0.45
    local alongCount=math.max(1,math.ceil(dist/alongStep))
    alongCount=math.min(alongCount,64)

    for i=0,alongCount do
        local t=i/alongCount
        local cx=a.x+dx*t
        local cz=a.z+dz*t

        local rx=(a.rx or 1)+((b.rx or 1)-(a.rx or 1))*t
        local rz=(a.rz or 0)+((b.rz or 0)-(a.rz or 0))*t
        local rLen=math.sqrt(rx*rx+rz*rz)
        if rLen<0.0001 then
            rx,rz=1,0
        else
            rx,rz=rx/rLen,rz/rLen
        end

        local width=math.max(0.50,(a.width or 0)+((b.width or 0)-(a.width or 0))*t)
        local half=width*0.5
        local acrossStep=cellSize*0.45
        local acrossCount=math.max(1,math.ceil(width/acrossStep))
        acrossCount=math.min(acrossCount,80)

        for j=0,acrossCount do
            local u=(j/acrossCount)-0.5
            local offset=u*width
            local wx=cx+rx*offset
            local wz=cz+rz*offset
            local ix=math.floor(wx/cellSize)
            local iz=math.floor(wz/cellSize)
            self:markCoverageCell(ix,iz,runId,segmentId,touched)
        end

        -- Guarantee both implement edges are stamped even with very narrow tools.
        for _,offset in ipairs({-half,half}) do
            local wx=cx+rx*offset
            local wz=cz+rz*offset
            local ix=math.floor(wx/cellSize)
            local iz=math.floor(wz/cellSize)
            self:markCoverageCell(ix,iz,runId,segmentId,touched)
        end
    end

    if self.coverageAreaDirty then
        self:syncCoverageWorkedArea(owner)
    end
end

-- Returns whether a work area should count as real field work for the monitor.
-- Auxiliary/ridge/swath-only areas are ignored so they cannot start paint by
-- themselves. The object's own getIsWorkAreaActive() is used because GIANTS
-- specializations add the correct lowered / turned-on / ground-contact rules.


function TGGPSHUDMonitor:isRelevantCoverageWorkArea(workArea)
    if workArea==nil then return false end

    if workArea.functionName~=nil and HUD_WORK_AREA_SKIP[workArea.functionName] then
        return false
    end

    if WorkAreaType~=nil and WorkAreaType.AUXILIARY~=nil and workArea.type==WorkAreaType.AUXILIARY then
        return false
    end

    return true
end

function TGGPSHUDMonitor:getCoverageFallbackWidth(owner)
    if owner==nil then return 6.0 end
    -- Exact active workAreas remain authoritative. This value is used only by
    -- unusual tools without readable nodes; in AUTO mode prefer the latest
    -- detector measurement so guidance and fallback paint use the same width.
    if owner.autoWidthEnabled==true and tonumber(owner.detectedWidth or 0)>0 then
        return math.max(0.50,tonumber(owner.detectedWidth))
    end
    return math.max(0.50,tonumber(owner.width) or 6.0)
end

-- Tests one vehicle/implement. For seeders/planters the WorkArea specialization
-- normally reports active when the implement is lowered/has ground contact. For
-- sprayers and other TurnOnVehicle tools the same call also honours the
-- needsSetIsTurnedOn flag, so turning the pump/tool off immediately stops paint.

function TGGPSHUDMonitor:isCoverageObjectWorking(object)
    if object==nil then return false end

    local spec=object.spec_workArea
    if spec~=nil and type(spec.workAreas)=="table" and object.getIsWorkAreaActive~=nil then
        for _,workArea in pairs(spec.workAreas) do
            if self:isRelevantCoverageWorkArea(workArea) then
                local ok,isActive=pcall(object.getIsWorkAreaActive,object,workArea)
                if ok and isActive==true then
                    return true
                end
            end
        end
    end

    -- Safe fallback for tools that expose TurnOnVehicle but no usable workArea
    -- table to script mods. This mainly covers unusual/custom sprayer-style mods.
    if object.spec_turnOnVehicle~=nil and object.getIsTurnedOn~=nil then
        local ok,isOn=pcall(object.getIsTurnedOn,object)
        if ok and isOn==true then
            -- If the tool can be lowered too, require it to be lowered. A
            -- permanently mounted/self-propelled tool usually has no lowering API.
            if object.getIsLowered~=nil then
                local okLower,lowered=pcall(object.getIsLowered,object,false)
                if okLower then return lowered==true end
            end
            return true
        end
    end

    return false
end

-- Scan the tractor and its complete attached-implement tree. We intentionally
-- do not depend on self.owner.active: coverage represents the IMPLEMENT working,
-- exactly like a real guidance monitor, even while steering is manual.

function TGGPSHUDMonitor:getCoverageWorkingState(vehicle)
    if vehicle==nil or vehicle.rootNode==nil or getWorldTranslation==nil or localDirectionToWorld==nil then
        return false,nil,nil,nil
    end

    -- Tractor heading is used ONLY as a sign/fallback reference. The real
    -- coverage frame below comes from the active implement workArea nodes.
    -- This is important for articulated/pulled implements: their work area can
    -- yaw relative to the tractor, and using the tractor axes makes the paint
    -- slide sideways on turns.
    local vx,_,vz=getWorldTranslation(vehicle.rootNode)
    local vehicleFx,_,vehicleFz=localDirectionToWorld(vehicle.rootNode,0,0,1)
    if vx==nil or vz==nil or vehicleFx==nil or vehicleFz==nil then
        return false,nil,nil,nil
    end
    local vehicleFLen=math.sqrt(vehicleFx*vehicleFx+vehicleFz*vehicleFz)
    if vehicleFLen<0.0001 then return false,nil,nil,nil end
    vehicleFx,vehicleFz=vehicleFx/vehicleFLen,vehicleFz/vehicleFLen
    local vehicleRx,vehicleRz=vehicleFz,-vehicleFx

    local visited={}
    local workingObject=nil
    local fallbackObject=nil
    local activeAreas={}

    local function scan(object)
        if object==nil or visited[object] then return end
        visited[object]=true

        local objectHasActiveArea=false
        local spec=object.spec_workArea
        if spec~=nil and type(spec.workAreas)=="table" and object.getIsWorkAreaActive~=nil then
            for _,workArea in pairs(spec.workAreas) do
                if self:isRelevantCoverageWorkArea(workArea)
                    and workArea.start~=nil and workArea.width~=nil and workArea.height~=nil then
                    local ok,isActive=pcall(object.getIsWorkAreaActive,object,workArea)
                    if ok and isActive==true then
                        local sx,_,sz=getWorldTranslation(workArea.start)
                        local wx,_,wz=getWorldTranslation(workArea.width)
                        local hx,_,hz=getWorldTranslation(workArea.height)
                        if sx~=nil and sz~=nil and wx~=nil and wz~=nil and hx~=nil and hz~=nil then
                            -- GIANTS defines a workArea by three rectangle points:
                            -- start, width and height. The fourth point is
                            -- width + height - start. Keep those WORLD points so
                            -- the footprint follows the implement itself.
                            local qx=wx+hx-sx
                            local qz=wz+hz-sz
                            local wdx=wx-sx
                            local wdz=wz-sz
                            local hdx=hx-sx
                            local hdz=hz-sz
                            local wLen=math.sqrt(wdx*wdx+wdz*wdz)
                            local hLen=math.sqrt(hdx*hdx+hdz*hdz)
                            activeAreas[#activeAreas+1]={
                                sx=sx,sz=sz,wx=wx,wz=wz,hx=hx,hz=hz,qx=qx,qz=qz,
                                wdx=wdx,wdz=wdz,hdx=hdx,hdz=hdz,
                                wLen=wLen,hLen=hLen,object=object
                            }
                            objectHasActiveArea=true
                            workingObject=workingObject or object
                        end
                    end
                end
            end
        end

        if not objectHasActiveArea and fallbackObject==nil and self:isCoverageObjectWorking(object) then
            fallbackObject=object
        end

        if object.getAttachedImplements~=nil then
            local ok,implements=pcall(object.getAttachedImplements,object)
            if ok and implements~=nil then
                for _,implement in pairs(implements) do
                    local child=implement~=nil and implement.object or nil
                    if child~=nil then scan(child) end
                end
            end
        end
    end

    scan(vehicle)

    local function getName(object)
        if object==nil then return nil end
        if self.owner~=nil and self.owner.getDisplayName~=nil then
            local ok,value=pcall(self.owner.getDisplayName,self.owner,object)
            if ok then return value end
        end
        return nil
    end

    if #activeAreas>0 then
        -- V19: build one stable implement frame from ALL active workAreas.
        -- Some large planters expose many small workAreas on articulated sections.
        -- Picking just one section as the reference made the combined bounding box
        -- explode during a U-turn. A weighted average follows the whole implement
        -- while remaining attached to its real workArea nodes.
        local sumRx,sumRz,sumWeight=0,0,0
        local maxAreaLength=0
        local centerXSum,centerZSum,centerWeight=0,0,0
        for _,area in ipairs(activeAreas) do
            local wLen=tonumber(area.wLen) or 0
            local hLen=tonumber(area.hLen) or 0
            maxAreaLength=math.max(maxAreaLength,hLen)
            if wLen>0.0001 then
                local ux=area.wdx/wLen
                local uz=area.wdz/wLen
                if ux*vehicleRx+uz*vehicleRz<0 then ux,uz=-ux,-uz end
                sumRx=sumRx+ux*wLen
                sumRz=sumRz+uz*wLen
                sumWeight=sumWeight+wLen
            end
            local acx=(area.sx+area.wx+area.hx+area.qx)*0.25
            local acz=(area.sz+area.wz+area.hz+area.qz)*0.25
            local cw=math.max(0.10,wLen)
            centerXSum=centerXSum+acx*cw
            centerZSum=centerZSum+acz*cw
            centerWeight=centerWeight+cw
        end

        local rx,rz=vehicleRx,vehicleRz
        if sumWeight>0.0001 then
            local rLen=math.sqrt(sumRx*sumRx+sumRz*sumRz)
            if rLen>0.0001 then rx,rz=sumRx/rLen,sumRz/rLen end
        end
        if rx*vehicleRx+rz*vehicleRz<0 then rx,rz=-rx,-rz end

        -- Use the perpendicular of the averaged real width axis. This avoids
        -- longitudinal inflation when individual workArea sections yaw slightly
        -- relative to each other in a turn.
        local fx,fz=-rz,rx
        if fx*vehicleFx+fz*vehicleFz<0 then fx,fz=-fx,-fz end

        local worldX=(centerWeight>0.0001) and (centerXSum/centerWeight) or vx
        local worldZ=(centerWeight>0.0001) and (centerZSum/centerWeight) or vz
        local minX,maxX=math.huge,-math.huge
        local minZ,maxZ=math.huge,-math.huge
        local function includePoint(px,pz)
            local dx=px-worldX
            local dz=pz-worldZ
            local lx=dx*rx+dz*rz
            local lz=dx*fx+dz*fz
            minX=math.min(minX,lx)
            maxX=math.max(maxX,lx)
            minZ=math.min(minZ,lz)
            maxZ=math.max(maxZ,lz)
        end

        for _,area in ipairs(activeAreas) do
            includePoint(area.sx,area.sz)
            includePoint(area.wx,area.wz)
            includePoint(area.hx,area.hz)
            includePoint(area.qx,area.qz)
        end

        if minX<=maxX and minZ<=maxZ then
            local rawWidth=math.max(0.25,maxX-minX)
            local rawLength=math.max(0.05,maxZ-minZ)

            -- TG's manual lane spacing must not truncate real active work areas.
            local width=rawWidth

            -- Likewise, front/back workArea length must come from the individual
            -- workArea height edges, not from the spread of many articulated
            -- sections. This prevents the leading edge from jumping metres away
            -- and creating huge blue blocks on headland turns.
            local length=rawLength
            if maxAreaLength>0.05 then
                length=math.min(length,math.max(0.25,maxAreaLength*1.30))
            else
                length=math.min(length,math.max(0.50,width*0.20))
            end

            local footprint={
                x=worldX,
                z=worldZ,
                fx=fx,fz=fz,rx=rx,rz=rz,
                width=math.max(0.25,width),
                length=math.max(0.05,length),
                rawWidth=rawWidth,
                rawLength=rawLength,
                localMinX=minX,localMaxX=maxX,
                localMinZ=minZ,localMaxZ=maxZ,
                activeAreaCount=#activeAreas,
                exactWorkArea=true,
                implementAligned=true,
                stabilizedTurnFootprint=true
            }
            return true,workingObject,getName(workingObject),footprint
        end
    end

    -- Compatibility fallback for unusual custom tools that expose only a
    -- turned-on/lowered state but no readable workArea nodes.
    if fallbackObject~=nil then
        return true,fallbackObject,getName(fallbackObject),nil
    end

    return false,nil,nil,nil
end

function TGGPSHUDMonitor:recordCoveragePoint(owner,vehicle,footprint)
    if owner==nil or vehicle==nil or vehicle.rootNode==nil
        or getWorldTranslation==nil or localDirectionToWorld==nil then
        return
    end

    local x,z,fx,fz,rx,rz,width,length

    if footprint~=nil and footprint.x~=nil and footprint.z~=nil then
        -- Exact mode: center and dimensions are derived from the active workArea
        -- footprint, so a rear planter paints behind the tractor and a cutter
        -- paints in front exactly where its real processing area is located.
        x,z=footprint.x,footprint.z
        fx,fz=footprint.fx,footprint.fz
        rx,rz=footprint.rx,footprint.rz
        width=math.max(0.25,footprint.width or self:getCoverageFallbackWidth(owner))
        length=math.max(0.05,footprint.length or 0.05)
    else
        -- Safe fallback for custom implements without accessible workArea nodes.
        local y
        x,y,z=getWorldTranslation(vehicle.rootNode)
        fx,y,fz=localDirectionToWorld(vehicle.rootNode,0,0,1)
        if x==nil or z==nil or fx==nil or fz==nil then return end
        local fLen=math.sqrt(fx*fx+fz*fz)
        if fLen<0.0001 then return end
        fx,fz=fx/fLen,fz/fLen
        rx,rz=fz,-fx
        width=self:getCoverageFallbackWidth(owner)
        length=0.05
    end

    local fLen=math.sqrt((fx or 0)*(fx or 0)+(fz or 0)*(fz or 0))
    if fLen<0.0001 then return end
    fx,fz=fx/fLen,fz/fLen
    local rLen=math.sqrt((rx or 0)*(rx or 0)+(rz or 0)*(rz or 0))
    if rLen<0.0001 then
        rx,rz=fz,-fx
    else
        rx,rz=rx/rLen,rz/rLen
    end

    -- Paint using the LEADING edge of the real work area. On the first frame we
    -- also seed the trailing edge, which fills the entire implement length at
    -- the exact place where work starts instead of starting at the tractor axle.
    local leadX=x+fx*length*0.5
    local leadZ=z+fz*length*0.5
    local p={x=leadX,z=leadZ,fx=fx,fz=fz,rx=rx,rz=rz,width=width,length=length}
    local last=self.coverageLastPoint
    local minDist=hudClamp(math.min(width*0.10,math.max(0.30,length*0.40)),0.30,1.00)
    local shouldAdd=last==nil

    if last~=nil then
        local dx=p.x-last.x
        local dz=p.z-last.z
        local dist=math.sqrt(dx*dx+dz*dz)
        local dot=(last.fx or fx)*fx+(last.fz or fz)*fz
        shouldAdd=dist>=minDist or dot<0.9970

        -- V19 safety: a custom/articulated implement can briefly switch active
        -- workArea nodes during a headland turn. Never bridge a large teleport
        -- with one full-width strip; end that visual run and restart at the real
        -- current footprint instead. Normal driving samples are far below 8 m.
        local maxBridge=hudClamp(math.max(3.0,(length or 0.05)*3.0),3.0,8.0)
        if dist>maxBridge then
            self.currentCoverageRun=nil
            self.currentCoverageRunId=nil
            self.coverageLastPoint=nil
            last=nil
            shouldAdd=true
        end
    end

    if not shouldAdd then return end

    if self.currentCoverageRun==nil then
        self.currentCoverageRun={}
        table.insert(self.coverageRuns,self.currentCoverageRun)
        self.coverageRunSerial=(self.coverageRunSerial or 0)+1
        self.currentCoverageRunId=self.coverageRunSerial

        local trail={
            x=x-fx*length*0.5,
            z=z-fz*length*0.5,
            fx=fx,fz=fz,rx=rx,rz=rz,
            width=width,length=length
        }
        table.insert(self.currentCoverageRun,trail)
        table.insert(self.currentCoverageRun,p)
        self.coveragePointCount=(self.coveragePointCount or 0)+2
        self:rasterizeCoverageSegment(trail,p,self.currentCoverageRunId,owner)

        if self.indexCoverageRenderSegment~=nil then self:indexCoverageRenderSegment(trail,p) end
        self.coveragePersistenceDirty=true
        self.coverageLastPoint=p
        return
    end

    if last~=nil and self.currentCoverageRunId~=nil then
        self:rasterizeCoverageSegment(last,p,self.currentCoverageRunId,owner)

        if self.indexCoverageRenderSegment~=nil then self:indexCoverageRenderSegment(last,p) end
    end

    table.insert(self.currentCoverageRun,p)
    self.coverageLastPoint=p
    self.coveragePointCount=(self.coveragePointCount or 0)+1
    self.coveragePersistenceDirty=true

    -- Safety cap for very long sessions. Remove the oldest complete runs first.
    local removedCoverageRun=false
    while (self.coveragePointCount or 0)>(self.coverageMaxPoints or 3500) and #self.coverageRuns>1 do
        local removed=table.remove(self.coverageRuns,1)
        self.coveragePointCount=self.coveragePointCount-#removed
        removedCoverageRun=true
        self.coverageGeometryPruned=true
    end
    if removedCoverageRun and self.rebuildCoverageRenderBuckets~=nil then
        self:rebuildCoverageRenderBuckets()
    end
end

