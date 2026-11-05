import unittest
import xml.etree.ElementTree as E
import test_monitor as baseline

class BorderPaintTests(unittest.TestCase):
    def setUp(self):
        baseline.MonitorTests.setUp(self)
        self.lua.execute('TGGPS.headlandControlRemoved=true;TGGPS.cabPerspective=true')
    check=baseline.MonitorTests.check

    def test_rectangular_border_is_closed_and_inset_by_half_real_tool_width(self):
        self.check('''
        metadata();assert(TGGPS:onGenerateBorder())
        assert(TGGPS.mode=='border' and not TGGPS.headlandEnabled and TGGPS.currentLane==0)
        assert(#TGGPS.basePath==5 and TGGPS.minLane==0 and TGGPS.maxLane==0)
        for _,p in ipairs(TGGPS.basePath) do
            assert(TGHeadlandGeometry.contains(TGGPS.fieldBoundary,p,2.999))
        end
        local a,b=TGGPS.basePath[1],TGGPS.basePath[5]
        assert(a.x==b.x and a.z==b.z and TGGPS:ensureLane(1)==nil)
        ''')

    def test_clockwise_and_concave_fields_keep_the_line_inside(self):
        self.check('''
        local polygon={{x=0,z=0},{x=60,z=0},{x=60,z=20},{x=20,z=20},{x=20,z=60},{x=0,z=60}}
        for i=1,2 do
            local path=TGBorder.create(polygon,3);assert(path and #path==7)
            for _,p in ipairs(path) do assert(TGHeadlandGeometry.contains(polygon,p,2.999)) end
            local reversed={};for j=#polygon,1,-1 do reversed[#reversed+1]=polygon[j] end;polygon=reversed
        end
        ''')

    def test_too_narrow_field_preserves_the_current_route(self):
        self.check('''
        metadata();TGGPS:update(100)
        local before=TGGPS.sourcePoints;local mode=TGGPS.mode
        local original=TGFieldBoundary.getAt
        function TGFieldBoundary.getAt() return {{x=0,z=0},{x=4,z=0},{x=4,z=4},{x=0,z=4}},3 end
        assert(not TGGPS:onGenerateBorder())
        assert(TGGPS.sourcePoints==before and TGGPS.mode==mode)
        TGFieldBoundary.getAt=original
        ''')

    def test_border_round_trips_through_quick_save_and_named_library(self):
        self.check('''
        metadata();TGGPS:update(100);assert(TGGPS:onGenerateBorder());assert(TGGPS:saveCourse())
        local first=TGGPS.basePath[1]
        TGGPS:onClear();TGGPS:loadCourse()
        assert(TGGPS.mode=='border' and #TGGPS.basePath==5 and TGGPS.basePath[1].x==first.x)
        local record=TGGPS.library:snapshot('Bordadura 3')
        local ok,saved=TGGPS.library:saveSnapshot(record,'Bordadura 3');assert(ok)
        TGGPS:onClear();assert(TGGPS.library:load(saved.id,{onlyLine=true}))
        assert(TGGPS.mode=='border' and TGGPS.minLane==0 and #TGGPS.basePath==5)
        assert(not TGGPS.headlandEnabled and TGGPS.turnState==nil)
        ''')

    def test_automatic_headland_controls_are_replaced_with_border_actions(self):
        self.check('''
        metadata();TGGPS.hud:setOpen(true);TGGPS.hud.page='headland'
        local generate,reverse=false,false
        for _,b in ipairs(TGGPS.hud:getButtons()) do
            assert(b.action~='onToggleHeadland' and b.action~='onTurnSpeedUp' and b.action~='onTurnRadiusUp')
            generate=generate or b.action=='onGenerateBorder';reverse=reverse or b.action=='onReverseBorder'
        end
        assert(generate and reverse)
        TGGPS.headlandEnabled=true;TGGPS.turnState={}
        TGGPS:getAutosteerProblem(tractor)
        assert(not TGGPS.headlandEnabled and TGGPS.turnState==nil)
        ''')

    def test_reverse_border_keeps_same_inset_and_reverses_orientation(self):
        self.check('''
        metadata();TGGPS:update(100);assert(TGGPS:onGenerateBorder())
        local function area(points)
            local value=0;for i=1,#points-1 do value=value+points[i].x*points[i+1].z-points[i+1].x*points[i].z end
            return value
        end
        local before=area(TGGPS.basePath);TGGPS:onReverseBorder()
        assert(math.abs(before+area(TGGPS.basePath))<.00001)
        ''')

    def test_fractional_strips_merge_into_a_smooth_trapezoid(self):
        self.check('''
        local pose={x=0,z=0,dx=0,dz=1}
        local shapes={{points={{x=-3.2,z=0},{x=3.2,z=0},{x=3.2,z=60},{x=-3.2,z=60}}}}
        local strips=TGGPSPerspective.paintStrips(pose,shapes,512,6000,true)
        local groups=TGGPSPerspective.smoothPaint(strips)
        assert(#strips>100 and #groups==1)
        local g=groups[1];assert(g.bottomR-g.bottomL>g.topR-g.topL)
        local y=(g.bottom+g.top)/2;local depth=22/(.95-y)-35
        local width=((g.bottomR-g.bottomL)+(g.topR-g.topL))/2
        assert(math.abs(width-6.4*1.9/(depth+35))<.000001)
        ''')

    def test_triangle_decomposition_preserves_polygon_area_without_pixel_steps(self):
        self.check('''
        local calls={}
        local screen={WIDTH=.24,HEIGHT=.18,quad=function(_,style,x,y,w,h,rotation)
            if w>0 and h>0 then calls[#calls+1]={style=style,w=w,h=h} end
        end}
        local polygon={{x=.2,y=.1},{x=.8,y=.1},{x=.6,y=.8},{x=.4,y=.8}}
        TGGPSPerspective.paintPolygon(screen,polygon,false)
        local area=0;for _,call in ipairs(calls) do
            assert(call.style=='paintBlueL' or call.style=='paintBlueR')
            area=area+call.w*call.h/2
        end
        local box=TGGPSGreenStar.MAP_BOX
        local expected=(.6+.2)/2*.7*box.w*screen.WIDTH*box.h*screen.HEIGHT
        assert(#calls<=4 and math.abs(area-expected)<.00000001)
        ''')

    def test_worked_blue_is_stronger_than_unworked_ground_and_triangles_are_opaque(self):
        root=E.parse(baseline.ROOT/'models/tgGPSMonitorPrimitives.i3d').getroot()
        def tint(name):
            return list(map(float,root.find('./Materials/Material[@name="'+name+'"]/CustomParameter[@name="lcdTint"]').get('value').split()))
        self.assertLess(sum(tint('guidancePaint')[:3]),sum(tint('guidanceGround')[:3]))
        for name in ('paintBlueL','paintBlueR','paintOverlapL','paintOverlapR'):
            node=root.find('.//Scene//Shape[@name="'+name+'"]')
            mesh=root.find('./Shapes/IndexedTriangleSet[@shapeId="'+node.get('shapeId')+'"]')
            self.assertEqual(mesh.find('Triangles').get('count'),'1')
            material=root.find('./Materials/Material[@materialId="'+node.get('materialIds')+'"]')
            self.assertIsNone(material.get('alphaBlending'))
