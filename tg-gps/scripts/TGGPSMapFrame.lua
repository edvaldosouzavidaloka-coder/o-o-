-- One local map frame for the PDA, paint, guidance and machine icon.
-- Vehicle-up and bounded LCD refresh follow the supplied CurveGPS monitor's
-- organization; all transforms here belong to TG GPS and never change guidance.
TGGPSMapFrame = {}
TGGPSMapFrame.__index = TGGPSMapFrame
TGGPSMapFrame.ASPECT = 2
TGGPSMapFrame.INTERVAL_MS = 250

local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local rasterCache=setmetatable({}, {__mode='k'})

local function fitStrips(frame,strips)
    local result={}
    for _,r in ipairs(strips) do result[#result+1]={x=frame.box.x+r.x*frame.box.w,
        y=frame.box.y+r.y*frame.box.h,w=r.w*frame.box.w,h=r.h*frame.box.h,role=r.role} end
    return result
end

function TGGPSMapFrame.new(owner,box,sw,sh,pose,centerX,centerZ)
    local up=owner.mapVehicleUp~=false
    local fx,fz=0,1
    if up and pose and finite(pose.dx) and finite(pose.dz) then
        local length=math.sqrt(pose.dx*pose.dx+pose.dz*pose.dz)
        if length>0.000001 then fx,fz=pose.dx/length,pose.dz/length end
    end
    local x,z=pose and pose.x or centerX,pose and pose.z or centerZ
    local zoom=TGGPSMap.getZoom(owner)
    local width=clamp((owner.width or 6)*10.5,42,180)/zoom
    local vehicle=type(owner.getControlledVehicle)=='function' and owner:getControlledVehicle() or nil
    local old=owner.mapViewport
    local now=owner.mapTime
    local settingChanged=not old or old.up~=up or old.width~=width or old.vehicle~=vehicle
    local due=now==nil or not old or old.time==nil or now-old.time>=TGGPSMapFrame.INTERVAL_MS
    if settingChanged or due then
        -- Suppress idle vibration without snapping a moving machine to a grid.
        local moved=not old or (x-old.x)^2+(z-old.z)^2>0.05^2
            or fx*old.fx+fz*old.fz<math.cos(math.rad(0.1))
        if settingChanged or moved then
            old={x=x,z=z,fx=fx,fz=fz,up=up,width=width,vehicle=vehicle,time=now}
            owner.mapViewport=old
        elseif old then old.time=now end
    end
    local fitted={x=box.x,y=box.y,w=box.w,h=box.h}
    local aspect=box.w*sw/(box.h*sh)
    if aspect>TGGPSMapFrame.ASPECT then
        fitted.w=box.h*sh*TGGPSMapFrame.ASPECT/sw
        fitted.x=box.x+(box.w-fitted.w)/2
    else
        fitted.h=box.w*sw/(TGGPSMapFrame.ASPECT*sh)
        fitted.y=box.y+(box.h-fitted.h)/2
    end
    local self=setmetatable({box=fitted,sw=sw,sh=sh,x=old.x,z=old.z,fx=old.fx,fz=old.fz,
        rx=old.fz,rz=-old.fx,spanX=width,spanZ=width/TGGPSMapFrame.ASPECT,vehicleUp=up},TGGPSMapFrame)
    self.pixelsPerMetre=fitted.w*sw/width
    self.worldBounds={math.huge,math.huge,-math.huge,-math.huge}
    for _,p in ipairs({{0,0},{0,1},{1,0},{1,1}}) do
        local wx,wz=self:worldAt(p[1],p[2])
        self.worldBounds[1]=math.min(self.worldBounds[1],wx);self.worldBounds[2]=math.min(self.worldBounds[2],wz)
        self.worldBounds[3]=math.max(self.worldBounds[3],wx);self.worldBounds[4]=math.max(self.worldBounds[4],wz)
    end
    return self
end

function TGGPSMapFrame:localAt(wx,wz)
    local dx,dz=wx-self.x,wz-self.z
    return 0.5+(dx*self.rx+dz*self.rz)/self.spanX,0.5+(dx*self.fx+dz*self.fz)/self.spanZ
end
function TGGPSMapFrame:project(point)
    local u,v=self:localAt(point.x,point.z)
    return self.box.x+u*self.box.w,self.box.y+v*self.box.h
end
function TGGPSMapFrame:worldAt(u,v)
    local right,forward=(u-0.5)*self.spanX,(v-0.5)*self.spanZ
    return self.x+right*self.rx+forward*self.fx,self.z+right*self.rz+forward*self.fz
end

local function slice(polygon,y,above)
    local result={}
    local a=polygon[#polygon]
    if not a then return result end
    local insideA=above and a.y>=y or (not above and a.y<=y)
    for _,b in ipairs(polygon) do
        local insideB=above and b.y>=y or (not above and b.y<=y)
        if insideA~=insideB then
            local t=(y-a.y)/(b.y-a.y)
            result[#result+1]={x=a.x+(b.x-a.x)*t,y=y}
        end
        if insideB then result[#result+1]=b end
        a,insideA=b,insideB
    end
    return result
end

-- Rasterize rotated WORLD rectangles into clipped horizontal LCD strips. The
-- stored paint stays in world coordinates; only this bounded display is sampled.
-- Shared edges touch, and no rotated quad can protrude into the terminal cards.
function TGGPSMapFrame:rasterize(cells,budget,fieldColors)
    local columns,rows=96,48
    local result
    budget=math.max(4,budget or 1200)
    local cacheKey=tostring(budget)..(fieldColors and ':field' or ':paint')
    local cache=rasterCache[cells] or {}
    rasterCache[cells]=cache
    local old=cache[cacheKey]
    if old and old.x==self.x and old.z==self.z and old.fx==self.fx and old.fz==self.fz
        and old.spanX==self.spanX and old.spanZ==self.spanZ then return fitStrips(self,old.strips) end
    repeat
        local grid={}
        for _,cell in ipairs(cells) do
            local polygon={}
            local lo,hi=math.huge,-math.huge
            for _,p in ipairs({{cell.x,cell.z},{cell.x+cell.w,cell.z},{cell.x+cell.w,cell.z+cell.h},{cell.x,cell.z+cell.h}}) do
                local u,v=self:localAt(p[1],p[2])
                local y=v*rows
                polygon[#polygon+1]={x=u*columns,y=y};lo=math.min(lo,y);hi=math.max(hi,y)
            end
            local role=fieldColors and (cell.role=='headland' and 2 or 1) or (cell.overlap and 2 or 1)
            for row=math.max(0,math.floor(lo)),math.min(rows-1,math.ceil(hi)-1) do
                local strip=slice(slice(polygon,row,true),row+1,false)
                local left,right=math.huge,-math.huge
                for _,p in ipairs(strip) do left=math.min(left,p.x);right=math.max(right,p.x) end
                local first,last=math.max(0,math.floor(left+0.0000001)),math.min(columns-1,math.ceil(right-0.0000001)-1)
                if first<=last then
                    grid[row]=grid[row] or {}
                    for col=first,last do grid[row][col]=math.max(grid[row][col] or 0,role) end
                end
            end
        end
        result={}
        for row=0,rows-1 do
            local values,active,first=grid[row] or {},nil,0
            for col=0,columns do
                local role=col<columns and values[col] or nil
                if role~=active then
                    if active then result[#result+1]={x=first/columns,
                        y=row/rows,w=(col-first)/columns,h=1/rows,
                        role=fieldColors and (active==2 and 'headland' or 'field') or (active==2 and 'coverage_overlap' or 'coverage')}
                    end
                    active,first=role,col
                end
            end
        end
        columns,rows=math.max(1,math.floor(columns/2)),math.max(1,math.floor(rows/2))
    until #result<=budget
    cache[cacheKey]={x=self.x,z=self.z,fx=self.fx,fz=self.fz,spanX=self.spanX,spanZ=self.spanZ,strips=result}
    return fitStrips(self,result)
end
