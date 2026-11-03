"""Extrai DLCs que sejam arquivos ZIP/TAR comuns. Python 3.12 ou superior."""
import argparse
from pathlib import Path
import sys
import tarfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('arquivo', type=Path, help='Caminho do arquivo .dlc')
    parser.add_argument('-o', '--saida', type=Path, help='Pasta nova para extração')
    args = parser.parse_args()
    source = args.arquivo.resolve()
    destination = (args.saida or source.with_name(source.stem + '_extraido')).resolve()
    if not source.is_file():
        parser.error('Arquivo não encontrado.')
    if destination.exists():
        parser.error('A pasta de saída já existe. Escolha outra para preservar seus arquivos.')
    if zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as archive:
            members = archive.infolist()
            if any(item.flag_bits & 1 for item in members):
                parser.error('ZIP criptografado: este programa não remove proteção.')
            for item in members:
                name = item.filename.replace('\\', '/')
                target = (destination / name).resolve()
                if not target.is_relative_to(destination) or ':' in name:
                    parser.error('Arquivo contém caminho inseguro; extração cancelada.')
                mode = item.external_attr >> 16
                if mode & 0o170000 == 0o120000:
                    parser.error('Arquivo contém link simbólico; extração cancelada.')
            destination.mkdir(parents=True)
            # Use the validated normalized paths on every platform.
            for item in members:
                target = destination / item.filename.replace('\\', '/')
                if item.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(item) as src, target.open('xb') as dst:
                        import shutil
                        shutil.copyfileobj(src, dst)
    elif tarfile.is_tarfile(source):
        with tarfile.open(source) as archive:
            members = archive.getmembers()
            if any(not (item.isfile() or item.isdir()) for item in members):
                parser.error('TAR contém links ou arquivos especiais; extração cancelada.')
            destination.mkdir(parents=True)
            archive.extractall(destination, members=members, filter='data')
    else:
        with source.open('rb') as stream:
            signature = stream.read(16).hex(' ')
        parser.error('Formato proprietário, criptografado ou não suportado. '
                     'Renomear para ZIP não resolve. Assinatura: ' + signature)
    print('Extraído em:', destination)


if __name__ == '__main__':
    try:
        main()
    except (OSError, zipfile.BadZipFile, tarfile.TarError, RuntimeError) as error:
        print('Falha:', error, file=sys.stderr)
        print('Se uma pasta parcial foi criada, use outra pasta ao tentar novamente.', file=sys.stderr)
        sys.exit(1)
