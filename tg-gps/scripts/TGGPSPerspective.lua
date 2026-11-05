-- Ground-plane guidance for the physical GreenStar display. No PDA is loaded.
TGGPSPerspective={}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function TGGPSPerspective.project(pose,x,z)
    local dx,dz=x-pose.x,z-pose.z
    local right=dx*pose.dz-dz*pose.dx
    local forward=dx*pose.dx+dz*pose.dz
    if forward < -10.000001 or forward>160.000001 then return nil end
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
-- Project continuous work-area edges before scan conversion. Keep fractional
-- horizontal boundaries, unioning spans so adjacent triangles never double-paint.
function TGGPSPerspective.paintStrips(pose,shapes,rows,budget,restrictOverlap)
    local polygons={};local exact=false
    for _,shape in ipairs(shapes) do
        local source=shape.points or {{x=shape.x,z=shape.z},{x=shape.x+shape.w,z=shape.z},
            {x=shape.x+shape.w,z=shape.z+shape.h},{x=shape.x,z=shape.z+shape.h}}
        -- Clip in WORLD space first; geometry crossing the near plane must not
        -- disappear, and geometry behind the machine must not fold over itself.
        for _,cut in ipairs({{-10,true},{160,false}}) do
            local clipped={};local a=source[#source]
            local function depth(p) return (p.x-pose.x)*pose.dx+(p.z-pose.z)*pose.dz end
            if a then
                local da=depth(a);local ia=cut[2] and da>=cut[1] or not cut[2] and da<=cut[1]
                for _,b in ipairs(source) do
                    local db=depth(b);local ib=cut[2] and db>=cut[1] or not cut[2] and db<=cut[1]
                    if ia~=ib then
                        local t=(cut[1]-da)/(db-da)
                        clipped[#clipped+1]={x=a.x+(b.x-a.x)*t,z=a.z+(b.z-a.z)*t}
                    end
                    if ib then clipped[#clipped+1]=b end
                    a,da,ia=b,db,ib
                end
            end
            source=clipped
        end
        local polygon={}
        for _,p in ipairs(source) do
            local x,y=TGGPSPerspective.project(pose,p.x,p.z)
            if x then polygon[#polygon+1]={x=x,y=y} end
        end
        if #polygon>=3 then
            polygons[#polygons+1]={points=polygon,overlap=shape.overlap==true,exact=shape.points~=nil}
            exact=exact or shape.points~=nil
        end
    end
    local result
    repeat
        result={}
        for row=0,rows-1 do
            local y=(row+.5)*.93/rows;local spans={}
            for _,polygon in ipairs(polygons) do
                local hits={};local a=polygon.points[#polygon.points]
                for _,b in ipairs(polygon.points) do
                    if (a.y<=y and b.y>y) or (b.y<=y and a.y>y) then hits[#hits+1]=a.x+(y-a.y)*(b.x-a.x)/(b.y-a.y) end
                    a=b
                end
                table.sort(hits)
                for i=1,#hits-1,2 do
                    local left,right=clamp(hits[i],0,1),clamp(hits[i+1],0,1)
                    if right>left then spans[#spans+1]={left,right,polygon.overlap,polygon.exact} end
                end
            end
            -- Resolve true overlap independently of draw order, preserving
            -- exact fractional x edges instead of snapping to a coarse grid.
            local edges={}
            for _,span in ipairs(spans) do edges[#edges+1]=span[1];edges[#edges+1]=span[2] end
            table.sort(edges)
            local active
            for i=1,#edges-1 do
                local left,right=edges[i],edges[i+1]
                if right-left>1e-9 then
                    local middle=(left+right)/2;local covered,overlap,precise=false,false,false
                    for _,span in ipairs(spans) do
                        if middle>=span[1] and middle<=span[2] then
                            covered=true;overlap=overlap or span[3];precise=precise or span[4]
                        end
                    end
                    if restrictOverlap and exact and not precise then covered=false end
                    if covered then
                        if active and active.overlap==overlap and math.abs(active.x+active.w-left)<1e-8 then active.w=right-active.x
                        else active={x=left,y=row*.93/rows,w=right-left,h=.93/rows,overlap=overlap};result[#result+1]=active end
                    else active=nil end
                end
            end
        end
        rows=math.max(1,math.floor(rows/2))
    until #result<=budget or rows==1
    return result
end

-- Merge scan spans into sloped polygons. A straight worked strip becomes one
-- trapezoid, drawn as triangles, rather than hundreds of visible rectangular steps.
function TGGPSPerspective.smoothPaint(strips)
    local groups={};local active={}
    for _,strip in ipairs(strips) do
        local middle=strip.y+strip.h/2;local match
        for _,g in ipairs(active) do
            if g.overlap==strip.overlap and math.abs(g.top-strip.y)<1e-8 then
                local delta=middle-g.middle
                if g.slopeL==nil then
                    if math.min(g.right,strip.x+strip.w)>math.max(g.left,strip.x) then match=g;break end
                elseif math.abs(g.left+g.slopeL*delta-strip.x)<1e-7
                    and math.abs(g.right+g.slopeR*delta-strip.x-strip.w)<1e-7 then match=g;break end
            end
        end
        if match then
            local delta=middle-match.middle
            if match.slopeL==nil then
                match.slopeL=(strip.x-match.left)/delta;match.slopeR=(strip.x+strip.w-match.right)/delta
                match.bottomL=match.firstL-match.slopeL*match.half
                match.bottomR=match.firstR-match.slopeR*match.half
            end
            match.top=strip.y+strip.h;match.left=strip.x;match.right=strip.x+strip.w;match.middle=middle
            match.topL=strip.x+(match.slopeL or 0)*strip.h/2
            match.topR=strip.x+strip.w+(match.slopeR or 0)*strip.h/2
        else
            match={bottom=strip.y,top=strip.y+strip.h,middle=middle,left=strip.x,right=strip.x+strip.w,
                firstL=strip.x,firstR=strip.x+strip.w,bottomL=strip.x,bottomR=strip.x+strip.w,
                topL=strip.x,topR=strip.x+strip.w,half=strip.h/2,overlap=strip.overlap}
            groups[#groups+1]=match;active[#active+1]=match
        end
        for i=#active,1,-1 do if active[i].top<strip.y-1e-8 then table.remove(active,i) end end
    end
    return groups
end

function TGGPSPerspective.paintPolygon(screen,points,overlap)
    local box=TGGPSGreenStar.MAP_BOX;local transformed={}
    for _,p in ipairs(points) do transformed[#transformed+1]={
        x=(box.x+clamp(p.x,0,1)*box.w-.5)*screen.WIDTH,
        y=(box.y+clamp(p.y,0,.95)*box.h-.5)*screen.HEIGHT} end
    local prefix=overlap and 'paintOverlap' or 'paintBlue'
    local function triangle(a,b,c)
        local function sq(p,q) return (p.x-q.x)^2+(p.y-q.y)^2 end
        if sq(a,c)>sq(a,b) and sq(a,c)>=sq(b,c) then b,c=c,b
        elseif sq(b,c)>sq(a,b) then a,b,c=b,c,a end
        local cross=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
        if cross<0 then a,b=b,a;cross=-cross end
        local dx,dy=b.x-a.x,b.y-a.y;local length=math.sqrt(dx*dx+dy*dy)
        if length<1e-9 or cross<1e-12 then return end
        local t=clamp(((c.x-a.x)*dx+(c.y-a.y)*dy)/(length*length),0,1)
        local x,y=a.x+t*dx,a.y+t*dy
        local angle=math.atan2(dy,dx);local height=cross/length
        screen:quad(prefix..'L',x,y,t*length,height,angle,2)
        screen:quad(prefix..'R',x,y,(1-t)*length,height,angle,2)
    end
    for i=2,#transformed-1 do triangle(transformed[1],transformed[i],transformed[i+1]) end
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
    for offset=-12,12 do
        local x=math.floor(pose.x/10)*10+offset*10
        local z=math.floor(pose.z/10)*10+offset*10
        segment('guidanceGrid',{x=x,z=pose.z-170},{x=x,z=pose.z+170},1)
        segment('guidanceGrid',{x=pose.x-170,z=z},{x=pose.x+170,z=z},1)
    end
    if owner.coverage then
        local shapes=owner.coverage:getMapVisuals(pose.x-180,pose.z-180,pose.x+180,pose.z+180)
        local strips=TGGPSPerspective.paintStrips(pose,shapes,512,6000,not owner.coverage.coverageGeometryPruned)
        for _,g in ipairs(TGGPSPerspective.smoothPaint(strips)) do
            TGGPSPerspective.paintPolygon(screen,{{x=g.bottomL,y=g.bottom},{x=g.bottomR,y=g.bottom},
                {x=g.topR,y=g.top},{x=g.topL,y=g.top}},g.overlap)
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
