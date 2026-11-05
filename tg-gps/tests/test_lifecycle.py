import unittest
import test_monitor as baseline


class LifecycleTests(unittest.TestCase):
    setUp = baseline.MonitorTests.setUp
    check = baseline.MonitorTests.check

    def test_unload_after_vehicle_cascade_skips_invalid_scene_entities(self):
        self.check('''
        metadata();TGGPS:update(100);TGGPS:update(450);TGGPS:update(1800)
        local manager=TGGPS.monitor;local screen=manager.screenRenderer
        local model,content,template,symbols,overlay=manager.monitorNode,screen.contentRoot,
            screen.templateRoot,screen.symbolTemplateRoot,screen.greenStar.overlay
        local pda=screen.nativeNode;assert(pda and entityExists(pda))
        delete(tractor.rootNode) -- Native vehicle cleanup precedes deleteMap.
        for _,node in ipairs({model,content,template,symbols,overlay,pda}) do assert(not entityExists(node)) end
        TGGPS:deleteMap()
        assert(TGGPS.monitor==nil and TGGPS.audio==nil and screen.contentRoot==nil)
        assert(manager.monitorNode==nil and screen.symbolTemplateRoot==nil and screen.greenStar==nil)
        assert(next(screen.pools)==nil and next(screen.nodeBrightness)==nil)
        ''')

    def test_partial_external_lcd_cleanup_releases_remaining_owned_nodes(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local manager=TGGPS.monitor;local screen=manager.screenRenderer
        local model,template,symbols=manager.monitorNode,screen.templateRoot,screen.symbolTemplateRoot
        delete(screen.contentRoot);delete(screen.greenStar.overlay)
        assert(entityExists(model) and entityExists(template) and entityExists(symbols))
        manager:removeMonitor()
        assert(not entityExists(model) and not entityExists(template) and not entityExists(symbols))
        assert(screen.contentRoot==nil and screen.templateRoot==nil and screen.greenStar==nil)
        ''')

    def test_vehicle_delete_event_detaches_monitor_before_native_component_removal(self):
        self.lua.execute((baseline.ROOT/'scripts/TGGPSVehicle.lua').read_text())
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local manager=TGGPS.monitor;local model=manager.monitorNode
        manager.editing=true
        TGGPSVehicle.onDelete(tractor)
        assert(entityExists(tractor.rootNode) and not entityExists(model))
        assert(manager.monitorNode==nil and manager.vehicle==nil and not manager.editing)
        assert(tractor.tgGpsSupported==false)
        delete(tractor.rootNode);TGGPS:deleteMap()
        ''')

    def test_other_vehicle_delete_preserves_active_monitor_and_cancels_its_pending_attach(self):
        self.lua.execute((baseline.ROOT/'scripts/TGGPSVehicle.lua').read_text())
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local manager=TGGPS.monitor;local model=manager.monitorNode
        local other={tgGpsSupported=true}
        manager.pendingVehicle,manager.pendingSince=other,manager.clock
        TGGPSVehicle.onDelete(other)
        assert(manager.pendingVehicle==nil and entityExists(model))
        assert(manager.vehicle==tractor and manager.monitorNode==model)
        ''')

    def test_repeated_monitor_and_map_cleanup_are_idempotent_with_strict_native_delete(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local manager=TGGPS.monitor;local screen=manager.screenRenderer
        manager:removeMonitor();manager:removeMonitor();screen:detach()
        manager:delete();manager:delete();TGGPS:deleteMap();TGGPS:deleteMap()
        assert(manager.monitorNode==nil and next(screen.templates)==nil and screen.count==0)
        ''')

    def test_renderer_does_not_touch_nodes_after_native_parent_deletion(self):
        self.check('''
        TGGPS:update(100);TGGPS:update(450)
        local screen=TGGPS.monitor.screenRenderer
        local original=setVisibility
        function setVisibility(node,value)
            assert(entityExists(node),'Visibility queried on an unknown entity')
            original(node,value)
        end
        delete(tractor.rootNode)
        screen:update(250)
        TGGPS:deleteMap()
        ''')


if __name__ == '__main__': unittest.main()
