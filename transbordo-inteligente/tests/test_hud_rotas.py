"""HUD acionavel, ajustes persistentes e rotas internas com contratos Lua 5.1."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]


class HudRotasTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        for name in ['TITalhao.lua','TIProtecao.lua','TIManobraCarreta.lua','TIConfiguracao.lua',
                     'TIRotasCampo.lua','TIHUD.lua','TransbordoInteligente.lua','tests/fixture.lua']:
            self.lua.execute((ROOT/name).read_text())
        self.lua.execute('''
        C,H,R,P=TIConfiguracao,TIHUD,TIRotasCampo,TIProtecao
        function tractor:getIsEntered() return self.entered~=false end
        RenderText={ALIGN_CENTER=1,ALIGN_LEFT=0}
        function setTextColor() end
        function setTextBold() end
        function setTextAlignment() end
        drawings,texts={},{}
        H.renderRect=function(x,y,w,h,color) drawings[#drawings+1]={x=x,y=y,w=w,h=h,color=color} end
        function renderText(x,y,size,text) texts[#texts+1]={x=x,y=y,size=size,text=text} end
        Input={MOUSE_BUTTON_LEFT=1,KEY_esc=27}
        g_inputBinding={cursor=false,
            getShowMouseCursor=function(self) return self.cursor end,
            setShowMouseCursor=function(self,value) self.cursor=value end}
        function xmlMemory()
            return {values={},getValue=function(self,k,d) local v=self.values[k];if v==nil then return d end;return v end,
                setValue=function(self,k,v) self.values[k]=v end}
        end
        function click(id)
            for _,b in ipairs(H.buttons) do
                if b.id==id then return H:mouseEvent(b.x+b.w/2,b.y+b.h/2,true,false,1) end
            end
            error('Botao ausente: '..id)
        end
        function finishMap()
            local m=assert(R.iniciarMapa(tractor))
            while m.status=='mapeando' do R.atualizarMapa(m) end
            return m
        end
        function moveCommand(ms)
            local c=tractor.command
            if c.allowed then
                local g=P.geometria(tractor,tractor.spec_transbordoInteligente.colheitadeiraAlvo)
                local k=math.max(-1/g.raioGiro,math.min(1/g.raioGiro,2*c.x/math.max(1,c.x^2+c.z^2)))
                local ds=(c.forwards and 1 or -1)*c.speed/3.6*ms/1000
                local p=P.avancarPose(g.pose,k,ds,g.drawbar)
                tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=p.x,p.z,p.a
                wagon.rootNode.parent=nil
                wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=p.x-math.sin(p.t)*g.drawbar,p.z-math.cos(p.t)*g.drawbar,p.t
                tractor.speed,tractor.movingDirection=c.speed,c.forwards and 1 or -1
            else tractor.speed=0 end
            assert(P.posicaoNoTalhao(tractor,tractor.rootNode.x,tractor.rootNode.z),'Carroceria fora do campo')
        end
        ''')

    def check(self,code):
        self.lua.execute(code)

    def test_settings_are_per_vehicle_and_clamped_without_changing_global_limits(self):
        self.check('''
        local other=vehicle(10,0);TI.onLoad(other)
        C.set(tractor,'velocidadeViagem',99)
        assert(C.get(tractor,'velocidadeViagem')==30 and C.get(other,'velocidadeViagem')==15)
        assert(TI.CONFIG.velocidadeViagem==15)
        C.set(tractor,'offsetCarreta',-99);assert(C.get(tractor,'offsetCarreta')==-1)
        C.set(tractor,'velocidadeViagem',0/0);assert(C.get(tractor,'velocidadeViagem')==15)
        C.set(tractor,'hudAberto',false);assert(C.get(tractor,'hudAberto')==false)
        C.set(tractor,'usarRotas',true);assert(C.get(tractor,'usarRotas')==true)
        assert(not C.set(tractor,'desligarProtecao',true))
        ''')

    def test_settings_survive_xml_roundtrip_but_automatic_does_not_start_on_load(self):
        self.check('''
        C.set(tractor,'velocidadeChegadaColheitadeira',19);C.set(tractor,'offsetColheitadeira',0.4)
        C.set(tractor,'usarRotas',true);C.set(tractor,'hudAberto',false)
        local xml=xmlMemory()
        TI.saveToXMLFile(tractor,xml,'vehicles.vehicle(0).'..TI.NAMESPACE,{})
        local other=vehicle(10,0)
        TI.onLoad(other,{xmlFile=xml,key='vehicles.vehicle(0)'})
        assert(C.get(other,'velocidadeChegadaColheitadeira')==19 and C.get(other,'offsetColheitadeira')==0.4)
        assert(C.get(other,'usarRotas') and not C.get(other,'hudAberto'))
        assert(not other.spec_transbordoInteligente.isAtivo and other.spec_transbordoInteligente.talhao==nil)
        TI.onLoad(other,{xmlFile=xml,key='vehicles.vehicle(0)',resetVehicles=true})
        assert(C.get(other,'offsetColheitadeira')==0 and not C.get(other,'usarRotas'))
        ''')

    def test_xml_schema_matches_namespaced_vehicle_save_key(self):
        self.check('''
        XMLValueType={BOOL=1,FLOAT=2}
        local paths={}
        Vehicle={xmlSchemaSavegame={register=function(_,t,k) paths[k]=t end}}
        TI.initSpecialization()
        assert(paths['vehicles.vehicle(?).'..TI.NAMESPACE..'#usarRotas']==1)
        assert(paths['vehicles.vehicle(?).'..TI.NAMESPACE..'#offsetCarreta']==2)
        ''')

    def test_lateral_and_longitudinal_settings_change_measured_combine_goal(self):
        self.check('''
        activate();tick()
        local x,z=TI.alvoReceber(tractor,combine)
        C.set(tractor,'offsetColheitadeira',0.4);C.set(tractor,'offsetLongitudinal',0.7)
        local ax,az=TI.alvoReceber(tractor,combine)
        assert(math.abs(ax-x-0.4)<0.000001 and math.abs(az-z-0.7)<0.000001)
        assert(combine.dischargeNode.node.x==-6)
        ''')

    def test_trailer_offset_agrees_between_native_alignment_and_local_parking_map(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick()
        local x,z=TI.alvoDescarregar(tractor,trailer,3)
        local ax,az=TIManobraCarreta.faixa(tractor,trailer,3)
        C.set(tractor,'offsetCarreta',0.3)
        local nx,nz=TI.alvoDescarregar(tractor,trailer,3)
        local bx,bz=TIManobraCarreta.faixa(tractor,trailer,3)
        assert(math.abs(nx-x-0.3)<0.000001 and math.abs(nz-z)<0.000001)
        assert(math.abs(bx-ax-0.3)<0.000001 and bz==az)
        assert(wagon.dischargeNode.node.x==-5)
        ''')

    def test_speed_controls_change_actual_arrival_command(self):
        self.check('''
        teleport(-6,-80);C.set(tractor,'velocidadeChegadaColheitadeira',18)
        activate();tick();tick(100)
        assert(tractor.command.allowed and tractor.command.speed==18)
        C.set(tractor,'velocidadeChegadaColheitadeira',5);teleport(-6,70);tick(100)
        assert(tractor.command.allowed and tractor.command.speed<=5)
        ''')

    def test_forced_360_search_finds_combine_behind_below_automatic_threshold(self):
        self.check('''
        tractor.rootNode.angle=math.pi
        combine.units[2].level=2500
        TI.forcarBusca(tractor,false);tick(100)
        local s=tractor.spec_transbordoInteligente
        assert(s.colheitadeiraAlvo==combine and s.isAtivo and state()==E.APROXIMANDO)
        assert(not s.buscaForcada)
        ''')

    def test_forced_search_keeps_field_farm_and_crop_constraints(self):
        self.check('''
        defaultField=makeField(-40,-40,40,150)
        combine.farm=2
        local foreign=makeCombine(200,0,9000)
        table.insert(g_currentMission.vehicleSystem.vehicles,foreign)
        TI.forcarBusca(tractor,false);tick(100)
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo==nil)
        assert(state()==E.BUSCANDO and not tractor.command.allowed)
        ''')

    def test_next_combine_releases_old_reservation_when_far_from_machine(self):
        self.check('''
        local other=makeCombine(20,90,6000);table.insert(g_currentMission.vehicleSystem.vehicles,other)
        activate();tick()
        local previous=tractor.spec_transbordoInteligente.colheitadeiraAlvo
        TI.forcarBusca(tractor,true);tick(100)
        assert(tractor.spec_transbordoInteligente.colheitadeiraAlvo~=previous)
        assert(TI.reservasColheitadeiras[previous]==nil)
        ''')

    def test_hud_keeps_text_inside_lateral_panel_and_has_all_setting_pages(self):
        self.check('''
        activate();tick();TI.onDraw(tractor)
        assert(#texts>0 and #drawings>0)
        for _,t in ipairs(texts) do assert(t.x>=0.74 and t.y>=0.20 and t.y<=0.90) end
        H.cursorAtivo(tractor,true)
        click('tab_velocidades');TI.onDraw(tractor)
        local plus=0
        for _,b in ipairs(H.buttons) do if b.id:find('mais_',1,true) then plus=plus+1 end end
        assert(plus==6)
        click('tab_ajustes');TI.onDraw(tractor)
        click('mais_offsetColheitadeira')
        assert(C.get(tractor,'offsetColheitadeira')==0.1)
        assert(not H:mouseEvent(0.5,0.5,true,false,1))
        local s=tractor.spec_transbordoInteligente
        s.estadoAtual,s.mensagem,s.mensagemNavegacao=E.BUSCANDO_CARRETA,nil,nil
        s.motivoBuscaDestino='Pare o caminhao para receber a carga'
        texts={};TI.onDraw(tractor)
        local found=false
        for _,t in ipairs(texts) do found=found or t.text:find('Pare o caminhao',1,true) end
        assert(found)
        ''')

    def test_cursor_restores_original_camera_flags_on_close_exit_and_escape(self):
        self.check('''
        local a,b={isRotatable=true},{isRotatable=false}
        tractor.spec_enterable={cameras={a,b}}
        TI.onDraw(tractor);H.cursorAtivo(tractor,true)
        assert(not a.isRotatable and not b.isRotatable and g_inputBinding.cursor)
        H:mouseEvent(0,0,false,false,1)
        H:keyEvent(0,27,0,true)
        assert(a.isRotatable and not b.isRotatable and not g_inputBinding.cursor)
        H.cursorAtivo(tractor,true);tractor.entered=false;H:update(16)
        assert(a.isRotatable and not b.isRotatable and not H.cursor)
        tractor.entered=true;H.cursorAtivo(tractor,true);H.toggle(tractor)
        assert(not C.get(tractor,'hudAberto') and not H.cursor)
        ''')

    def test_hud_minimize_and_drag_keep_panel_on_screen(self):
        self.check('''
        TI.onDraw(tractor);H.cursorAtivo(tractor,true);TI.onDraw(tractor)
        click('drag');H:mouseEvent(0.2,0.3,false,false,1);H:mouseEvent(0.2,0.3,false,true,1)
        TI.onDraw(tractor)
        assert(H.bounds.x>=0.01 and H.bounds.x+H.bounds.w<=0.99)
        assert(H.bounds.y>=0.04 and H.bounds.y+H.bounds.h<=0.97)
        click('fechar');TI.onDraw(tractor)
        assert(H.bounds.h<0.05 and not H.cursor)
        ''')

    def test_menu_releases_owned_cursor_and_does_not_draw_over_game_menu(self):
        self.check('''
        TI.onDraw(tractor);H.cursorAtivo(tractor,true)
        g_gui={getIsGuiVisible=function() return true end}
        local count=#texts;TI.onDraw(tractor)
        assert(#texts==count and not H.cursor and not g_inputBinding.cursor)
        ''')

    def test_native_action_events_register_old_shortcuts_and_hud_controls(self):
        self.check('''
        InputAction={TI_TOGGLE_TRANSBORDO=1,TI_FORCE_UNLOAD=2,TI_HUD_TOGGLE=3,TI_HUD_CURSOR=4}
        function g_inputBinding:setActionEventText() end
        function g_inputBinding:setActionEventTextVisibility() end
        function tractor:clearActionEventsTable() self.callbacks={} end
        function tractor:addActionEvent(_,id,target,callback) self.callbacks[id]=callback;return true,id end
        TI.onRegisterActionEvents(tractor,true,false)
        for i=1,4 do assert(tractor.callbacks[i]) end
        tractor.callbacks[3](tractor,nil,1);assert(not C.get(tractor,'hudAberto'))
        tractor.callbacks[4](tractor,nil,1);assert(H.cursor and C.get(tractor,'hudAberto'))
        tractor.callbacks[1](tractor,nil,1);assert(tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_map_uses_bounded_grid_and_incremental_work(self):
        self.check('''
        activate()
        local m=R.iniciarMapa(tractor)
        assert(m.nx*m.nz<=R.CONFIG.ladoMaximo^2)
        R.atualizarMapa(m,1);assert(m.next==2 and m.status=='mapeando')
        while m.status=='mapeando' do R.atualizarMapa(m) end
        assert(m.livres>0 and m.field==tractor.spec_transbordoInteligente.talhao)
        ''')

    def test_no_field_does_not_create_a_fictitious_map(self):
        self.check('''
        g_farmlandManager=nil
        assert(R.iniciarMapa(tractor)==nil)
        assert(tractor.spec_transbordoInteligente.mapaCampo==nil)
        ''')

    def test_mapping_after_deactivation_uses_the_current_field_before_reactivation(self):
        self.check('''
        activate();TI.desativar(tractor)
        defaultField=makeField(-200,-30,-100,100)
        teleport(-150,20)
        local map=assert(R.iniciarMapa(tractor))
        assert(map.field.objeto==defaultField)
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_route_goes_around_concave_cutout_instead_of_crossing_outside(self):
        self.check('''
        teleport(-55,50);activate()
        local s=tractor.spec_transbordoInteligente
        s.talhao=TITalhao.criar({}, {-80,-80,80,-80,80,80,30,80,30,-20,-30,-20,-30,80,-80,80})
        local m=finishMap()
        assert(not TITalhao.segmentoDentro(s.talhao,-55,50,55,50))
        local job=assert(R.iniciarRota(tractor,55,50,nil))
        R.avancar(job,1);assert(job.expanded<=1)
        while job.status=='buscando' do R.avancar(job) end
        assert(job.status=='pronto')
        local wentAround=false
        for i,p in ipairs(job.path) do
            wentAround=wentAround or p.z< -30
            if i>1 then local a=job.path[i-1];assert(TITalhao.segmentoDentro(s.talhao,a.x,a.z,p.x,p.z,m.radius)) end
        end
        assert(wentAround)
        ''')

    def test_route_is_followed_with_whole_rig_inside_concave_field(self):
        self.check('''
        teleport(-55,50);tractor.rootNode.angle=math.pi;activate()
        local s=tractor.spec_transbordoInteligente
        s.talhao=TITalhao.criar({}, {-80,-80,80,-80,80,80,30,80,30,-20,-30,-20,-30,80,-80,80})
        finishMap();C.set(tractor,'usarRotas',true)
        local reached=false
        for i=1,4000 do
            TI.dirigirViagem(tractor,100,55,50,8,nil)
            moveCommand(100)
            if (tractor.rootNode.x-55)^2+(tractor.rootNode.z-50)^2<100 then reached=true;break end
        end
        assert(reached,'Nao concluiu a rota interna')
        ''')

    def test_route_avoids_selected_vehicle_body_and_header(self):
        self.check('''
        defaultField=makeField(-80,-80,80,80)
        teleport(0,-50);teleport(0,0,combine)
        combine.size={width=20,length=10}
        activate();finishMap()
        local job=R.iniciarRota(tractor,0,50,combine)
        while job.status=='buscando' do R.avancar(job) end
        assert(job.status=='pronto')
        local detour=false
        for _,p in ipairs(job.path) do if math.abs(p.z)<10 then detour=detour or math.abs(p.x)>12 end end
        assert(detour)
        ''')

    def test_field_without_an_interior_corridor_holds_position(self):
        self.check('''
        defaultField=makeField(-10,-40,10,100)
        activate();finishMap();C.set(tractor,'usarRotas',true)
        TI.dirigirViagem(tractor,100,0,80,15,nil)
        assert(not tractor.command.allowed and tractor.spec_transbordoInteligente.isAtivo)
        assert(tractor.spec_transbordoInteligente.navegacaoCampo.status=='semRota')
        ''')

    def test_map_tab_draws_current_field_and_route_without_center_text(self):
        self.check('''
        activate();finishMap();H.tab='campo';TI.onDraw(tractor)
        assert(#drawings>20)
        for _,t in ipairs(texts) do assert(t.x>=0.74) end
        ''')

    def test_articulation_does_not_move_the_final_combine_receiver_target(self):
        self.check('''
        activate();tick()
        wagon.rootNode.parent=nil
        tractor.rootNode.angle=0.7
        wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=-math.sin(0.7)*2,-math.cos(0.7)*2-6,0
        local hook=node(0,6,wagon.rootNode)
        function wagon:getActiveInputAttacherJoint() return {node=hook} end
        local x,z=TI.alvoReceber(tractor,combine)
        assert(math.abs(x+6)<0.000001 and math.abs(z-108)<0.000001)
        ''')

    def test_blocked_oblique_combine_entry_recovers_behind_header_without_contact(self):
        self.check('''
        defaultField=makeField(-90,0,90,180)
        tractor.size={width=2.8,length=5};wagon.size={width=3,length=7}
        combine.size={width=5,length=8};combine.dischargeNode.node.x=-9.5
        local header=vehicle(0,107);header.spec_cutter={};header.size={width=14.6,length=3}
        header.rootVehicle=combine;combine.attached={{object=header}}
        teleport(-12,111);tractor.rootNode.angle=math.pi/2
        activate();tick()
        local s=tractor.spec_transbordoInteligente
        s.bloqueioEntradaEm=1100
        local recovered,planned=false,false
        for i=1,3000 do
            tick(100)
            planned=planned or s.manobraEntrada~=nil
            if s.entradaPelaTraseira and s.manobraEntrada==nil then recovered=true;break end
            moveCommand(100)
            assert(P.posicaoLivre(tractor,combine,tractor.rootNode.x,tractor.rootNode.z,nil,0),'Contato com plataforma')
        end
        assert(recovered and planned and math.cos(tractor.rootNode.angle)>0.9)
        assert(tractor.rootNode.z<combine.rootNode.z and s.isAtivo)
        ''')

    def test_clicking_hud_does_not_switch_to_a_vehicle_behind_it(self):
        self.check('''
        TI.onDraw(tractor);H.cursorAtivo(tractor,true)
        local calls=0
        local function switch() calls=calls+1 end
        TI.enterVehicleRaycastClickToSwitch(tractor,switch,0.8,0.4)
        assert(calls==0)
        TI.enterVehicleRaycastClickToSwitch(tractor,switch,0.3,0.4)
        assert(calls==1)
        ''')

    def test_changing_offset_during_unloading_stops_flow_before_realigning(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick();alignTrailer();permitUnload();tick(100);tick(100)
        assert(state()==E.DESCARREGANDO and wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
        C.set(tractor,'offsetCarreta',0.5)
        assert(state()==E.APROXIMANDO_CARRETA and wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OFF)
        assert(not tractor.command.allowed and wagon.units[2].level==20000)
        ''')


if __name__=='__main__':
    unittest.main(verbosity=2)
