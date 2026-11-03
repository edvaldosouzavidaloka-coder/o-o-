"""Confinamento do conjunto, receptores na borda e alinhamento final em Lua 5.1."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]


class LimiteTalhaoTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        for name in ['TITalhao.lua','TIProtecao.lua','TransbordoInteligente.lua','tests/fixture.lua']:
            self.lua.execute((ROOT/name).read_text())
        self.lua.execute('''
        T,P=TITalhao,TIProtecao
        tractor.size={width=3,length=6}
        wagon.size={width=3.5,length=8}
        function field(x1,z1,x2,z2)
            defaultField=makeField(x1,z1,x2,z2)
            g_farmlandManager={getFarmlandAtWorldPosition=function()
                return {getField=function() return defaultField end}
            end}
        end
        ''')

    def check(self,code):
        self.lua.execute(code)

    def test_farmland_road_is_not_mistaken_for_field_polygon(self):
        self.check('''
        field(-40,-40,40,40)
        teleport(80,0)
        assert(TI.getTalhao(tractor)==nil)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.talhao==nil)
        assert(tractor.spec_transbordoInteligente.isAtivo and not tractor.command.allowed)
        ''')

    def test_missing_polygon_holds_instead_of_falling_back_to_radius(self):
        self.check('''
        g_farmlandManager,g_fieldManager=nil,nil
        activate();tick()
        TI.dirigir(tractor,100,0,100,15)
        assert(not tractor.command.allowed and tractor.command.speed==0)
        assert(tractor.spec_transbordoInteligente.isAtivo)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('Talhao nao reconhecido'))
        ''')

    def test_field_manager_fallback_uses_actual_contour(self):
        self.check('''
        g_farmlandManager=nil
        local a,b=makeField(-40,-40,40,40),makeField(100,-40,200,40)
        g_fieldManager={getFields=function() return {a,b} end}
        activate()
        assert(tractor.spec_transbordoInteligente.talhao.objeto==a)
        ''')

    def test_locked_field_does_not_switch_when_vehicle_moves_to_another(self):
        self.check('''
        local a,b=makeField(-50,-50,50,150),makeField(150,-50,250,150)
        g_farmlandManager={getFarmlandAtWorldPosition=function(_,x)
            return {getField=function() return x<100 and a or b end}
        end}
        local other=makeCombine(200,100,9000)
        table.insert(g_currentMission.vehicleSystem.vehicles,other)
        activate();tick()
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==combine)
        teleport(200,0)
        TI.dirigir(tractor,100,200,50,8)
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.talhao.objeto==a)
        ''')

    def test_concave_cut_is_not_crossed_between_two_inside_points(self):
        self.check('''
        local t=T.criar({}, {0,0,100,0,100,100,60,100,60,40,40,40,40,100,0,100})
        assert(T.contem(t,25,80) and T.contem(t,75,80))
        assert(not T.segmentoDentro(t,25,80,75,80,0.35))
        -- Todos os cantos cabem, mas as arestas atravessam o recorte.
        assert(not T.retanguloDentro(t,{x=50,z=80,a=0,hw=30,hl=10},0.35))
        ''')

    def test_braking_keeps_whole_train_inside_front_boundary_without_target(self):
        self.check('''
        field(-40,-40,40,40);activate()
        teleport(0,24)
        local v=15/3.6
        for i=1,120 do
            tractor.speed=v*3.6
            local limit=P.limitar(tractor,100,0,100,15,true)
            local requested=limit/3.6
            local nextV=requested<v and math.max(requested,v-0.2) or math.min(requested,v+0.1)
            tractor.rootNode.z=tractor.rootNode.z+(v+nextV)*0.05
            v=nextV
            assert(P.posicaoNoTalhao(tractor,tractor.rootNode.x,tractor.rootNode.z))
            if v<0.001 then break end
        end
        assert(v<0.001 and tractor.rootNode.z<37)
        ''')

    def test_reverse_braking_checks_wagon_tail_before_it_leaves_field(self):
        self.check('''
        field(-40,-20,40,50);activate()
        local v=10/3.6
        for i=1,120 do
            tractor.speed,tractor.movingDirection=v*3.6,-1
            local limit=P.limitar(tractor,100,0,-50,10,false)
            local requested=limit/3.6
            local nextV=requested<v and math.max(requested,v-0.2) or math.min(requested,v+0.1)
            tractor.rootNode.z=tractor.rootNode.z-(v+nextV)*0.05
            v=nextV
            assert(P.posicaoNoTalhao(tractor,0,tractor.rootNode.z))
            if v<0.001 then break end
        end
        assert(v<0.001 and tractor.rootNode.z>-8)
        ''')

    def test_no_command_moves_when_implement_is_already_outside(self):
        self.check('''
        field(-40,-40,40,40);teleport(0,-32);activate()
        TI.dirigir(tractor,100,0,0,8)
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('limite do talhao'))
        ''')

    def test_roadside_receiver_requires_space_for_entire_auger_inside(self):
        self.check('''
        field(-40,-40,40,40)
        wagon.units[2].level,wagon.units[2].kind=20000,1
        trailer.rootNode.x,trailer.rootNode.z=42,0
        activate();tick()
        local s=tractor.spec_transbordoInteligente
        assert(s.caminhaoAlvo==trailer)
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        assert(x<40 and dz<0 and P.posicaoNoTalhao(tractor,x,z,math.atan2(dx,dz)))
        -- Mais longe, o cano nao alcanca sem colocar a bazuca fora do campo.
        trailer.rootNode.x=46
        assert(TI.encontrarCaminhao(tractor)==nil)
        ''')

    def test_forced_delivery_cannot_select_truck_in_other_field(self):
        self.check('''
        field(-40,-40,40,40)
        wagon.units[2].level,wagon.units[2].kind=5000,1
        teleport(200,0,trailer)
        activate();TI.actionEventForcarDescarga(tractor,nil,1);tick()
        local s=tractor.spec_transbordoInteligente
        assert(s.caminhaoAlvo==nil and state()==E.BUSCANDO_CARRETA)
        assert(s.isAtivo and not tractor.command.allowed)
        ''')

    def test_approach_reduces_rear_distance_to_fit_inside_field(self):
        self.check('''
        field(-40,-20,40,100)
        teleport(0,20,combine)
        activate();tick()
        local x,z,dx,dz=TI.alvoReceber(tractor,combine)
        local ax,az=P.aproximacao(tractor,combine,x,z,dx,dz,50)
        assert(ax~=nil and az>-8 and az<0)
        assert(P.posicaoNoTalhao(tractor,ax,az,0))
        ''')

    def test_ray_permission_does_not_stop_truck_approach_before_center(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        local x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=x-dx,z-dz,math.atan2(dx,dz)
        permitUnload()
        assert(TI.podeDescarregar(tractor))
        tick(100)
        assert(state()==E.APROXIMANDO_CARRETA and tractor.command.allowed)
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OFF)
        tractor.rootNode.x,tractor.rootNode.z=x,z
        tick(100);assert(state()==E.DESCARREGANDO)
        tick(100);assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
        ''')

    def test_open_turn_is_faster_but_turn_beside_combine_stays_limited(self):
        self.check('''
        activate()
        TI.dirigir(tractor,100,0,-100,TI.CONFIG.velocidadeManobra,true,true)
        assert(tractor.command.allowed and tractor.command.speed==8)
        tick();teleport(-15,90)
        TI.dirigir(tractor,100,-15,30,8,true,true)
        assert(tractor.command.speed<=5)
        ''')

    def test_turns_inward_before_running_out_of_turning_room(self):
        self.check('''
        field(-40,-40,40,40);teleport(0,26);activate()
        TI.dirigir(tractor,100,0,100,8)
        assert(tractor.command.allowed and math.abs(tractor.command.x)>1)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('dentro do talhao'))
        for i=1,50 do
            TI.dirigir(tractor,100,0,100,8)
            local c=tractor.command
            if c.allowed then
                local k=math.max(-0.1,math.min(0.1,2*c.x/math.max(1,c.x^2+c.z^2)))
                local ds=c.speed/3.6*0.1
                local a=tractor.rootNode.angle
                tractor.rootNode.x=tractor.rootNode.x+math.sin(a+k*ds/2)*ds
                tractor.rootNode.z=tractor.rootNode.z+math.cos(a+k*ds/2)*ds
                tractor.rootNode.angle=a+k*ds
                tractor.speed=c.speed
            else tractor.speed=0 end
            assert(P.posicaoNoTalhao(tractor,tractor.rootNode.x,tractor.rootNode.z))
        end
        ''')

    def test_selected_truck_moving_outside_does_not_pull_auger_out(self):
        self.check('''
        field(-40,-40,40,40)
        trailer.rootNode.x=20
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==trailer)
        trailer.rootNode.x=100
        tick()
        assert(tractor.spec_transbordoInteligente.caminhaoAlvo==nil)
        assert(state()==E.BUSCANDO_CARRETA and not tractor.command.allowed)
        ''')


if __name__=='__main__':
    unittest.main(verbosity=2)
