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


if __name__=='__main__':
    unittest.main(verbosity=2)
