"""Regressoes Lua simuladas; executar com Python + lupa==2.6 (Lua 5.1)."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class TransbordoTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'TransbordoInteligente.lua').read_text())
        self.lua.execute((ROOT / 'tests' / 'fixture.lua').read_text())

    def check(self, code):
        self.lua.execute(code)

    def test_threshold_exactly_sixty_and_fuel_excluded(self):
        self.check('''
        activate()
        combine.units[2].level=5999
        tick(); assert(state() == E.BUSCANDO)
        combine.units[2].level=6000
        tick(); assert(state() == E.APROXIMANDO)
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo == combine)
        assert(TI.getCarga(combine).percentual == 60)
        assert(TI.getCarga(wagon).percentual == 0)
        ''')

    def test_most_full_then_nearest_with_unlimited_scan(self):
        self.check('''
        for i=1,35 do table.insert(g_currentMission.vehicleSystem.vehicles,makeCombine(i,50,6000)) end
        local highest=makeCombine(15,80,9500)
        table.insert(g_currentMission.vehicleSystem.vehicles,highest)
        activate(); tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo == highest)
        ''')

    def test_equal_fill_prioritizes_nearest(self):
        self.check('''
        local near=makeCombine(0,25,6000)
        table.insert(g_currentMission.vehicleSystem.vehicles,near)
        activate(); tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo == near)
        ''')

    def test_player_and_native_combine_worker_both_eligible(self):
        for ai in ('true', 'false'):
            with self.subTest(native_combine_worker=ai):
                self.setUp()
                self.check(f'''
                combine.nativeAI={ai}
                activate(); tick(); assert(state() == E.APROXIMANDO)
                ''')

    def test_other_farm_and_wrong_crop_not_selected(self):
        self.check('''
        activate()
        combine.farm=2; tick(); assert(state() == E.BUSCANDO)
        combine.farm=1; wagon.units[2].supported[1]=false
        tick(); assert(state() == E.BUSCANDO)
        ''')

    def test_two_augers_do_not_reserve_same_combine(self):
        self.check('''
        activate(); tick()
        local other=vehicle(5,0)
        local auger=vehicle(5,-8)
        unit(auger,2,20000,0,0); discharger(auger,2,-5,0)
        other.attached={{object=auger}}
        TI.onLoad(other); activate(other); tick(1000,other)
        assert(state(other) == E.BUSCANDO)
        activate(); tick(1000,other)
        assert(state(other) == E.APROXIMANDO)
        ''')

    def test_field_lock_excludes_more_full_combine_on_other_field(self):
        self.check('''
        local fieldA=makeField(-30,-10,30,150)
        local fieldB=makeField(100,-10,150,150)
        g_farmlandManager={getFarmlandAtWorldPosition=function(_,x,z)
            local f=x<70 and fieldA or fieldB
            return {getField=function() return f end}
        end}
        local other=makeCombine(120,100,10000)
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        activate(); tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo == combine)
        ''')

    def test_trailer_filter_checks_capacity_crop_farm_and_attachment(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        local full=makeTrailer(1,0,30000,1)
        local wrong=makeTrailer(2,0,1000,2)
        local foreign=makeTrailer(3,0,0,0,2)
        local unsupported=makeTrailer(4,0); unsupported.units[3].supported[1]=false
        local tank=vehicle(1,0); unit(tank,3,50000,0,0)
        for _,v in ipairs({full,wrong,foreign,unsupported,tank}) do
            table.insert(g_currentMission.vehicleSystem.vehicles,v)
        end
        activate(); tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo == trailer)
        assert(tractor.spec_transbordoInteligente.indiceCarreta == 3)
        ''')

    def test_stationary_nearest_trailer_and_scan_radius(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        trailer.speed=2
        local far=makeTrailer(500,0)
        local near=makeTrailer(20,0)
        table.insert(g_currentMission.vehicleSystem.vehicles,far)
        table.insert(g_currentMission.vehicleSystem.vehicles,near)
        activate(); tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo == near)
        ''')

    def test_edge_restriction_ignores_trailer_in_middle_of_large_field(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        local field=makeField(-500,-500,500,500)
        g_farmlandManager={getFarmlandAtWorldPosition=function()
            return {getField=function() return field end}
        end}
        local edge=makeTrailer(490,0)
        table.insert(g_currentMission.vehicleSystem.vehicles,edge)
        activate(); tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo == edge)
        ''')

    def test_waits_with_brake_when_no_compatible_trailer(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        trailer.units[3].level=30000; trailer.units[3].kind=1
        activate(); tick()
        assert(state() == E.BUSCANDO_CARRETA)
        assert(tractor.command.allowed == false and tractor.command.speed == 0)
        assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OFF)
        ''')

    def test_follows_actual_fill_root_and_does_not_multiply_speed(self):
        self.check('''
        activate(); tick()
        local x,z=TI.alvoReceber(tractor,combine)
        assert(x == -6 and z == 108)
        teleport(x,z-18); tick()
        teleport(x,z); combine.speed=8; tick()
        assert(state() == E.ACOMPANHANDO)
        tick()
        assert(tractor.command.speed == 8)
        assert(tractor.command.forwards and tractor.command.dt == 1000)
        combine.speed=0; tick()
        assert(not tractor.command.allowed)
        ''')

    def test_full_auger_leaves_combine_then_seeks_trailer(self):
        self.check('''
        activate(); tick()
        wagon.units[2].level=20000; wagon.units[2].kind=1
        tick(); assert(state() == E.SAINDO)
        local spec=tractor.spec_transbordoInteligente
        teleport(spec.saidaX,spec.saidaZ); tick()
        assert(state() == E.BUSCANDO_CARRETA)
        assert(TI.reservasColheitadeiras[combine] == nil)
        tick(); assert(state() == E.APROXIMANDO_CARRETA)
        ''')

    def test_empty_combine_does_not_send_part_filled_auger_to_truck(self):
        self.check('''
        activate(); tick()
        wagon.units[2].level=5000; wagon.units[2].kind=1
        combine.units[2].level=0
        tick(); assert(state() == E.SAINDO)
        local spec=tractor.spec_transbordoInteligente
        teleport(spec.saidaX,spec.saidaZ); tick()
        assert(state() == E.BUSCANDO)
        assert(wagon.units[2].level == 5000)
        ''')

    def test_navigation_cannot_enable_discharge_by_proximity_alone(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        activate(); tick()
        local x,z=TI.alvoDescarregar(tractor,trailer,3)
        assert(x == 45 and z == 8)
        teleport(x,z-18); tick()
        teleport(x,z); tick()
        assert(state() == E.APROXIMANDO_CARRETA)
        assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OFF)
        ''')

    def test_only_exact_engine_target_and_fill_unit_can_receive(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        activate(); tick()
        permitUnload(makeTrailer(40,0),3)
        assert(not TI.podeDescarregar(tractor))
        permitUnload(trailer,1); assert(not TI.podeDescarregar(tractor))
        permitUnload(trailer,3); assert(TI.podeDescarregar(tractor))
        wagon.canDischarge=false; assert(not TI.podeDescarregar(tractor))
        ''')

    def test_unload_cycle_uses_object_constant_and_repeats_search(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        activate(); tick(); permitUnload()
        tick(); assert(state() == E.DESCARREGANDO)
        tick(); assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OBJECT)
        assert(wagon.turnedOn and trailer.prepared == 3)
        -- O teste injeta a mudanca que seria feita pelo sistema de graos do jogo.
        wagon.units[2].level=0
        tick(); assert(state() == E.BUSCANDO)
        assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OFF)
        assert(not wagon.turnedOn)
        assert(TI.reservasCarretas[trailer] == nil)
        tick(); assert(state() == E.APROXIMANDO)
        ''')

    def test_lost_discharge_target_stops_before_realigning(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        activate(); tick(); permitUnload(); tick(); tick()
        wagon.raycastObject=nil
        tick()
        assert(state() == E.APROXIMANDO_CARRETA)
        assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OFF)
        assert(not tractor.command.allowed)
        ''')

    def test_full_trailer_reselected_without_losing_remaining_grain(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        local other=makeTrailer(50,0)
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        activate(); tick(); permitUnload(); tick(); tick()
        wagon.units[2].level=10000
        trailer.units[3].level=30000; trailer.units[3].kind=1
        tick(); assert(state() == E.BUSCANDO_CARRETA)
        assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OFF)
        tick(); assert(tractor.spec_transbordoInteligente.caminhaoAlvo == other)
        assert(wagon.units[2].level == 10000)
        ''')

    def test_stall_watchdog_disables_discharge(self):
        self.check('''
        wagon.units[2].level=20000; wagon.units[2].kind=1
        activate(); tick(); permitUnload(); tick(); tick()
        tick(TI.CONFIG.tempoSemDescarga+1)
        assert(state() == E.PAUSADO)
        assert(wagon.dischargeState == Dischargeable.DISCHARGE_STATE_OFF)
        assert(TI.reservasCarretas[trailer] == nil)
        ''')

    def test_detach_deactivate_and_delete_release_reservations(self):
        self.check('''
        activate(); tick()
        assert(not wagon.spec_pipe.automaticDischarge)
        tractor.attached={}; tick()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        assert(TI.reservasColheitadeiras[combine] == nil)
        assert(wagon.spec_pipe.automaticDischarge)
        assert(not tractor.command.allowed)
        tractor.attached={{object=wagon}}
        activate(); tick(); TI.onDelete(tractor)
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        assert(TI.reservasColheitadeiras[combine] == nil)
        ''')

    def test_native_worker_conflict_and_multiplayer_refused(self):
        self.check('''
        tractor.nativeAI=true; activate()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        tractor.nativeAI=false
        g_currentMission.missionDynamicInfo.isMultiplayer=true; activate()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        g_currentMission.missionDynamicInfo.isMultiplayer=false; activate(); tick()
        tractor.nativeAI=true; tick()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        assert(TI.reservasColheitadeiras[combine] == nil)
        ''')

    def test_clients_cannot_drive_or_activate(self):
        self.check('''
        tractor.isServer=false; activate(); tick()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        assert(tractor.command == nil)
        ''')

    def test_approach_timeout_brakes_and_does_not_circle_forever(self):
        self.check('''
        activate(); tick(); tick(TI.CONFIG.tempoManobra+1)
        assert(state() == E.PAUSADO)
        assert(not tractor.command.allowed)
        assert(TI.reservasColheitadeiras[combine] == nil)
        ''')

    def test_update_activity_wrapper_preserves_normal_behavior(self):
        self.check('''
        assert(TI.getIsActive(tractor,function() return false end) == false)
        activate()
        assert(TI.getIsActive(tractor,function() return false end) == true)
        ''')

    def test_pipe_fill_unit_preferred_over_unrelated_tip_node(self):
        self.check('''
        function combine:getPipeDischargeNodeIndex() return 7 end
        function combine:getDischargeNodeByIndex(index)
            assert(index == 7)
            return self.dischargeNode
        end
        function combine:getCurrentDischargeNode() return {fillUnitIndex=1} end
        assert(TI.getCarga(combine).percentual == 60)
        activate(); tick(); assert(state() == E.APROXIMANDO)
        ''')

    def test_native_worker_can_take_over_even_while_paused(self):
        self.check('''
        activate(); TI.mudarEstado(tractor,E.PAUSADO)
        tractor.nativeAI=true; tick()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_no_receiving_flow_pauses_instead_of_following_forever(self):
        self.check('''
        activate(); tick()
        local x,z=TI.alvoReceber(tractor,combine)
        teleport(x,z-18); tick(); teleport(x,z); tick()
        assert(state() == E.ACOMPANHANDO)
        tick(); tick(TI.CONFIG.tempoSemDescarga+1)
        assert(state() == E.PAUSADO and not tractor.command.allowed)
        ''')

    def test_deleted_combine_is_released_without_nil_node_failure(self):
        self.check('''
        activate(); tick(); combine.rootNode.deleted=true; tick()
        assert(state() == E.BUSCANDO)
        assert(TI.reservasColheitadeiras[combine] == nil)
        assert(not tractor.command.allowed)
        ''')

    def test_bootstrap_attaches_only_eligible_vehicle_types(self):
        self.check('''
        g_currentModName='FS25_TransbordoInteligente'
        g_modIsLoaded={[g_currentModName]=true}
        SpecializationUtil={hasSpecialization=function(s,list)
            for _,v in ipairs(list) do if v==s then return true end end
            return false
        end}
        g_specializationManager={getSpecializationByName=function() return {classObject=TI} end}
        TypeManager={finalizeTypes=function(self) self.finalized=true end}
        Utils={prependedFunction=function(original,extra)
            return function(...) extra(...); return original(...) end
        end}
        manager={typeName='vehicle',types={
            tractor={specializations={Drivable,Motorized,Wheels}},
            trailer={specializations={Wheels}},
            existing={specializations={Drivable,Motorized,Wheels,TI}}
        },added={}}
        function manager:addSpecialization(name,spec) self.added[name]=spec end
        ''')
        self.lua.execute((ROOT / 'Bootstrap.lua').read_text())
        self.check('''
        TypeManager.finalizeTypes(manager)
        assert(manager.finalized)
        assert(manager.added.tractor == 'FS25_TransbordoInteligente.transbordoInteligente')
        assert(manager.added.trailer == nil and manager.added.existing == nil)
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
