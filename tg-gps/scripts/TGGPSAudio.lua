-- Local two-dimensional terminal cues. No sound-template or vehicle overrides.
TGGPSAudio = {}
TGGPSAudio.__index = TGGPSAudio

function TGGPSAudio.new(owner, directory)
    local self=setmetatable({owner=owner,samples={},clock=0,lastTime=-10000},TGGPSAudio)
    if createSample==nil or loadSample==nil or playSample==nil or g_dedicatedServer~=nil then return self end
    for _,name in ipairs({'connect','disconnect'}) do
        local sample=createSample('TGGPS_'..name)
        if sample~=nil and sample~=0 then
            if loadSample(sample,directory..'sounds/'..name..'.ogg',false) then
                if setSampleGroup and AudioGroup and AudioGroup.VEHICLE then setSampleGroup(sample,AudioGroup.VEHICLE) end
                self.samples[name]=sample
            else
                delete(sample)
                if Logging then Logging.warning('[TG GPS PRO] Som do terminal indisponivel: '..name) end
            end
        end
    end
    return self
end

function TGGPSAudio:update(dt) self.clock=self.clock+math.max(0,dt or 0) end

function TGGPSAudio:play(name)
    local vehicle=self.owner:getControlledVehicle()
    if self.owner.monitorSounds==false or vehicle==nil or not vehicle.tgGpsSupported then return false end
    local sample=self.samples[name]
    if sample==nil or playSample==nil or (self.lastName==name and self.clock-self.lastTime<350) then return false end
    for _,other in pairs(self.samples) do if stopSample then stopSample(other,0,0) end end
    playSample(sample,1,0.35,0,0,0)
    self.lastName,self.lastTime=name,self.clock
    return true
end

function TGGPSAudio:delete()
    for _,sample in pairs(self.samples) do
        if stopSample then stopSample(sample,0,0) end
        delete(sample)
    end
    self.samples={}
end
