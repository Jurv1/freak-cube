"""Сборка: python build.py [номера...] [--preview-only]
Пишет ../models/*.glb, ../models_obj/*, ../preview/*.png и общий лист ../preview.png"""
import io
import os
import sys

from PIL import Image, ImageDraw

from kit import font, render, write_glb, write_obj
from monsters import ALL

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    preview_only = '--preview-only' in sys.argv
    back = '--back' in sys.argv
    picks = [int(a) for a in args] or list(range(1, len(ALL) + 1))
    for d in ('models', 'models_obj', 'preview'):
        os.makedirs(os.path.join(ROOT, d), exist_ok=True)
    for num in picks:
        m = ALL[num - 1]()
        P, N, UV, C, I = m.bake()
        atlas, _, _ = m.atlas()
        buf = io.BytesIO()
        atlas.save(buf, 'PNG', optimize=True)
        if not preview_only:
            write_glb(os.path.join(ROOT, 'models', m.key + '.glb'), m.key, P, N, UV, I, buf.getvalue())
            write_obj(os.path.join(ROOT, 'models_obj'), m.key, P, N, UV, I, atlas)
        render(P, N, C, I, size=560, yaw=-28, pitch=10).save(os.path.join(ROOT, 'preview', f'{num:02d}_{m.key}.png'))
        if back:
            render(P, N, C, I, size=560, yaw=140, pitch=14).save(os.path.join(ROOT, 'preview', f'{num:02d}_{m.key}_back.png'))
        size = P.max(0) - P.min(0)
        print(f'{num:2d} {m.title:<24} tris={len(I):5d} verts={len(P):5d} size={size[0]:.1f}x{size[1]:.1f}x{size[2]:.1f}')
    sheet()


def sheet():
    cell, pad, cap = 420, 16, 74
    cols = 5
    rows = (len(ALL) + cols - 1) // cols
    W = cols * cell + (cols + 1) * pad
    H = rows * (cell + cap) + (rows + 1) * pad + 90
    img = Image.new('RGB', (W, H), (255, 246, 232))
    d = ImageDraw.Draw(img)
    d.text((W / 2, 50), 'Пекарня монстриков — 15 моделей', font=font(46), fill=(120, 62, 40), anchor='mm')
    for i, fn in enumerate(ALL):
        m = fn()
        path = os.path.join(ROOT, 'preview', f'{i + 1:02d}_{m.key}.png')
        if not os.path.exists(path):
            continue
        x = pad + (i % cols) * (cell + pad)
        y = 90 + pad + (i // cols) * (cell + cap + pad)
        tile = Image.open(path).resize((cell, cell), Image.LANCZOS)
        mask = Image.new('L', (cell, cell), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, cell - 1, cell - 1], 28, fill=255)
        img.paste(tile, (x, y), mask)
        d.text((x + cell / 2, y + cell + 22), f'{i + 1}. {m.title}', font=font(25), fill=(92, 46, 30), anchor='mm')
        d.text((x + cell / 2, y + cell + 53), f'{m.recipe}  ·  {m.key}', font=font(18, False), fill=(150, 104, 84), anchor='mm')
    img.save(os.path.join(ROOT, 'preview.png'))


if __name__ == '__main__':
    main()
