-- TOP GAMERS | GIANTS Editor 10.0.14
-- Selecione uma spline no Scenegraph e execute este arquivo no Script Editor.
-- O resultado fica em %TEMP%\TG_Cerca_Spline.csv.

local function fail(message)
    print("[TG CERCA] ERRO: " .. message)
end

local selected = getSelection(0)
if selected == nil or selected == 0 then
    fail("Selecione uma spline no Scenegraph.")
    return
end

local ok, length = pcall(getSplineLength, selected)
if not ok or type(length) ~= "number" or length < 0.2 then
    fail("A selecao nao e uma spline valida.")
    return
end

local spacing = 2.0 -- distancia aproximada entre pontos em metros
local steps = math.max(1, math.ceil(length / spacing))
local tmp = (os and os.getenv and os.getenv("TEMP")) or nil
if not tmp or tmp == "" then
    fail("A variavel TEMP do Windows nao esta acessivel.")
    return
end
local path = tmp .. "\\TG_Cerca_Spline.csv"
local file, err = io.open(path, "w")
if file == nil then
    fail("Falha ao gravar " .. path .. ": " .. tostring(err))
    return
end

file:write("x,y,z\n")
for i = 0, steps do
    local x, y, z = getSplinePosition(selected, i / steps)
    if x == nil or y == nil or z == nil then
        file:close()
        fail("Falha ao obter posicao na spline.")
        return
    end
    file:write(string.format("%.4f,%.4f,%.4f\n", x, y, z))
end
file:close()
print(string.format("[TG CERCA] %d pontos salvos em %s", steps+1, path))
print("[TG CERCA] Abra TG_Cerca_Editor.py e selecione o XML da cerca e do mapa.")
