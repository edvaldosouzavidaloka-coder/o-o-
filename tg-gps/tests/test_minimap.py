import unittest
import test_monitor as baseline


class MinimapTests(unittest.TestCase):
    setUp = baseline.MonitorTests.setUp
    check = baseline.MonitorTests.check

    def test_rotated_pda_landmark_matches_guidance_and_vehicle_up(self):
        self.check('''
        metadata();tractor.rootNode.ry=math.pi/2
        local commands=TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})
        local image,body,line
        for _,c in ipairs(commands) do
            if c.type=='pda' then image=c end
            if c.part=='body' then body=c end
            if c.role=='selected_lane' then line=c end
        end
        assert(image and body and line)
        assert(body.type=='symbol' and math.abs(body.rotation)<0.000001)
        assert(math.abs(line.y1-line.y2)<0.000001 and math.abs(line.x1-line.x2)>0.01)
        -- The old north-facing reference is left/right of an east-facing tractor.
        -- Interpolate the real PDA UVs at a known world landmark on that line.
        local map=TGGPSPDA.get()
        local pdaWidth=image.worldBounds[4]-image.worldBounds[2]
        local u,v=0.5-10/pdaWidth,0.5
        local function sample(index)
            local a=image.uvs[index]*(1-v)+image.uvs[index+2]*v
            local b=image.uvs[index+4]*(1-v)+image.uvs[index+6]*v
            return a*(1-u)+b*u
        end
        local expectedU,expectedV=TGGPSPDA.uv(map,0,10)
        assert(math.abs(sample(1)-expectedU)<0.000001)
        assert(math.abs(sample(2)-expectedV)<0.000001)
        ''')

    def test_panel_and_cab_use_identical_world_crop_rotation_and_zoom(self):
        self.check('''
        metadata();tractor.rootNode.ry=math.rad(44.5)
        TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        local function compare()
            local image
            for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0.1,y=0.2,w=0.5,h=0.4})) do
                if c.type=='pda' then image=c end
            end
            local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']
            for i=0,3 do
                local text=xml[string.format('i3D.Shapes.IndexedTriangleSet(0).Vertices.v(%d)#t0',i)]
                local a,b=text:match('([^ ]+) ([^ ]+)')
                assert(math.abs(tonumber(a)-image.uvs[i*2+1])<0.0000001)
                assert(math.abs(tonumber(b)-image.uvs[i*2+2])<0.0000001)
            end
            return image
        end
        local first=compare();local previous=screen.nativeNode
        move(15.4,24.8);tractor.rootNode.ry=math.rad(99)
        TGGPS:onZoomIn();TGGPS:update(250)
        local next=compare()
        assert(previous.deleted and screen.nativeNode~=previous)
        assert(next.worldBounds[1]~=first.worldBounds[1])
        assert(math.abs((next.worldBounds[1]+next.worldBounds[3])/2-15.4)<0.00001)
        ''')

    def test_turning_the_map_preserves_old_paint_at_its_world_position(self):
        self.check('''
        metadata();TGGPS:update(100);tool.active=false;TGGPS:update(100)
        local coverage=TGGPS.coverage
        local cells,runs,area=coverage.coverageDisplayList,coverage.coverageRuns,coverage:getWorkedHa()
        assert(area>0)
        for _,yaw in ipairs({0,math.pi/4,math.pi/2,math.pi,math.pi*1.5}) do
            tractor.rootNode.ry=yaw;TGGPS.mapTime=nil
            local commands=TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})
            local box
            for _,c in ipairs(commands) do if c.type=='pda' then box=c end end
            local frame=TGGPSMapFrame.new(TGGPS,box,1920,1080,TGGPS:getVehiclePose(tractor),0,0)
            local x,y=frame:project({x=0,z=-8})
            local found=false
            for _,c in ipairs(commands) do
                if c.role=='coverage' and x>=c.x-0.000001 and x<=c.x+c.w+0.000001
                    and y>=c.y-0.000001 and y<=c.y+c.h+0.000001 then found=true end
            end
            assert(found,'old paint moved away from its world position')
            assert(coverage.coverageDisplayList==cells and coverage.coverageRuns==runs and coverage:getWorkedHa()==area)
        end
        ''')

    def test_orientation_button_is_visual_only_and_its_setting_is_persistent(self):
        self.check('''
        metadata();tractor.rootNode.ry=math.pi/2
        TGGPS.hud:setOpen(true);TGGPS.hud.page='settings'
        TGGPS.autosteerEnabled=true
        local lines,points,width=TGGPS.guidanceLines,TGGPS.sourcePoints,TGGPS.width
        local button
        for _,b in ipairs(TGGPS.hud:getButtons()) do if b.id=='map_orientation' then button=b end end
        assert(button and button.enabled);TGGPS.hud:_run(button)
        assert(TGGPS.mapVehicleUp==false and TGGPS.autosteerEnabled)
        assert(TGGPS.guidanceLines==lines and TGGPS.sourcePoints==points and TGGPS.width==width)
        TGGPS.mapVehicleUp=true;TGGPS:loadHudSettings();assert(TGGPS.mapVehicleUp==false)
        local body
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do if c.part=='body' then body=c end end
        assert(body.type=='symbol' and math.abs(body.rotation+math.pi/2)<0.000001)
        local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/hud.xml']
        xml['tgGpsHud#vehicleUp']=nil;TGGPS:loadHudSettings();assert(TGGPS.mapVehicleUp==true)
        ''')

    def test_rotated_dense_coverage_stays_inside_lcd_and_within_budget(self):
        self.check('''
        metadata();local coverage=TGGPS.coverage
        for x=-20,20 do for z=-10,10 do
            if (x+z)%3~=0 then coverage:markCoverageDisplayWorld(x*1.75,z*1.75,(x+z)%5==0) end
        end end
        local count=#coverage.coverageDisplayList
        for angle=0,345,15 do
            TGGPS.mapTime=nil;tractor.rootNode.ry=math.rad(angle)
            local commands=TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1},{coverageBudget=130,drawField=false})
            local image
            for _,c in ipairs(commands) do if c.type=='pda' then image=c end end
            local paint=0
            for _,c in ipairs(commands) do
                if c.role=='coverage' or c.role=='coverage_overlap' then
                    paint=paint+1
                    assert(c.x>=image.x-0.000001 and c.y>=image.y-0.000001)
                    assert(c.x+c.w<=image.x+image.w+0.000001 and c.y+c.h<=image.y+image.h+0.000001)
                end
            end
            assert(paint>0 and paint<=130 and #coverage.coverageDisplayList==count)
        end
        TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.count<=screen.MAX_PRIMITIVES and screen.used.symbol_tractor>0)
        assert(screen.used.selected_lane>0)
        ''')

    def test_rotated_pda_edges_never_sample_wrapped_texture_coordinates(self):
        self.check('''
        metadata();move(1010,1010);tractor.rootNode.ry=math.rad(37)
        local image
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do if c.type=='pda' then image=c end end
        assert(image)
        for _,uv in ipairs(image.uvs) do assert(uv>=0 and uv<=1) end
        ''')

    def test_machine_icon_scales_with_zoom_and_keeps_a_readable_limit(self):
        self.check('''
        metadata()
        local function body()
            for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0.1,y=0.2,w=0.3,h=0.4})) do if c.part=='body' then return c end end
        end
        local first=body();TGGPS:onZoomIn();local zoomed=body()
        assert(zoomed.h>first.h)
        for i=1,40 do TGGPS:onZoomIn() end
        local close=body();assert(close.h<=72/1080)
        ''')

    def test_idle_heading_jitter_does_not_reload_cab_pda(self):
        self.check('''
        metadata();TGGPS:update(100);TGGPS:update(450);tool.active=false
        local node=TGGPS.monitor.screenRenderer.nativeNode
        for i=1,4 do tractor.rootNode.ry=math.rad(0.02*i);TGGPS:update(250) end
        assert(TGGPS.monitor.screenRenderer.nativeNode==node and not node.deleted)
        ''')

    def test_lifted_implement_remains_visible_without_recording_new_paint(self):
        self.check('''
        metadata();TGGPS:update(100);local area=TGGPS.coverage:getWorkedHa()
        tool.active=false;TGGPS:update(100)
        assert(not TGGPS.coverage.working and TGGPS.coverage:getWorkedHa()==area)
        local visible=false
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do
            if c.role=='implement' then visible=true end
        end
        assert(visible and TGGPS.coverage.footprint==nil and TGGPS.coverage:getWorkedHa()==area)
        ''')


if __name__ == '__main__':
    unittest.main()
