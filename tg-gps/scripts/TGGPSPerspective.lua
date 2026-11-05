-- Ground-plane guidance for the physical GreenStar display. No PDA is loaded.
TGGPSPerspective={}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function TGGPSPerspective.project(pose,x,z)
    local dx,dz=x-pose.x,z-pose.z
    local right=dx*pose.dz-dz*pose.dx
    local forward=dx*pose.dx+dz*pose.dz
    if forward < -10 or forward>160 then return nil end
    return .5+right*1.9/(forward+35),.95-22/(forward+35)
end
local function clip(x,y,u,v)
    local dx,dy=u-x,v-y
    local low,high=0,1
    local p,q={-dx,dx,-dy,dy},{x,1-x,y,.95-y}
    for i=1,4 do
        if math.abs(p[i])<1e-9 then if q[i]<0 then return end
        else
            local r=q[i]/p[i]
            if p[i]<0 then low=math.max(low,r) else high=math.min(high,r) end
            if low>high then return end
        end
    end
    return x+low*dx,y+low*dy,x+high*dx,y+high*dy
end
function TGGPSPerspective.draw(screen)
    local owner=screen.owner
    local pose=owner:getVehiclePose(screen.vehicle)
    local box=TGGPSGreenStar.MAP_BOX
    local function rect(style,x,y,w,h,layer)
        screen:quad(style,(box.x+(x+w/2)*box.w-.5)*screen.WIDTH,
            (box.y+(y+h/2)*box.h-.5)*screen.HEIGHT,w*box.w*screen.WIDTH,h*box.h*screen.HEIGHT,0,layer)
    end
    rect('guidanceGround',0,0,1,1,0)
    -- Blue orientation view: all coordinates and paint remain world based.
    if not pose then return end
    local function segment(style,a,b,layer)
        local ax=(a.x-pose.x)*pose.dx+(a.z-pose.z)*pose.dz
        local bx=(b.x-pose.x)*pose.dx+(b.z-pose.z)*pose.dz
        local lo,hi=0,1
        if math.abs(bx-ax)<1e-9 then if ax< -10 or ax>160 then return end
        else
            local t1,t2=(-10-ax)/(bx-ax),(160-ax)/(bx-ax)
            lo,hi=math.max(0,math.min(t1,t2)),math.min(1,math.max(t1,t2))
            if lo>hi then return end
        end
        local x,y=TGGPSPerspective.project(pose,a.x+(b.x-a.x)*lo,a.z+(b.z-a.z)*lo)
        local u,v=TGGPSPerspective.project(pose,a.x+(b.x-a.x)*hi,a.z+(b.z-a.z)*hi)
        if not x or not u then return end
        x,y,u,v=clip(x,y,u,v);if not x then return end
        local dx,dy=(u-x)*box.w*screen.WIDTH,(v-y)*box.h*screen.HEIGHT
        screen:quad(style,(box.x+(x+u)/2*box.w-.5)*screen.WIDTH,
            (box.y+(y+v)/2*box.h-.5)*screen.HEIGHT,math.sqrt(dx*dx+dy*dy),.00055,math.atan2(dy,dx),layer or 4)
    end
    -- The grid is unique in world space; opaque strips avoid accumulating alpha
    -- when adjacent projected cells meet. Real second passes use darker blue.
    if owner.coverage then
        local cells=owner.coverage:getMapCells(pose.x-100,pose.z-100,pose.x+100,pose.z+100,80)
        for _,cell in ipairs(cells) do
            local x,y=TGGPSPerspective.project(pose,cell.x+cell.w/2,cell.z+cell.h/2)
            if x then
                local corners={{cell.x,cell.z},{cell.x+cell.w,cell.z},{cell.x+cell.w,cell.z+cell.h},{cell.x,cell.z+cell.h}}
                local points={}
                for _,p in ipairs(corners) do
                    local u,v=TGGPSPerspective.project(pose,p[1],p[2])
                    if u then points[#points+1]={x=u,y=v} end
                end
                if #points==4 then
                    local bottom,top=1,0
                    for _,p in ipairs(points) do bottom=math.min(bottom,p.y);top=math.max(top,p.y) end
                    for row=0,2 do
                        local y1,y2=bottom+(top-bottom)*row/3,bottom+(top-bottom)*(row+1)/3
                        local middle=(y1+y2)/2
                        local left,right=math.huge,-math.huge
                        for i,p in ipairs(points) do
                            local q=points[i%4+1]
                            if (p.y<=middle and q.y>middle) or (q.y<=middle and p.y>middle) then
                                local at=p.x+(middle-p.y)*(q.x-p.x)/(q.y-p.y)
                                left,right=math.min(left,at),math.max(right,at)
                            end
                        end
                        left,right=clamp(left,0,1),clamp(right,0,1)
                        y1,y2=clamp(y1,0,.93),clamp(y2,0,.93)
                        if right>left and y2>y1 then rect(cell.overlap and 'guidanceOverlap' or 'guidancePaint',left,y1,right-left,y2-y1,2) end
                    end
                end
            end
        end
    end
    for offset=-4,4 do
        local lane=(owner.currentLane or 0)+offset
        local sections=owner:getLaneSections(lane)
        for _,path in ipairs(sections or {}) do
            local stride=math.max(1,math.ceil((#path-1)/20))
            for i=1,#path-1,stride do segment(offset==0 and 'guidanceSelected' or 'guidanceLane',path[i],path[math.min(#path,i+stride)],4) end
        end
    end
    local boundary=owner.fieldBoundary or (owner.recognition and owner.recognition.boundary)
    if boundary then
        local stride=math.max(1,math.ceil(#boundary/32))
        for i=1,#boundary,stride do segment('boundary',boundary[i],boundary[(math.min(#boundary,i+stride-1)%#boundary)+1],4) end
    end
    local context=owner:getMonitorContext()
    local footprint=owner.coverage and owner.coverage.footprint
    if footprint then
        local half=(footprint.width or owner.width or 6)/2
        local rx,rz=footprint.rx or pose.dz,footprint.rz or -pose.dx
        segment('guidancePaint',{x=footprint.x-rx*half,z=footprint.z-rz*half},
            {x=footprint.x+rx*half,z=footprint.z+rz*half},6)
    end
    local kind=context.kind=='combine' and (context.implement and context.implement.spec_cutter and 'combine_cutter' or 'combine') or 'tractor'
    screen:quad('symbol_'..kind,(box.x+.5*box.w-.5)*screen.WIDTH,
        (box.y+(.95-22/35)*box.h-.5)*screen.HEIGHT,.025,.025,
        -(owner.steeringCommand or 0)*.12,7)
end
