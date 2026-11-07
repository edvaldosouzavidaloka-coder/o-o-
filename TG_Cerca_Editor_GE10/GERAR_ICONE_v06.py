"""Cria ícone TG + EDVALDO para o executável Windows (Pillow)."""
from PIL import Image, ImageDraw, ImageFont

image=Image.new('RGBA',(256,256),'#0a2618')
draw=ImageDraw.Draw(image)
draw.rounded_rectangle((6,6,250,250),radius=48,outline='#58de81',width=9)
try:
    font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',112)
    small=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',21)
except OSError:
    font=ImageFont.load_default()
    small=font

def middle(text,font,y,fill):
    box=draw.textbbox((0,0),text,font=font)
    x=(256-(box[2]-box[0]))/2
    draw.text((x,y),text,font=font,fill=fill)

middle('TG',font,41,'#d9ffd8')
middle('EDVALDO',small,181,'#ecca6a')
image.save('tg_edvaldo.ico',format='ICO',sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
print('Ícone do programa criado')
