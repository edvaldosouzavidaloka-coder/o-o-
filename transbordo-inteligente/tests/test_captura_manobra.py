"""Captura resistente a dados incompletos e entrada com direcao estabilizada."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]


class CapturaManobraTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        for name in ['TITalhao.lua','TIProtecao.lua','TIManobraCarreta.lua','TransbordoInteligente.lua','tests/fixture.lua']:
            self.lua.execute((ROOT/name).read_text())

    def check(self,code):
        self.lua.execute(code)

    def test_mission_vehicle_list_fallback_finds_combine(self):
        self.check('''
        g_currentMission.vehicles=g_currentMission.vehicleSystem.vehicles
        g_currentMission.vehicleSystem.vehicles={}
        activate();tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        ''')

    def test_duplicate_root_and_attached_receiver_are_scanned_once(self):
        self.check('''
        local truck=vehicle(40,15)
        trailer.rootVehicle=truck;truck.attached={{object=trailer}}
        g_currentMission.vehicles={truck,trailer,tractor}
        table.insert(g_currentMission.vehicleSystem.vehicles,truck)
        local count=0
        local old=trailer.getFillUnitSupportsFillType
        function trailer:getFillUnitSupportsFillType(i,t) count=count+1;return old(self,i,t) end
        wagon.units[2].level,wagon.units[2].kind=5000,1
        activate()
        assert(TI.encontrarCaminhao(tractor)==trailer)
        assert(count==1)
        ''')

    def test_broken_combine_data_does_not_abort_capture_of_other_combine(self):
        self.check('''
        local broken=makeCombine(0,30,10000)
        function broken:getCurrentDischargeNode() error('dados temporariamente indisponiveis') end
        table.insert(g_currentMission.vehicleSystem.vehicles,broken)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        ''')

    def test_broken_receiver_owner_or_root_does_not_abort_other_receivers(self):
        self.check('''
        local a,b=makeTrailer(1,0),makeTrailer(2,0)
        function a:getOwnerFarmId() error('mod sem proprietario') end
        function b:getRootVehicle() error('root nao disponivel') end
        table.insert(g_currentMission.vehicleSystem.vehicles,a)
        table.insert(g_currentMission.vehicleSystem.vehicles,b)
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        ''')

    def test_malformed_attached_entries_do_not_abort_scan(self):
        self.check('''
        local broken=vehicle(10,0)
        broken.attached={{object=42},{object=trailer}}
        g_currentMission.vehicles={broken}
        table.insert(g_currentMission.vehicleSystem.vehicles,123)
        wagon.units[2].level,wagon.units[2].kind=5000,1
        activate()
        assert(TI.encontrarCaminhao(tractor)==trailer)
        ''')

    def test_auto_aim_getter_error_falls_back_to_exact_receiver(self):
        self.check('''
        function trailer:getFillUnitAutoAimTargetNode() error('autoAimTarget ausente') end
        local x,_,z,n=TI.pontoEnchimento(trailer,3)
        assert(x==40 and z==0 and n==trailer.units[3].fillRoot)
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        ''')

    def test_deleted_auto_aim_node_falls_back_to_live_exact_receiver(self):
        self.check('''
        local dead=node(50,0);dead.deleted=true
        function trailer:getFillUnitAutoAimTargetNode() return dead end
        local x,_,z,n=TI.pontoEnchimento(trailer,3)
        assert(x==40 and z==0 and n==trailer.units[3].fillRoot)
        ''')

    def test_fill_root_is_used_when_exact_and_auto_aim_are_missing(self):
        self.check('''
        function trailer:getFillUnitAutoAimTargetNode() return 0 end
        function trailer:getFillUnitExactFillRootNode() return nil end
        function trailer:getFillUnitRootNode(i) return self.units[i].fillRoot end
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        ''')

    def test_fill_units_getter_supports_receiver_without_raw_unit_list(self):
        self.check('''
        trailer.spec_fillUnit.fillUnits=nil
        function trailer:getFillUnits() return {[3]={}} end
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        assert(tractor.spec_transbordoInteligente.indiceCarreta==3)
        ''')

    def test_unreachable_pipe_outside_field_does_not_steal_combine_capture(self):
        self.check('''
        defaultField=makeField(-40,-40,40,160)
        local other=makeCombine(38,80,10000)
        other.dischargeNode.node.x=9
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        ''')

    def test_accessible_combine_is_preferred_to_header_blocking_center(self):
        self.check('''
        combine.units[2].level=10000
        local header=vehicle(0,8)
        header.rootNode.parent=combine.rootNode;header.rootVehicle=combine
        header.spec_cutter={};header.size={width=20,length=3}
        combine.attached={{object=header}}
        local other=makeCombine(30,80,7000)
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==other)
        ''')

    def test_closed_pipe_can_still_be_captured_and_opened(self):
        self.check('''
        combine.spec_pipe.currentState,combine.spec_pipe.targetState=1,1
        combine.dischargeNode.node.x=0
        function combine:setPipeState(s)
            self.spec_pipe.currentState,self.spec_pipe.targetState=s,s
            self.dischargeNode.node.x=-6
        end
        activate();tick();tick(100)
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        assert(combine.spec_pipe.currentState==2 and tractor.command.allowed)
        ''')

    def test_scan_does_not_overwrite_active_pipe_metadata(self):
        self.check('''
        activate();tick()
        TI.alvoReceber(tractor,combine)
        local other=makeCombine(30,80,9500)
        other.dischargeNode.node.x=8
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        assert(TI.encontrarColheitadeira(tractor)==other)
        local s=tractor.spec_transbordoInteligente
        assert(s.colheitadeiraAlvo==combine and s.ladoCano==-1 and s.alcanceCano==6)
        ''')

    def test_temporary_combine_read_failure_keeps_reservation_then_resumes(self):
        self.check('''
        activate();tick();tick(100)
        local old=combine.getFillUnitCapacity
        function combine:getFillUnitCapacity() return 0 end
        tick(100)
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        assert(TI.reservasColheitadeiras[combine]==tractor)
        combine.getFillUnitCapacity=old
        tick(100)
        assert(tractor.command.allowed and state()==E.APROXIMANDO)
        ''')

    def test_permanent_combine_read_failure_eventually_releases_capture(self):
        self.check('''
        activate();tick();tick(100)
        function combine:getFillUnitCapacity() return 0 end
        tick(TI.CONFIG.toleranciaLeituraAlvo+1)
        assert(state()==E.BUSCANDO and TI.reservasColheitadeiras[combine]==nil)
        assert(not tractor.command.allowed and tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_turning_combine_is_not_chased_until_heading_stabilizes(self):
        self.check('''
        activate();tick();tick(100)
        combine.rootNode.angle=math.pi/2
        tick(100)
        local s=tractor.spec_transbordoInteligente
        assert(not tractor.command.allowed and not s.entradaPelaTraseira)
        assert(s.colheitadeiraAlvo==combine and TI.reservasColheitadeiras[combine]==tractor)
        assert(s.mensagemNavegacao:find('terminar a curva'))
        combine.rootNode.angle=math.pi*0.75
        tick(100);tick(500)
        assert(not tractor.command.allowed)
        tick(TI.CONFIG.tempoEstabilizarColheitadeira+1)
        assert(tractor.command.allowed and s.colheitadeiraAlvo==combine)
        ''')

    def test_heading_wrap_and_small_jitter_do_not_create_false_turn(self):
        self.check('''
        combine.rootNode.angle=math.rad(179)
        activate();tick();tick(100)
        combine.rootNode.angle=math.rad(-179)
        tick(100)
        assert((tractor.spec_transbordoInteligente.curvaColheitadeiraEm or 0)==0)
        assert(tractor.command.allowed)
        ''')

    def test_reaching_rear_waypoint_crosswise_does_not_finish_alignment(self):
        self.check('''
        activate();tick()
        local x,z,dx,dz=TI.alvoReceber(tractor,combine)
        local ax,az=TIProtecao.aproximacao(tractor,combine,x,z,dx,dz,50)
        teleport(ax,az);tractor.rootNode.angle=math.pi/2
        assert(not TI.entradaColheitadeira(tractor,100,combine,x,z,dx,dz))
        assert(not tractor.spec_transbordoInteligente.entradaPelaTraseira)
        assert(tractor.spec_transbordoInteligente.alinhandoEntrada and tractor.command.allowed)
        tractor.rootNode.angle=0
        assert(TI.entradaColheitadeira(tractor,100,combine,x,z,dx,dz))
        assert(tractor.spec_transbordoInteligente.entradaPelaTraseira)
        ''')

    def test_outside_train_holds_before_search_and_does_not_change_field(self):
        self.check('''
        defaultField=makeField(-40,-40,40,160)
        activate();tick()
        local s=tractor.spec_transbordoInteligente
        local locked=s.talhao
        teleport(60,0)
        wagon.dischargeState=Dischargeable.DISCHARGE_STATE_OBJECT
        tick(100)
        assert(s.talhao==locked and s.colheitadeiraAlvo==combine)
        assert(not tractor.command.allowed and wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OFF)
        assert(s.mensagemNavegacao:find('Conjunto fora do talhao'))
        ''')

    def test_hud_identifies_loaded_version_vehicle_and_locked_field(self):
        self.check('''
        function combine:getName() return 'Colheitadeira teste' end
        function defaultField:getId() return 7 end
        function tractor:getIsEntered() return true end
        RenderText={ALIGN_CENTER=1,ALIGN_LEFT=0}
        function setTextColor() end
        function setTextAlignment() end
        function setTextBold() end
        local lines={}
        function renderText(_,__,___,s) lines[#lines+1]=s end
        activate();tick();TI.onDraw(tractor)
        local all=table.concat(lines,' | ')
        assert(all:find(TI.VERSAO,1,true))
        assert(all:find('Alvo: Colheitadeira teste',1,true) and all:find('Campo 7',1,true))
        ''')

    def test_deleted_cached_discharge_node_is_replaced_by_live_node(self):
        self.check('''
        assert(TI.getCarga(combine).node==combine.dischargeNode)
        combine.dischargeNode.node.deleted=true
        local replacement={node=node(-8,0,combine.rootNode),fillUnitIndex=2}
        combine.dischargeNode=nil
        combine.spec_dischargeable.dischargeNodes={replacement}
        assert(TI.getCarga(combine).node==replacement)
        activate();tick()
        local x=TI.alvoReceber(tractor,combine)
        assert(x==-8 and tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        ''')

    def test_projected_direction_does_not_shift_combine_receiver_alignment(self):
        self.check('''
        local original=localDirectionToWorld
        function localDirectionToWorld(n,x,y,z)
            local wx,wy,wz=original(n,x,y,z)
            if n==tractor.rootNode or n==combine.rootNode then return wx*0.9,wy,wz*0.9 end
            return wx,wy,wz
        end
        activate()
        combine.rootNode.angle=0.7
        local x,z,dx,dz=TI.alvoReceber(tractor,combine)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x,z,math.atan2(dx,dz)
        local fx,_,fz=TI.pontoEnchimento(wagon,2)
        local px,_,pz=getWorldTranslation(combine.dischargeNode.node)
        assert(math.abs(fx-px)<0.000001 and math.abs(fz-pz)<0.000001)
        ''')

    def test_projected_direction_does_not_shift_trailer_discharge_alignment(self):
        self.check('''
        local original=localDirectionToWorld
        function localDirectionToWorld(n,x,y,z)
            local wx,wy,wz=original(n,x,y,z)
            if n==tractor.rootNode or n==trailer.rootNode then return wx*0.85,wy,wz*0.85 end
            return wx,wy,wz
        end
        activate()
        trailer.rootNode.angle=0.5
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x,z,math.atan2(dx,dz)
        local px,_,pz=getWorldTranslation(wagon.dischargeNode.node)
        local fx,_,fz=TI.pontoEnchimento(trailer,3)
        assert(math.abs(fx-px)<0.000001 and math.abs(fz-pz)<0.000001)
        ''')

    def test_pitch_projection_change_is_not_mistaken_for_heading_turn(self):
        self.check('''
        local original=localDirectionToWorld
        local projection=0.9
        function localDirectionToWorld(n,x,y,z)
            local wx,wy,wz=original(n,x,y,z)
            if n==combine.rootNode then return wx*projection,wy,wz*projection end
            return wx,wy,wz
        end
        activate();tick();tick(100)
        projection=0.8
        tick(100)
        assert((tractor.spec_transbordoInteligente.curvaColheitadeiraEm or 0)==0)
        assert(tractor.command.allowed)
        ''')

    def test_bad_field_api_holds_instead_of_driving_without_boundary(self):
        self.check('''
        g_farmlandManager={getFarmlandAtWorldPosition=function() error('contorno indisponivel') end}
        activate();tick()
        assert(tractor.spec_transbordoInteligente.talhao==nil)
        assert(tractor.spec_transbordoInteligente.isAtivo and not tractor.command.allowed)
        ''')


if __name__=='__main__':
    unittest.main(verbosity=2)
