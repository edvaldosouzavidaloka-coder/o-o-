"""Regressoes de reconhecimento e continuidade; sem fisica/fluxo real do FS25."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class ReconhecimentoTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        for name in ['TITalhao.lua', 'TIProtecao.lua', 'TransbordoInteligente.lua', 'tests/fixture.lua']:
            self.lua.execute((ROOT / name).read_text())

    def check(self, code):
        self.lua.execute(code)

    def test_auto_aim_center_precedes_offset_exact_trigger(self):
        self.check('''
        wagon.units[2].fillRoot.z=3
        local aim=node(0,0,wagon.rootNode)
        function wagon:getFillUnitAutoAimTargetNode(i) assert(i==2);return aim end
        activate()
        local x,z=TI.alvoReceber(tractor,combine)
        teleport(x,z)
        local fx,_,fz=TI.pontoEnchimento(wagon,2)
        local px,_,pz=getWorldTranslation(combine.dischargeNode.node)
        assert(math.abs(fx-px)<0.000001 and math.abs(fz-pz)<0.000001)
        assert(z==108) -- o gatilho antigo faria parar tres metros antes
        ''')

    def test_dynamic_aim_range_uses_midpoint_without_moving_engine_node(self):
        self.check('''
        local aim=node(1,4,wagon.rootNode)
        function wagon:getFillUnitAutoAimTargetNode() return aim end
        wagon.spec_fillUnit.fillUnits[2].autoAimTarget={node=aim,
            baseTrans={1,0,2},startZ=-2,endZ=6}
        local x,_,z=TI.pontoEnchimento(wagon,2)
        assert(x==1 and z==-6)
        aim.z=-2 -- a engine animou a mira para outra ponta da cacamba
        local nx,_,nz=TI.pontoEnchimento(wagon,2)
        assert(nx==x and nz==z and aim.z==-2)
        ''')

    def test_first_discharge_confirmation_does_not_stop_before_safe_center(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        enterCombineRear()
        teleport(x,z-2)
        combine.raycastObject,combine.raycastIndex,combine.canDischarge=wagon,2,true
        local tx,tz=TI.alvoReceber(tractor,combine)
        assert(tx==x and tz==z)
        local spec=tractor.spec_transbordoInteligente
        assert(spec.recebimentoConfirmado and spec.recebimentoZLocal==nil)
        tick(100)
        assert(tractor.command.allowed and tractor.command.forwards)
        assert(tractor.command.speed>=1.3)
        ''')

    def test_final_approach_crosses_native_one_kmh_cutoff_and_stops_at_center(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        enterCombineRear()
        teleport(x,z-1.2)
        for i=1,120 do
            tick(100)
            local command=tractor.command
            -- FS25 nao acelera quando o limite de velocidade fica abaixo de 1.
            if command.allowed and command.speed>=1 then
                tractor.rootNode.z=tractor.rootNode.z+(command.forwards and 1 or -1)*command.speed/3.6*0.1
            end
        end
        assert(math.abs(tractor.rootNode.z-z)<TI.CONFIG.toleranciaLongitudinal)
        assert(not tractor.command.allowed and tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_stationary_combine_overshoot_reenters_from_rear_in_forward_gear(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        enterCombineRear()
        teleport(x,z+1)
        tick(100)
        assert(state()==E.APROXIMANDO and not tractor.spec_transbordoInteligente.entradaPelaTraseira)
        tick(100)
        assert(tractor.command.allowed and not tractor.command.forwards)
        assert(tractor.command.z<0 and math.abs(tractor.command.x)<0.001)
        ''')

    def test_lateral_error_alone_does_not_hold_stationary_combine_follower(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        enterCombineRear()
        teleport(x-0.5,z)
        tick(100)
        assert(tractor.command.allowed and tractor.command.x>0)
        ''')

    def test_trailer_on_current_side_can_be_served_in_opposite_heading(self):
        self.check('''
        activate()
        teleport(35,0)
        tractor.rootNode.angle=math.pi
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        assert(x<40 and dz<0 and tractor.spec_transbordoInteligente.sentidoDestino==-1)
        tractor.rootNode.x,tractor.rootNode.z=x,z
        local px,_,pz=getWorldTranslation(wagon.dischargeNode.node)
        local fx,_,fz=TI.pontoEnchimento(trailer,3)
        assert(math.abs(px-fx)<0.000001 and math.abs(pz-fz)<0.000001)
        local ax,az=TIProtecao.aproximacao(tractor,trailer,x,z,dx,dz,18)
        assert((ax-x)*dx+(az-z)*dz<=-18)
        assert(TIProtecao.posicaoLivre(tractor,trailer,ax,az,math.pi))
        ''')

    def test_trailer_aim_node_aligns_pipe_instead_of_exact_trigger(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        trailer.units[3].fillRoot.z=-4
        local aim=node(0,1,trailer.rootNode)
        function trailer:getFillUnitAutoAimTargetNode() return aim end
        activate();tick()
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x,z,math.atan2(dx,dz)
        local px,_,pz=getWorldTranslation(wagon.dischargeNode.node)
        local fx,_,fz=getWorldTranslation(aim)
        assert(math.abs(px-fx)<0.000001 and math.abs(pz-fz)<0.000001)
        ''')

    def test_truck_final_approach_crawls_then_corrects_small_overshoot(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x-dx,z-dz,math.atan2(dx,dz)
        tick(100)
        assert(tractor.command.allowed and tractor.command.forwards and tractor.command.speed>=1.3)
        tractor.rootNode.x,tractor.rootNode.z=x+dx,z+dz
        tick(100)
        assert(tractor.command.allowed and not tractor.command.forwards)
        assert(tractor.command.speed==TI.CONFIG.velocidadeRe)
        ''')

    def test_far_truck_overshoot_returns_to_approach_without_join_reset_loop(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x+dx*30,z+dz*30,math.atan2(dx,dz)
        tractor.spec_transbordoInteligente.aproximacaoConcluida=true
        tick();tick()
        assert(tractor.command.allowed)
        assert(not tractor.spec_transbordoInteligente.aproximacaoConcluida)
        ''')

    def test_search_finds_roadside_trailer_beyond_old_initial_radius(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        teleport(350,0,trailer)
        activate();tick(250)
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        ''')

    def test_search_does_not_leave_current_field_for_distant_trailer(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        local field=makeField(-30,-10,30,150)
        g_farmlandManager={getFarmlandAtWorldPosition=function()
            return {getField=function() return field end}
        end}
        teleport(250,0,trailer)
        activate();tick(250)
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==nil)
        teleport(1000,0,trailer)
        assert(TI.encontrarCaminhao(tractor)==nil)
        ''')

    def test_search_reacts_to_new_trailer_in_quarter_second(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        trailer.units[3].supported[1]=false
        activate();tick(250)
        assert(state()==E.BUSCANDO_CARRETA)
        trailer.units[3].supported[1]=true
        tick(250)
        assert(state()==E.APROXIMANDO_CARRETA)
        ''')

    def test_cached_discharge_node_keeps_empty_wagon_readable_and_active(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick();alignTrailer();permitUnload();tick();tick()
        wagon.units[2].level,wagon.units[2].kind=0,0
        function wagon:getCurrentDischargeNode() return nil end
        wagon.spec_dischargeable.dischargeNodes={}
        assert(TI.getCarga(wagon).percentual==0)
        tick()
        assert(state()==E.SAINDO and tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_missing_cargo_data_waits_and_recovers_without_turning_off(self):
        self.check('''
        activate()
        local original=wagon.getFillUnitCapacity
        wagon.getFillUnitCapacity=function() return 0 end
        tick()
        assert(tractor.spec_transbordoInteligente.isAtivo and not tractor.command.allowed)
        wagon.getFillUnitCapacity=original
        tick();assert(state()==E.APROXIMANDO)
        ''')

    def test_empty_source_can_be_replaced_by_another_ready_combine(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        teleport(x,z);tick()
        local other=makeCombine(30,100,7000)
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        combine.units[2].level=0
        tick();assert(state()==E.SAINDO)
        local spec=tractor.spec_transbordoInteligente
        teleport(spec.saidaX,spec.saidaZ);tick();tick()
        assert(spec.isAtivo and spec.colheitadeiraAlvo==other)
        ''')

    def test_exit_without_header_is_forward_and_outward(self):
        self.check('''
        activate();tick()
        teleport(-6,108)
        wagon.units[2].level,wagon.units[2].kind=20000,1
        tick();assert(state()==E.SAINDO)
        local spec=tractor.spec_transbordoInteligente
        assert(spec.saidaZ>108 and spec.saidaX<-6 and not spec.saidaDeRe)
        tick();assert(tractor.command.forwards and tractor.command.allowed)
        ''')

    def test_behind_waypoint_gets_consistent_turn_point_ahead(self):
        self.check('''
        activate()
        TI.dirigir(tractor,100,0,-40,15)
        assert(tractor.command.forwards and tractor.command.allowed)
        assert(tractor.command.z>0 and math.abs(tractor.command.x)>1)
        local side=tractor.command.x
        TI.dirigir(tractor,100,-0.1,-40,15)
        assert(tractor.command.x*side>0)
        ''')

    def test_direction_change_brakes_until_stopped_before_reverse(self):
        self.check('''
        activate()
        tractor.speed,tractor.movingDirection=2,1
        TI.dirigir(tractor,100,0,-2,1.5,false)
        assert(not tractor.command.allowed and not tractor.command.forwards)
        tractor.speed=0
        TI.dirigir(tractor,100,0,-2,1.5,false)
        assert(tractor.command.allowed and not tractor.command.forwards)
        ''')

    def test_two_complete_cycles_do_not_require_toggle_again(self):
        self.check('''
        activate()
        for cycle=1,2 do
            tick();assert(state()==E.APROXIMANDO)
            local x,z=TI.alvoReceber(tractor,combine)
            enterCombineRear()
            teleport(x,z);tick()
            wagon.units[2].level,wagon.units[2].kind=5000,1
            combine.units[2].level=0
            tick();assert(state()==E.AGUARDANDO_CARGA)
            tick(60000);assert(state()==E.AGUARDANDO_CARGA)
            combine.units[2].level=1000
            tick();assert(state()==E.ACOMPANHANDO)
            wagon.units[2].level=20000
            tick();assert(state()==E.SAINDO)
            local spec=tractor.spec_transbordoInteligente
            teleport(spec.saidaX,spec.saidaZ);tick();tick()
            assert(state()==E.APROXIMANDO_CARRETA)
            local tx,tz,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
            teleport(tx,tz);tractor.rootNode.angle=math.atan2(dx,dz)
            alignTrailer();permitUnload();tick();tick()
            assert(state()==E.DESCARREGANDO and wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
            wagon.units[2].level,wagon.units[2].kind=0,0
            tick();assert(state()==E.SAINDO)
            teleport(spec.saidaX,spec.saidaZ);tick()
            assert(state()==E.BUSCANDO and spec.isAtivo and not wagon.turnedOn)
            assert(TI.reservasCarretas[trailer]==nil and TI.reservasColheitadeiras[combine]==nil)
            combine.units[2].level=6000
        end
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
