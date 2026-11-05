-- Adapter for the uploaded GIANTS 10 GreenStar 3 model. The binary case,
-- display and DDS remain original. The outer pivot alone normalizes cab axes.
TGGPSGreenStar = {}
TGGPSGreenStar.__index = TGGPSGreenStar
TGGPSGreenStar.BOOT_MS = 1800
TGGPSGreenStar.MAP_BOX = {x=14/1024,y=323/1024,w=744/1024,h=414/1024}

local function valid(n) return n~=nil and n~=0 end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
function TGGPSGreenStar.find(node,name)
    if not valid(node) then return nil end
    if getName(node)==name then return node end
    for i=0,getNumOfChildren(node)-1 do
        local found=TGGPSGreenStar.find(getChildAt(node,i),name)
        if found then return found end
    end
end

function TGGPSGreenStar.prepare(model)
    local root=TGGPSGreenStar.find(model,'MonitorRoot')
    local pivot=TGGPSGreenStar.find(model,'GreenStarModel')
    local screen=TGGPSGreenStar.find(model,'MonitorScreen')
    if not root or not pivot or not screen or not getShapeGeometryBoundingSphere
        or not worldDirectionToLocal or not localToLocal or not setDirection then return nil end
    local x,y,z,r=getShapeGeometryBoundingSphere(screen)
    if not finite(x) or not finite(y) or not finite(z) or not finite(r) or r<0.02 or r>0.75 then return nil end
    -- An unloaded I3D root is still in world identity. Invert the actual native
    -- display basis before parenting the model to any vehicle/camera hierarchy.
    local dx,dy,dz=worldDirectionToLocal(screen,0,0,1)
    local ux,uy,uz=worldDirectionToLocal(screen,0,1,0)
    setDirection(pivot,dx,dy,dz,ux,uy,uz)
    local cx,cy,cz=localToLocal(screen,root,x,y,z)
    setTranslation(pivot,-cx,-cy,-cz)
    -- The supplied GreenStar display is a 4:3 LCD; its diagonal is read from
    -- the actual binary mesh. This avoids applying the old tablet's dimensions.
    return {root=root,screen=screen,width=r*1.6,height=r*1.2}
end

function TGGPSGreenStar.new(owner,model,vehicle,layout,directory,content)
    local self=setmetatable({owner=owner,vehicle=vehicle,layout=layout,content=content,
        screen=layout.screen,boot=TGGPSGreenStar.find(model,'GreenStarBoot'),
        light=TGGPSGreenStar.find(model,'light'),state='off',elapsed=0,angle=0},TGGPSGreenStar)
    local overlay=loadI3DFile(directory..'models/tgGreenStarOverlay.i3d',false,false,false)
    if not valid(overlay) then return nil end
    link(layout.root,overlay);setScale(overlay,layout.width,layout.height,1)
    self.overlay=overlay
    self.controls=TGGPSGreenStar.find(overlay,'GreenStarOriginalControls')
    self.bootProgress=TGGPSGreenStar.find(overlay,'GreenStarBootProgress')
    self.fill=TGGPSGreenStar.find(overlay,'BootProgressFill')
    self.workRing=TGGPSGreenStar.find(overlay,'GreenStarWorkRing')
    self.bootRing=TGGPSGreenStar.find(overlay,'GreenStarBootRing')
    if not self.boot or not self.controls or not self.bootProgress or not self.fill or not self.workRing or not self.bootRing then
        delete(overlay);return nil
    end
    self:update(0)
    return self
end

function TGGPSGreenStar:update(dt)
    dt=math.max(0,dt or 0)
    local on=self.vehicle.getIsMotorStarted==nil or self.vehicle:getIsMotorStarted()
    local previous=self.state
    if not on then self.state,self.elapsed='off',0
    elseif self.state=='off' then self.state,self.elapsed='boot',0
    else
        self.elapsed=math.min(TGGPSGreenStar.BOOT_MS,self.elapsed+dt)
        if self.elapsed>=TGGPSGreenStar.BOOT_MS then self.state='ready' end
    end
    if self.owner.audio and previous~=self.state then
        if self.state=='ready' then self.owner.audio:play('connect')
        elseif self.state=='off' and previous~='off' then self.owner.audio:play('disconnect') end
    end
    local ready,booting=self.state=='ready',self.state=='boot'
    setVisibility(self.screen,ready);setVisibility(self.boot,booting)
    setVisibility(self.controls,ready);setVisibility(self.bootProgress,booting)
    setVisibility(self.content,not booting)
    if valid(self.light) then setVisibility(self.light,ready) end
    self.progress=math.min(1,self.elapsed/TGGPSGreenStar.BOOT_MS)
    local width=222/512*self.progress
    setScale(self.fill,math.max(0.00001,width),30/512,1)
    setTranslation(self.fill,155/512-.5+width/2,.5-278/512,0.008)
    local coverage=self.owner.coverage
    local speed=self.vehicle.getLastSpeed and self.vehicle:getLastSpeed() or 0
    self.working=ready and coverage~=nil and coverage.working==true and math.abs(speed)>0.2
    setVisibility(self.workRing,self.working)
    if booting or self.working then self.angle=(self.angle-math.rad(350)*dt/1000)%(2*math.pi) end
    setRotation(self.workRing,0,0,self.angle);setRotation(self.bootRing,0,0,self.angle)
end

function TGGPSGreenStar:delete()
    if valid(self.overlay) then delete(self.overlay) end
    self.overlay=nil
end
