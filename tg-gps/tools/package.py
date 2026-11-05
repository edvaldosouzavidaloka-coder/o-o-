"""Build the installable mod; validate entries, XML references and ZIP CRCs."""
from pathlib import Path
import argparse
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT.parent / 'FS25_TG_GPS.zip')
args = parser.parse_args()
members = {name: (ROOT / name).read_bytes() for name in ('modDesc.xml', 'icon.dds', 'LEIA-ME.txt')}
for folder in ('scripts', 'models', 'shaders', 'sounds', 'licenses'):
    for path in sorted((ROOT / folder).rglob('*')):
        if path.is_file():
            members[path.relative_to(ROOT).as_posix()] = path.read_bytes()
desc = ET.fromstring(members['modDesc.xml'])
for element in desc.findall('./extraSourceFiles/sourceFile') + desc.findall('./specializations/specialization'):
    assert element.attrib['filename'] in members, element.attrib['filename']
assert desc.findtext('iconFilename') in members
actions = {e.attrib['name'] for e in desc.findall('./actions/action')}
bindings = {e.attrib['action'] for e in desc.findall('./inputBinding/actionBinding')}
assert actions == bindings
for action in actions:
    assert desc.find('./l10n/text[@name="input_' + action + '"]') is not None
for name, content in members.items():
    if name.endswith('.i3d'):
        model = ET.fromstring(content)
        external = model.find('Shapes').get('externalShapesFile')
        if external:
            binary=(ROOT/name).parent.joinpath(external).resolve()
            assert binary.is_relative_to(ROOT) and binary.relative_to(ROOT).as_posix() in members, external
        for ref in model.findall('./Files/File'):
            if ref.attrib['filename'].startswith(('$data/', '$dataS/')): continue
            resolved = (ROOT / name).parent.joinpath(ref.attrib['filename']).resolve()
            assert resolved.is_relative_to(ROOT) and resolved.relative_to(ROOT).as_posix() in members, ref.attrib['filename']
assert f'TGGPS.VERSION = "{desc.findtext("version")}"' in members['scripts/TGGPS.lua'].decode()
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for name, content in sorted(members.items()):
        info = zipfile.ZipInfo(name, date_time=(2026, 11, 3, 12, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, content)
with zipfile.ZipFile(args.output) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == set(members)
    for name, content in members.items(): assert archive.read(name) == content
print(f'Pacote {desc.findtext("version")}: {args.output} ({args.output.stat().st_size} bytes)')
print('XML, dependencias, acoes, versao e integridade ZIP: OK')
