-- One inset perimeter reference. No speed, lifting or automatic headland turn.
TGBorder={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e7 end
local function cross(x,z,u,v) return x*v-z*u end
local function length(path)
    local n=0
    for i=2,#path do n=n+math.sqrt((path[i].x-path[i-1].x)^2+(path[i].z-path[i-1].z)^2) end
    return n
end
function TGBorder.create(boundary,offset)
    if type(boundary)~='table' or #boundary<3 or not finite(offset) or offset<=0 then return nil,'invalid_polygon' end
    local points={}
    for _,p in ipairs(boundary) do
        if not finite(p.x) or not finite(p.z) then return nil,'invalid_polygon' end
        local last=points[#points]
        if not last or (p.x-last.x)^2+(p.z-last.z)^2>.000001 then points[#points+1]={x=p.x,z=p.z} end
    end
    if #points>3 and (points[1].x-points[#points].x)^2+(points[1].z-points[#points].z)^2<.000001 then table.remove(points) end
    local changed=true
    while changed and #points>3 do
        changed=false
        for i=#points,1,-1 do
            local a,b,c=points[(i-2)%#points+1],points[i],points[i%#points+1]
            local dx,dz=c.x-a.x,c.z-a.z;local square=dx*dx+dz*dz
            if square>0 then
                local t=((b.x-a.x)*dx+(b.z-a.z)*dz)/square
                if t>0 and t<1 and math.abs(cross(dx,dz,b.x-a.x,b.z-a.z))/math.sqrt(square)<.005 then
                    table.remove(points,i);changed=true;break
                end
            end
        end
    end
    if #points>500 then return nil,'geometry_too_complex' end
    local area=0
    for i,p in ipairs(points) do local q=points[i%#points+1];area=area+p.x*q.z-q.x*p.z end
    if math.abs(area)<.001 then return nil,'invalid_polygon' end
    local sign=area>0 and 1 or -1
    local edges={}
    for i,p in ipairs(points) do
        local q=points[i%#points+1];local dx,dz=q.x-p.x,q.z-p.z
        local size=math.sqrt(dx*dx+dz*dz)
        if size<.001 then return nil,'invalid_polygon' end
        edges[i]={dx=dx/size,dz=dz/size,nx=-dz/size*sign,nz=dx/size*sign}
    end
    local result={}
    for i,p in ipairs(points) do
        local a,b=edges[(i-2)%#points+1],edges[i]
        local denominator=cross(a.dx,a.dz,b.dx,b.dz)
        local x,z=p.x+b.nx*offset,p.z+b.nz*offset
        if math.abs(denominator)>1e-8 then
            local t=cross((b.nx-a.nx)*offset,(b.nz-a.nz)*offset,b.dx,b.dz)/denominator
            x,z=p.x+a.nx*offset+a.dx*t,p.z+a.nz*offset+a.dz*t
        end
        if not finite(x) or not finite(z) or not TGHeadlandGeometry.contains(points,{x=x,z=z},offset-.001) then
            return nil,'field_too_narrow'
        end
        result[#result+1]={x=x,z=z}
    end
    result[#result+1]={x=result[1].x,z=result[1].z}
    -- Reject loops or a bridge across a concave gap rather than drawing a false
    -- perimeter. Native analytic clipping checks every point of every segment.
    for i=1,#result-1 do
        for j=i+2,#result-1 do
            if not (i==1 and j==#result-1) then
                local a,b,c,d=result[i],result[i+1],result[j],result[j+1]
                local den=cross(b.x-a.x,b.z-a.z,d.x-c.x,d.z-c.z)
                if math.abs(den)>1e-9 then
                    local t=cross(c.x-a.x,c.z-a.z,d.x-c.x,d.z-c.z)/den
                    local u=cross(c.x-a.x,c.z-a.z,b.x-a.x,b.z-a.z)/den
                    if t>=0 and t<=1 and u>=0 and u<=1 then return nil,'field_too_narrow' end
                end
            end
        end
    end
    local clipped=TGHeadlandGeometry.clipPolylines({[0]={result}},points,math.max(0,offset-.001))
    if not clipped or not clipped.lanes[0] or #clipped.lanes[0]~=1
        or math.abs(length(clipped.lanes[0][1])-length(result))>.01 then return nil,'field_too_narrow' end
    return result
end

function TGGPS:onGenerateBorder()
    self:syncWorkingWidth()
    local vehicle=self:getControlledVehicle()
    local pose=vehicle and self:getVehiclePose(vehicle)
    if not pose then self:notify('Entre na maquina para gerar a bordadura');return false end
    local boundary,reason=TGFieldBoundary.getAt(pose.x,pose.z)
    if not boundary then self:notify('Contorno do talhao indisponivel: '..tostring(reason));return false end
    local width=TGGPSWidthProfiles.detect(vehicle) or self.width
    local path,problem=TGBorder.create(boundary,width/2)
    if not path then self:notify('Bordadura recusada: talhao estreito ou contorno complexo ('..tostring(problem)..')');return false end
    self:stopAutosteer();self.headlandEnabled=false;self.turnState=nil
    self.width=width
    if self.widthProfiles then self.widthProfiles:remember(width) end
    self.mode,self.fieldBoundary,self.sourcePoints='border',boundary,path
    self.activeCourseName='Bordadura - '..self:getMonitorContext().fieldName
    self.fieldCurveReference=nil;self.trackOffset=0;self.currentLane=0;self.currentSection=1
    self.autoLaneSelection=false;self.isRecording=false;self.pointA=nil
    self:rebuildGuidance()
    self:notify(string.format('Bordadura criada: centro da linha %.2f m dentro do talhao',width/2))
    return true
end

function TGGPS:onReverseBorder()
    if self.mode~='border' or not self.fieldBoundary then return end
    self:stopAutosteer()
    local points={}
    for i=#self.fieldBoundary,1,-1 do points[#points+1]=self.fieldBoundary[i] end
    self.fieldBoundary=points;self:rebuildGuidance()
    self:notify('Sentido da bordadura invertido')
end
