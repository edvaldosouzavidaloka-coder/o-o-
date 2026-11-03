"""Empacotamento reproduzivel do mod de teste; nao modifica o Lua enviado."""
from pathlib import Path
import struct
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent


def icon_dds():
    """Icone original simples, DDS BGRA sem compressao, 256 x 256."""
    w = h = 256
    header = struct.pack('<7I', 124, 0x100F, h, w, w * 4, 0, 0)
    header += struct.pack('<11I', *([0] * 11))
    header += struct.pack('<8I', 32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    header += struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    assert len(header) == 124
    pixels = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b = 18, 32, 39
            if 55 <= y <= 145 and 42 + (y-55)//4 <= x <= 178 - (y-55)//4:
                r, g, b = 61, 190, 119
            if 143 <= y <= 157 and 55 <= x <= 190:
                r, g, b = 228, 239, 233
            if any((x-cx)**2 + (y-177)**2 <= 21**2 for cx in (83, 151)):
                r, g, b = 228, 239, 233
            if 150 <= x <= 215 and abs(y - (216-x)) <= 6:
                r, g, b = 61, 190, 119
            pixels.extend((b, g, r, 255))
    return b'DDS ' + header + bytes(pixels)


def write_zip(path, members):
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, content in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 2, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, content)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        assert set(z.namelist()) == set(members)
        for name, content in members.items():
            assert z.read(name) == content


def main():
    members = {
        'modDesc.xml': (ROOT / 'modDesc.xml').read_bytes(),
        'scripts/TransbordoInteligente.lua': (ROOT / 'TransbordoInteligente.lua').read_bytes(),
        'scripts/Bootstrap.lua': (ROOT / 'Bootstrap.lua').read_bytes(),
        'scripts/TIProtecao.lua': (ROOT / 'TIProtecao.lua').read_bytes(),
        'LEIA-ME.md': (ROOT / 'LEIA-ME.md').read_bytes(),
        'icon.dds': icon_dds(),
    }
    desc = ET.fromstring(members['modDesc.xml'])
    for entry in desc.findall('./extraSourceFiles/sourceFile') + desc.findall('./specializations/specialization'):
        assert entry.attrib['filename'] in members, entry.attrib['filename']
    assert desc.findtext('iconFilename') in members
    actions = {entry.attrib['name'] for entry in desc.findall('./actions/action')}
    bindings = {entry.attrib['action'] for entry in desc.findall('./inputBinding/actionBinding')}
    assert actions == bindings == {'TI_TOGGLE_TRANSBORDO', 'TI_FORCE_UNLOAD'}
    for action in actions:
        assert desc.find(f'./l10n/text[@name="input_{action}"]') is not None
    lua_version = re.search(r'TI\.VERSAO="([\d.]+)"', members['scripts/TransbordoInteligente.lua'].decode()).group(1)
    assert desc.findtext('version') == lua_version
    write_zip(ROOT / 'FS25_TransbordoInteligente.zip', members)
    sources = {p.relative_to(ROOT).as_posix(): p.read_bytes() for p in ROOT.rglob('*')
               if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.zip'}
    write_zip(ROOT / 'TransbordoInteligente_fontes.zip', sources)
    print('Mod:', ROOT / 'FS25_TransbordoInteligente.zip')
    print('Fontes e testes:', ROOT / 'TransbordoInteligente_fontes.zip')
    print('XML, referencias, CRC e conteudos dos dois pacotes conferidos.')


if __name__ == '__main__':
    main()
