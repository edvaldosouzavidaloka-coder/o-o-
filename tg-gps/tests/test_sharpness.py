import struct
import unittest
import xml.etree.ElementTree as ET
import test_monitor as baseline


class SharpnessTests(unittest.TestCase):
    setUp = baseline.MonitorTests.setUp
    check = baseline.MonitorTests.check

    def test_vehicle_sprites_are_1024px_bc3_with_full_mips_and_complete_payload(self):
        for name in ['tractor', 'combine', 'combine_cutter']:
            data = (baseline.ROOT / 'models/textures' / (name + '.dds')).read_bytes()
            self.assertEqual(data[:4], b'DDS ')
            self.assertEqual(data[84:88], b'DXT5')
            height, width = struct.unpack_from('<II', data, 12)
            self.assertEqual((width, height), (1024, 1024))
            self.assertEqual(struct.unpack_from('<I', data, 28)[0], 11)
            size = 128
            for level in range(11):
                n = max(1, 1024 >> level)
                size += max(1, (n + 3) // 4) ** 2 * 16
            self.assertEqual(len(data), size)

    def test_cab_symbols_have_detailed_coplanar_geometry_and_real_material_references(self):
        root = ET.parse(baseline.ROOT / 'models/tgGPSVehicleSymbols.i3d').getroot()
        meshes = {m.get('shapeId'): m for m in root.findall('./Shapes/IndexedTriangleSet')}
        materials = {m.get('materialId'): m.get('name') for m in root.findall('./Materials/Material')}
        for group in root.findall('./Scene/TransformGroup'):
            vertices = 0
            colors = set()
            for shape in group:
                colors.add(materials[shape.get('materialIds')])
                mesh = meshes[shape.get('shapeId')]
                points = [list(map(float, v.get('p').split())) for v in mesh.findall('./Vertices/v')]
                vertices += len(points)
                for x, y, z in points:
                    self.assertLessEqual(max(abs(x), abs(y)), .500001)
                    self.assertEqual(z, 0)
                for t in mesh.findall('./Triangles/t'):
                    a, b, c = [points[i] for i in map(int, t.get('vi').split())]
                    self.assertGreater((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]), -1e-10)
            self.assertGreater(vertices, 600)
            self.assertTrue({'glass', 'tire', 'rim', 'green'}.issubset(colors))

    def test_vertical_merging_keeps_a_one_pixel_strip_without_lowering_resolution(self):
        self.check('''
        local grid={}
        for row=0,191 do grid[row]={[137]=1} end
        local rects=TGGPSMapFrame.mergeGrid(grid,384,192)
        assert(#rects==1 and math.abs(rects[1].w-1/384)<0.00000001)
        assert(math.abs(rects[1].h-1)<0.00000001)
        ''')

    def test_visual_paint_preserves_fractional_work_width_instead_of_grid_blocks(self):
        self.check('''
        local c=TGGPS.coverage
        c.coverageRuns={{{x=0,z=-5,rx=1,rz=0,width=6.4},{x=0,z=5,rx=1,rz=0,width=6.4}}}
        c.coveragePointCount=2
        local oldGrid,area=c.coverageGrid,c:getWorkedHa()
        local shapes=c:getMapVisuals(-32,-16,32,16)
        assert(#shapes==2 and shapes[1].points)
        local minX,maxX=math.huge,-math.huge
        for _,shape in ipairs(shapes) do for _,p in ipairs(shape.points) do
            minX,maxX=math.min(minX,p.x),math.max(maxX,p.x)
        end end
        assert(math.abs(maxX-minX-6.4)<0.000001)
        local frame=TGGPSMapFrame.new(TGGPS,{x=0,y=0,w=1,h=1},1920,1080,TGGPS:getVehiclePose(tractor),0,0)
        local strips=frame:rasterize(shapes,130,false)
        assert(#strips<=4)
        assert(c.coverageGrid==oldGrid and c:getWorkedHa()==area)
        ''')

    def test_archive_paint_and_overlap_remain_available_after_visual_runs_are_pruned(self):
        self.check('''
        local c=TGGPS.coverage
        c:markCoverageDisplayWorld(-12,-12,false)
        c:markCoverageDisplayWorld(12,12,true)
        c.coverageGeometryPruned=true
        c.coverageRuns={{{x=0,z=-2,rx=1,rz=0,width=6},{x=0,z=2,rx=1,rz=0,width=6}}}
        local green,yellow,vector=false,false,false
        for _,p in ipairs(c:getMapVisuals(-20,-20,20,20)) do
            if p.points then vector=true elseif p.overlap then yellow=true else green=true end
        end
        assert(green and yellow and vector)
        ''')

    def test_hud_symbol_rotates_around_machine_center_and_releases_its_overlay(self):
        self.check('''
        metadata();TGGPS.hud:setOpen(true)
        local ids,deleted,draws={}, {}, {}
        function createImageOverlay(filename) ids[#ids+1]={filename=filename};return #ids end
        function setOverlayColor() end
        function setOverlayRotation(id,rotation) ids[id].rotation=rotation end
        function renderOverlay(id,x,y,w,h)
            if ids[id].filename:find('/models/textures/',1,true) then
                draws[#draws+1]={id=id,x=x,y=y,w=w,h=h,angle=-ids[id].rotation}
            end
        end
        local oldDelete=delete
        function delete(n) if type(n)=='number' then deleted[n]=true else oldDelete(n) end end
        TGGPS.mapVehicleUp=false
        for _,angle in ipairs({0,math.pi/2,math.pi,math.pi*1.5}) do
            tractor.rootNode.ry=angle;TGGPS.mapTime=nil
            local symbol
            for _,command in ipairs(TGGPS.hud:getDrawCommands()) do if command.type=='symbol' then symbol=command end end
            TGGPS.hud:draw();local r=draws[#draws]
            local aspect=g_screenWidth/g_screenHeight
            local x=r.x+r.w/2*math.cos(r.angle)-r.h/2/aspect*math.sin(r.angle)
            local y=r.y+r.w/2*aspect*math.sin(r.angle)+r.h/2*math.cos(r.angle)
            assert(math.abs(x-symbol.cx)<0.000001 and math.abs(y-symbol.cy)<0.000001)
        end
        local iconId=draws[1].id
        assert(draws[#draws].id==iconId)
        TGGPS.hud:delete();assert(deleted[iconId])
        ''')


if __name__ == '__main__':
    unittest.main()
