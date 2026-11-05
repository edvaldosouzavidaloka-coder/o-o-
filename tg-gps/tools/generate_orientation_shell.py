"""Draw a high-resolution instrument UI shell; values remain live Lua data.

The supplied reference defines proportions and visual style. No screenshot,
fake instrument readings or PDA imagery is baked into this asset.
"""
from pathlib import Path
from math import sin,cos,pi
from PIL import Image,ImageDraw,ImageFont
from generate_vehicle_icons import dds_with_mips

ROOT=Path(__file__).resolve().parents[1]
S=6
im=Image.new('RGBA',(440*S,330*S),(0,0,0,0));d=ImageDraw.Draw(im)
fonts={}
def text(value,x,y,size=9,color='#253447',bold=False,center=False):
    key=(size,bold)
    if key not in fonts:fonts[key]=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans'+('-Bold' if bold else '')+'.ttf',round(size*S))
    f=fonts[key]
    if center:x-=d.textlength(value,font=f)/S/2
    d.text((round(x*S),round(y*S)),value,font=f,fill=color)
def line(points,fill='#334664',width=1):d.line([(round(x*S),round(y*S)) for x,y in points],fill=fill,width=max(1,round(width*S)))
def rect(box,fill,outline=None,width=1):d.rectangle(tuple(round(v*S) for v in box),fill=fill,outline=outline,width=round(width*S))
def gradient(box,top,bottom):
    a=tuple(bytes.fromhex(top.lstrip('#')));b=tuple(bytes.fromhex(bottom.lstrip('#')))
    x1,y1,x2,y2=box
    for y in range(round(y1*S),round(y2*S)):
        t=(y-y1*S)/max(1,(y2-y1)*S)
        d.line((round(x1*S),y,round(x2*S),y),fill=tuple(round(a[i]*(1-t)+b[i]*t) for i in range(3))+(255,))
def button(box):
    gradient(box,'#e6ecf4','#a8b9d4')
    rect(box,None,'#627eac',.7)
    x,y,u,v=box;line([(x+1,v-1),(x+1,y+1),(u-1,y+1)],'#f3f8ff',.7)
def heading(value,x,y,w):
    gradient((x,y,x+w,y+10),'#3f4145','#20242a');text(value,x+w/2,y+.5,6,'#f2f5fb',center=True)
def circle(x,y,r=9):d.ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S),fill='#283f65',outline='#c4d7ef',width=S)
def arrow(x,y,right=True,color='#293c60'):
    q=1 if right else -1;d.polygon([(x-q*3)*S,y*S,(x+q*3)*S,(y-4)*S,(x+q*3)*S,(y+4)*S],fill=color)

# Exact reference-like proportions: 20% left column, 60% view, 20% controls.
gradient((0,0,440,29),'#2f7824','#074a15');line([(0,1),(439,1)],'#8cb475')
text('Orientação',7,6,12,'#e8f3f5',True)
for x in (374,417):circle(x,13,7);arrow(x,13,x==417,'#e5edf8')
gradient((0,29,89,293),'#d5e0ef','#aebfd9')
gradient((354,29,440,293),'#dce5f1','#aabbd6')
for x in (89,354):line([(x,29),(x,293)],'#465e8b',1)
for title,y in [('Área trabalhada',30),('Velocidade',76),('Próxima pista',121),('Consumo',202)]:
    heading(title,1,y,87)
heading('Posição',355,30,84);heading('Orientação',355,76,84)
text('Selecionar pista',360,90,8)
button((360,106,435,125));text('Selecionar',397,109,9,center=True)
text('Deslocamento',358,158,8,bold=True)
button((359,175,435,209));button((359,219,394,252));button((400,219,435,252))
line([(392,183),(392,202)],width=1.5);arrow(383,192,True);arrow(402,192,False)
line([(369,228),(369,243)],width=1.3);arrow(377,235,True)
line([(424,228),(424,243)],width=1.3);arrow(416,235,False)
text('Passo do ajuste',359,276,7)
button((7,172,82,194));text('Trocar',49,178,9,center=True)
line([(15,183),(28,177),(24,185)],width=.7)
text('ha',67,55,7);text('km/h',61,101,7);text('l/h',66,229,7)
gradient((90,29,353,69),'#303941','#171e29')
rect((90,69,354,84),'#ced9eb')
for x in range(91,354,9):line([(x,70),(x,83)],'#6e83a6',.4)
rect((90,84,354,112),'#7a9ad2')
for x,sign in [(296,'-'),(328,'+')]:
    d.ellipse(((x-6)*S,40*S,(x+6)*S,52*S),outline='#d5e2f7',width=S)
    line([(x+4,50),(x+10,56)],'#d5e2f7',1.8);line([(x-3,46),(x+3,46)],'#d5e2f7',1)
    if sign=='+':line([(x,43),(x,49)],'#d5e2f7',1)
rect((109,40,123,57),None,'#c2d4f3',.8);line([(112,53),(116,43),(120,53)],'#c2d4f3',.7)
for x,y in [(169,40),(179,50),(169,60),(159,50)]:d.polygon([(x*S,(y-3)*S),((x+3)*S,y*S),(x*S,(y+3)*S),((x-3)*S,y*S)],fill='#657589')
circle(334,103,11);line([(330,98),(335,103),(335,109)],'#e4edfa',1)
# Keep the central guidance window fully transparent.
rect((90,112,353,292),(0,0,0,0))
for x,y,kind in [(105,255,'menu'),(137,287,'list'),(333,255,'flag')]:
    circle(x,y,11)
    if kind=='list':
        for yy in (y-4,y,y+4):line([(x-5,yy),(x+5,yy)],'#e5eef9',1)
    elif kind=='flag':line([(x-3,y+6),(x-3,y-6),(x+5,y-3),(x-3,y)],'#e5eef9',1)
    else:
        rect((x-5,y-4,x+5,y+3),None,'#e5eef9',1);line([(x-6,y+5),(x+6,y+5)],'#e5eef9',1)
# Bottom toolbar: small monochrome controls, beveled like the instrument UI.
labels=['AJUSTES','TRABALHO','AUTOTRAC','ORIENTAÇÃO','A-B','ISO','FERRAM.','VOLUME','LIGAR','MENU']
for i,label in enumerate(labels):
    x=i*44;button((x,294,x+44,329));text(label,x+22,317,6,center=True)
    cx=x+22;cy=305
    if i==2:
        d.ellipse(((cx-7)*S,(cy-7)*S,(cx+7)*S,(cy+7)*S),outline='#164c2c',width=2*S);text('A',cx,298,9,'#164c2c',True,True)
    elif i in (3,4):
        d.ellipse(((cx-6)*S,(cy-6)*S,(cx+6)*S,(cy+6)*S),outline='#263f63',width=S)
        line([(cx,cy-9),(cx,cy+9)],'#263f63',.8)
        if i==3:d.polygon([(cx*S,(cy-4)*S),((cx-3)*S,(cy+4)*S),((cx+3)*S,(cy+4)*S)],fill='#263f63')
        if i==4:text('A-B',cx,301,5,center=True)
    elif i==5:text('ISO',cx,300,8,bold=True,center=True)
    elif i==8:
        d.arc(((cx-6)*S,(cy-6)*S,(cx+6)*S,(cy+6)*S),-45,225,fill='#253f5d',width=2*S);line([(cx,cy-9),(cx,cy-1)],width=1.5)
    elif i==9:
        for xx in (cx-5,cx+1):
            for yy in (cy-5,cy+1):rect((xx,yy,xx+4,yy+4),None,'#244361',.8)
    elif i==7:
        d.polygon([((cx-6)*S,(cy-3)*S),((cx-2)*S,(cy-3)*S),((cx+3)*S,(cy-7)*S),((cx+3)*S,(cy+7)*S),((cx-2)*S,(cy+3)*S),((cx-6)*S,(cy+3)*S)],fill='#2b4161')
        d.arc(((cx+2)*S,(cy-7)*S,(cx+11)*S,(cy+7)*S),-60,60,fill='#2b4161',width=S)
    elif i==0:
        for yy in (300,305,310):line([(cx-9,yy),(cx-6,yy+2),(cx-3,yy-2)],width=.8);line([(cx,yy),(cx+8,yy)],width=1.2)
    elif i==1:d.ellipse(((cx-4)*S,(cy-4)*S,(cx+4)*S,(cy+4)*S),fill='#4fbc64',outline='#216135',width=S)
    else:
        rect((cx-6,cy-3,cx+6,cy+4),None,'#283e5a',1);rect((cx-3,cy-8,cx+3,cy-3),None,'#283e5a',1)
        for xx in (cx-7,cx+5):rect((xx,cy+2,xx+3,cy+7),'#283e5a')
out=ROOT/'models/textures/orientationShell.dds'
image=im.resize((2048,2048),Image.Resampling.LANCZOS)
dds_with_mips(image,out)
image.save(ROOT/'validacao/orientation-shell.png')
print('Instrument shell: 2048 x 2048 with full BC3 mip chain; transparent live view')
