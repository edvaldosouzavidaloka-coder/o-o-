-- Bounded parallel curves, analytically clipped to the same polygon/headland
-- contract as straight field lanes. The recorded curve remains the reference.
TGFieldCurves={}
function TGFieldCurves.generate(owner,boundary,reference,width,offset,margin)
    if type(reference)~='table' or #reference<2 then return nil,'curve_required' end
    if type(width)~='number' or width<1 or width>50 then return nil,'invalid_width' end
    local base=owner:smoothPath(reference,2.0)
    if #base>1500 then return nil,'geometry_too_complex' end
    local a,b=base[1],base[2]
    local dx,dz=b.x-a.x,b.z-a.z
    if dx*dx+dz*dz<0.000001 then return nil,'invalid_direction' end
    local checked,reason=TGFieldBoundary.generateLanes(boundary,a,{dx=dx,dz=dz},width)
    if not checked then return nil,reason end
    local minX,maxX,minZ,maxZ=math.huge,-math.huge,math.huge,-math.huge
    for _,p in ipairs(boundary) do minX=math.min(minX,p.x);maxX=math.max(maxX,p.x);minZ=math.min(minZ,p.z);maxZ=math.max(maxZ,p.z) end
    local span=math.sqrt((maxX-minX)^2+(maxZ-minZ)^2)
    local function extend(p,q)
        local x,z=p.x-q.x,p.z-q.z;local length=math.sqrt(x*x+z*z)
        if length<0.00001 then return {x=p.x,z=p.z} end
        local distance=span+math.sqrt((p.x-(minX+maxX)/2)^2+(p.z-(minZ+maxZ)/2)^2)
        return {x=p.x+x/length*distance,z=p.z+z/length*distance}
    end
    local first=extend(base[1],base[2]);local last=extend(base[#base],base[#base-1])
    table.insert(base,1,first);base[#base+1]=last
    local low,high=0,0
    for i=1,#base-1 do
        local p,q=base[i],base[i+1]
        local vx,vz=q.x-p.x,q.z-p.z;local length=math.sqrt(vx*vx+vz*vz)
        if length>0.00001 then for _,v in ipairs(boundary) do
            local s=(-vz*(v.x-p.x)+vx*(v.z-p.z))/length
            low,high=math.min(low,s),math.max(high,s)
        end end
    end
    local minLane,maxLane=math.floor((low-(offset or 0))/width)-1,math.ceil((high-(offset or 0))/width)+1
    if maxLane-minLane+1>400 or (maxLane-minLane+1)*(#base-1)*#boundary>2000000 then return nil,'geometry_too_complex' end
    local lanes={}
    for lane=minLane,maxLane do
        local shifted=owner:offsetPath(base,lane*width+(offset or 0))
        local sections,current={},nil
        for i=1,#shifted-1 do
            local p,q=shifted[i],shifted[i+1]
            local a,b=base[i],base[i+1]
            if (q.x-p.x)*(b.x-a.x)+(q.z-p.z)*(b.z-a.z)>0.000001 then
                if not current then current={p};sections[#sections+1]=current end
                current[#current+1]=q
            else current=nil end
        end
        lanes[lane]=sections
    end
    local clipped,why=TGHeadlandGeometry.clipPolylines(lanes,boundary,margin or 0)
    if clipped then clipped.basePath=base end
    return clipped,why
end
