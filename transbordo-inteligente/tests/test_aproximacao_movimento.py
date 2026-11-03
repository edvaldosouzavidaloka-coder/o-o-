"""Convergencia com direcao cinemática simples; nao substitui a fisica do FS25."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class AproximacaoMovimentoTests(unittest.TestCase):
    def simulate(self, mode, x, z, angle):
        lua = LuaRuntime(unpack_returned_tuples=True)
        for name in ['TIProtecao.lua', 'TransbordoInteligente.lua', 'tests/fixture.lua']:
            lua.execute((ROOT / name).read_text())
        lua.globals().mode = mode
        lua.globals().startx = x
        lua.globals().startz = z
        lua.globals().starta = angle
        lua.execute('''
        tractor.rootNode.x,tractor.rootNode.z,tractor.rootNode.angle=startx,startz,starta
        if mode=='truck' then wagon.units[2].level,wagon.units[2].kind=20000,1 end
        activate()
        local reached=false
        -- Movimento integra a curvatura do comando enviado ao controlador nativo.
        -- Engate rigido e velocidade instantanea: validam convergencia, nao fisica.
        for i=1,1200 do
            tick(100)
            local x,z,dx,dz
            if mode=='combine' then x,z,dx,dz=TI.alvoReceber(tractor,combine)
            else x,z,dx,dz=TI.alvoDescarregar(tractor,trailer,3) end
            local ex,ez=x-tractor.rootNode.x,z-tractor.rootNode.z
            local c=tractor.command
            if math.abs(ex*dx+ez*dz)<TI.CONFIG.toleranciaLongitudinal
                and math.abs(ex*dz-ez*dx)<TI.CONFIG.toleranciaLateral and not c.allowed then
                reached=true;break
            end
            if c.allowed and c.speed>=1 then
                local curvature=math.max(-0.1,math.min(0.1,2*c.x/math.max(1,c.x*c.x+c.z*c.z)))
                local ds=(c.forwards and 1 or -1)*c.speed/3.6*0.1
                local a=tractor.rootNode.angle
                tractor.rootNode.x=tractor.rootNode.x+math.sin(a+curvature*ds/2)*ds
                tractor.rootNode.z=tractor.rootNode.z+math.cos(a+curvature*ds/2)*ds
                tractor.rootNode.angle=a+curvature*ds
                tractor.speed=c.speed
                tractor.movingDirection=c.forwards and 1 or -1
            else tractor.speed=0 end
            assert(tractor.spec_transbordoInteligente.isAtivo)
            assert(wagon.dischargeState~=Dischargeable.DISCHARGE_STATE_OBJECT)
        end
        assert(reached,'Nao convergiu para o centro dentro de 120 segundos simulados')
        ''')

    def test_combine_from_aligned_rear(self):
        self.simulate('combine', -6, 75, 0)

    def test_combine_from_pipe_side_oblique(self):
        self.simulate('combine', -50, 20, 0)

    def test_combine_from_opposite_side(self):
        self.simulate('combine', 20, 20, 0)

    def test_truck_after_arriving_from_combine(self):
        self.simulate('truck', -6, 120, 0)

    def test_truck_approached_from_side_and_opposite_heading(self):
        self.simulate('truck', 0, 0, 0)

    def test_truck_already_parallel_in_opposite_heading(self):
        self.simulate('truck', 35, 30, 3.141592653589793)


if __name__ == '__main__':
    unittest.main(verbosity=2)
