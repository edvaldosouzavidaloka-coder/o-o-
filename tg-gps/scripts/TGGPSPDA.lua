-- Borrow the game's own PDA image and world-to-image transform, without changing
-- its map object/overlay. Based on the native-map bridge in the supplied HUD.
TGGPSPDA = {}
function TGGPSPDA.get()
    local m=g_currentMission
    if m==nil then return nil end
    local candidates={}
    local function add(v) if v then candidates[#candidates+1]=v end end
    if m.hud then add(m.hud.ingameMap);add(m.hud.map) end
    add(m.ingameMap);add(m.missionInfo and m.missionInfo.ingameMap)
    for _, map in ipairs(candidates) do
        local image=map.mapOverlay or (map.mapElement and map.mapElement.overlay)
        if image and type(image.filename)=="string" and image.filename~=""
            and type(map.worldSizeX)=="number" and map.worldSizeX>0
            and type(map.worldSizeZ)=="number" and map.worldSizeZ>0 then return map,image.filename end
    end
end
function TGGPSPDA.uv(map,x,z)
    local scale=map.mapExtensionScaleFactor or 1
    local u=((x+(map.worldCenterOffsetX or 0))/map.worldSizeX)*scale+(map.mapExtensionOffsetX or 0)
    local v=1-(((z+(map.worldCenterOffsetZ or 0))/map.worldSizeZ)*scale+(map.mapExtensionOffsetZ or 0))
    return u,v
end
function TGGPSPDA.command(map,filename,box,minX,minZ,maxX,maxZ)
    local u1,v1=TGGPSPDA.uv(map,minX,minZ)
    local u2,v2=TGGPSPDA.uv(map,maxX,maxZ)
    local du,dv=u2-u1,v2-v1
    if du<=0 or dv>=0 then return nil end
    local left,right,bottom,top=math.max(0,u1),math.min(1,u2),math.min(1,v1),math.max(0,v2)
    if right<=left or bottom<=top then return nil end
    local tx,ty=(left-u1)/du,(bottom-v1)/dv
    local tw,th=(right-left)/du,(top-bottom)/dv
    -- Overlay UV order is bottom-left, top-left, bottom-right, top-right.
    return {type="pda",role="native_pda",filename=filename,x=box.x+box.w*tx,y=box.y+box.h*ty,w=box.w*tw,h=box.h*th,
        uvs={left,bottom,left,top,right,bottom,right,top},worldBounds={minX,minZ,maxX,maxZ}}
end

-- Runtime I3D uses the same PDA texture and four cropped UVs. No terrain capture,
-- external imagery, guessed map size or private engine texture setter is needed.
function TGGPSPDA.createCabBackground(command,parent,width,height)
    if createXMLFile==nil or setXMLString==nil or saveXMLFile==nil then return nil end
    local folder=getUserProfileAppPath()..TGGPS.SAVE_FOLDER
    if createFolder then createFolder(folder) end
    local path=folder.."/pdaMonitor.i3d"
    local xml=createXMLFile("TGGPSPDA",path,"i3D")
    if xml==nil or xml==0 then return nil end
    local function put(key,value) setXMLString(xml,"i3D"..key,tostring(value)) end
    put("#name","TGGPSNativePDA");put("#version","1.6")
    put(".Files.File(0)#fileId",1);put(".Files.File(0)#filename",command.filename)
    local material=".Materials.Material(0)"
    put(material.."#name","nativePda");put(material.."#materialId",1)
    put(material.."#diffuseColor","1 1 1 1");put(material.."#specularColor","0 0 0")
    put(material..".Texture#fileId",1)
    local shape=".Shapes.IndexedTriangleSet(0)"
    put(shape.."#name","nativePdaPlane");put(shape.."#shapeId",1)
    put(shape.."#meshUsage",0);put(shape.."#bvCenter","0 0 0");put(shape.."#bvRadius",0.708)
    put(shape..".Vertices#count",4);put(shape..".Vertices#normal","true");put(shape..".Vertices#uv0","true")
    local positions={{-0.5,-0.5},{-0.5,0.5},{0.5,-0.5},{0.5,0.5}}
    for i,p in ipairs(positions) do
        local k=shape..string.format(".Vertices.v(%d)",i-1)
        put(k.."#p",p[1].." "..p[2].." 0");put(k.."#n","0 0 1")
        put(k.."#t0",command.uvs[i*2-1].." "..command.uvs[i*2])
    end
    put(shape..".Triangles#count",2)
    put(shape..".Triangles.t(0)#vi","0 2 3");put(shape..".Triangles.t(1)#vi","0 3 1")
    put(shape..".Subsets#count",1)
    for key,value in pairs({firstVertex=0,numVertices=4,firstIndex=0,numIndices=6,uvDensity0=1}) do
        put(shape..".Subsets.Subset(0)#"..key,value)
    end
    local scene=".Scene.Shape(0)"
    for key,value in pairs({name="NativePDA",nodeId=1,shapeId=1,materialIds=1,castsShadows="false",receiveShadows="false"}) do
        put(scene.."#"..key,value)
    end
    local saved=saveXMLFile(xml);delete(xml)
    if saved==false then return nil end
    local node=loadI3DFile(path,false,false,false)
    if node==nil or node==0 then return nil end
    link(parent,node)
    setTranslation(node,(command.x+command.w/2-0.5)*width,(command.y+command.h/2-0.5)*height,0.00404)
    setScale(node,command.w*width,command.h*height,1)
    return node
end
