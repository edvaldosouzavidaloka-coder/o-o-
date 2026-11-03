"""Entrada pela traseira, comando de descarga e recuperacao por progresso."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class EntradaDescargaTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        for name in ['TIProtecao.lua', 'TransbordoInteligente.lua', 'tests/fixture.lua']:
            self.lua.execute((ROOT / name).read_text())

    def check(self, code):
        self.lua.execute(code)

    def test_alongside_combine_cannot_skip_entry_from_rear(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        teleport(x,z-2)
        combine.raycastObject,combine.raycastIndex,combine.canDischarge=wagon,2,true
        tick(100)
        local s=tractor.spec_transbordoInteligente
        assert(not s.entradaPelaTraseira and state()==E.APROXIMANDO)
        assert(tractor.command.allowed and tractor.command.forwards)
        assert(tractor.command.z>0 and math.abs(tractor.command.x)>1)
        assert(s.mensagem:find('Entrando por tras'))
        ''')

    def test_already_behind_can_enter_only_by_driving_forward(self):
        self.check('''
        activate();tick()
        local x,z=enterCombineRear()
        assert(tractor.command.allowed and tractor.command.forwards)
        for _,offset in ipairs({20,10,3,1}) do
            teleport(x,z-offset);tick(100)
            assert(tractor.command.allowed and tractor.command.forwards)
            assert(tractor.spec_transbordoInteligente.entradaPelaTraseira)
        end
        teleport(x,z);tick(100)
        assert(not tractor.command.allowed)
        assert(math.abs(tractor.spec_transbordoInteligente.erroLongitudinalReceber)<0.001)
        ''')

    def test_motion_and_grain_progress_do_not_trigger_total_time_pause(self):
        self.check('''
        activate();tick()
        tick()
        for i=1,150 do
            tractor.rootNode.z=tractor.rootNode.z+0.5
            tick(1000)
            assert(state()~=E.RETOMANDO and state()~=E.PAUSADO)
        end
        local s=tractor.spec_transbordoInteligente
        assert(s.tempoEstado>TI.CONFIG.tempoManobra and s.tempoSemProgresso==0)
        ''')

    def test_actual_stall_retries_without_off_switch(self):
        self.check('''
        activate();tick();tick()
        tick(TI.CONFIG.tempoManobra+1)
        assert(state()==E.RETOMANDO and not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.isAtivo)
        tick(TI.CONFIG.intervaloRetentativa);tick()
        assert(state()==E.APROXIMANDO and tractor.command.allowed)
        ''')

    def test_forced_unload_sends_partial_cargo_to_far_trailer(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=5000,1
        teleport(1500,0,trailer)
        activate()
        TI.actionEventForcarDescarga(tractor,nil,1)
        local s=tractor.spec_transbordoInteligente
        assert(s.caminhaoAlvo==trailer and state()==E.BUSCANDO_CARRETA)
        tick(250);assert(state()==E.APROXIMANDO_CARRETA)
        assert(s.isAtivo and wagon.units[2].level==5000)
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OFF)
        ''')

    def test_forced_unload_can_activate_controller_and_uses_exact_raycast(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=5000,1
        TI.actionEventForcarDescarga(tractor,nil,1)
        assert(tractor.spec_transbordoInteligente.isAtivo)
        tick();permitUnload(makeTrailer(40,0),3);tick()
        assert(state()~=E.DESCARREGANDO)
        permitUnload();tick();tick()
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
        ''')

    def test_forced_unload_leaves_source_before_travel(self):
        self.check('''
        activate();tick();enterCombineRear()
        local x,z=TI.alvoReceber(tractor,combine)
        teleport(x,z);tick()
        wagon.units[2].level,wagon.units[2].kind=5000,1
        TI.actionEventForcarDescarga(tractor,nil,1)
        local s=tractor.spec_transbordoInteligente
        assert(state()==E.SAINDO and s.depoisSaida==E.BUSCANDO_CARRETA)
        assert(s.colheitadeiraAlvo==combine and s.caminhaoAlvo==trailer)
        teleport(s.saidaX,s.saidaZ);tick();tick()
        assert(state()==E.APROXIMANDO_CARRETA)
        ''')

    def test_no_trailer_keeps_searching_and_explains_reason(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=5000,1
        trailer.units[3].supported[1]=false
        activate();TI.actionEventForcarDescarga(tractor,nil,1);tick()
        local s=tractor.spec_transbordoInteligente
        assert(s.isAtivo and state()==E.BUSCANDO_CARRETA and not tractor.command.allowed)
        assert(s.motivoBuscaDestino:find('Nenhuma carreta'))
        trailer.units[3].supported[1]=true;tick(250)
        assert(s.caminhaoAlvo==trailer and state()==E.APROXIMANDO_CARRETA)
        ''')

    def test_moving_trailer_reason_is_explicit_and_search_resumes(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        trailer.speed=4
        activate();tick()
        assert(tractor.spec_transbordoInteligente.motivoBuscaDestino:find('Pare o caminhao'))
        trailer.speed=0;tick(250)
        assert(state()==E.APROXIMANDO_CARRETA)
        ''')

    def test_local_compatible_trailer_precedes_global_fallback(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        local far=makeTrailer(1200,0)
        table.insert(g_currentMission.vehicleSystem.vehicles,far)
        activate()
        assert(TI.encontrarCaminhao(tractor)==trailer)
        trailer.units[3].supported[1]=false
        assert(TI.encontrarCaminhao(tractor)==far)
        ''')

    def test_empty_forced_unload_does_not_depart_or_discharge(self):
        self.check('''
        TI.actionEventForcarDescarga(tractor,nil,1)
        assert(state()==E.BUSCANDO)
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==nil)
        assert(tractor.spec_transbordoInteligente.mensagem:find('vazia'))
        TI.actionEventForcarDescarga(tractor,nil,0)
        assert(state()==E.BUSCANDO)
        ''')

    def test_manifest_and_input_registration_support_both_shortcuts(self):
        desc = ET.parse(ROOT / 'modDesc.xml').getroot()
        actions = {x.attrib['name'] for x in desc.findall('./actions/action')}
        bindings = {x.attrib['action']: x.find('binding').attrib['input']
                    for x in desc.findall('./inputBinding/actionBinding')}
        self.assertEqual(actions, {'TI_TOGGLE_TRANSBORDO', 'TI_FORCE_UNLOAD'})
        self.assertEqual(bindings['TI_FORCE_UNLOAD'], 'KEY_lctrl KEY_lalt KEY_d')
        self.check('''
        InputAction={TI_TOGGLE_TRANSBORDO=123,TI_FORCE_UNLOAD=124}
        g_inputBinding={setActionEventText=function() end,setActionEventTextVisibility=function() end}
        function tractor:clearActionEventsTable() self.callbacks={} end
        function tractor:addActionEvent(events,id,target,callback)
            assert(target==self)
            self.callbacks[id]=callback
            return true,id
        end
        TI.onRegisterActionEvents(tractor,true,false)
        wagon.units[2].level,wagon.units[2].kind=5000,1
        tractor.callbacks[124](tractor,'TI_FORCE_UNLOAD',1)
        assert(tractor.spec_transbordoInteligente.isAtivo and state()==E.BUSCANDO_CARRETA)
        tractor.callbacks[123](tractor,'TI_TOGGLE_TRANSBORDO',1)
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
