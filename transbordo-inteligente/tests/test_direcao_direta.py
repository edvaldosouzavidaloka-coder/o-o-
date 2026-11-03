"""Direcao direta, alvos e bloqueio local do dano de rodas; engine simulada."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class DirecaoDiretaTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'TransbordoInteligente.lua').read_text())
        self.lua.execute((ROOT / 'tests/fixture.lua').read_text())
        self.lua.execute('''
        function nativeWheelDamage(v)
            return g_currentMission.missionInfo.fruitDestruction and not v:getIsAIActive()
                and (v.getBlockFoliageDestruction==nil or not v:getBlockFoliageDestruction())
        end
        g_currentMission.missionInfo={fruitDestruction=true}
        ''')

    def check(self, code):
        self.lua.execute(code)

    def test_immediate_native_command_without_route_crop_or_obstacle_queries(self):
        self.check('''
        local function forbidden() error('Leitura ou planejamento removido foi chamado') end
        TransbordoNavegacao={dirigir=forbidden,reset=forbidden}
        overlapBox=forbidden
        g_fruitTypeManager=nil
        DensityMapModifier,DensityMapFilter,DensityCoordType=nil,nil,nil
        activate()
        TI.dirigir(tractor,20,15,40,12)
        assert(tractor.command.allowed and tractor.command.forwards)
        assert(tractor.command.x==15 and tractor.command.z==40)
        assert(tractor.command.speed==12 and tractor.command.dt==20)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao==nil)
        assert(tractor.spec_transbordoInteligente.navegacao==nil)
        ''')

    def test_native_target_is_converted_to_steering_node_coordinates(self):
        self.check('''
        activate()
        tractor.rootNode.angle=math.pi/2
        TI.dirigir(tractor,16,20,0,10)
        assert(math.abs(tractor.command.x)<0.000001)
        assert(math.abs(tractor.command.z-20)<0.000001)
        ''')

    def test_intercept_and_truck_approach_work_without_navigation_module(self):
        self.check('''
        TransbordoNavegacao=nil
        g_fruitTypeManager,DensityMapModifier,overlapBox=nil,nil,nil
        activate();tick();tick()
        assert(state()==E.APROXIMANDO and tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        TI.desativar(tractor)
        wagon.units[2].level=20000;wagon.units[2].kind=1
        activate();tick();tick()
        assert(state()==E.APROXIMANDO_CARRETA and tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        ''')

    def test_damage_is_blocked_only_for_active_tractor_and_wagon(self):
        self.check('''
        local other=vehicle(2,0)
        assert(nativeWheelDamage(tractor) and nativeWheelDamage(wagon))
        activate()
        assert(not nativeWheelDamage(tractor) and not nativeWheelDamage(wagon))
        assert(nativeWheelDamage(other))
        assert(g_currentMission.missionInfo.fruitDestruction==true)
        activate()
        assert(nativeWheelDamage(tractor) and nativeWheelDamage(wagon))
        assert(tractor.getBlockFoliageDestruction==nil and wagon.getBlockFoliageDestruction==nil)
        ''')

    def test_global_destruction_setting_is_never_enabled(self):
        self.check('''
        g_currentMission.missionInfo.fruitDestruction=false
        activate();tick();tick()
        assert(not nativeWheelDamage(tractor) and not nativeWheelDamage(wagon))
        assert(g_currentMission.missionInfo.fruitDestruction==false)
        activate()
        assert(g_currentMission.missionInfo.fruitDestruction==false)
        ''')

    def test_original_damage_callback_is_restored_on_detach(self):
        self.check('''
        local old=function() return false end
        wagon.getBlockFoliageDestruction=old
        activate()
        assert(wagon.getBlockFoliageDestruction~=old and wagon:getBlockFoliageDestruction())
        wagon.rootVehicle=wagon
        assert(wagon:getBlockFoliageDestruction()==false)
        tractor.attached={};tick()
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        assert(wagon.getBlockFoliageDestruction==old)
        ''')

    def test_new_implement_is_protected_and_removed_implement_restored(self):
        self.check('''
        activate()
        local extra=vehicle(0,-16)
        extra.rootVehicle=tractor
        table.insert(tractor.attached,{object=extra})
        tick()
        assert(extra:getBlockFoliageDestruction())
        table.remove(tractor.attached,2)
        extra.rootVehicle=extra
        tick()
        assert(extra.getBlockFoliageDestruction==nil)
        assert(tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_existing_inherited_callback_is_not_replaced_permanently(self):
        self.check('''
        local prior=function() return true end
        setmetatable(wagon,{__index={getBlockFoliageDestruction=prior}})
        assert(rawget(wagon,'getBlockFoliageDestruction')==nil)
        activate();activate()
        assert(rawget(wagon,'getBlockFoliageDestruction')==nil)
        assert(wagon.getBlockFoliageDestruction==prior)
        ''')

    def test_foreign_wrapper_added_after_activation_is_preserved(self):
        self.check('''
        activate()
        local ours=wagon.getBlockFoliageDestruction
        local foreign=function(v) return ours(v) end
        wagon.getBlockFoliageDestruction=foreign
        activate()
        assert(wagon.getBlockFoliageDestruction==foreign)
        assert(wagon:getBlockFoliageDestruction()==false)
        ''')

    def test_both_pipe_sides_align_actual_wagon_receiver_with_combine_pipe(self):
        self.check('''
        activate()
        for _,side in ipairs({-1,1}) do
            combine.dischargeNode.node.x=6*side
            combine.rootNode.angle=0.7
            local x,z=assert(TI.alvoReceber(tractor,combine))
            tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x,z,0.7
            local fx,_,fz=getWorldTranslation(wagon:getFillUnitExactFillRootNode(2))
            local px,_,pz=getWorldTranslation(combine.dischargeNode.node)
            assert(math.abs(fx-px)<0.000001 and math.abs(fz-pz)<0.000001)
            assert(tractor.spec_transbordoInteligente.ladoCano==side)
        end
        ''')

    def test_trailer_alignment_matches_real_fill_root_with_turned_truck(self):
        self.check('''
        activate()
        local truck=vehicle(40,10)
        truck.rootNode.angle=1.1
        trailer.rootVehicle=truck
        trailer.rootNode.angle=0.9
        local x,z=TI.alvoDescarregar(tractor,trailer,3)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x,z,1.1
        local px,_,pz=getWorldTranslation(wagon.dischargeNode.node)
        local fx,_,fz=getWorldTranslation(trailer:getFillUnitExactFillRootNode(3))
        assert(math.abs(px-fx)<0.000001 and math.abs(pz-fz)<0.000001)
        ''')

    def test_header_width_metadata_does_not_replace_actual_pipe_position(self):
        self.check('''
        activate()
        combine.size={width=15}
        tractor.size={width=5}
        local x,z=TI.alvoReceber(tractor,combine)
        assert(x==-6 and z==108)
        ''')

    def test_rigid_grain_truck_with_fill_volume_can_be_selected(self):
        self.check('''
        wagon.units[2].level=20000;wagon.units[2].kind=1
        local truck=makeTrailer(10,0)
        truck.spec_trailer=nil
        truck.spec_fillVolume={}
        table.insert(g_currentMission.vehicleSystem.vehicles,truck)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==truck)
        assert(tractor.spec_transbordoInteligente.indiceCarreta==3)
        ''')

    def test_mixer_is_not_mistaken_for_nearest_grain_truck(self):
        self.check('''
        wagon.units[2].level=20000;wagon.units[2].kind=1
        local mixer=makeTrailer(1,0)
        mixer.spec_mixerWagon={}
        table.insert(g_currentMission.vehicleSystem.vehicles,mixer)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        ''')

    def test_stopping_vehicle_still_sends_zero_speed(self):
        self.check('''
        activate()
        TI.dirigir(tractor,16,0,30,10)
        TI.dirigir(tractor,16,0,30,0)
        assert(not tractor.command.allowed and tractor.command.speed==0)
        ''')

    def test_shortcut_invokes_direct_mode_with_selected_vehicle(self):
        self.check('''
        InputAction={TI_TOGGLE_TRANSBORDO=123}
        g_inputBinding={setActionEventText=function() end,setActionEventTextVisibility=function() end}
        function tractor:clearActionEventsTable() end
        function tractor:addActionEvent(events,action,target,callback)
            assert(action==123 and target==self)
            self.callback=callback
            return true,42
        end
        TI.onRegisterActionEvents(tractor,true,false)
        tractor.callback(tractor,'TI_TOGGLE_TRANSBORDO',1)
        assert(tractor.spec_transbordoInteligente.isAtivo)
        assert(wagon:getBlockFoliageDestruction())
        tractor.callback(tractor,'TI_TOGGLE_TRANSBORDO',1)
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
