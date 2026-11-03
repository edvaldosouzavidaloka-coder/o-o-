"""Ajustes locais com cano curto, semirreboque e movimento articulado simplificado."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]


class AjusteCurtoTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        for name in ['TITalhao.lua','TIProtecao.lua','TIManobraCarreta.lua','TransbordoInteligente.lua','tests/fixture.lua']:
            self.lua.execute((ROOT/name).read_text())
        self.lua.execute('''
        M,P=TIManobraCarreta,TIProtecao
        function shortPipeScene()
            tractor.size={width=2.8,length=5};wagon.size={width=3,length=7}
            trailer.rootNode.x,trailer.rootNode.z=0,0
            trailer.size={width=2.6,length=12}
            truck=vehicle(0,13);truck.size={width=2.8,length=6}
            truck.attached={{object=trailer}};trailer.rootVehicle=truck
            g_currentMission.vehicleSystem.vehicles={tractor,trailer,truck}
            wagon.units[2].level,wagon.units[2].kind=20000,1
            wagon.dischargeNode.node.x,wagon.dischargeNode.node.z=-4.2,3
            aim=node(0,0,trailer.rootNode)
            function trailer:getFillUnitAutoAimTargetNode() return aim end
            trailer.spec_fillUnit.fillUnits[3].autoAimTarget={node=aim,baseTrans={0,0,0},startZ=-5.1,endZ=5.1}
            teleport(-5,0);tractor.rootNode.angle=math.pi/2
            activate();tick()
        end
        function parkingJob()
            local _,_,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
            return assert(M.iniciar(tractor,trailer,3,dx,dz))
        end
        function finishSearch(job)
            while job.status=='buscando' do M.avancar(job,60) end
        end
        function alternativeScene(exact,x,z)
            shortPipeScene()
            wagon.dischargeNode.node.x=-4.7
            teleport(x or -9,z or -8)
            tractor.rootNode.angle=math.pi/2
            if exact then
                trailer.getFillUnitAutoAimTargetNode=nil
                trailer.spec_fillUnit.fillUnits[3].autoAimTarget=nil
            end
        end
        function moveParkingFrame(ms)
            tick(ms)
            if M.distanciaCano(tractor,trailer,3)<0.4 then permitUnload() end
            if state()==E.DESCARREGANDO then return true end
            local c=tractor.command
            if c.allowed then
                local g=P.geometria(tractor,trailer)
                local k=math.max(-1/g.raioGiro,math.min(1/g.raioGiro,2*c.x/math.max(1,c.x^2+c.z^2)))
                local ds=(c.forwards and 1 or -1)*c.speed/3.6*ms/1000
                local p=P.avancarPose(g.pose,k,ds,g.drawbar)
                tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=p.x,p.z,p.a
                wagon.rootNode.parent=nil
                wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=p.x-math.sin(p.t)*g.drawbar,p.z-math.cos(p.t)*g.drawbar,p.t
                tractor.speed,tractor.movingDirection=c.speed,c.forwards and 1 or -1
            else tractor.speed=0 end
            assert(P.posicaoLivre(tractor,trailer,tractor.rootNode.x,tractor.rootNode.z,nil,0),'Contato com carreta ou cabine')
            assert(P.posicaoNoTalhao(tractor,tractor.rootNode.x,tractor.rootNode.z),'Saiu do campo')
            assert(tractor.spec_transbordoInteligente.isAtivo)
            return false
        end
        ''')

    def check(self,code):
        self.lua.execute(code)

    def test_receiving_range_is_inset_and_engine_aim_node_is_not_moved(self):
        self.check('''
        shortPipeScene()
        local ax,az,bx,bz=TI.faixaEnchimento(trailer,3)
        assert(ax==0 and bx==0 and math.abs(az+4.5)<0.000001 and math.abs(bz-4.5)<0.000001)
        assert(aim.z==0)
        aim.z=4
        local _,naz,_,nbz=TI.faixaEnchimento(trailer,3)
        assert(naz==az and nbz==bz and aim.z==4)
        ''')

    def test_missing_range_keeps_exact_receiver_instead_of_guessing_box_edges(self):
        self.check('''
        activate()
        local ax,az,bx,bz=TI.faixaEnchimento(trailer,3)
        local x,_,z=TI.pontoEnchimento(trailer,3)
        assert(ax==x and bx==x and az==z and bz==z)
        ''')

    def test_real_hitch_stabilizes_pipe_geometry_while_tractor_is_angled(self):
        self.check('''
        shortPipeScene()
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=0,0,0.7
        wagon.rootNode.parent=nil
        wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=-math.sin(0.7)*2,-math.cos(0.7)*2-6,0
        local hook=node(0,6,wagon.rootNode)
        function wagon:getActiveInputAttacherJoint() return {node=hook} end
        local g=P.geometria(tractor,trailer)
        assert(math.abs(g.drawbar-6)<0.000001)
        local ox,oz=TI.canoAlinhado(tractor,TI.getCarga(wagon))
        assert(math.abs(ox+4.2)<0.000001 and math.abs(oz+5)<0.000001)
        ''')

    def test_short_pipe_scene_finds_bounded_front_and_reverse_adjustments(self):
        self.check('''
        shortPipeScene()
        local job=parkingJob()
        M.avancar(job,3)
        assert(job.expanded<=3 and job.status=='buscando')
        assert(coroutine==nil)
        finishSearch(job)
        assert(job.status=='pronto' and #job.path>0)
        local front,back=false,false
        for _,segment in ipairs(job.path) do
            front=front or segment.dir>0;back=back or segment.dir<0
            assert(segment.distance<=M.CONFIG.percursoMaximo and segment.changes<=4)
            assert(P.poseLivre(job.g,segment.p,P.CONFIG.margemPrecisao))
            assert((segment.p.x-job.start.x)^2+(segment.p.z-job.start.z)^2<=M.CONFIG.raioLocal^2)
        end
        assert(front and back and job.path[#job.path].distance<30)
        ''')

    def test_short_pipe_drive_reaches_bucket_without_contact_or_large_loop(self):
        self.check('''
        shortPipeScene()
        local reached,front,back=false,false,false
        for i=1,1000 do
            tick(100)
            local distance=M.distanciaCano(tractor,trailer,3)
            if distance<0.4 then permitUnload() end
            if state()==E.DESCARREGANDO then reached=true;break end
            local c=tractor.command
            if c.allowed then
                front=front or c.forwards;back=back or not c.forwards
                local g=P.geometria(tractor,trailer)
                local k=math.max(-1/g.raioGiro,math.min(1/g.raioGiro,2*c.x/math.max(1,c.x^2+c.z^2)))
                local ds=(c.forwards and 1 or -1)*c.speed/3.6*0.1
                local p=P.avancarPose(g.pose,k,ds,g.drawbar)
                tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=p.x,p.z,p.a
                wagon.rootNode.parent=nil
                wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=p.x-math.sin(p.t)*g.drawbar,p.z-math.cos(p.t)*g.drawbar,p.t
                tractor.speed,tractor.movingDirection=c.speed,c.forwards and 1 or -1
            else tractor.speed=0 end
            assert(P.posicaoLivre(tractor,trailer,tractor.rootNode.x,tractor.rootNode.z,nil,0))
            assert(P.posicaoNoTalhao(tractor,tractor.rootNode.x,tractor.rootNode.z))
        end
        local s=tractor.spec_transbordoInteligente
        assert(reached and front and back and s.manobraCarreta.distance<30)
        tick(100)
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
        ''')

    def test_tight_field_does_not_allow_a_manoeuvre_outside_to_reach_truck(self):
        self.check('''
        shortPipeScene()
        tractor.spec_transbordoInteligente.talhao=TITalhao.criar({}, {-17,-2,-2,-2,-2,2,-17,2})
        assert(P.posicaoNoTalhao(tractor,-5,0))
        local job=assert(M.iniciar(tractor,trailer,3,0,-1))
        finishSearch(job)
        assert(job.status=='semEspaco' and job.path==nil)
        assert(tractor.rootNode.x==-5 and tractor.rootNode.z==0)
        ''')

    def test_planning_budget_is_bounded_when_no_short_plan_is_found(self):
        self.check('''
        shortPipeScene()
        local job=parkingJob()
        M.CONFIG.maxNos=1
        M.avancar(job,100)
        assert(job.status=='semEspaco' and job.expanded==1)
        assert(job.path==nil)
        ''')

    def test_small_reverse_can_leave_travel_padding_without_overriding_contact(self):
        self.check('''
        shortPipeScene();tractor.size.length=6
        local s=tractor.spec_transbordoInteligente
        assert(not P.posicaoLivre(tractor,trailer,-5,0))
        assert(P.posicaoLivre(tractor,trailer,-5,0,nil,P.CONFIG.margemPrecisao))
        s.manobraCarretaCurta=true
        TI.dirigir(tractor,100,-7,0,1.5,false)
        assert(tractor.command.allowed and not tractor.command.forwards)
        tractor.rootNode.x=-4
        TI.dirigir(tractor,100,-7,0,1.5,false)
        assert(not tractor.command.allowed)
        ''')

    def test_moving_target_invalidates_local_adjustment(self):
        self.check('''
        shortPipeScene()
        local _,_,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        local s=tractor.spec_transbordoInteligente
        for i=1,100 do
            M.comandar(tractor,16,trailer,3,dx,dz)
            if s.manobraCarreta.job.status=='pronto' then break end
        end
        assert(s.manobraCarreta.job.status=='pronto')
        trailer.rootNode.x=1
        local command=M.comandar(tractor,100,trailer,3,dx,dz)
        assert(command.speed==0 and s.manobraCarreta.replans==1)
        assert(command.message:find('Atualizando a posicao real'))
        ''')

    def test_no_observed_motion_stops_and_rechecks_instead_of_accelerating_forever(self):
        self.check('''
        shortPipeScene()
        local _,_,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        local stoppedForProgress=false
        for i=1,100 do
            local command=M.comandar(tractor,100,trailer,3,dx,dz)
            if command.message:find('conferir a folga real') then stoppedForProgress=true;break end
        end
        assert(stoppedForProgress and tractor.rootNode.x==-5 and tractor.rootNode.z==0)
        ''')

    def test_slow_adjustment_at_sixty_frames_per_second_is_not_treated_as_stuck(self):
        self.check('''
        shortPipeScene()
        for i=1,600 do
            tick(16)
            local c=tractor.command
            if c.allowed then
                local g=P.geometria(tractor,trailer)
                local k=math.max(-1/g.raioGiro,math.min(1/g.raioGiro,2*c.x/math.max(1,c.x^2+c.z^2)))
                local ds=(c.forwards and 1 or -1)*c.speed/3.6*0.016
                local p=P.avancarPose(g.pose,k,ds,g.drawbar)
                tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=p.x,p.z,p.a
                wagon.rootNode.parent=nil
                wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=p.x-math.sin(p.t)*g.drawbar,p.z-math.cos(p.t)*g.drawbar,p.t
                tractor.speed,tractor.movingDirection=c.speed,c.forwards and 1 or -1
            else tractor.speed=0 end
        end
        local control=tractor.spec_transbordoInteligente.manobraCarreta
        assert(control.distance>2 and control.replans==0)
        assert((control.noMotion or 0)<200)
        ''')

    def test_native_receiver_identity_is_required_even_with_pipe_at_target(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick();alignTrailer()
        permitUnload(makeTrailer(40,0),3)
        tick(100)
        assert(state()==E.APROXIMANDO_CARRETA and wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OFF)
        permitUnload(trailer,3);tick(100);tick(100)
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
        ''')

    def test_native_turning_radius_is_used_by_prediction(self):
        self.check('''
        shortPipeScene();tractor.maxTurningRadius=7
        assert(P.geometria(tractor,trailer).raioGiro==7)
        tractor.maxTurningRadius=0
        assert(P.geometria(tractor,trailer).raioGiro==P.CONFIG.raioGiro)
        ''')

    def test_lost_receiving_spot_advances_inside_bucket_without_restarting_long_approach(self):
        self.check('''
        shortPipeScene()
        teleport(-4.2,-9.5);tractor.rootNode.angle=math.pi
        wagon.rootNode.parent=nil
        wagon.rootNode.x,wagon.rootNode.z,wagon.rootNode.angle=-4.2,-1.5,math.pi
        local s=tractor.spec_transbordoInteligente
        s.fracaoDescarga=0
        permitUnload();tick(100);tick(100)
        assert(state()==E.DESCARREGANDO)
        wagon.canDischarge=false
        tick(100)
        assert(state()==E.APROXIMANDO_CARRETA and s.manobraCarreta==nil)
        assert(math.abs(s.pontoDescargaFixo-1.5/9)<0.000001)
        local ax,az,bx,bz=M.faixa(tractor,trailer,3)
        assert(ax==bx and az==bz and math.abs(az+3)<0.000001)
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OFF)
        ''')

    def test_goal_without_native_receiver_confirmation_requests_another_target(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick();alignTrailer()
        local _,_,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        local retry=false
        for i=1,40 do
            local command=M.comandar(tractor,1000,trailer,3,dx,dz)
            assert(command.speed==0 and wagon.units[2].level==20000)
            if command.retryTarget then retry=true;break end
        end
        assert(retry and wagon.dischargeState~=Dischargeable.DISCHARGE_STATE_OBJECT)
        ''')

    def test_mapping_measures_pipe_and_both_bodies_and_only_keeps_safe_parking_poses(self):
        self.check('''
        alternativeScene(false)
        local map=M.atualizarMapa(tractor,trailer,3)
        assert(map.largura==2.6 and map.comprimento==12 and map.larguraBazuca==3)
        assert(math.abs(map.alcance-4.7)<0.000001 and #map.vagas>0)
        for _,vaga in ipairs(map.vagas) do
            assert(P.poseLivre(map.g,vaga.p,P.CONFIG.margemPrecisao))
            local x,z,a=P.poseParte(map.g,vaga.p,wagon)
            local px,pz=x+math.cos(a)*map.pipeX+math.sin(a)*map.pipeZ,z-math.sin(a)*map.pipeX+math.cos(a)*map.pipeZ
            assert(math.abs(px)<0.000001 and pz>=-4.500001 and pz<=4.500001)
        end
        assert(map.folga>0.2)
        ''')

    def test_mapping_does_not_make_short_pipe_longer_to_fit_the_trailer(self):
        self.check('''
        alternativeScene(true)
        wagon.dischargeNode.node.x,wagon.dischargeNode.node.z=-1,0
        local map=M.mapear(tractor,trailer,3)
        assert(map.alcance==1 and #map.vagas==0)
        assert(wagon.dischargeNode.node.x==-1)
        ''')

    def test_mapping_excludes_truck_cabin_even_when_trailer_itself_would_fit(self):
        self.check('''
        alternativeScene(true)
        local map=M.mapear(tractor,trailer,3)
        local before=#map.vagas
        assert(before>0)
        truck.size={width=16,length=24}
        truck.rootNode.z=0
        map=M.mapear(tractor,trailer,3)
        assert(#map.vagas==0)
        ''')

    def test_mapping_updates_after_target_moves_and_is_cleared_on_target_release(self):
        self.check('''
        alternativeScene(false)
        local map=M.atualizarMapa(tractor,trailer,3)
        trailer.rootNode.x=trailer.rootNode.x+2
        tractor.spec_transbordoInteligente.tempoTotal=tractor.spec_transbordoInteligente.tempoTotal+500
        local nextMap=M.atualizarMapa(tractor,trailer,3)
        assert(nextMap~=map and nextMap.ax==map.ax+2)
        TI.desativar(tractor)
        assert(tractor.spec_transbordoInteligente.mapaCarreta==nil)
        ''')

    def test_failed_short_search_continues_with_another_entry_and_reaches_trailer(self):
        self.check('''
        defaultField=makeField(-50,-45,50,40)
        alternativeScene(false)
        local short=parkingJob()
        finishSearch(short)
        assert(short.status=='semEspaco')
        local reached,alternative=false,false
        for i=1,1800 do
            reached=moveParkingFrame(100)
            local control=tractor.spec_transbordoInteligente.manobraCarreta
            alternative=alternative or (control~=nil and control.nivel>1)
            if reached then break end
        end
        local s=tractor.spec_transbordoInteligente
        assert(reached and alternative and s.manobraCarreta.distance<65)
        tick(100)
        assert(wagon.dischargeState==Dischargeable.DISCHARGE_STATE_OBJECT)
        ''')

    def test_mapped_reentry_reaches_exact_receiver_without_guessing_a_loading_range(self):
        self.check('''
        defaultField=makeField(-55,-50,55,45)
        alternativeScene(true,-5,0)
        local reached,mapped=false,false
        for i=1,3000 do
            reached=moveParkingFrame(100)
            local c=tractor.spec_transbordoInteligente.manobraCarreta
            mapped=mapped or (c~=nil and c.job~=nil and c.job.entradaMapeada==true)
            if reached then break end
        end
        assert(reached and mapped)
        assert(tractor.spec_transbordoInteligente.manobraCarreta.distance<=M.CONFIG.percursoTotal)
        ''')

    def test_all_alternatives_remain_blocked_in_a_field_with_no_manoeuvring_space(self):
        self.check('''
        alternativeScene(false,-5,0)
        local s=tractor.spec_transbordoInteligente
        s.talhao=TITalhao.criar({}, {-17,-2,-2,-2,-2,2,-17,2})
        local command
        for i=1,300 do command=M.comandar(tractor,100,trailer,3,0,-1) end
        assert(s.manobraCarreta.nivel==#M.ALTERNATIVAS)
        assert(s.manobraCarreta.job.status=='semEspaco')
        assert(command.speed==0 and s.isAtivo)
        assert(tractor.rootNode.x==-5 and tractor.rootNode.z==0)
        ''')

    def test_reentry_checks_a_limited_number_of_curve_samples_each_update(self):
        self.check('''
        alternativeScene(true,-5,0)
        local _,_,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        local job=M.iniciar(tractor,trailer,3,dx,dz,3)
        local calls=0
        local free=P.poseLivre
        P.poseLivre=function(...) calls=calls+1;return free(...) end
        M.prepararCurvas(job);job.curvesStarted=true
        assert(#job.curves>0 and #job.curves<=M.CONFIG.maxCurvas)
        calls=0
        M.avancar(job,3)
        assert(calls<=3 and job.status=='buscando')
        finishSearch(job)
        assert(job.status=='pronto' and job.entradaMapeada)
        ''')

    def test_unavailable_direct_entry_starts_local_alternatives_instead_of_holding_forever(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        teleport(35,-20)
        activate();tick()
        M.entrada=function() return nil end
        tick(100)
        local s=tractor.spec_transbordoInteligente
        assert(s.carretaBloqueada and not tractor.command.allowed)
        tick(100)
        assert(s.manobraCarreta~=nil and s.manobraCarreta.job~=nil)
        assert(s.caminhaoAlvo==trailer and s.isAtivo)
        ''')

    def test_already_aligned_pipe_never_starts_a_large_reentry(self):
        self.check('''
        wagon.units[2].level,wagon.units[2].kind=20000,1
        activate();tick();alignTrailer()
        local _,_,dx,dz=TI.alvoDescarregar(tractor,trailer,3)
        local job=M.iniciar(tractor,trailer,3,dx,dz,3)
        M.avancar(job,1)
        assert(job.status=='pronto' and #job.path==0 and job.curves==nil)
        assert(not TI.podeDescarregar(tractor))
        ''')

    def test_hud_reports_measured_trailer_pipe_and_parking_clearance(self):
        self.check('''
        alternativeScene(false)
        M.atualizarMapa(tractor,trailer,3)
        RenderText={ALIGN_CENTER=1,ALIGN_LEFT=0}
        function setTextColor() end
        function setTextAlignment() end
        function setTextBold() end
        function tractor:getIsEntered() return true end
        local lines={}
        function renderText(x,y,size,text) lines[#lines+1]=text end
        TI.onDraw(tractor)
        local dimensions,clearance=false,false
        for _,line in ipairs(lines) do
            dimensions=dimensions or (line:find('Cacamba 2.6 x 12.0 m') and line:find('Cano 4.7 m'))
            clearance=clearance or line:find('Posicoes livres no talhao:')
        end
        assert(dimensions and clearance)
        ''')

    def test_combine_arrival_is_faster_on_a_straight_open_stretch(self):
        self.check('''
        teleport(-6,-80)
        activate();tick();tick(100)
        assert(tractor.command.allowed and tractor.command.speed==25)
        assert(TI.velocidadeChegada(tractor,combine,-6,50)==25)
        assert(TI.velocidadeChegada(tractor,combine,80,0)==15)
        ''')

    def test_faster_combine_arrival_still_slows_down_near_combine_and_field_edge(self):
        self.check('''
        teleport(-6,75)
        activate();tick();tick(100)
        assert(tractor.command.speed<=TI.CONFIG.velocidadeViagem)
        assert(TI.velocidadeChegada(tractor,combine,-6,105)==15)
        local s=tractor.spec_transbordoInteligente
        s.talhao=TITalhao.criar({}, {-25,40,25,40,25,90,-25,90})
        TI.dirigir(tractor,100,-6,120,25,true,true)
        assert(tractor.command.speed<25)
        assert(P.posicaoNoTalhao(tractor,-6,75))
        ''')


if __name__=='__main__':
    unittest.main(verbosity=2)
