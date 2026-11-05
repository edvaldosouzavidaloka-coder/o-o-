"""Generate original mono connection cues (Python stdlib + FFmpeg)."""
from pathlib import Path
import math
import struct
import subprocess
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 44100
directory = ROOT/'sounds'
directory.mkdir(exist_ok=True)
for name, notes in [('connect', [(784,.09), (988,.09), (1175,.17)]),
                    ('disconnect', [(988,.12), (659,.20)])]:
    values=[]
    for hz, duration in notes:
        count=int(duration*RATE)
        for i in range(count):
            envelope=min(1,i/(RATE*.008),(count-1-i)/(RATE*.018))
            signal=.24*math.sin(2*math.pi*hz*i/RATE)+.035*math.sin(4*math.pi*hz*i/RATE)
            values.append(round(32767*signal*max(0,envelope)))
        values.extend([0]*int(RATE*.028))
    with tempfile.TemporaryDirectory(prefix='tg-gps-audio-') as temporary:
        source=Path(temporary)/'cue.wav'
        with wave.open(str(source),'wb') as wav:
            wav.setparams((1,2,RATE,0,'NONE','not compressed'))
            wav.writeframes(struct.pack('<'+'h'*len(values),*values))
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(source),
                        '-c:a','libvorbis','-q:a','5',str(directory/(name+'.ogg'))],check=True)
    print(name+'.ogg: original generated cue, mono 44100 Hz')
