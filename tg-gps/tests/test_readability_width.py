import unittest
import xml.etree.ElementTree as E
import test_monitor as baseline

class ReadabilityWidthTests(unittest.TestCase):
    setUp=baseline.MonitorTests.setUp
    check=baseline.MonitorTests.check

    def test_stop_sample_uses_the_three_native_arguments_on_play_and_cleanup(self):
        self.check('''
        local calls=0
        function stopSample(...)
            assert(select('#',...)==3,'Native stopSample requires exactly three arguments')
            local sample,delay,fade=...;assert(delay==0 and fade==0)
            calls=calls+1;sample.stopped=true
        end
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        TGGPS:stopAutosteer();tractor.motorOn=false;TGGPS:update(250)
        TGGPS:deleteMap();assert(calls>=6)
        ''')

    def test_fractional_paint_edges_match_real_tool_width_at_each_perspective_depth(self):
        self.check('''
        local pose={x=0,z=0,dx=0,dz=1}
        for _,width in ipairs({2.4,6.4,12.8}) do
            local half=width/2
            local shapes={{points={{x=-half,z=0},{x=half,z=0},{x=half,z=60}}},
                {points={{x=-half,z=0},{x=half,z=60},{x=-half,z=60}}}}
            local strips=TGGPSPerspective.paintStrips(pose,shapes,128,180,true)
            assert(#strips>10 and #strips<=180)
            for _,strip in ipairs(strips) do
                local depth=22/(.95-strip.y-strip.h/2)-35
                local expected=width*1.9/(depth+35)
                assert(math.abs(strip.w-expected)<.000001)
                assert(math.abs(strip.x+strip.w/2-.5)<.000001)
            end
        end
        ''')

    def test_overlap_grid_cannot_expand_continuous_implement_edges(self):
        self.check('''
        local pose={x=0,z=0,dx=0,dz=1}
        local shapes={{points={{x=-3.2,z=0},{x=3.2,z=0},{x=3.2,z=60},{x=-3.2,z=60}}},
            {x=-4,z=0,w=8,h=60,overlap=true}}
        for _,strip in ipairs(TGGPSPerspective.paintStrips(pose,shapes,128,180,true)) do
            local depth=22/(.95-strip.y-strip.h/2)-35
            assert(strip.overlap and math.abs(strip.w-6.4*1.9/(depth+35))<.000001)
        end
        ''')

    def test_turning_machine_rotates_paint_without_changing_width(self):
        self.check('''
        local pose={x=10,z=20,dx=1,dz=0}
        local shapes={{points={{x=10,z=16.8},{x=10,z=23.2},{x=70,z=23.2},{x=70,z=16.8}}}}
        for _,strip in ipairs(TGGPSPerspective.paintStrips(pose,shapes,128,180,true)) do
            local depth=22/(.95-strip.y-strip.h/2)-35
            assert(math.abs(strip.w-6.4*1.9/(depth+35))<.000001)
        end
        ''')

    def test_accented_labels_use_real_glyphs_and_are_full_height(self):
        self.check('''
        TGGPS.cabPerspective=true;metadata();TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        screen:pixelText('Orientação',20,20,30,20,true)
        assert(screen.templates.text_231 and screen.templates.text_227 and screen.templates.text_176)
        assert((screen.used.textWhite_231 or 0)>0 and (screen.used.textWhite_227 or 0)>0)
        assert(screen.count<=screen.MAX_PRIMITIVES)
        ''')
        root=E.parse(baseline.ROOT/'models/tgGPSMonitorPrimitives.i3d').getroot()
        for code in (65,97,231,227):
            node=root.find('.//Scene//Shape[@name="text_'+str(code)+'"]')
            shape=root.find('./Shapes/IndexedTriangleSet[@shapeId="'+node.get('shapeId')+'"]')
            points=[list(map(float,v.get('p').split())) for v in shape.findall('./Vertices/v')]
            self.assertGreater(max(v[1] for v in points)-min(v[1] for v in points),.60)

    def test_production_display_hides_old_baked_screen_and_reflective_glass(self):
        self.check('''
        TGGPS.cabPerspective=true;TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local display=TGGPS.monitor.screenRenderer.greenStar
        assert(display.state=='ready' and not display.screen.visible)
        local glass=TGGPSGreenStar.find(display.layout.root,'glass');assert(glass and not glass.visible)
        assert(display.orientation.visible and not display.controls.visible)
        ''')

    def test_instrument_shell_has_full_2k_bc3_mips_and_transparent_live_window(self):
        import struct
        from PIL import Image
        path=baseline.ROOT/'models/textures/orientationShell.dds'
        data=path.read_bytes()
        self.assertEqual(data[84:88],b'DXT5')
        self.assertEqual(struct.unpack_from('<II',data,12),(2048,2048))
        self.assertEqual(struct.unpack_from('<I',data,28)[0],12)
        size=128
        for i in range(12):
            n=max(1,2048>>i);size+=max(1,(n+3)//4)**2*16
        self.assertEqual(len(data),size)
        image=Image.open(path).convert('RGBA')
        self.assertEqual(image.getpixel((1024,1200))[3],0)
        self.assertEqual(image.getpixel((30,30))[3],255)

    def test_font_advances_preserve_punctuation_and_proportional_spacing(self):
        self.check('''
        assert(TGGPSGlyphs[46]<TGGPSGlyphs[48] and TGGPSGlyphs[105]<TGGPSGlyphs[77])
        ''')
        root=E.parse(baseline.ROOT/'models/tgGPSMonitorPrimitives.i3d').getroot()
        node=root.find('.//Scene//Shape[@name="text_46"]')
        mesh=root.find('./Shapes/IndexedTriangleSet[@shapeId="'+node.get('shapeId')+'"]')
        ys=[float(v.get('p').split()[1]) for v in mesh.findall('./Vertices/v')]
        self.assertLess(max(ys)-min(ys),.25)
