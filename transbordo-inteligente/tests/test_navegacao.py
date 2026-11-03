"""Planejador e adaptadores FS25 com sensores deterministas, sem engine instalada."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class NavegacaoTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        for path in ['TINavegacao.lua', 'TransbordoInteligente.lua', 'tests/fixture.lua']:
            self.lua.execute((ROOT / path).read_text())
        self.lua.execute('''
        N=TransbordoNavegacao
        activate()
        tractor.size={width=3,length=5,height=3}
        wagon.size={width=3,length=7,height=3}
        function model() return N.modelo(tractor) end
        -- Obstaculos circulares com discriminacao de mascara.
        obstacles={}
        function overlapBox(x,y,z,rx,a,rz,hw,hh,hl,callback,target,mask)
            for _,o in ipairs(obstacles) do
                if mask~=CollisionFlag.TREE or o.tree then
                    local lx=math.cos(a)*(o.x-x)-math.sin(a)*(o.z-z)
                    local lz=math.sin(a)*(o.x-x)+math.cos(a)*(o.z-z)
                    local cx=math.max(-hw,math.min(hw,lx))
                    local cz=math.max(-hl,math.min(hl,lz))
                    if (lx-cx)^2+(lz-cz)^2 <= (o.r or 0.1)^2 then target[callback](target,o.node or o) end
                end
            end
        end
        function findPath(x,z,sensor,goalAngle)
            local m=model()
            local search=N.criarBusca(m,sensor or assert(N.sensor(m)),N.pose(m),{x=x,z=z,a=goalAngle})
            for i=1,100000 do
                local done,result,reason=N.atualizarBusca(search)
                if done then return result,reason,i end
            end
            error('Busca nao terminou no limite do teste')
        end
        function wheat(state)
            g_fruitTypeManager.fruitTypes={{index=1,name='WHEAT',startStateChannel=0,numStateChannels=4,
                numGrowthStates=7,terrainDataPlaneId=100,cutStates={[9]=true},
                getDataPlaneInfo=function(self) return self.terrainDataPlaneId,self.startStateChannel,self.numStateChannels end,
                getIsCut=function(self,state) return self.cutStates[state]~=nil end}}
            g_currentMission.fruits=nil
            cropState=state
            DensityMapModifier.new=function(id,first,count,terrain)
                assert(id==100 and first==0 and count==4 and terrain==g_currentMission.terrainRootNode)
                return {
                    setParallelogramWorldCoords=function(self,x1,z1,x2,z2,x3,z3,kind)
                        self.coords={x1,z1,x2,z2,x3,z3}
                    end,
                    executeGet=function(self,filter,cut)
                        local s=cropState
                        local present=s>=filter.minimum and s<=filter.maximum
                        if cut and s==cut.minimum then present=false end
                        if cropRegion then
                            local c=self.coords
                            local cx=(c[3]+c[5])/2
                            local cz=(c[4]+c[6])/2
                            present=present and cropRegion(cx,cz,c)
                        end
                        return present and 100 or 0,present and 10 or 0,10
                    end
                }
            end
            DensityMapFilter.new=function(modifier)
                return {setValueCompareParams=function(self,kind,minimum,maximum)
                    self.kind,self.minimum,self.maximum=kind,minimum,maximum
                end}
            end
        end
        ''')

    def check(self, code):
        return self.lua.execute(code)

    def test_straight_path_in_clear_area_has_no_side_swerving(self):
        self.check('''
        local path=assert(findPath(0,40,nil,0))
        assert(#path>5)
        for _,p in ipairs(path) do assert(math.abs(p.x)<0.001 and math.abs(p.a)<0.001) end
        ''')

    def test_path_goes_around_pole_instead_of_through_it(self):
        self.check('''
        obstacles={{x=0,z=22,r=0.15}}
        local path=assert(findPath(0,50,nil,0))
        local sensor=assert(N.sensor(model()))
        local detour=false
        for _,p in ipairs(path) do
            assert(sensor:livre(p))
            if math.abs(p.x)>3 then detour=true end
        end
        assert(detour)
        ''')

    def test_tree_clearance_avoids_dense_woodland_edge(self):
        self.check('''
        obstacles={{x=0,z=22,r=1,tree=true},{x=2,z=23,r=1,tree=true}}
        local path=assert(findPath(0,55,nil,0))
        local sensor=assert(N.sensor(model()))
        local detour=false
        for _,p in ipairs(path) do
            assert(sensor:livre(p))
            if math.abs(p.x)>6 then detour=true end
        end
        assert(detour)
        ''')

    def test_seedlings_and_mature_crop_block_but_harvested_area_does_not(self):
        for growth, blocked in [(1, True), (3, True), (7, True), (9, False), (0, False)]:
            with self.subTest(growth=growth):
                self.check(f'''
                wheat({growth})
                local m=model()
                local clear=assert(N.sensor(m)):livre(N.pose(m))
                assert(clear == {str(not blocked).lower()})
                ''')

    def test_fs25_data_plane_accessor_works_without_mission_fruits(self):
        self.check('''
        wheat(5)
        assert(g_currentMission.fruits==nil)
        local fruit=g_fruitTypeManager.fruitTypes[1]
        -- A fonte autoritativa e o accessor, mesmo sem campos publicos duplicados.
        fruit.terrainDataPlaneId,fruit.startStateChannel,fruit.numStateChannels=nil,nil,nil
        function fruit:getDataPlaneInfo() return 100,0,4 end
        local m=model()
        local sensor,reason=N.sensor(m)
        assert(sensor,reason)
        assert(#sensor.readers==1 and not sensor:livre(N.pose(m)))
        cropState=0
        assert(sensor:livre(N.pose(m)))
        ''')

    def test_fs25_public_descriptor_fields_work_without_accessor(self):
        self.check('''
        wheat(5)
        g_fruitTypeManager.fruitTypes[1].getDataPlaneInfo=nil
        local m=model()
        local sensor,reason=N.sensor(m)
        assert(sensor,reason)
        assert(not sensor:livre(N.pose(m)))
        ''')

    def test_native_cut_states_use_raw_state_numbers_and_all_cut_states(self):
        self.check('''
        wheat(3)
        local fruit=g_fruitTypeManager.fruitTypes[1]
        fruit.cutStates={[3]=true,[5]=true}
        local m=model()
        local sensor=assert(N.sensor(m))
        assert(sensor:livre(N.pose(m)))
        cropState=5;assert(sensor:livre(N.pose(m)))
        cropState=4;assert(not sensor:livre(N.pose(m)))
        cropState=6;assert(not sensor:livre(N.pose(m)))
        ''')

    def test_optional_legacy_map_adapter_still_checks_crop(self):
        self.check('''
        wheat(5)
        local fruit=g_fruitTypeManager.fruitTypes[1]
        fruit.getDataPlaneInfo,fruit.terrainDataPlaneId=nil,nil
        fruit.getIsCut,fruit.cutStates=nil,nil
        fruit.cutState=8
        g_currentMission.fruits={[1]={id=100}}
        local m=model()
        assert(not assert(N.sensor(m)):livre(N.pose(m)))
        ''')

    def test_fruit_not_loaded_in_this_map_does_not_need_a_reader(self):
        self.check('''
        wheat(5)
        g_fruitTypeManager.fruitTypes[1].getDataPlaneInfo=function() return 0,0,4 end
        local m=model()
        local sensor=assert(N.sensor(m))
        assert(#sensor.readers==0 and sensor:livre(N.pose(m)))
        ''')

    def test_accessor_failure_or_incomplete_crop_still_blocks_movement(self):
        self.check('''
        wheat(5)
        local fruit=g_fruitTypeManager.fruitTypes[1]
        fruit.getDataPlaneInfo=function() error('mapa nao carregado') end
        TI.dirigir(tractor,100,0,40,10,'seguir')
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('getDataPlaneInfo'))
        fruit.getDataPlaneInfo,fruit.terrainDataPlaneId=nil,nil
        TI.dirigir(tractor,100,0,40,10,'seguir')
        assert(not tractor.command.allowed)
        ''')

    def test_invalid_density_response_never_counts_as_free_ground(self):
        self.check('''
        wheat(0)
        local m=model()
        local sensor=assert(N.sensor(m))
        sensor.readers[1].modifier.executeGet=function() return nil,nil end
        assert(sensor:livre(N.pose(m))==nil)
        ''')

    def test_route_uses_harvested_corridor_around_crop(self):
        self.check('''
        wheat(5)
        cropRegion=function(x,z,c)
            -- Intersecao conservadora da area consultada com o retangulo de cultura.
            local minx,maxx=math.huge,-math.huge
            local minz,maxz=math.huge,-math.huge
            for i=1,5,2 do minx=math.min(minx,c[i]);maxx=math.max(maxx,c[i]);minz=math.min(minz,c[i+1]);maxz=math.max(maxz,c[i+1]) end
            return minx<6 and maxx>-6 and minz<32 and maxz>16
        end
        local path=assert(findPath(0,50,nil,0))
        local sensor=assert(N.sensor(model()))
        local detour=false
        for _,p in ipairs(path) do
            assert(sensor:livre(p))
            if math.abs(p.x)>8 then detour=true end
        end
        assert(detour)
        ''')

    def test_no_route_through_blocked_goal(self):
        self.check('''
        N.CONFIG.maxNos=300
        obstacles={{x=0,z=30,r=10}}
        local path,reason=findPath(0,30)
        assert(path==nil and reason~=nil)
        ''')

    def test_search_advances_across_frames_instead_of_blocking_one_frame(self):
        self.check('''
        N.CONFIG.consultasPorQuadro=3
        local path,reason,frames=findPath(0,40)
        assert(path and frames>3)
        ''')

    def test_planning_and_native_drive_work_with_coroutine_absent(self):
        self.check('''
        assert(coroutine==nil)
        local path=assert(findPath(0,40,nil,0))
        assert(#path>1)
        for i=1,200 do
            TI.dirigir(tractor,100,0,40,10,'viagem',0,1)
            if tractor.command.allowed then break end
        end
        assert(tractor.command.allowed)
        ''')

    def test_one_query_per_frame_preserves_partial_curve_progress(self):
        self.check('''
        N.CONFIG.consultasPorQuadro=1
        local m=model()
        local sensor={calls=0,livre=function(self,p) self.calls=self.calls+1;return true end}
        local search=N.criarBusca(m,sensor,N.pose(m),{x=0,z=24,a=0})
        local result
        for i=1,2000 do
            local before=sensor.calls
            local done,path=N.atualizarBusca(search)
            assert(sensor.calls-before<=1)
            assert(search.consultasUltimoQuadro<=1)
            if done then result=path;break end
        end
        assert(result and #result>3)
        ''')

    def test_same_detour_with_small_and_large_frame_budgets(self):
        self.check('''
        obstacles={{x=0,z=22,r=0.15}}
        N.CONFIG.consultasPorQuadro=1
        local small=assert(findPath(0,50,nil,0))
        N.CONFIG.consultasPorQuadro=1000
        local large=assert(findPath(0,50,nil,0))
        assert(#small==#large)
        for i,p in ipairs(small) do
            assert(math.abs(p.x-large[i].x)<0.000001)
            assert(math.abs(p.z-large[i].z)<0.000001)
            assert(math.abs(p.a-large[i].a)<0.000001)
        end
        ''')

    def test_search_creation_failure_brakes_and_retries_without_frame_spam(self):
        self.check('''
        local attempts,warnings=0,0
        Logging.warning=function() warnings=warnings+1 end
        N.criarBusca=function() attempts=attempts+1;error('falha de inicializacao injetada') end
        TI.dirigir(tractor,100,0,40,10)
        assert(attempts==1 and warnings==1 and not tractor.command.allowed)
        for i=1,10 do TI.dirigir(tractor,100,0,40,10) end
        assert(attempts==1 and warnings==1 and not tractor.command.allowed)
        TI.dirigir(tractor,1000,0,40,10)
        assert(attempts==2 and warnings==1 and not tractor.command.allowed)
        ''')

    def test_sensor_error_mid_search_finishes_without_unchecked_route(self):
        self.check('''
        N.CONFIG.consultasPorQuadro=1
        local m=model()
        local sensor={calls=0,livre=function(self,p)
            self.calls=self.calls+1
            if self.calls>2 then return nil,'Sensor de teste indisponivel' end
            return true
        end}
        local search=N.criarBusca(m,sensor,N.pose(m),{x=0,z=40})
        local done,path,reason
        for i=1,20 do
            done,path,reason=N.atualizarBusca(search)
            if done then break end
        end
        assert(done and path==nil and reason=='Sensor de teste indisponivel')
        ''')

    def test_finished_search_is_stable_and_does_not_repeat_sensor_reads(self):
        self.check('''
        local m=model()
        local sensor={calls=0,livre=function(self,p) self.calls=self.calls+1;return true end}
        local search=N.criarBusca(m,sensor,N.pose(m),{x=0,z=12,a=0})
        local result
        for i=1,100 do
            local done,path=N.atualizarBusca(search)
            if done then result=path;break end
        end
        assert(result)
        local calls=sensor.calls
        local done,path=N.atualizarBusca(search)
        assert(done and path==result and sensor.calls==calls)
        ''')

    def test_thin_obstacle_between_waypoints_is_not_skipped(self):
        self.check('''
        obstacles={{x=0,z=12.4,r=0.05}}
        local path=assert(findPath(0,40,nil,0))
        local sensor=assert(N.sensor(model()))
        for i=2,#path do
            local p=path[i-1]
            local curve=(path[i].turn or 0)/model().radius
            for j=1,4 do p=N.avancar(model(),p,curve,1);assert(sensor:livre(p)) end
        end
        ''')

    def test_wagon_body_and_offtracking_are_checked(self):
        self.check('''
        local m=model()
        local sensor=assert(N.sensor(m))
        local p={x=0,z=20,a=0,t=math.rad(25)}
        local bodies=N.corpos(m,p)
        assert(math.abs(bodies[2].x)>2)
        obstacles={{x=bodies[2].x,z=bodies[2].z,r=0.2}}
        assert(not sensor:livre(p))
        obstacles={{x=0,z=12,r=0.1}}
        assert(not sensor:livre({x=0,z=20,a=0,t=0}))
        ''')

    def test_only_own_components_are_ignored_not_combine(self):
        self.check('''
        local m=model()
        local sensor=assert(N.sensor(m))
        local ownChild=node(0,0,tractor.rootNode)
        obstacles={{x=0,z=0,node=ownChild}}
        assert(sensor:livre(N.pose(m)))
        g_currentMission.nodeToObject[combine.rootNode]=combine
        obstacles={{x=0,z=0,node=combine.rootNode}}
        assert(not sensor:livre(N.pose(m)))
        ''')

    def test_failed_sensors_brake_instead_of_driving_blind(self):
        self.check('''
        overlapBox=nil
        TI.dirigir(tractor,100,0,50,15)
        assert(tractor.command.allowed==false)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao~=nil)
        N.reset(tractor); overlapBox=function() error('falha de engine') end
        TI.dirigir(tractor,100,0,50,15,'seguir')
        assert(tractor.command.allowed==false)
        ''')

    def test_missing_crop_metadata_is_not_treated_as_clear(self):
        self.check('''
        wheat(5)
        g_fruitTypeManager.fruitTypes[1].numGrowthStates=nil
        TI.dirigir(tractor,100,0,50,15)
        assert(not tractor.command.allowed)
        ''')

    def test_appearance_of_vehicle_ahead_causes_immediate_braking(self):
        self.check('''
        TI.dirigir(tractor,100,0,40,10,'seguir')
        assert(tractor.command.allowed)
        obstacles={{x=0,z=6,r=0.7}}
        TI.dirigir(tractor,100,0,40,10,'seguir')
        assert(not tractor.command.allowed and tractor.command.speed==0)
        ''')

    def test_safe_route_does_not_ignore_new_obstacle_after_planning(self):
        self.check('''
        for i=1,200 do
            TI.dirigir(tractor,100,0,40,10)
            if tractor.command.allowed then break end
        end
        assert(tractor.command.allowed)
        obstacles={{x=0,z=6,r=0.2}}
        TI.dirigir(tractor,100,0,40,10)
        assert(not tractor.command.allowed)
        ''')

    def test_both_pipe_sides_are_supported_from_actual_node(self):
        self.check('''
        local x=assert(TI.alvoReceber(tractor,combine)); assert(x<0)
        combine.dischargeNode.node.x=6
        x=assert(TI.alvoReceber(tractor,combine)); assert(x>0)
        combine.dischargeNode.node.x=0
        assert(TI.alvoReceber(tractor,combine)==nil)
        ''')

    def test_closed_pipe_waits_without_using_folded_geometry(self):
        self.check('''
        tick()
        combine.spec_pipe.currentState=0
        combine.spec_pipe.targetState=2
        tick()
        assert(not tractor.command.allowed)
        assert(tractor.spec_transbordoInteligente.mensagemNavegacao:find('cano'))
        ''')

    def test_wrong_side_does_not_cross_combine_during_following(self):
        self.check('''
        tractor.spec_transbordoInteligente.colheitadeiraAlvo=combine
        TI.mudarEstado(tractor,E.ACOMPANHANDO)
        teleport(6,108)
        tick()
        assert(state()==E.APROXIMANDO and not tractor.command.allowed)
        ''')

    def test_travel_uses_direct_native_commands_without_cruise_or_raw_steering(self):
        self.check('''
        for i=1,200 do
            TI.dirigir(tractor,50,0,40,10)
            if tractor.command.allowed then break end
        end
        assert(tractor.command.allowed and tractor.command.forwards)
        assert(tractor.command.dt==50)
        assert(tractor.rotatedTime==nil and tractor.cruise==nil)
        ''')

    def test_kinematic_follower_reaches_destination_around_pole_with_wagon(self):
        self.check('''
        -- Integracao cinematica de comandos, sem simular fisica GIANTS.
        N.CONFIG.consultasPorQuadro=200
        obstacles={{x=0,z=22,r=0.15}}
        local m=model()
        local p=N.pose(m)
        local arrived=false
        local curved=false
        for i=1,4000 do
            TI.dirigir(tractor,100,0,55,10,'viagem',0,1)
            local c=tractor.command
            if c.allowed then
                local curvature=math.max(-1/m.radius,math.min(1/m.radius,2*c.x/math.max(1,c.x*c.x+c.z*c.z)))
                p=N.avancar(m,p,curvature,c.speed/3.6*0.1)
                assert(assert(N.sensor(m)):livre(p))
                if math.abs(p.x)>3 then curved=true end
                tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=p.x,p.z,p.a
                wagon.rootNode.parent=nil
                wagon.rootNode.x=p.x-8*math.sin(p.t)
                wagon.rootNode.z=p.z-8*math.cos(p.t)
                wagon.rootNode.angle=p.t
                tractor.speed=c.speed
            else tractor.speed=0 end
            if math.sqrt(p.x*p.x+(p.z-55)^2)<3 then arrived=true;break end
        end
        assert(arrived and curved)
        ''')

    def test_shortcut_registers_with_selected_vehicle_flag_and_invokes_toggle(self):
        self.check('''
        TI.desativar(tractor)
        InputAction={TI_TOGGLE_TRANSBORDO=123}
        g_inputBinding={
            setActionEventTextVisibility=function(_,id,visible) assert(id==42 and visible) end,
            setActionEventText=function(_,id,text) assert(id==42 and #text>0) end
        }
        function tractor:clearActionEventsTable(t) self.cleared=true end
        function tractor:addActionEvent(events,action,target,callback)
            assert(action==123 and target==self)
            self.boundCallback=callback
            return true,42
        end
        TI.onRegisterActionEvents(tractor,true,false)
        assert(tractor.boundCallback~=nil and tractor.cleared)
        tractor.boundCallback(tractor,'TI_TOGGLE_TRANSBORDO',0)
        assert(not tractor.spec_transbordoInteligente.isAtivo)
        tractor.boundCallback(tractor,'TI_TOGGLE_TRANSBORDO',1)
        assert(tractor.spec_transbordoInteligente.isAtivo)
        ''')

    def test_shortcut_absent_action_and_inherited_activity_do_not_break_vehicle(self):
        self.check('''
        TI.desativar(tractor)
        InputAction={}
        Logging.warning=function() end
        function tractor:clearActionEventsTable() end
        function tractor:addActionEvent() error('nao deveria registrar') end
        TI.onRegisterActionEvents(tractor,true,true)
        SpecializationUtil={registerOverwrittenFunction=function() error('funcao nao registrada') end}
        TI.registerOverwrittenFunctions({functions={}})
        ''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
