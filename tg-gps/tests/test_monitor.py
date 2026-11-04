from pathlib import Path
import math
import unittest
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'tests/fixture.lua').read_text())
        self.lua.globals().g_currentModName = 'FS25_TG_GPS'
        self.lua.globals().g_currentModDirectory = str(ROOT) + '/'

        def load_model(path, *_):
            self.lua.globals().loadedModels[len(self.lua.globals().loadedModels) + 1] = path
            data = ET.parse(path).getroot()
            make = self.lua.globals().makeNode
            root = make('i3dRoot')

            def visit(element, parent):
                node = make(element.get('name', element.tag), parent)
                for child in element:
                    if child.tag in ('TransformGroup', 'Shape'):
                        visit(child, node)

            for element in data.find('Scene'):
                visit(element, root)
            return root

        self.lua.globals().loadI3DFile = load_model
        manifest = ET.parse(ROOT / 'modDesc.xml').getroot()
        for element in manifest.findall('./extraSourceFiles/sourceFile'):
            self.lua.execute((ROOT / element.attrib['filename']).read_text())
        self.lua.execute('TGGPS:loadMap(); route(TGGPS)')

    def check(self, source):
        self.lua.execute(source)

    def test_all_sources_compile_and_manifest_dependencies_exist(self):
        compile_lua = self.lua.eval('function(s,n) local f,e=loadstring(s,n);assert(f,e) end')
        for path in (ROOT / 'scripts').glob('*.lua'):
            compile_lua(path.read_text(), '@' + path.name)
        manifest = ET.parse(ROOT / 'modDesc.xml').getroot()
        for node in manifest.findall('./specializations/specialization'):
            self.assertTrue((ROOT / node.attrib['filename']).is_file())
        self.check('assert(#listeners==1 and listeners[1]==TGGPS); assert(CurveGPS==nil and CurveGPSHUDMonitor==nil)')

    def test_coverage_tracks_work_area_behind_tractor_with_manual_steering(self):
        self.check('''
        TGGPS.autosteerEnabled=false;TGGPS.hud:setOpen(false)
        TGGPS:update(100)
        local c=TGGPS.coverage
        assert(c.working and c.footprint.exactWorkArea)
        assert(c.footprint.x==0 and c.footprint.z==-8)
        assert(c.footprint.width==6 and c:getWorkedHa()>0)
        for _,run in ipairs(c.coverageRuns) do for _,p in ipairs(run) do assert(p.z<0) end end
        ''')

    def test_no_route_or_no_tool_never_paints(self):
        self.check('''
        TGGPS.sourcePoints={};TGGPS:update(100)
        assert(TGGPS.coverage:getWorkedHa()==0)
        route(TGGPS);tractor.attached={};TGGPS:update(100)
        assert(TGGPS.coverage:getWorkedHa()==0 and not TGGPS.coverage.working)
        ''')

    def test_lifting_ends_pass_and_lowering_does_not_bridge_gap(self):
        self.check('''
        TGGPS:update(100);local first=TGGPS.coverage:getWorkedHa()
        tool.active=false;move(0,30);TGGPS:update(100)
        assert(not TGGPS.coverage.working and TGGPS.coverage:getWorkedHa()==first)
        tool.active=true;TGGPS:update(100)
        assert(#TGGPS.coverage.coverageRuns==2)
        assert(TGGPS.coverage.coverageGrid['0:10']==nil)
        ''')

    def test_repeated_stationary_samples_do_not_inflate_area_or_overlap(self):
        self.check('''
        TGGPS:update(100);local first=TGGPS.coverage:getWorkedHa()
        for i=1,50 do TGGPS:update(100) end
        assert(TGGPS.coverage:getWorkedHa()==first)
        assert(TGGPS.coverage:getOverlapHa()==0)
        ''')

    def test_repass_marks_overlap_without_double_counting_worked_hectares(self):
        self.check('''
        TGGPS:update(100);local first=TGGPS.coverage:getWorkedHa()
        tool.active=false;TGGPS:update(100)
        tool.active=true;TGGPS:update(100)
        assert(TGGPS.coverage:getWorkedHa()==first)
        assert(TGGPS.coverage:getOverlapHa()>0)
        ''')

    def test_implement_axes_and_width_take_precedence_over_tractor_width(self):
        self.check('''
        TGGPS.width=1;tool.rootNode.ry=math.pi/2
        TGGPS:update(100)
        local f=TGGPS.coverage.footprint
        assert(math.abs(f.width-6)<0.0001)
        assert(math.abs(f.rx)<0.0001 and math.abs(f.rz)>0.99)
        ''')

    def test_nested_attachments_and_auxiliary_work_areas(self):
        self.check('''
        tractor.attached={{object={getAttachedImplements=function() return {{object=tool}} end}}}
        tool.attached={{object=tractor}}
        tool.area.type=WorkAreaType.AUXILIARY;TGGPS:update(100)
        assert(not TGGPS.coverage.working)
        tool.area.type=nil;TGGPS:update(100)
        assert(TGGPS.coverage.working)
        ''')

    def test_custom_turned_on_tool_fallback_stops_when_turned_off(self):
        self.check('''
        tool.spec_workArea=nil;tool.spec_turnOnVehicle={};tool.on=true;tool.lowered=true
        function tool:getIsTurnedOn() return self.on end
        function tool:getIsLowered() return self.lowered end
        TGGPS:update(100);assert(TGGPS.coverage.working and TGGPS.coverage.estimated)
        local first=TGGPS.coverage:getWorkedHa()
        tool.on=false;move(0,4);TGGPS:update(100)
        assert(not TGGPS.coverage.working and TGGPS.coverage:getWorkedHa()==first)
        ''')

    def test_teleport_starts_a_new_run_instead_of_painting_between_positions(self):
        self.check('''
        TGGPS:update(100);move(0,70);TGGPS:update(100)
        assert(#TGGPS.coverage.coverageRuns==2)
        assert(TGGPS.coverage.coverageGrid['0:40']==nil)
        ''')

    def test_leaving_vehicle_stops_work_and_removes_monitor(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local root=TGGPS.monitor.monitorNode;assert(root~=nil)
        g_currentMission.controlledVehicle=nil;TGGPS:update(100)
        assert(root.deleted and TGGPS.monitor.monitorNode==nil)
        assert(not TGGPS.coverage.working)
        ''')

    def test_switch_back_during_debounce_reattaches_without_leaking_models(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local original=TGGPS.monitor.monitorNode
        local other={rootNode=makeNode('other'),tgGpsSupported=true,components={}}
        g_currentMission.controlledVehicle=other;TGGPS:update(100)
        assert(original.deleted)
        g_currentMission.controlledVehicle=tractor;TGGPS:update(100);TGGPS:update(450)
        assert(TGGPS.monitor.monitorNode~=nil and TGGPS.monitor.vehicle==tractor)
        ''')

    def test_coverage_and_overlap_are_visible_inside_map_bounds(self):
        self.check('''
        TGGPS:update(100);tool.active=false;TGGPS:update(100);tool.active=true;TGGPS:update(100)
        local commands=TGGPSMap.getDrawCommands(TGGPS,{x=0.1,y=0.2,w=0.7,h=0.5})
        local overlap,selected,implement,tractorIcon=0,0,0,0
        for _,c in ipairs(commands) do
            if c.role=='coverage_overlap' then
                overlap=overlap+1
                assert(c.x>=0.1 and c.y>=0.2 and c.x+c.w<=0.800001 and c.y+c.h<=0.700001)
            end
            if c.role=='selected_lane' then selected=selected+1 end
            if c.role=='implement' then implement=implement+1 end
            if c.role=='tractor' then tractorIcon=tractorIcon+1 end
        end
        assert(overlap>0 and selected>0 and implement>0 and tractorIcon==3)
        ''')

    def test_draw_budget_coarsens_coverage_without_losing_stored_cells(self):
        self.check('''
        local c=TGGPS.coverage
        for x=-40,40,2 do for z=-40,40,2 do
            if (x+z)%4==0 then c:markCoverageDisplayWorld(x,z,false) end
        end end
        local count=#c.coverageDisplayList
        assert(#c:getMapCells(-45,-45,45,45,30)<=30)
        assert(#c.coverageDisplayList==count)
        ''')

    def test_physical_monitor_attaches_to_cab_parent_not_rotating_camera(self):
        self.check('''
        local cab=makeNode('cab',tractor.rootNode)
        local camera=makeNode('insideCamera',cab,0,2,0)
        tractor.spec_enterable.cameras={{isInside=true,cameraPositionNode=camera}}
        TGGPS:update(100);assert(TGGPS.monitor.monitorNode==nil)
        TGGPS:update(450)
        local m=TGGPS.monitor
        assert(m.parentNode==cab and m.monitorNode.parent==cab)
        local x,y,z=getTranslation(m.monitorNode)
        assert(math.abs(x+0.35)<0.0001 and math.abs(y-1.75)<0.0001 and math.abs(z-0.65)<0.0001)
        camera.ry=1;assert(m.monitorNode.ry==math.pi)
        ''')

    def test_physical_screen_uses_shared_coverage_and_engine_power(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.owner.coverage==TGGPS.coverage)
        assert((screen.used.coverage or 0)>0 and (screen.used.tractor or 0)==3)
        tractor.motorOn=false;TGGPS:update(250)
        assert(screen.used.off==1 and screen.used.coverage==0)
        tractor.motorOn=true;TGGPS:update(250)
        assert((screen.used.coverage or 0)>0)
        assert(screen.count<=screen.MAX_PRIMITIVES)
        ''')

    def test_editing_blocks_drive_and_cancel_restores_position(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local m=TGGPS.monitor;local x=m.placement.positionX
        m:toggleEditMode();assert(m.editing)
        TGGPS:keyEvent(0,Input.KEY_right,0,true)
        assert(m.placement.positionX~=x)
        local a,b,brake=TGGPS:applyDriveControl(tractor,1,1,false,16)
        assert(a==0 and b==0 and brake)
        TGGPS:keyEvent(0,Input.KEY_esc,0,true)
        assert(not m.editing and m.placement.positionX==x)
        ''')

    def test_monitor_settings_save_and_restore_for_same_vehicle_model(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local m=TGGPS.monitor;m:toggleEditMode()
        m:keyEvent(0,Input.KEY_pageup,0,true)
        local y=m.placement.positionY
        m:keyEvent(0,Input.KEY_return,0,true)
        assert(not m.editing)
        local replacement=TGGPSMonitorManager.new(TGGPS,TGGPS.MOD_DIRECTORY)
        assert(replacement.settings['tractor.xml'].positionY==y)
        replacement:delete()
        ''')

    def test_position_edit_is_refused_when_moving(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        tractor.speed=6;TGGPS.monitor:toggleEditMode()
        assert(not TGGPS.monitor.editing)
        ''')

    def test_map_unload_deletes_every_loaded_scene_node(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local content=TGGPS.monitor.screenRenderer.contentRoot
        local root=TGGPS.monitor.monitorNode
        TGGPS:deleteMap()
        assert(root.deleted and content.deleted and TGGPS.coverage==nil and TGGPS.monitor==nil)
        ''')

    def test_i3d_geometry_material_and_glyph_references(self):
        for path in (ROOT / 'models').glob('*.i3d'):
            data = ET.parse(path).getroot()
            self.assertEqual(len(data.find('Files')), 0)
            shapes = {s.attrib['shapeId']: s for s in data.find('Shapes')}
            materials = {m.attrib['materialId'] for m in data.find('Materials')}
            for node in data.findall('.//Scene//Shape'):
                self.assertIn(node.attrib['shapeId'], shapes)
                self.assertTrue(set(node.attrib['materialIds'].split(',')) <= materials)
            for shape in shapes.values():
                vertices, triangles = shape.find('Vertices'), shape.find('Triangles')
                self.assertEqual(len(vertices), int(vertices.attrib['count']))
                self.assertEqual(len(triangles), int(triangles.attrib['count']))
                for triangle in triangles:
                    self.assertTrue(all(0 <= int(i) < len(vertices) for i in triangle.attrib['vi'].split()))
        primitive = ET.parse(ROOT / 'models/tgGPSMonitorPrimitives.i3d').getroot()
        names = {n.get('name') for n in primitive.findall('.//Scene//Shape')}
        for style in self.lua.globals().TGGPSMonitorScreen.STYLES.values():
            self.assertIn(style, names)
        for code in range(33, 127):
            self.assertIn(f'text_{code}', names)

    def test_existing_ab_generation_and_lane_controls_still_work(self):
        self.check('''
        TGGPS.fieldBoundary=nil;TGGPS.pointA=nil;TGGPS.sourcePoints={}
        move(0,0);TGGPS:onMarkAB();assert(TGGPS.pointA~=nil)
        move(0,40);TGGPS:onMarkAB()
        assert(TGGPS.mode=='straight' and #TGGPS.basePath>=2)
        assert(TGGPS.guidanceLines[0]~=nil)
        TGGPS:selectManualLane(1)
        assert(TGGPS.currentLane==1 and not TGGPS.autoLaneSelection)
        TGGPS:onToggleAutoLane();assert(TGGPS.autoLaneSelection)
        ''')

    def test_existing_field_guidance_and_headland_trimming_still_work(self):
        self.check('''
        TGGPS.mode='field';TGGPS.fieldOrigin={x=0,z=0};TGGPS.fieldDirection={dx=0,dz=1}
        assert(TGGPS:rebuildGuidance())
        local initial=TGGPS:getLanePath(0,1)
        local span=math.abs(initial[#initial].z-initial[1].z)
        TGGPS.headlandEnabled=true
        assert(TGGPS:rebuildGuidance())
        local trimmed=TGGPS:getLanePath(0,1)
        assert(math.abs(trimmed[#trimmed].z-trimmed[1].z)<span)
        ''')


if __name__ == '__main__':
    unittest.main()
