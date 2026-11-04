import unittest
import test_monitor as baseline


class TerminalTests(unittest.TestCase):
    setUp=baseline.MonitorTests.setUp
    check=baseline.MonitorTests.check

    def test_farm_owner_field_and_implement_are_read_from_game(self):
        self.check('''
        metadata();local c=TGGPS:getMonitorContext()
        assert(c.farmName=='Fazenda Vidal' and c.ownerName=='Proprietario do campo')
        assert(c.fieldName=='Talhao 3' and c.fieldId=='3' and c.machineName=='Trator de teste')
        assert(c.implementName=='Semeadora de teste' and c.kind=='tractor')
        ''')

    def test_unknown_map_metadata_is_not_fabricated(self):
        self.check('''
        local c=TGGPS:getMonitorContext()
        assert(c.farmName=='Nao informado' and c.ownerName=='Nao informado')
        assert(c.fieldId=='' and c.fieldName=='Nao informado')
        ''')

    def test_width_is_independent_per_vehicle_and_attached_implement(self):
        self.check('''
        tool.configFileName='planterA.xml';tool.uniqueId='planter-A'
        TGGPS:syncWorkingWidth();TGGPS:onWidthUp();assert(TGGPS.width==6.5)
        local first=tool
        local second={rootNode=makeNode('planterB'),configFileName='planterB.xml',uniqueId='planter-B',spec_sowingMachine={}}
        function second:getAttacherToolWorkingWidth() return 12 end
        tractor.attached={{object=second}};TGGPS:update(16);assert(TGGPS.width==12)
        TGGPS:onWidthDown();assert(TGGPS.width==11.5)
        local combine={rootNode=makeNode('combine'),tgGpsSupported=true,spec_combine={},components={}}
        function combine:getAttacherToolWorkingWidth() return 9 end
        g_currentMission.controlledVehicle=combine;TGGPS:update(16);assert(TGGPS.width==9)
        TGGPS:onWidthUp();assert(TGGPS.width==9.5)
        g_currentMission.controlledVehicle=tractor;TGGPS:update(16);assert(TGGPS.width==11.5)
        tractor.attached={{object=first}};TGGPS:update(16);assert(TGGPS.width==6.5)
        ''')

    def test_named_route_does_not_replace_current_implement_width(self):
        self.check('''
        TGGPS:syncWorkingWidth();TGGPS:onWidthUp();local width=TGGPS.width
        local snapshot=TGGPS.library:snapshot('Linha de outra maquina');snapshot.width=18
        local ok,r=TGGPS.library:saveSnapshot(snapshot,snapshot.name);assert(ok)
        assert(TGGPS.library:load(r.id))
        assert(TGGPS.width==width and TGGPS.width~=r.width)
        ''')

    def test_same_vehicle_model_instances_keep_independent_widths(self):
        self.check('''
        TGGPS:syncWorkingWidth();TGGPS:onWidthUp()
        local other={rootNode=makeNode('other'),tgGpsSupported=true,configFileName=tractor.configFileName,components={}}
        g_currentMission.controlledVehicle=other;TGGPS:update(16);assert(TGGPS.width==6)
        TGGPS:onWidthDown();assert(TGGPS.width==5.5)
        g_currentMission.controlledVehicle=tractor;TGGPS:update(16);assert(TGGPS.width==6.5)
        ''')

    def test_vehicle_width_profiles_round_trip_in_native_savegame_xml(self):
        self.lua.execute((baseline.ROOT/'scripts/TGGPSVehicle.lua').read_text())
        self.check('''
        XMLValueType={INT=1,FLOAT=2,STRING=3}
        Vehicle={xmlSchemaSavegame={paths={},register=function(self,kind,path) self.paths[path]=true end}}
        TGGPSVehicle.initSpecialization()
        local key='vehicles.vehicle(0).'..TGGPSVehicle.NAMESPACE
        assert(Vehicle.xmlSchemaSavegame.paths['vehicles.vehicle(?).'..TGGPSVehicle.NAMESPACE..'.widthProfile(?)#width'])
        tool.configFileName='planter.xml';tool.uniqueId='tool-123';TGGPS:syncWorkingWidth();TGGPS:onWidthUp()
        local xml={values={},setValue=function(self,k,v) self.values[k]=v end,
            getValue=function(self,k,default) local v=self.values[k];if v==nil then return default end;return v end}
        TGGPSVehicle.saveToXMLFile(tractor,xml,key)
        local restored={}
        TGGPSVehicle.onLoad(restored,{xmlFile=xml,key='vehicles.vehicle(0)'})
        assert(restored.tgGpsSupported and restored.tgGpsWidths[TGGPSWidthProfiles.key(tractor)]==6.5)
        ''')

    def test_tiny_manual_steering_immediately_releases_straight_and_headland_control(self):
        self.check('''
        TGGPS:syncWorkingWidth()
        TGGPS.calculateSteering=function() error('must release before calculating GPS steering') end
        tractor.spec_drivable={lastInputValues={axisSteer=0.000001}}
        for _,phase in ipairs({'straight','turning','lowering'}) do
            TGGPS.autosteerEnabled=true;TGGPS.activeVehicle=tractor
            TGGPS.turnState=phase~='straight' and {phase=phase} or nil
            local forward,side,brake=TGGPS:applyDriveControl(tractor,0.6,0.000001,false,16)
            assert(not TGGPS.autosteerEnabled and TGGPS.turnState==nil)
            assert(forward==0.6 and side==0.000001 and brake==false)
        end
        tractor.spec_drivable.lastInputValues.axisSteer=0
        TGGPS.autosteerEnabled=true;TGGPS.activeVehicle=tractor
        assert(TGGPS:applySteering(tractor,0,0.001,false,16)==0.001)
        assert(not TGGPS.autosteerEnabled)
        ''')

    def test_neutral_manual_input_does_not_cancel_gps_steering(self):
        self.check('''
        TGGPS:syncWorkingWidth();TGGPS.autosteerEnabled=true;TGGPS.activeVehicle=tractor
        tractor.spec_drivable={lastInputValues={axisSteer=0}}
        TGGPS.calculateSteering=function() return {steering=0.4,atEnd=false} end
        local side=TGGPS:applySteering(tractor,0.5,0,false,16)
        assert(TGGPS.autosteerEnabled and side~=0)
        ''')

    def test_heading_uses_initial_direction_for_a_closed_recorded_curve(self):
        self.check('''
        local heading=TGGPSContext.heading({{x=0,z=0},{x=0,z=0},{x=5,z=0},{x=0,z=0}})
        assert(math.abs(heading-90)<0.00001)
        ''')

    def test_unparseable_library_is_not_overwritten(self):
        self.check('''
        xmlFiles[TGGPS.library:path()]={}
        loadXMLFile=function() return 0 end
        local lib=TGGPSCourseLibrary.new(TGGPS)
        assert(lib.readError)
        assert(not lib:saveSnapshot(TGGPS.library:snapshot('Nova'),'Nova'))
        ''')

    def test_mouse_buttons_nudge_and_load_saved_route(self):
        self.check('''
        TGGPS.hud:setOpen(true);TGGPS.hud.page='map'
        local function click(id)
            for _,b in ipairs(TGGPS.hud:getButtons()) do if b.id==id then
                local x,y=b.x+b.w/2,b.y+b.h/2
                assert(TGGPS.hud:mouseEvent(x,y,true,false,1))
                assert(TGGPS.hud:mouseEvent(x,y,false,true,1));return
            end end
            error('button not found: '..id)
        end
        click('nudge_right');assert(math.abs(TGGPS.trackOffset-0.1)<0.00001)
        local ok,r=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('Linha do campo 3'),'Linha do campo 3');assert(ok)
        TGGPS:onClear();TGGPS.hud.page='library';click('load_course_'..r.id)
        assert(TGGPS.activeCourseName=='Linha do campo 3' and TGGPS.hud.page=='map')
        ''')

    def test_pda_overlay_is_owned_by_terminal_and_deleted_on_close(self):
        self.check('''
        metadata();rendered={}
        Overlay={new=function(filename)
            return {filename=filename,setPosition=function(self,x,y) self.x,self.y=x,y end,
                setDimension=function() end,setColor=function() end,setUVs=function(self,v) self.uvs=v end,
                render=function(self) rendered[self.filename]=true end,delete=function(self) self.deleted=true end}
        end}
        TGGPS.hud:setOpen(true);TGGPS.hud:draw()
        local overlay=TGGPS.hud.nativeOverlay
        assert(overlay and #overlay.uvs==8 and rendered['/maps/native_pda.dds'])
        assert(g_currentMission.hud.ingameMap.mapOverlay.uvs==nil)
        TGGPS.hud:delete();assert(overlay.deleted)
        ''')

    def test_corrupt_library_file_is_preserved_when_saving_new_record(self):
        self.check('''
        local path=TGGPS.library:path()
        xmlFiles[path]={['tgGpsLibrary#count']=9999}
        local library=TGGPSCourseLibrary.new(TGGPS)
        assert(library.readError)
        assert(not library:saveSnapshot(TGGPS.library:snapshot('Nova'),'Nova'))
        assert(xmlFiles[path]['tgGpsLibrary#count']==9999)
        ''')

    def test_icon_changes_to_combine_and_active_header_paints_in_front(self):
        self.check('''
        tractor.spec_combine={};tool.spec_cutter={};tool.rootNode.z=8
        TGGPS.monitorContext=nil;TGGPS:update(100)
        assert(TGGPS:getMonitorContext().kind=='combine')
        assert(TGGPS.coverage.footprint.z==8 and TGGPS.coverage:getWorkedHa()>0)
        local header,cab,body=false,false,false
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do
            if c.part=='header' then header=true end
            if c.part=='cab' then cab=true end
            if c.part=='body' then assert(c.machineType=='combine');body=true end
        end
        assert(header and cab and body)
        tractor.spec_combine=nil;TGGPS.monitorContext=nil
        local tractorBody=false
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do
            if c.part=='body' then assert(c.machineType=='tractor');tractorBody=true end
            assert(c.part~='header')
        end
        assert(tractorBody)
        ''')

    def test_nudge_and_snap_change_guidance_without_moving_paint(self):
        self.check('''
        TGGPS.fieldBoundary=nil;TGGPS:rebuildGuidance();TGGPS:update(100)
        local area=TGGPS.coverage:getWorkedHa()
        TGGPS.autosteerEnabled=true;TGGPS:onNudgeLineRight()
        assert(not TGGPS.autosteerEnabled and math.abs(TGGPS.trackOffset-0.1)<0.00001)
        assert(math.abs(TGGPS:getLanePath(0,1)[1].x+0.1)<0.00001)
        move(4,20);TGGPS:onSnapLine()
        assert(math.abs(TGGPS:getLanePath(0,1)[1].x-4)<0.00001)
        assert(TGGPS.coverage:getWorkedHa()==area)
        TGGPS:onResetTrackOffset();assert(TGGPS.trackOffset==0)
        ''')

    def test_shifted_field_lines_are_clipped_and_keep_headland_margin(self):
        self.check('''
        TGGPS.mode='field';TGGPS.fieldOrigin={x=0,z=0};TGGPS.fieldDirection={dx=0,dz=1}
        TGGPS.headlandEnabled=true;assert(TGGPS:rebuildGuidance())
        assert(TGGPS:changeTrackOffset(1.2))
        for _,sections in pairs(TGGPS.guidanceSections) do for _,path in ipairs(sections) do
            for _,p in ipairs(path) do assert(TGHeadlandGeometry.contains(TGGPS.fieldBoundary,p,0)) end
        end end
        assert(TGGPS.headlandEnabled and math.abs(TGGPS.trackOffset-1.2)<0.00001)
        ''')

    def test_named_library_round_trip_filter_and_duplicate_names(self):
        self.check('''
        metadata();TGGPS:rebuildGuidance();TGGPS:changeTrackOffset(0.2)
        local snapshot=TGGPS.library:snapshot('Talhao 3 Norte')
        local ok,r=TGGPS.library:saveSnapshot(snapshot,'Talhao 3 Norte');assert(ok)
        local first=r.id
        ok,r=TGGPS.library:saveSnapshot(snapshot,'Talhao 3 Norte');assert(ok and r.id~=first)
        local reopened=TGGPSCourseLibrary.new(TGGPS)
        assert(#reopened:list('Talhao 3')==2 and #reopened:list('nao existe')==0)
        TGGPS.library=reopened;TGGPS:onClear();TGGPS.autosteerEnabled=true
        assert(TGGPS.library:load(first))
        assert(TGGPS.activeCourseName=='Talhao 3 Norte' and not TGGPS.autosteerEnabled)
        assert(math.abs(TGGPS.trackOffset-0.2)<0.00001 and #TGGPS.basePath>=2)
        ''')

    def test_field_library_round_trip_keeps_original_origin_and_offset(self):
        self.check('''
        metadata();TGGPS.mode='field';TGGPS.fieldOrigin={x=0,z=0};TGGPS.fieldDirection={dx=0,dz=1}
        TGGPS.headlandEnabled=true;assert(TGGPS:rebuildGuidance());assert(TGGPS:changeTrackOffset(0.6))
        local before=TGGPS:getLanePath(0,1)[1].x
        local ok,r=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('Campo 3'),'Campo 3');assert(ok)
        TGGPS:onClear();assert(TGGPS.library:load(r.id))
        assert(TGGPS.mode=='field' and TGGPS.headlandEnabled and TGGPS.fieldOrigin.x==0)
        assert(math.abs(TGGPS:getLanePath(0,1)[1].x-before)<0.00001)
        ''')

    def test_corrupt_route_or_other_map_cannot_replace_current_route(self):
        self.check('''
        local ok,r=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('Teste'),'Teste');assert(ok)
        local previous=TGGPS.guidanceLines
        r.mapId='anotherMap';assert(not TGGPS.library:load(r.id))
        assert(TGGPS.guidanceLines==previous)
        r.mapId=TGGPSContext.mapId();r.sourcePoints[1].x=0/0
        assert(not TGGPS.library:load(r.id) and TGGPS.guidanceLines==previous)
        ''')

    def test_failed_disk_save_is_reported_and_does_not_add_a_record(self):
        self.check('''
        saveXMLFile=function() return false end
        local ok,message=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('Teste'),'Teste')
        assert(not ok and #TGGPS.library.records==0 and type(message)=='string')
        ''')

    def test_name_dialog_and_search_are_functional_and_cancel_is_non_destructive(self):
        self.check('''
        metadata();g_gui.showTextInputDialog=function(self,options) self.pending=options end
        TGGPS:onSaveNamedCourse();assert(TGGPS.dialogBusy)
        g_gui.pending.callback(g_gui.pending.target,'Talhao 3 - Norte',true)
        assert(not TGGPS.dialogBusy and #TGGPS.library:list('Norte')==1)
        TGGPS:onSearchCourses();g_gui.pending.callback(g_gui.pending.target,'Talhao 3',true)
        assert(TGGPS.libraryFilter=='Talhao 3' and TGGPS.hud.page=='library')
        TGGPS:onSaveNamedCourse();g_gui.pending.callback(g_gui.pending.target,'Cancelar',false)
        assert(#TGGPS.library.records==1)
        ''')

    def test_zoom_is_shared_and_persisted(self):
        self.check('''
        TGGPS:onZoomIn();TGGPS:onZoomIn();assert(TGGPSMap.getZoom(TGGPS)==2)
        TGGPS.mapZoom=1;TGGPS:loadHudSettings();assert(TGGPSMap.getZoom(TGGPS)==2)
        for i=1,40 do TGGPS:onZoomIn() end;assert(TGGPSMap.getZoom(TGGPS)==12)
        TGGPS:onZoomFit();assert(TGGPSMap.getZoom(TGGPS)==1)
        ''')

    def test_native_pda_uses_game_filename_and_world_coordinates(self):
        self.check('''
        metadata();local map,filename=TGGPSPDA.get()
        assert(filename=='/maps/native_pda.dds')
        local u,v=TGGPSPDA.uv(map,0,0);assert(u==0.5 and v==0.5)
        u,v=TGGPSPDA.uv(map,1024,-1024);assert(u==1 and v==1)
        local image
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do if c.type=='pda' then image=c end end
        assert(image and image.filename==filename and #image.uvs==8)
        assert(map.mapOverlay.filename==filename and map.mapOverlay.uvs==nil)
        ''')

    def test_native_pda_extends_and_crops_without_texture_wrapping(self):
        self.check('''
        metadata();local map=TGGPSPDA.get()
        map.mapExtensionScaleFactor=0.5;map.mapExtensionOffsetX=0.2;map.mapExtensionOffsetZ=0.1
        local u,v=TGGPSPDA.uv(map,0,0)
        assert(math.abs(u-0.45)<0.00001 and math.abs(v-0.65)<0.00001)
        local cmd=TGGPSPDA.command(map,'native',{x=0,y=0,w=1,h=1},-4096,-4096,4096,4096)
        for _,uv in ipairs(cmd.uvs) do assert(uv>=0 and uv<=1) end
        assert(cmd.w<1 and cmd.h<1)
        ''')

    def test_native_pda_visible_before_any_guidance_is_created(self):
        self.check('''
        metadata();TGGPS:onClear()
        local hasImage,hasBody=false,false
        for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do
            if c.type=='pda' then hasImage=true end
            if c.part=='body' then hasBody=true end
        end
        assert(hasImage and hasBody)
        ''')

    def test_native_cab_background_serializes_texture_and_uvs_and_is_cleaned_up(self):
        self.check('''
        metadata();TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.nativeNode~=nil and not screen.nativeNode.deleted)
        local path=getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d'
        assert(xmlFiles[path]['i3D.Files.File(0)#filename']=='/maps/native_pda.dds')
        assert(xmlFiles[path]['i3D.Shapes.IndexedTriangleSet(0).Vertices.v(0)#t0']~=nil)
        local old=screen.nativeNode;TGGPS:onZoomIn();TGGPS:update(250)
        assert(old.deleted and screen.nativeNode~=old)
        local current=screen.nativeNode;TGGPS:deleteMap();assert(current.deleted)
        ''')

    def test_all_terminal_pages_have_working_actions_and_bounded_buttons(self):
        self.check('''
        metadata();TGGPS.hud:setOpen(true)
        for _,page in ipairs({'map','guide','headland','library','settings'}) do
            TGGPS.hud.page=page
            local bounds=TGGPS.hud:getBounds()
            assert(#TGGPS.hud:getDrawCommands()>0)
            for _,button in ipairs(TGGPS.hud:getButtons()) do
                assert(button.x>=bounds.x and button.y>=bounds.y)
                assert(button.x+button.w<=bounds.x+bounds.w+0.00001)
                assert(button.y+button.h<=bounds.y+bounds.h+0.00001)
                if button.action:sub(1,2)=='on' then assert(type(TGGPS[button.action])=='function') end
            end
        end
        TGGPS.hud.page='map'
        for _,b in ipairs(TGGPS.hud:getButtons()) do if b.id=='nudge_right' then TGGPS.hud:_run(b) end end
        assert(math.abs(TGGPS.trackOffset-0.1)<0.00001)
        ''')

    def test_combine_header_headland_lift_turn_lower_sequence(self):
        self.check('''
        tractor.spec_combine={};tool.spec_cutter={};tool.lowered=true
        function tool:getAllowsLowering() return true end
        function tool:getIsLowered() return self.lowered end
        function tool:setLoweredAll(value,joint) assert(joint==1);self.lowered=value;self.active=value end
        tractor.spec_attacherJoints={attachedImplements={{object=tool,jointDescIndex=1}}}
        TGGPS.mode='field';TGGPS.fieldOrigin={x=0,z=0};TGGPS.fieldDirection={dx=0,dz=1}
        TGGPS.headlandEnabled=true;assert(TGGPS:rebuildGuidance())
        move(0,100)
        assert(TGHeadlandControl.begin(TGGPS,tractor,{direction=1}))
        assert(TGGPS.turnState.phase=='lifting' and not tool.lowered)
        for i=1,4 do TGHeadlandControl.step(TGGPS,tractor,TGGPS:getVehiclePose(tractor),250) end
        assert(TGGPS.turnState.phase=='turning')
        local path=TGGPS.turnState.path
        for i=1,#path do
            local p=path[i];local prev=path[math.max(1,i-1)];local next=path[math.min(#path,i+1)]
            local dx,dz=next.x-prev.x,next.z-prev.z;local len=math.sqrt(dx*dx+dz*dz)
            local pose={x=p.x,z=p.z,dx=dx/len,dz=dz/len,speed=0}
            TGHeadlandControl.step(TGGPS,tractor,pose,16)
            if TGGPS.turnState.phase=='lowering' then break end
        end
        assert(TGGPS.turnState.phase=='lowering')
        for i=1,8 do
            if TGGPS.turnState then TGHeadlandControl.step(TGGPS,tractor,TGGPS:getVehiclePose(tractor),250) end
        end
        assert(TGGPS.turnState==nil and tool.lowered and TGGPS.currentLane~=0)
        ''')

    def test_pda_default_is_a_local_window_that_follows_vehicle(self):
        self.check('''
        metadata();TGGPS.fieldBoundary={{x=-1000,z=-1000},{x=1000,z=-1000},{x=1000,z=1000},{x=-1000,z=1000}}
        local function image()
            for _,c in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do if c.type=='pda' then return c end end
        end
        move(0,0);local a=image();local size=a.worldBounds[3]-a.worldBounds[1]
        assert(size<200)
        move(140,230);local b=image()
        assert(math.abs((b.worldBounds[1]+b.worldBounds[3])/2-140)<0.00001)
        assert(math.abs((b.worldBounds[2]+b.worldBounds[4])/2-230)<0.00001)
        TGGPS:onZoomIn();local c=image();assert(c.worldBounds[3]-c.worldBounds[1]<size)
        ''')


if __name__=='__main__': unittest.main()
