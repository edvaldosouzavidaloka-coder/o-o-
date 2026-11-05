-- Read-only recognition for the monitor. Native field polygons are observed;
-- route generation, implement activation and steering still require TG controls.
TGGPSRecognition = {}
TGGPSRecognition.__index = TGGPSRecognition

local function samePolygon(a,b)
    if not a or not b or #a~=#b then return false end
    for i,p in ipairs(a) do if p.x~=b[i].x or p.z~=b[i].z then return false end end
    return true
end

function TGGPSRecognition.new(owner)
    return setmetatable({owner=owner,timer=1000},TGGPSRecognition)
end

function TGGPSRecognition.measure(boundary,pose)
    if not boundary or #boundary<3 or not pose then return nil,nil,false end
    local nearest,forward,inside=math.huge,math.huge,false
    for i,a in ipairs(boundary) do
        local b=boundary[i%#boundary+1]
        local dx,dz=b.x-a.x,b.z-a.z
        local square=dx*dx+dz*dz
        local t=square>0 and math.max(0,math.min(1,((pose.x-a.x)*dx+(pose.z-a.z)*dz)/square)) or 0
        nearest=math.min(nearest,math.sqrt((pose.x-a.x-t*dx)^2+(pose.z-a.z-t*dz)^2))
        if (a.z>pose.z)~=(b.z>pose.z) and pose.x<(b.x-a.x)*(pose.z-a.z)/(b.z-a.z)+a.x then inside=not inside end
        local fx,fz=pose.dx or 0,pose.dz or 1
        local cross=fx*dz-fz*dx
        if math.abs(cross)>0.000001 then
            local ax,az=a.x-pose.x,a.z-pose.z
            local distance=(ax*dz-az*dx)/cross
            local edge=(ax*fz-az*fx)/cross
            if distance>=0 and edge>=0 and edge<=1 then forward=math.min(forward,distance) end
        end
    end
    return nearest,forward<math.huge and forward or nil,inside
end

function TGGPSRecognition:update(dt)
    self.timer=self.timer+math.max(0,dt or 0)
    local vehicle=self.owner:getControlledVehicle()
    if vehicle==nil or not vehicle.tgGpsSupported then
        self.vehicle,self.boundary,self.state=nil,nil,nil;self.timer=1000;return
    end
    local context=self.owner:getMonitorContext()
    if self.vehicle~=vehicle or self.fieldId~=context.fieldId or self.timer>=1000 then
        self.timer,self.vehicle,self.fieldId=0,vehicle,context.fieldId
        local pose=self.owner:getVehiclePose(vehicle)
        local polygon,id
        if pose then polygon,id=TGFieldBoundary.getAt(pose.x,pose.z) end
        if not samePolygon(self.boundary,polygon) then self.boundary=polygon end
        self.polygonId,self.reason=polygon and id or nil,not polygon and id or nil
    end
    local pose=self.owner:getVehiclePose(vehicle)
    local distance,forward,inside=self.measure(self.boundary,pose)
    local depth=math.max(0,self.owner.headlandDepth or 18)
    self.state={vehicle=vehicle,kind=context.kind,machineName=context.machineName,implement=context.implement,
        width=self.owner.width,pose=pose,fieldId=self.polygonId,boundary=self.boundary,
        borderDistance=distance,forwardDistance=forward,inField=inside,
        nearHeadland=inside and distance~=nil and distance<=depth,reason=self.reason}
end
