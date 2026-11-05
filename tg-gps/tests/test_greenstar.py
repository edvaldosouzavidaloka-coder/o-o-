import hashlib
import json
from pathlib import Path
import subprocess
import unittest
import xml.etree.ElementTree as ET
import test_monitor as baseline

ROOT = baseline.ROOT


class GreenStarTests(unittest.TestCase):
    setUp = baseline.MonitorTests.setUp
    check = baseline.MonitorTests.check

    def test_original_binary_and_all_characters_are_preserved_byte_for_byte(self):
        folder = ROOT/'models/greenstar'
        hashes = json.loads((folder/'source-hashes.json').read_text())
        self.assertEqual(len(hashes), 7)
        for name, digest in hashes.items():
            self.assertEqual(hashlib.sha256((folder/name).read_bytes()).hexdigest(), digest, name)
        self.assertEqual(hashes['Textures/GPS3000.dds'], 'df206ade9e4f58179a42d31166e5b785d16b20418d3cd9d45fcd367093c2b5a3')
        root = ET.parse(ROOT/'models/curveGPSMonitor.i3d').getroot()
        self.assertEqual(root.find('Shapes').get('externalShapesFile'), 'greenstar/GPS.i3d.shapes')
        self.assertEqual({n.get('shapeId') for n in root.findall('.//Scene//Shape')}, set(map(str, range(1, 15))))
        self.assertTrue(all(',' not in n.get('materialIds') for n in root.findall('.//Scene//Shape')))

    def test_actual_imported_scene_is_normalized_before_cab_parenting(self):
        self.check('''
        local model=loadI3DFile(TGGPS.MOD_DIRECTORY..'models/curveGPSMonitor.i3d')
        local layout=TGGPSGreenStar.prepare(model);assert(layout)
        local cx,cy,cz,r=getShapeGeometryBoundingSphere(layout.screen)
        local x,y,z=localToLocal(layout.screen,layout.root,cx,cy,cz)
        assert(math.abs(x)+math.abs(y)+math.abs(z)<0.000001)
        local dx,dy,dz=localDirectionToWorld(layout.screen,0,0,1)
        local ux,uy,uz=localDirectionToWorld(layout.screen,0,1,0)
        assert(math.abs(dx)+math.abs(dy)+math.abs(dz-1)<0.000001)
        assert(math.abs(ux)+math.abs(uy-1)+math.abs(uz)<0.000001)
        assert(math.abs(layout.width/layout.height-4/3)<0.000001)
        assert(math.abs(layout.width^2+layout.height^2-4*r*r)<0.000001)
        delete(model)
        ''')

    def test_boot_progress_power_cycle_and_connection_tones_follow_motor_state(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer;local display=screen.greenStar
        assert(display.state=='boot' and display.boot.visible and not display.screen.visible)
        assert(not screen.contentRoot.visible and display.progress>0 and display.progress<1)
        assert(#soundEvents==0)
        local previous=display.progress;TGGPS:update(500);assert(display.progress>previous)
        TGGPS:update(1000)
        assert(display.state=='ready' and display.screen.visible and screen.contentRoot.visible)
        assert(not display.boot.visible and #soundEvents==1)
        assert(soundEvents[1].sample.name=='TGGPS_connect')
        TGGPS:update(1000);assert(#soundEvents==1)
        tractor.motorOn=false;TGGPS:update(250)
        assert(display.state=='off' and not display.boot.visible and not display.screen.visible)
        assert(not display.controls.visible and screen.used.off==1)
        assert(#soundEvents==2 and soundEvents[2].sample.name=='TGGPS_disconnect')
        tractor.motorOn=true;TGGPS:update(250);assert(display.state=='boot' and display.progress==0)
        TGGPS:update(1800);assert(display.state=='ready' and #soundEvents==3)
        ''')

    def test_uploaded_work_ring_moves_only_with_real_work_and_vehicle_motion(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local display=TGGPS.monitor.screenRenderer.greenStar
        assert(not display.working and not display.workRing.visible)
        tractor.speed=6;move(0,2);TGGPS:update(100)
        assert(TGGPS.coverage.working and display.working and display.workRing.visible)
        local rotation=display.workRing.rz
        move(0,3);TGGPS:update(100);assert(display.workRing.rz~=rotation)
        tool.active=false;TGGPS:update(100)
        assert(not display.working and not display.workRing.visible)
        rotation=display.workRing.rz;TGGPS:update(100);assert(display.workRing.rz==rotation)
        tool.active=true;tractor.speed=0;TGGPS:update(100);assert(not display.working)
        ''')

    def test_real_map_stays_in_work_window_and_original_controls_are_restored_above_it(self):
        overlay = ET.parse(ROOT/'models/tgGreenStarOverlay.i3d').getroot()
        controls = overlay.find('./Scene/TransformGroup[@name="GreenStarOriginalControls"]')
        self.assertEqual(len([n for n in controls if n.get('name').startswith('originalControl')]), 8)
        texture = overlay.find('./Files/File[@fileId="2"]').get('filename')
        self.assertEqual(texture, 'greenstar/Textures/GPS3000.dds')
        self.check('''
        metadata();TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.nativeNode and screen.greenStar.controls.visible)
        assert(screen.used.symbol_tractor>0 and screen.used.coverage>0)
        local box=TGGPSGreenStar.MAP_BOX
        for _,style in ipairs({'coverage','coverage_overlap','selected_lane','boundary','symbol_tractor'}) do
            for i=1,screen.used[style] or 0 do
                local node=screen.pools[style][i]
                local x,y=node.x/screen.WIDTH+.5,node.y/screen.HEIGHT+.5
                assert(x>=box.x-0.00001 and x<=box.x+box.w+0.00001)
                assert(y>=box.y-0.00001 and y<=box.y+box.h+0.00001)
                assert(node.z<0.0075)
            end
        end
        ''')

    def test_tractor_and_combine_choose_stable_cab_corners_and_saved_placement_wins(self):
        self.check('''
        local cab=makeNode('tractorCab',tractor.rootNode)
        local camera=makeNode('camera',cab,0,2,0)
        tractor.spec_enterable.cameras={{isInside=true,cameraPositionNode=camera}}
        TGGPS:update(100);TGGPS:update(450)
        local manager=TGGPS.monitor
        assert(manager.parentNode==cab and manager.placement.positionX==-.35)
        manager.settings['combine.xml']={positionX=-.6,positionY=2.1,positionZ=.9,
            rotationX=-8,rotationY=175,rotationZ=1,scale=1.1}
        local other={rootNode=makeNode('combine'),tgGpsSupported=true,configFileName='combine.xml',spec_combine={},components={}}
        other.components={{node=other.rootNode}}
        local cab2=makeNode('combineCab',other.rootNode)
        local camera2=makeNode('camera',cab2,0,2.5,.1)
        other.spec_enterable={cameras={{isInside=true,cameraPositionNode=camera2}}}
        g_currentMission.controlledVehicle=other;TGGPS:update(100);TGGPS:update(450)
        assert(manager.parentNode==cab2 and manager.defaultPlacement.positionX==-.42)
        assert(math.abs(manager.defaultPlacement.positionY-2.2)<0.000001)
        assert(manager.placement.positionX==-.6 and manager.placement.scale==1.1)
        camera2.ry=1.5;assert(manager.monitorNode.ry==math.rad(175))
        ''')

    def test_combine_header_width_kind_and_footprint_are_recognized_together(self):
        self.check('''
        metadata();tractor.spec_combine={};tool.spec_cutter={}
        tool.area.start.x=-4.5;tool.area.width.x=4.5;tool.area.height.x=-4.5
        TGGPS:update(100);TGGPS:update(450)
        local state=TGGPS.recognition.state
        assert(state.kind=='combine' and state.implement==tool and math.abs(state.width-9)<0.000001)
        assert(state.pose.x==0 and state.pose.z==0 and TGGPS.coverage.footprint.z<0)
        local screen=TGGPS.monitor.screenRenderer;assert(screen.used.symbol_combine_cutter>0)
        ''')

    def test_native_field_edges_and_headland_are_detected_without_generating_or_driving(self):
        self.check('''
        metadata();TGGPS.fieldBoundary=nil;TGGPS.sourcePoints={};TGGPS.basePath={};TGGPS.guidanceLines={}
        TGGPS:update(100)
        local state=TGGPS.recognition.state
        assert(state.fieldId==3 and state.inField and math.abs(state.borderDistance-30)<0.00001)
        assert(math.abs(state.forwardDistance-120)<0.00001 and not state.nearHeadland)
        assert(TGGPS.fieldBoundary==nil and #TGGPS.sourcePoints==0 and not TGGPS.autosteerEnabled)
        local boundary=TGGPS.recognition.boundary
        move(0,110);TGGPS:update(1000)
        state=TGGPS.recognition.state
        assert(state.nearHeadland and math.abs(state.borderDistance-10)<0.00001)
        assert(math.abs(state.forwardDistance-10)<0.00001 and TGGPS.recognition.boundary==boundary)
        local hasBoundary=false
        for _,command in ipairs(TGGPSMap.getDrawCommands(TGGPS,{x=0,y=0,w=1,h=1})) do
            if command.role=='boundary' then hasBoundary=true end
        end
        assert(hasBoundary and TGGPS.fieldBoundary==nil)
        move(0,125);TGGPS:update(1000);state=TGGPS.recognition.state
        assert(not state.inField and not state.nearHeadland)
        ''')

    def test_unavailable_field_api_clears_old_observation_without_guessing(self):
        self.check('''
        metadata();TGGPS:update(100);assert(TGGPS.recognition.boundary)
        g_farmlandManager=nil;TGGPS:update(1000)
        local state=TGGPS.recognition.state
        assert(state.boundary==nil and state.borderDistance==nil and state.forwardDistance==nil)
        assert(state.reason=='field_api_unavailable' and not state.nearHeadland)
        assert(not TGGPS.autosteerEnabled)
        ''')

    def test_border_measurement_handles_polygon_corners_and_reverse_heading(self):
        self.check('''
        local polygon={{x=0,z=0},{x=20,z=0},{x=20,z=20},{x=0,z=20}}
        local nearest,forward,inside=TGGPSRecognition.measure(polygon,{x=1,z=1,dx=0,dz=-1})
        assert(nearest==1 and forward==1 and inside)
        nearest,forward,inside=TGGPSRecognition.measure(polygon,{x=19,z=19,dx=1,dz=0})
        assert(nearest==1 and forward==1 and inside)
        nearest,forward,inside=TGGPSRecognition.measure(polygon,{x=25,z=10,dx=1,dz=0})
        assert(nearest==5 and forward==nil and not inside)
        ''')

    def test_engage_disengage_sounds_mute_and_persistence_are_event_driven(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local initial=#soundEvents
        TGGPS:update(400);TGGPS:onEnableAutosteer()
        assert(TGGPS.autosteerEnabled and #soundEvents==initial+1)
        assert(soundEvents[#soundEvents].sample.name=='TGGPS_connect')
        TGGPS:stopAutosteer();assert(#soundEvents==initial+2)
        TGGPS:stopAutosteer();assert(#soundEvents==initial+2)
        TGGPS:onToggleMonitorSounds();assert(not TGGPS.monitorSounds)
        TGGPS:update(400);TGGPS:onEnableAutosteer();TGGPS:stopAutosteer()
        assert(#soundEvents==initial+2)
        TGGPS.monitorSounds=true;TGGPS:loadHudSettings();assert(not TGGPS.monitorSounds)
        ''')

    def test_all_sound_samples_and_loaded_models_are_released_on_map_unload(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local overlay=TGGPS.monitor.screenRenderer.greenStar.overlay
        assert(#samples==2)
        TGGPS:deleteMap();assert(overlay.deleted and TGGPS.audio==nil and TGGPS.recognition==nil)
        for _,sample in ipairs(samples) do assert(sample.deleted and sample.stopped and sample.is3D==false) end
        for _,node in ipairs(nodes) do
            if node.name=='i3dRoot' then assert(node.deleted) end
        end
        ''')

    def test_silent_and_failed_audio_devices_do_not_break_monitor(self):
        self.check('''
        local active=samples
        TGGPS.audio:delete()
        function loadSample() return false end
        TGGPS.audio=TGGPSAudio.new(TGGPS,TGGPS.MOD_DIRECTORY)
        assert(next(TGGPS.audio.samples)==nil)
        TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        assert(TGGPS.monitor.screenRenderer.greenStar.state=='ready')
        for i=3,#samples do assert(samples[i].deleted) end
        createSample=nil;TGGPS.audio:delete()
        TGGPS.audio=TGGPSAudio.new(TGGPS,TGGPS.MOD_DIRECTORY)
        assert(not TGGPS.audio:play('connect'))
        ''')

    def test_connection_audio_is_mono_decodable_and_self_contained(self):
        for name in ('connect', 'disconnect'):
            path = ROOT/'sounds'/(name+'.ogg')
            info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-of', 'json', str(path)]))
            self.assertEqual(info['streams'][0]['channels'], 1)
            self.assertEqual(info['streams'][0]['sample_rate'], '44100')
            self.assertGreater(float(info['streams'][0]['duration']), .2)
            subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'null', '-'], check=True, capture_output=True)

    def test_fuel_per_hectare_readout_and_cross_track_indicator_use_real_values(self):
        self.check('''
        metadata();tractor.speed=10;tractor.spec_motorized={lastFuelUsageDisplay=12}
        TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        assert(screen.readoutFuel=='2.0' and screen.crossTrackMetres==0)
        TGGPS.autoLaneSelection=false;move(1,10);TGGPS:update(250)
        assert(math.abs(screen.crossTrackMetres-1)<0.000001)
        tool.active=false;TGGPS:update(250);assert(screen.readoutFuel=='--')
        ''')


if __name__ == '__main__': unittest.main()
