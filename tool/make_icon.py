"""Gera o logotipo da app (botão de play do YouTube + nota musical)."""
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersampling; reduzido no fim
OUT = 1024
RED_TOP, RED_BOT = (255, 64, 64), (204, 0, 0)
BG_TOP, BG_BOT = (44, 44, 52), (12, 12, 16)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgrad(size, top, bot):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        g.putpixel((0, y), lerp(top, bot, y / (size - 1)))
    return g.resize((size, size))


def emblem(scale, dx=0.0, dy=0.0):
    """Elemento central em RGBA (fundo transparente), ocupando `scale` do canvas."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = S // 2 + int(S * dx)
    cy = S // 2 + int(S * dy)
    w = int(S * scale)
    h = int(w * 0.70)
    box = (cx - w // 2, cy - h // 2 - int(S * 0.02), cx + w // 2, cy + h // 2 - int(S * 0.02))
    r = int(h * 0.30)

    # sombra
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        (box[0], box[1] + int(S * 0.025), box[2], box[3] + int(S * 0.025)), r, fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(S * 0.02))
    img.alpha_composite(sh)

    # botão vermelho com gradiente
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, r, fill=255)
    grad = vgrad(S, RED_TOP, RED_BOT).convert("RGBA")
    grad.putalpha(mask)
    img.alpha_composite(grad)

    d = ImageDraw.Draw(img)
    # triângulo de play
    tw = int(h * 0.50)
    th = int(tw * 1.12)
    px = cx - int(tw * 0.34)
    py = (box[1] + box[3]) // 2
    d.polygon([(px, py - th // 2), (px, py + th // 2), (px + tw, py)], fill=(255, 255, 255, 255))

    # selo com nota musical (canto inferior direito)
    br = int(h * 0.30)
    bx = box[2] - int(br * 0.30)
    by = box[3] - int(br * 0.05)
    ring = br + int(S * 0.012)
    d.ellipse((bx - ring, by - ring, bx + ring, by + ring), fill=(18, 18, 22, 255))
    d.ellipse((bx - br, by - br, bx + br, by + br), fill=(255, 255, 255, 255))

    # nota musical (colcheia) em vermelho
    u = br / 100.0
    note = (204, 0, 0, 255)
    hr = 24 * u  # cabeça da nota
    hx, hy = bx - 22 * u, by + 34 * u
    d.ellipse((hx - hr * 1.15, hy - hr * 0.85, hx + hr * 1.15, hy + hr * 0.85), fill=note)
    stem_w = 11 * u
    sx = hx + hr * 1.15 - stem_w
    d.rectangle((sx, by - 50 * u, sx + stem_w, hy), fill=note)
    d.polygon([(sx + stem_w, by - 50 * u), (sx + stem_w + 38 * u, by - 28 * u),
               (sx + stem_w + 38 * u, by - 6 * u), (sx + stem_w, by - 28 * u)], fill=note)
    return img


def save(img, path, size=OUT):
    img.resize((size, size), Image.LANCZOS).save(path)


# Ícone completo (opaco; iOS/macOS/web arredondam sozinhos ou usamos como está)
bg = vgrad(S, BG_TOP, BG_BOT).convert("RGBA")
bg.alpha_composite(emblem(0.66, -0.035, -0.03))
save(bg.convert("RGB"), "assets/icon/icon.png")

# Primeiro plano do ícone adaptativo do Android (zona segura ~66%)
save(emblem(0.52, -0.03, -0.025), "assets/icon/icon_foreground.png")

# Logo transparente para usar dentro da app
logo = emblem(0.86, -0.04, -0.03)
save(logo, "assets/icon/logo.png", 512)
print("ok")
