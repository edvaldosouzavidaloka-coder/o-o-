import unittest
import test_monitor as baseline

class PerspectiveTests(unittest.TestCase):
    def setUp(self):
        baseline.MonitorTests.setUp(self)
        self.lua.execute('TGGPS.cabPerspective=true')
    check=baseline.MonitorTests.check

    def test_default_view_has_original_controls_and_never_loads_pda(self):
        self.check('''
        TGGPS:loadMap();assert(TGGPS.cabPerspective);route(TGGPS);metadata()
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.nativeNode==nil and screen.used.guidanceGround==1)
        assert(screen.used.guidanceLane>0 and screen.used.guidanceSelected>0)
        assert(screen.greenStar.controls.visible and screen.used.symbol_tractor==1)
        for _,filename in ipairs(loadedModels) do assert(not filename:find('pdaMonitor')) end
        for filename in pairs(xmlFiles) do assert(not filename:find('pdaMonitor')) end
        ''')

    def test_real_world_guides_converge_and_follow_machine_rotation(self):
        self.check('''
        local pose={x=0,z=0,dx=0,dz=1}
        local near=TGGPSPerspective.project(pose,6,0)
        local far=TGGPSPerspective.project(pose,6,100)
        assert(near>far and far>.5)
        local u,v=TGGPSPerspective.project(pose,0,30);assert(u==.5)
        local turned={x=0,z=0,dx=1,dz=0}
        local a,b=TGGPSPerspective.project(turned,30,0)
        assert(math.abs(a-u)+math.abs(b-v)<.00001)
        assert(TGGPSPerspective.project(pose,0,-50)==nil)
        ''')

    def test_repeated_frames_do_not_accumulate_paint_or_scene_nodes(self):
        self.check('''
        tractor.speed=6;TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local screen=TGGPS.monitor.screenRenderer
        assert((screen.used.guidancePaint or 0)>0)
        local count,area,overlap=screen.count,TGGPS.coverage:getWorkedHa(),TGGPS.coverage:getOverlapHa()
        for i=1,30 do TGGPS:update(250) end
        assert(screen.count==count and screen.count<=screen.MAX_PRIMITIVES)
        assert(TGGPS.coverage:getWorkedHa()==area and TGGPS.coverage:getOverlapHa()==overlap)
        assert((screen.used.guidanceOverlap or 0)==0)
        ''')

    def test_real_second_pass_changes_paint_without_replacing_original_art(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        tool.active=false;TGGPS:update(250);tool.active=true;TGGPS:update(250)
        local screen=TGGPS.monitor.screenRenderer
        assert(TGGPS.coverage:getOverlapHa()>0 and screen.used.guidanceOverlap>0)
        assert(screen.greenStar.overlay~=nil and screen.used.guidanceGround==1)
        ''')

    def test_perspective_unload_after_vehicle_deletion_is_safe(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local screen=TGGPS.monitor.screenRenderer
        delete(tractor.rootNode);screen:update(250);TGGPS:deleteMap()
        assert(screen.contentRoot==nil and screen.greenStar==nil)
        ''')

    def test_paint_materials_are_opaque_to_avoid_cumulative_alpha(self):
        import xml.etree.ElementTree as E
        root=E.parse(baseline.ROOT/'models/tgGPSMonitorPrimitives.i3d').getroot()
        for name in ('guidancePaint','guidanceOverlap'):
            m=root.find('./Materials/Material[@name="'+name+'"]')
            self.assertIsNone(m.get('alphaBlending'))
            self.assertEqual(m.get('diffuseColor').split()[-1],'1')
            color=list(map(float,m.find('./CustomParameter[@name="lcdTint"]').get('value').split()))
            self.assertGreater(color[2],max(color[0],color[1]))

    def test_original_menu_icons_pulse_only_for_active_functions(self):
        self.check('''
        function getHasShaderParameter(node,name) assert(node.isShape);return name=='lcdBrightness' end
        function setShaderParameter(node,name,value) node.intensity=value end
        tractor.speed=6;TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local display=TGGPS.monitor.screenRenderer.greenStar
        local mapping=display.menuIcons.mapping;local guidance=display.menuIcons.guidance
        TGGPS:update(30)
        assert(mapping.intensity>.05 and guidance.intensity==.05)
        local previous=mapping.intensity;TGGPS:update(40);assert(mapping.intensity~=previous)
        TGGPS.autosteerEnabled=true;TGGPS.activeVehicle=tractor;TGGPS:update(30)
        assert(guidance.intensity>.05)
        tool.active=false;TGGPS:update(250);assert(mapping.intensity==.05)
        ''')

    def test_orientation_layout_reports_real_machine_width_and_heading(self):
        self.check('''
        metadata();local labels={}
        local original=TGGPSMonitorScreen.pixelText
        function TGGPSMonitorScreen:pixelText(value,...)
            labels[tostring(value)]=true;return original(self,value,...)
        end
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        assert(labels.Orientacao and labels['Ajustar Pista'] and labels['Faixa Seguinte'])
        assert(labels['6.000 m'] and labels['N  000 graus'])
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.crossTrackMetres==0 and screen.count<=screen.MAX_PRIMITIVES)
        local blue=screen.pools.guidanceGround[1]
        assert(blue.z>screen.pools.panelCard[1].z)
        for i=0,getNumOfChildren(screen.greenStar.controls)-1 do
            local node=getChildAt(screen.greenStar.controls,i)
            if getName(node):match('^originalControl') then assert(not node.visible) end
        end
        ''')
