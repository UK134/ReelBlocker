"""Draws the Reel Blocker app icon (1024x1024 PNG).

Usage: python3 scripts/make_icon.py OUTPUT.png
Design: pink-to-red gradient, a white vertical "reel" card with a play
triangle, struck through by a bold diagonal slash.
"""
import sys
from PIL import Image, ImageDraw

SIZE = 1024
SS = 4                      # supersampling for smooth edges
S = SIZE * SS

TOP_LEFT = (255, 64, 129)   # pink
BOTTOM_RIGHT = (255, 59, 48)  # red


def gradient():
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(0, S, SS):
        for x in range(0, S, SS):
            t = (x + y) / (2 * S)
            c = tuple(int(a + (b - a) * t) for a, b in zip(TOP_LEFT, BOTTOM_RIGHT))
            for dy in range(SS):
                for dx in range(SS):
                    px[x + dx, y + dy] = c
    return img


def round_line(draw, a, b, width, fill):
    draw.line([a, b], fill=fill, width=width)
    for p in (a, b):
        draw.ellipse([p[0] - width // 2, p[1] - width // 2, p[0] + width // 2, p[1] + width // 2], fill=fill)


def main(out):
    img = gradient()

    # Card + play triangle are drawn on their own layer (as a mask) so the slash
    # can cut a clean transparent gap through them.
    mask = Image.new("L", (S, S), 0)
    m = ImageDraw.Draw(mask)
    cw, ch = int(S * 0.36), int(S * 0.58)
    cx, cy = S // 2, S // 2
    card = [cx - cw // 2, cy - ch // 2, cx + cw // 2, cy + ch // 2]
    m.rounded_rectangle(card, radius=int(S * 0.06), outline=255, width=int(S * 0.035))
    r = int(S * 0.11)
    m.polygon([(cx - r * 0.75, cy - r), (cx - r * 0.75, cy + r), (cx + r * 1.05, cy)], fill=255)

    a = (int(S * 0.22), int(S * 0.22))
    b = (int(S * 0.78), int(S * 0.78))
    round_line(m, a, b, int(S * 0.085), 0)      # cut the gap
    round_line(m, a, b, int(S * 0.042), 255)    # the slash itself

    img.paste((255, 255, 255), (0, 0), mask)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(out, "PNG")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "icon.png")
