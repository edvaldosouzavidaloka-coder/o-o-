"""Regressoes da plataforma, alcance, conjuntos e frenagem; FS25 simulado."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]


class ProtecaoTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        for name in ['TIProtecao.lua','TransbordoInteligente.lua','tests/fixture.lua']:
            self.lua.execute((ROOT/name).read_text())
        self.lua.execute('''
        P=TIProtecao
        tractor.size={width=3,length=6}
        wagon.size={width=3.5,length=8}
        combine.size={width=4,length=10}
        trailer.size={width=3,length=8}
        function attachHeader(width)
            local h=vehicle(0,8)
            h.rootNode.parent=combine.rootNode
            h.rootVehicle=combine
            h.spec_cutter={}
            h.size={width=4,length=3}
            h.spec_workArea={workAreas={{
                start=node(-width/2,-1.5,h.rootNode),
                width=node(width/2,-1.5,h.rootNode),
                height=node(-width/2,1.5,h.rootNode)
            }}}
            combine.attached={{object=h}}
            return h
        end
        function selectCombine()
            activate();tick()
            assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        end
        ''')

    def check(self,code):
        self.lua.execute(code)

    def test_work_area_defines_attached_header_width_even_when_size_is_small(self):
        self.check('''
        local header=attachHeader(15)
        local b=P.medir(header)
        assert(math.abs(2*b.hw-15)<0.000001)
        assert(b.plataforma)
        ''')

    def test_ai_markers_and_missing_size_use_actual_width(self):
        self.check('''
        local header=attachHeader(6)
        header.size.width=nil
        local b=P.medir(header)
        assert(math.abs(2*b.hw-6)<0.000001)
        assert(not b.larguraEstimada)
        header.spec_workArea=nil
        b=P.medir(header)
        assert(b.larguraEstimada and 2*b.hw==P.CONFIG.larguraPlataformaPadrao)
        function header:getAIMarkers()
            return node(-8,0,self.rootNode),node(8,0,self.rootNode),node(0,-2,self.rootNode)
        end
        b=P.medir(header)
        assert(math.abs(2*b.hw-16)<0.000001)
        assert(not b.larguraEstimada)
        ''')

    def test_nominal_pipe_alignment_is_not_permission_to_hit_header(self):
        self.check('''
        attachHeader(15);selectCombine()
        local x,z=TI.alvoReceber(tractor,combine)
        assert(x==-6 and z==108)
        assert(not P.posicaoLivre(tractor,combine,x,z,0))
        teleport(x,z)
        TI.dirigir(tractor,16,x,z+6,8)
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('plataforma'))
        assert(tractor.spec_transbordoInteligente.larguraPlataforma==15)
        ''')

    def test_high_current_speed_brakes_before_reaching_platform(self):
        self.check('''
        attachHeader(15);selectCombine()
        teleport(-6,100)
        tractor.speed=15
        assert(P.posicaoLivre(tractor,combine,-6,100,0))
        TI.dirigir(tractor,16,-6,114,15)
        assert(not tractor.command.allowed and tractor.command.speed==0)
        ''')

    def test_approach_slows_before_contact_while_still_clear(self):
        self.check('''
        attachHeader(15);selectCombine()
        teleport(-6,100)
        tractor.speed=0
        TI.dirigir(tractor,16,-6,114,15)
        assert(tractor.command.allowed and tractor.command.speed<=5)
        assert(tractor.command.speed<15)
        ''')

    def test_braking_loop_stops_before_header_in_kinematic_simulation(self):
        self.check('''
        attachHeader(15);selectCombine()
        teleport(-6,90)
        local v=15/3.6
        local dt=0.1
        for i=1,250 do
            tractor.speed=v*3.6
            TI.dirigir(tractor,dt*1000,-6,114,15)
            local requested=tractor.command.speed/3.6
            local nextV
            if requested<v then nextV=math.max(requested,v-2*dt)
            else nextV=math.min(requested,v+dt) end
            tractor.rootNode.z=tractor.rootNode.z+(v+nextV)/2*dt
            v=nextV
            assert(P.posicaoLivre(tractor,combine,tractor.rootNode.x,tractor.rootNode.z))
        end
        assert(v<0.01 and tractor.rootNode.z<103)
        ''')

    def test_wide_header_does_not_block_safe_pipe_lane_behind_it(self):
        self.check('''
        attachHeader(15);selectCombine()
        assert(P.posicaoLivre(tractor,combine,-6,90,0))
        assert(not P.posicaoLivre(tractor,combine,-6,108,0))
        assert(P.posicaoLivre(tractor,combine,-12,108,0))
        ''')

    def test_pipe_reach_does_not_artificially_increase_to_header_width(self):
        self.check('''
        attachHeader(18);selectCombine()
        combine.dischargeNode.node.x=-6
        local x=TI.alvoReceber(tractor,combine)
        assert(x==-6 and tractor.spec_transbordoInteligente.alcanceCano==6)
        assert(not P.posicaoLivre(tractor,combine,x,108,0))
        ''')

    def test_confirmed_receive_position_is_held_behind_platform(self):
        self.check('''
        attachHeader(15)
        wagon.rootNode.z=-6
        wagon.size.length=10
        selectCombine()
        teleport(-6,101.5)
        combine.raycastObject,combine.raycastIndex,combine.canDischarge=wagon,2,true
        local x,z=TI.alvoReceber(tractor,combine)
        assert(math.abs(z-101.5)<0.000001)
        assert(tractor.spec_transbordoInteligente.recebimentoConfirmado)
        assert(P.posicaoLivre(tractor,combine,x,z,0))
        combine.speed=5
        tick(16)
        assert(state()==E.ACOMPANHANDO)
        assert(tractor.command.allowed and tractor.command.speed==5)
        assert(math.abs(tractor.spec_transbordoInteligente.recebimentoZLocal-1.5)<0.000001)
        -- Ajustes automaticos do cano nao devem puxar a frente para a plataforma.
        combine.dischargeNode.node.z=2
        local _,heldZ=TI.alvoReceber(tractor,combine)
        assert(math.abs(heldZ-101.5)<0.000001)
        ''')

    def test_ray_target_for_other_wagon_cannot_latch_receive_offset(self):
        self.check('''
        attachHeader(15);selectCombine()
        teleport(-6,101)
        combine.raycastObject,combine.raycastIndex,combine.canDischarge=makeTrailer(0,0),2,true
        TI.alvoReceber(tractor,combine)
        assert(not tractor.spec_transbordoInteligente.recebimentoConfirmado)
        assert(tractor.spec_transbordoInteligente.recebimentoZLocal==nil)
        ''')

    def test_header_rotation_and_reattachment_change_measured_footprint(self):
        self.check('''
        local header=attachHeader(16);selectCombine()
        combine.rootNode.angle=0.8
        local pointX,_,pointZ=localToWorld(header.rootNode,7,0,0)
        assert(not P.posicaoLivre(tractor,combine,pointX,pointZ,0.8))
        combine.attached={}
        assert(P.posicaoLivre(tractor,combine,pointX,pointZ,0.8))
        ''')

    def test_truck_cabin_is_protected_even_when_receiver_is_offset_away(self):
        self.check('''
        local truck=vehicle(0,10)
        truck.size={width=4,length=6}
        trailer.rootNode.x,trailer.rootNode.z=-8,0
        trailer.rootVehicle=truck
        truck.attached={{object=trailer}}
        activate()
        tractor.spec_transbordoInteligente.caminhaoAlvo=trailer
        tractor.spec_transbordoInteligente.indiceCarreta=3
        tractor.speed=15
        assert(P.posicaoLivre(tractor,trailer,0,0,0))
        TI.dirigir(tractor,16,0,30,15)
        assert(not tractor.command.allowed)
        ''')

    def test_braking_loop_stops_before_truck_cabin(self):
        self.check('''
        local truck=vehicle(0,20)
        truck.size={width=4,length=6}
        trailer.rootNode.x,trailer.rootNode.z=-8,0
        trailer.rootVehicle=truck
        truck.attached={{object=trailer}}
        activate()
        tractor.spec_transbordoInteligente.caminhaoAlvo=trailer
        local v=15/3.6
        for i=1,200 do
            tractor.speed=v*3.6
            TI.dirigir(tractor,100,0,35,15)
            local requested=tractor.command.speed/3.6
            local nextV=requested<v and math.max(requested,v-0.2) or math.min(requested,v+0.1)
            tractor.rootNode.z=tractor.rootNode.z+(v+nextV)*0.05
            v=nextV
            assert(P.posicaoLivre(tractor,trailer,tractor.rootNode.x,tractor.rootNode.z))
        end
        assert(v<0.01 and tractor.rootNode.z<14)
        ''')

    def test_wagon_actual_yaw_and_position_are_checked_without_double_offset(self):
        self.check('''
        activate()
        tractor.spec_transbordoInteligente.caminhaoAlvo=trailer
        teleport(40,12)
        wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=0,-8,0.6
        -- A bazuca esta junto a carreta; o trator esta mais a frente.
        assert(not P.posicaoLivre(tractor,trailer,40,12))
        wagon.rootNode.x=10
        assert(P.posicaoLivre(tractor,trailer,40,12))
        ''')

    def test_safe_unloading_alignment_keeps_target_identity_checks(self):
        self.check('''
        activate()
        tractor.spec_transbordoInteligente.caminhaoAlvo=trailer
        tractor.spec_transbordoInteligente.indiceCarreta=3
        local x,z=TI.alvoDescarregar(tractor,trailer,3)
        assert(P.posicaoLivre(tractor,trailer,x,z,0))
        permitUnload(makeTrailer(40,0),3)
        assert(not TI.podeDescarregar(tractor))
        permitUnload(trailer,3)
        wagon.units[2].level,wagon.units[2].kind=20000,1
        assert(TI.podeDescarregar(tractor))
        ''')

    def test_approach_point_is_behind_measured_target_and_own_front(self):
        self.check('''
        local header=attachHeader(15)
        header.rootNode.z=-14
        selectCombine()
        local x,z,dx,dz=TI.alvoReceber(tractor,combine)
        local ax,az=P.aproximacao(tractor,combine,x,z,dx,dz,18)
        assert(az<80)
        assert(P.posicaoLivre(tractor,combine,ax,az,0))
        ''')

    def test_no_crop_read_or_world_collision_api_is_needed(self):
        self.check('''
        attachHeader(15);selectCombine()
        coroutine,overlapBox,g_fruitTypeManager,DensityMapModifier=nil,nil,nil,nil
        teleport(-6,100)
        tractor.speed=15
        TI.dirigir(tractor,16,-6,114,15)
        assert(not tractor.command.allowed)
        ''')

    def test_invalid_native_markers_stop_without_escaping_update(self):
        self.check('''
        local header=attachHeader(15);selectCombine()
        function header:getAIMarkers() error('marcador de mod invalido') end
        TI.dirigir(tractor,16,-6,110,15)
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('medir'))
        ''')


if __name__=='__main__':
    unittest.main(verbosity=2)
