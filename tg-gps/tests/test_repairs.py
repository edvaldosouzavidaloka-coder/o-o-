import unittest
import xml.etree.ElementTree as ET
import test_monitor as baseline


class RepairTests(unittest.TestCase):
    setUp=baseline.MonitorTests.setUp
    check=baseline.MonitorTests.check

    def test_logged_basegame_texture_path_is_a_virtual_game_path_in_i3d(self):
        self.check('''
        metadata()
        local path='data/maps/mapUS/textures/ui/overview.png'
        g_currentMission.hud.ingameMap.mapOverlay.filename=path
        assetFiles[path]=true
        TGGPS:update(100);TGGPS:update(450)
        local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']
        assert(xml['i3D.Files.File(0)#filename']=='$'..path)
        assert(xml['i3D.Files.File(1)#filename']==TGGPS.MOD_DIRECTORY..'shaders/tgGpsPdaShader.xml')
        assert(TGGPSPDA.get()==g_currentMission.hud.ingameMap)
        local virtual,lookup=TGGPSPDA.textureForI3D('$data/maps/mapUS/textures/ui/overview.png')
        assert(virtual=='$'..path and lookup==path)
        local absolute=TGGPSPDA.textureForI3D('D:/maps/custom/overview.dds')
        assert(absolute=='D:/maps/custom/overview.dds')
        ''')

    def test_missing_texture_is_not_reloaded_and_logged_every_movement(self):
        self.check('''
        metadata();assetFiles['/maps/native_pda.dds']=nil
        warnings=0;Logging.warning=function() warnings=warnings+1 end
        TGGPS:update(100);TGGPS:update(450)
        for i=1,15 do move(i,0);TGGPS:update(1000) end
        assert(warnings==1)
        assert(xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']==nil)
        ''')

    def test_native_png_reference_uses_existing_dds_for_cab_texture(self):
        self.check('''
        metadata();local path='data/maps/mapUS/textures/ui/overview.png'
        g_currentMission.hud.ingameMap.mapOverlay.filename=path
        assetFiles['data/maps/mapUS/textures/ui/overview.dds']=true
        assert(not fileExists(path))
        TGGPS:update(100);TGGPS:update(450)
        local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']
        assert(xml and xml['i3D.Files.File(0)#filename']=='$data/maps/mapUS/textures/ui/overview.dds')
        assert(TGGPS.monitor.screenRenderer.nativeNode~=nil)
        assert(g_currentMission.hud.ingameMap.mapOverlay.filename==path)
        ''')

    def test_virtual_basegame_texture_is_not_rejected_by_literal_file_check(self):
        self.check('''
        metadata();local path='data/maps/mapUS/textures/ui/overview.png'
        g_currentMission.hud.ingameMap.mapOverlay.filename=path
        assert(not fileExists(path) and not fileExists(path:gsub('%.png$','.dds')))
        local warnings=0;Logging.warning=function() warnings=warnings+1 end
        TGGPS:update(100);TGGPS:update(450)
        local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']
        assert(xml and xml['i3D.Files.File(0)#filename']=='$'..path)
        assert(TGGPS.monitor.screenRenderer.nativeNode~=nil and warnings==0)
        ''')

    def test_custom_map_png_alias_is_resolved_without_changing_native_pda(self):
        self.check('''
        metadata();local image=g_currentMission.hud.ingameMap.mapOverlay
        image.filename='D:/mods/customMap/overview.PNG'
        assetFiles['D:/mods/customMap/overview.dds']=true
        local texture=TGGPSPDA.resolveCabTexture(image.filename)
        assert(texture=='D:/mods/customMap/overview.dds')
        assert(image.filename=='D:/mods/customMap/overview.PNG' and image.uvs==nil)
        ''')

    def test_loaded_native_overlay_can_back_a_custom_virtual_texture(self):
        self.check('''
        metadata();local image=g_currentMission.hud.ingameMap.mapOverlay
        image.filename='/packed-map/overview.png';image.overlayId=781
        assert(not fileExists(image.filename))
        TGGPS:update(100);TGGPS:update(450)
        assert(TGGPS.monitor.screenRenderer.nativeNode~=nil)
        local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']
        assert(xml['i3D.Files.File(0)#filename']==image.filename)
        image.overlayId=0
        assert(TGGPSPDA.resolveCabTexture(image.filename)==nil)
        ''')

    def test_missing_custom_png_recovers_when_only_its_dds_becomes_ready(self):
        self.check('''
        metadata();g_currentMission.hud.ingameMap.mapOverlay.filename='/maps/custom/overview.png'
        local warnings=0;Logging.warning=function() warnings=warnings+1 end
        TGGPS:update(100);TGGPS:update(450)
        assert(TGGPS.monitor.screenRenderer.nativeNode==nil and warnings==1)
        assetFiles['/maps/custom/overview.dds']=true;TGGPS:update(250)
        assert(TGGPS.monitor.screenRenderer.nativeNode~=nil and warnings==1)
        local xml=xmlFiles[getUserProfileAppPath()..TGGPS.SAVE_FOLDER..'/pdaMonitor.i3d']
        assert(xml['i3D.Files.File(0)#filename']=='/maps/custom/overview.dds')
        ''')

    def test_idle_vehicle_jitter_does_not_regenerate_the_pda_mesh(self):
        self.check('''
        metadata();TGGPS:update(100);TGGPS:update(450)
        local node=TGGPS.monitor.screenRenderer.nativeNode
        for i=1,10 do move(0.001*i,0.001*i);TGGPS:update(1000) end
        assert(TGGPS.monitor.screenRenderer.nativeNode==node and not node.deleted)
        ''')

    def test_pda_recovers_only_after_the_missing_texture_becomes_available(self):
        self.check('''
        metadata();assetFiles['/maps/native_pda.dds']=nil
        TGGPS:update(100);TGGPS:update(450)
        assert(TGGPS.monitor.screenRenderer.nativeNode==nil)
        assetFiles['/maps/native_pda.dds']=true;TGGPS:update(250)
        assert(TGGPS.monitor.screenRenderer.nativeNode~=nil)
        ''')

    def test_low_brightness_is_applied_to_all_lcd_geometry_and_saved(self):
        self.check('''
        function getHasShaderParameter() return true end
        function setShaderParameter(node,name,x,y,z,w) node.lcdIntensity=x end
        metadata();TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        assert(TGGPS.monitorBrightness==0.20 and screen.nativeShape.lcdIntensity==0.05)
        TGGPS:onBrightnessDown();TGGPS:update(250)
        assert(math.abs(screen.nativeShape.lcdIntensity-0.0375)<0.00001)
        TGGPS.monitorBrightness=1;TGGPS:loadHudSettings()
        assert(math.abs(TGGPS.monitorBrightness-0.15)<0.00001)
        local body=screen.pools.symbol_tractor[1]
        assert(body.z>screen.nativeNode.z+0.0005)
        ''')

    def test_brightness_never_queries_transform_group_shader_parameters(self):
        self.check('''
        local queries=0
        function getHasShaderParameter(node,name)
            assert(getHasClassId(node,ClassIds.SHAPE),"Shader queried on a transform group")
            queries=queries+1;return name=="lcdBrightness"
        end
        function setShaderParameter(node,name,value) node.lcdIntensity=value end
        metadata();TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        local icon=screen.pools.symbol_tractor[1]
        assert(not getHasClassId(icon,ClassIds.SHAPE) and #icon.children>0)
        local function verify(node,value)
            if getHasClassId(node,ClassIds.SHAPE) then
                assert(math.abs(node.lcdIntensity-value)<0.00001)
            end
            for i=0,getNumOfChildren(node)-1 do verify(getChildAt(node,i),value) end
        end
        verify(icon,0.05)
        local old=queries;screen:applyBrightness(icon);assert(queries==old)
        TGGPS.monitorBrightness=0.8;screen:applyBrightness(icon)
        verify(icon,0.2);assert(queries>old)
        ''')

    def test_materials_use_controlled_shader_and_dark_text_on_light_cards(self):
        root=ET.parse(baseline.ROOT/'models/tgGPSMonitorPrimitives.i3d').getroot()
        materials={m.get('name'):m for m in root.find('Materials')}
        for material in materials.values():
            self.assertIsNone(material.get('emissiveColor'))
            self.assertEqual(material.get('customShaderId'),'1')
            self.assertEqual(material.find('./CustomParameter[@name="lcdBrightness"]').get('value'),'0.05 0 0 0')
        card=float(materials['panelCard'].find('./CustomParameter[@name="lcdTint"]').get('value').split()[0])
        self.assertTrue(.70<card<.90)
        self.assertLess(float(materials['text'].find('./CustomParameter[@name="lcdTint"]').get('value').split()[0]),.05)
        self.assertTrue(materials['textWhite'].find('./CustomParameter[@name="lcdTint"]').get('value').startswith('0.94'))

    def test_hotkeys_register_for_active_input_and_open_settings_zoom_and_edit(self):
        self.lua.execute((baseline.ROOT/'scripts/TGGPSVehicle.lua').read_text())
        names=[n.get('name') for n in ET.parse(baseline.ROOT/'modDesc.xml').findall('./actions/action')]
        self.lua.globals().InputAction=self.lua.table_from({name:name for name in names})
        self.check('''
        callbacks={};tractor.isClient=true
        function tractor:clearActionEventsTable(t) for k in pairs(t) do t[k]=nil end end
        function tractor:addActionEvent(t,action,target,callback)
            callbacks[action]={target=target,callback=callback};t[action]=true;return true,action
        end
        g_inputBinding={cursor=false,getShowMouseCursor=function(self) return self.cursor end,
            setShowMouseCursor=function(self,value) self.cursor=value end,setActionEventTextPriority=function() end}
        TGGPSVehicle.onRegisterActionEvents(tractor,false,false)
        assert(callbacks.TG_GPS_MONITOR_SETTINGS and callbacks.TG_GPS_ZOOM_IN and callbacks.TG_GPS_ZOOM_OUT)
        local function press(name) local c=callbacks[name];c.callback(c.target,name,1) end
        press('TG_GPS_MONITOR_SETTINGS');assert(TGGPS.hud.isOpen and TGGPS.hud.page=='settings')
        press('TG_GPS_ZOOM_IN');assert(TGGPS.mapZoom==1.5)
        press('TG_GPS_ZOOM_OUT');assert(TGGPS.mapZoom==1)
        TGGPS:update(100);TGGPS:update(450)
        press('TG_GPS_MONITOR_EDIT');assert(TGGPS.monitor.editing)
        TGGPS:keyEvent(0,Input.KEY_return,0,true);assert(not TGGPS.monitor.editing)
        ''')

    def test_selected_same_model_implements_do_not_borrow_tractor_width(self):
        self.check('''
        local a,b=workTool('leveler',13),workTool('leveler',11)
        tractor.attached={{object=a},{object=b}};tractor.selected=a
        function tractor:getSelectedImplement() return {object=self.selected} end
        function tractor:getAttacherToolWorkingWidth() return 13 end
        TGGPS:syncWorkingWidth();assert(TGGPS.width==13);TGGPS:onWidthDown()
        tractor.selected=b;TGGPS:syncWorkingWidth();assert(TGGPS.width==11);TGGPS:onWidthDown()
        tractor.selected=a;TGGPS:syncWorkingWidth();assert(TGGPS.width==12.5)
        tractor.selected=b;TGGPS:syncWorkingWidth();assert(TGGPS.width==10.5)
        TGGPS:onResetImplementWidth();assert(TGGPS.width==11 and a.tgGpsWorkingWidth==12.5)
        assert(a.tgGpsProfileId~=b.tgGpsProfileId)
        ''')

    def test_width_and_profile_identity_follow_implement_to_another_tractor_and_savegame(self):
        self.lua.execute((baseline.ROOT/'scripts/TGGPSImplementProfile.lua').read_text())
        self.check('''
        local a=workTool('leveler',4);tractor.attached={{object=a}}
        TGGPS:syncWorkingWidth();TGGPS:onWidthUp();local id=a.tgGpsProfileId
        local another={rootNode=makeNode('tractor2'),tgGpsSupported=true,components={}}
        function another:getAttachedImplements() return {{object=a}} end
        g_currentMission.controlledVehicle=another;TGGPS:syncWorkingWidth();assert(TGGPS.width==4.5)
        local xml={values={},setValue=function(self,k,v) self.values[k]=v end,
            getValue=function(self,k,default) local v=self.values[k];if v==nil then return default end;return v end}
        local key='vehicles.vehicle(0).'..TGGPSImplementProfile.NAMESPACE
        TGGPSImplementProfile.saveToXMLFile(a,xml,key)
        local restored=workTool('leveler',4)
        TGGPSImplementProfile.onLoad(restored,{xmlFile=xml,key='vehicles.vehicle(0)'})
        assert(restored.tgGpsWorkingWidth==4.5 and restored.tgGpsProfileId==id)
        ''')

    def test_width_detection_combines_work_area_sections_instead_of_using_one_row(self):
        self.check('''
        local a=workTool('seeder',2)
        a.spec_workArea.workAreas={
            {start=makeNode('s1',a.rootNode,-6,0,-1),width=makeNode('w1',a.rootNode,-2,0,-1)},
            {start=makeNode('s2',a.rootNode,2,0,-1),width=makeNode('w2',a.rootNode,6,0,-1)}}
        tractor.attached={{object=a}};TGGPS:syncWorkingWidth();assert(TGGPS.width==12)
        ''')

    def test_field_and_implement_paint_and_guidance_remain_independent(self):
        self.check('''
        metadata();local fieldId=76
        local field={getId=function() return fieldId end,getDensityMapPolygon=function()
            local x=fieldId==76 and 0 or 200
            return {getVerticesList=function() return {x-30,-30,x+30,-30,x+30,120,x-30,120} end}
        end}
        g_farmlandManager.getFarmlandAtWorldPosition=function() return {farmId=1,getField=function() return field end} end
        TGGPS.monitorContext=nil;TGGPS:update(100)
        local original=TGGPS.coverage;local area=original:getWorkedHa();assert(area>0)
        local ok,r=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('Talhao 76'),'Talhao 76');assert(ok)
        fieldId=73;move(200,0);TGGPS.monitorContext=nil;TGGPS:syncWorkingWidth()
        assert(TGGPS.coverage~=original and TGGPS.coverage:getWorkedHa()==0)
        local width=TGGPS.width
        assert(TGGPS.library:load(r.id,{onlyLine=true,here=true}))
        assert(TGGPS.width==width and TGGPS.coverage:getWorkedHa()==0 and original:getWorkedHa()==area)
        assert(math.abs(TGGPS.fieldOrigin.x-200)<0.00001)
        fieldId=76;move(0,0);TGGPS.monitorContext=nil;TGGPS:syncWorkingWidth()
        assert(TGGPS.coverage==original and TGGPS.coverage:getWorkedHa()==area)
        local b=workTool('another',12);tractor.attached={{object=b}};TGGPS:syncWorkingWidth()
        assert(TGGPS.coverage~=original and TGGPS.coverage:getWorkedHa()==0)
        assert(#TGGPS.library:list()==0 and #TGGPS.library:list('',true)==1)
        assert(TGGPS.library:load(r.id,{onlyLine=true,here=true,shared=true}))
        assert(TGGPS.width==12 and TGGPS.coverage:getWorkedHa()==0 and original:getWorkedHa()==area)
        ''')

    def test_generating_field_from_a_curve_preserves_curvature_and_explicit_straight_option(self):
        self.check('''
        metadata();TGGPS.mode='curve';TGGPS.sourcePoints={{x=0,z=-10},{x=8,z=30},{x=0,z=70},{x=-5,z=100}}
        TGGPS:onGenerateField()
        assert(TGGPS.mode=='field' and TGGPS.fieldCurveReference and #TGGPS.fieldCurveReference==4)
        local curved=false
        for _,sections in pairs(TGGPS.guidanceSections) do for _,path in ipairs(sections) do
            if #path>3 then
                for i=2,#path-1 do
                    local a,b,c=path[i-1],path[i],path[i+1]
                    if math.abs((b.x-a.x)*(c.z-b.z)-(b.z-a.z)*(c.x-b.x))>0.00001 then curved=true end
                end
            end
            for _,p in ipairs(path) do assert(TGHeadlandGeometry.contains(TGGPS.fieldBoundary,p,0)) end
        end end
        assert(curved)
        TGGPS:onGenerateFieldStraight();assert(TGGPS.fieldCurveReference==nil)
        for _,sections in pairs(TGGPS.guidanceSections) do for _,path in ipairs(sections) do assert(#path==2) end end
        TGGPS:onGenerateFieldCurve();assert(TGGPS.fieldCurveReference and #TGGPS.fieldCurveReference==4)
        local ok,r=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('Curva 3'),'Curva 3');assert(ok)
        TGGPS.library=TGGPSCourseLibrary.new(TGGPS);TGGPS:onClear();assert(TGGPS.library:load(r.id))
        assert(TGGPS.fieldCurveReference and #TGGPS.fieldCurveReference==4)
        ''')

    def test_returning_to_a_field_uses_current_implement_width_for_its_parallel_lines(self):
        self.check('''
        metadata();local fieldId=76
        local field={getId=function() return fieldId end,getDensityMapPolygon=function()
            return {getVerticesList=function() return {-30,-30,30,-30,30,120,-30,120} end}
        end}
        g_farmlandManager.getFarmlandAtWorldPosition=function() return {farmId=1,getField=function() return field end} end
        TGGPS.monitorContext=nil;TGGPS:syncWorkingWidth();TGGPS:onGenerateFieldStraight()
        local origin=TGGPS.fieldOrigin
        fieldId=73;TGGPS.monitorContext=nil;TGGPS:syncWorkingWidth();TGGPS:onWidthUp()
        local width=TGGPS.width
        fieldId=76;TGGPS.monitorContext=nil;TGGPS:syncWorkingWidth()
        assert(TGGPS.fieldOrigin==origin and TGGPS.width==width)
        local p,q=TGGPS:getLanePath(0,1)[1],TGGPS:getLanePath(1,1)[1]
        assert(math.abs(math.abs(p.x-q.x)-width)<0.00001)
        ''')

    def test_curved_clipping_does_not_connect_across_a_concave_gap(self):
        self.check('''
        local polygon={{x=-20,z=-20},{x=20,z=-20},{x=20,z=80},{x=5,z=80},{x=5,z=0},{x=-5,z=0},{x=-5,z=80},{x=-20,z=80}}
        local data=TGHeadlandGeometry.clipPolylines({[0]={{{x=-15,z=40},{x=0,z=40},{x=15,z=40}}}},polygon,1)
        assert(data and #data.lanes[0]==2)
        for _,path in ipairs(data.lanes[0]) do
            for _,p in ipairs(path) do assert(TGHeadlandGeometry.contains(polygon,p,1)) end
            assert(path[1].x*path[#path].x>0)
        end
        ''')

    def test_deleting_one_saved_line_cannot_delete_another_implement_line(self):
        self.check('''
        TGGPS:syncWorkingWidth()
        local ok,a=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('A'),'A');assert(ok)
        local firstId=TGGPS.activeImplementId
        tractor.attached={{object=workTool('second',4)}};TGGPS:syncWorkingWidth();route(TGGPS)
        local ok,b=TGGPS.library:saveSnapshot(TGGPS.library:snapshot('B'),'B');assert(ok)
        local secondId=TGGPS.activeImplementId
        assert(not TGGPS.library:deleteOwn(a.id,secondId))
        assert(TGGPS.library:deleteOwn(a.id,firstId))
        assert(#TGGPS.library.records==1 and TGGPS.library.records[1].id==b.id)
        ''')

    def test_reset_confirmation_clears_the_selected_paint_even_if_tool_changes(self):
        self.check('''
        TGGPS:update(100);local first=TGGPS.coverage;assert(first:getWorkedHa()>0)
        g_gui.showYesNoDialog=function(self,options) self.pending=options end
        TGGPS:onResetCoverage()
        tractor.attached={{object=workTool('second',4)}};TGGPS:syncWorkingWidth();route(TGGPS);TGGPS.coverage:update(100)
        local second=TGGPS.coverage;local area=second:getWorkedHa();assert(area>0)
        g_gui.pending.callback(g_gui.pending.target,true)
        assert(first:getWorkedHa()==0 and second:getWorkedHa()==area and TGGPS.workedAreaHa>0)
        ''')


if __name__=='__main__': unittest.main()
