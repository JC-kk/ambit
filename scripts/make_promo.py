#!/usr/bin/env python3
"""Generates the Xiaohongshu carousel into promo/. 1080x1440 is the platform's 3:4 slot.

Same visual language as the app: graphite ground, clay for Claude, blue for Codex, monospace for
things a machine wrote. Two rules learned the hard way here:

* JetBrains Mono has no CJK glyphs, so anything that might contain Chinese must be set in the CJK
  face. Mono is reserved for pure-ASCII identifiers, numbers and quoted output.
* Wrapping has to be per-character for CJK but must not split a run of Latin letters, or a word
  like `subagent` ends up broken across two lines.
"""
import os
import re

from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1440
MARGIN = 84
BODY = W - 2 * MARGIN

CLAY = (217, 120, 87)
BLUE = (92, 148, 250)
AMBER = (230, 158, 61)
INK = (242, 241, 239)
DIM = (158, 159, 165)
FAINT = (112, 113, 119)
RULE = (255, 255, 255, 28)

CJK_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
MONO_FONT = os.path.expanduser("~/Library/Fonts/JetBrainsMonoNLNerdFont-Medium.ttf")
MONO_BOLD_FONT = os.path.expanduser("~/Library/Fonts/JetBrainsMonoNLNerdFont-Bold.ttf")


def sans(size, bold=True):
    return ImageFont.truetype(CJK_FONT, size, index=2 if bold else 0)


def mono(size, bold=False):
    return ImageFont.truetype(MONO_BOLD_FONT if bold else MONO_FONT, size)


def ground():
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        top, mid, bottom = (40, 42, 48), (26, 27, 31), (16, 17, 20)
        if t < 0.4:
            k = t / 0.4
            c = tuple(round(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.4) / 0.6
            c = tuple(round(mid[i] + (bottom[i] - mid[i]) * k) for i in range(3))
        grad.putpixel((0, y), c)
    return grad.resize((W, H), Image.BILINEAR).convert("RGBA")


TOKEN = re.compile(r"[A-Za-z0-9@._/\-]+|.", re.S)


def wrap(draw, text, font, max_width):
    """Character wrapping that keeps Latin/identifier runs intact."""
    lines = []
    for para in text.split("\n"):
        line = ""
        for tok in TOKEN.findall(para):
            trial = line + tok
            if draw.textlength(trial, font=font) > max_width and line:
                lines.append(line.rstrip())
                line = tok.lstrip() if tok == " " else tok
            else:
                line = trial
        lines.append(line.rstrip())
    return lines


# ------------------------------------------------------------------ blocks
# Each block measures itself, so a slide can be centred vertically instead of
# hanging off the top of the frame.

class Text:
    def __init__(self, text, font, fill, leading=1.5, gap=34, indent=0):
        self.text, self.font, self.fill = text, font, fill
        self.leading, self.gap, self.indent = leading, gap, indent

    def height(self, d):
        n = len(wrap(d, self.text, self.font, BODY - self.indent))
        return int(n * self.font.size * self.leading) + self.gap

    def draw(self, d, img, y):
        for line in wrap(d, self.text, self.font, BODY - self.indent):
            d.text((MARGIN + self.indent, y), line, font=self.font, fill=self.fill)
            y += int(self.font.size * self.leading)
        return y + self.gap


class Space:
    def __init__(self, h): self.h = h
    def height(self, d): return self.h
    def draw(self, d, img, y): return y + self.h


class Rule:
    def __init__(self, gap=44): self.gap = gap
    def height(self, d): return self.gap * 2
    def draw(self, d, img, y):
        y += self.gap
        d.rectangle((MARGIN, y, W - MARGIN, y + 1), fill=RULE)
        return y + self.gap


class Bullet:
    def __init__(self, text, colour=CLAY, font=None, gap=26):
        self.text, self.colour, self.gap = text, colour, gap
        self.font = font or sans(36, bold=False)

    def height(self, d):
        n = len(wrap(d, self.text, self.font, BODY - 48))
        return int(n * self.font.size * 1.5) + self.gap

    def draw(self, d, img, y):
        d.ellipse((MARGIN + 3, y + 15, MARGIN + 18, y + 30), fill=self.colour)
        for line in wrap(d, self.text, self.font, BODY - 48):
            d.text((MARGIN + 48, y), line, font=self.font, fill=INK)
            y += int(self.font.size * 1.5)
        return y + self.gap


class Finding:
    """A mono identifier line over a Chinese explanation, with an amber tick in the margin."""
    def __init__(self, code, body, gap=46):
        self.code, self.body, self.gap = code, body, gap
        self.code_font, self.body_font = mono(30, bold=True), sans(33, bold=False)

    def height(self, d):
        a = len(wrap(d, self.code, self.code_font, BODY - 36))
        b = len(wrap(d, self.body, self.body_font, BODY - 36))
        return int(a * self.code_font.size * 1.45) + 10 + int(b * self.body_font.size * 1.5) + self.gap

    def draw(self, d, img, y):
        top = y
        for line in wrap(d, self.code, self.code_font, BODY - 36):
            d.text((MARGIN + 36, y), line, font=self.code_font, fill=INK)
            y += int(self.code_font.size * 1.45)
        y += 10
        for line in wrap(d, self.body, self.body_font, BODY - 36):
            d.text((MARGIN + 36, y), line, font=self.body_font, fill=DIM)
            y += int(self.body_font.size * 1.5)
        d.rectangle((MARGIN, top + 6, MARGIN + 5, y - 8), fill=AMBER)
        return y + self.gap


class Quote:
    def __init__(self, label, quote, gap=54):
        self.label, self.quote, self.gap = label, quote, gap
        self.lf, self.qf = sans(29, bold=False), mono(30)

    def height(self, d):
        n = len(wrap(d, self.quote, self.qf, BODY - 84))
        return 52 + int(n * self.qf.size * 1.5) + 46 + self.gap

    def draw(self, d, img, y):
        n = len(wrap(d, self.quote, self.qf, BODY - 84))
        box_h = 52 + int(n * self.qf.size * 1.5) + 34
        d.rounded_rectangle((MARGIN, y, W - MARGIN, y + box_h), radius=20,
                            fill=(255, 255, 255, 13), outline=RULE, width=2)
        d.text((MARGIN + 40, y + 26), self.label, font=self.lf, fill=FAINT)
        yy = y + 74
        for line in wrap(d, self.quote, self.qf, BODY - 84):
            d.text((MARGIN + 40, yy), line, font=self.qf, fill=AMBER)
            yy += int(self.qf.size * 1.5)
        return y + box_h + self.gap


class SwitchRow:
    def __init__(self, label, colour, on, gap=34):
        self.label, self.colour, self.on, self.gap = label, colour, on, gap

    def height(self, d): return 62 + self.gap

    def draw(self, d, img, y):
        d.text((MARGIN, y + 12), self.label, font=mono(38, bold=True), fill=self.colour)
        x, w, h, inset = MARGIN + 300, 110, 58, 10
        knob = h - inset * 2
        d.rounded_rectangle((x, y, x + w, y + h), radius=h // 2,
                            fill=self.colour + (64,) if self.on else (255, 255, 255, 16))
        d.rounded_rectangle((x, y, x + w, y + h), radius=h // 2,
                            outline=self.colour + (150,) if self.on else (255, 255, 255, 52), width=3)
        cx = x + w - inset - knob // 2 if self.on else x + inset + knob // 2
        d.ellipse((cx - knob // 2, y + inset, cx + knob // 2, y + inset + knob),
                  fill=self.colour + (255,) if self.on else (152, 153, 159, 255))
        d.text((x + w + 34, y + 14), "ON" if self.on else "OFF",
               font=mono(34, bold=True), fill=self.colour if self.on else FAINT)
        return y + h + self.gap


class Shot:
    """A zoomed crop of the real app, so the rows are actually readable at phone size."""
    def __init__(self, path, crop_frac, gap=56):
        self.path, self.crop_frac, self.gap = path, crop_frac, gap

    def _image(self):
        im = Image.open(self.path).convert("RGBA")
        l, t, r, b = self.crop_frac
        im = im.crop((int(im.width * l), int(im.height * t), int(im.width * r), int(im.height * b)))
        return im.resize((BODY, round(im.height * BODY / im.width)), Image.LANCZOS)

    def height(self, d): return self._image().height + self.gap

    def draw(self, d, img, y):
        shot = self._image()
        mask = Image.new("L", shot.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width, shot.height), radius=20, fill=255)
        img.paste(shot, (MARGIN, y), mask)
        d.rounded_rectangle((MARGIN, y, MARGIN + shot.width, y + shot.height),
                            radius=20, outline=RULE, width=2)
        return y + shot.height + self.gap


class Brand:
    def __init__(self, gap=64):
        self.gap = gap

    def height(self, d): return 188 + self.gap

    def draw(self, d, img, y):
        icon = Image.open("Resources/AppIcon-preview.png").convert("RGBA").resize((188, 188), Image.LANCZOS)
        img.paste(icon, (MARGIN, y), icon)
        d.text((MARGIN + 226, y + 30), "Ambit", font=sans(86), fill=INK)
        d.text((MARGIN + 230, y + 140), "macOS menu bar", font=mono(28), fill=FAINT)
        return y + 188 + self.gap


class LinkBox:
    def __init__(self, gap=46):
        self.gap = gap

    def height(self, d): return 200 + self.gap

    def draw(self, d, img, y):
        plate = Image.new("RGBA", (W - 2 * MARGIN, 200), (0, 0, 0, 0))
        pd = ImageDraw.Draw(plate)
        pd.rounded_rectangle((0, 0, plate.width - 1, plate.height - 1), radius=22,
                             fill=(14, 15, 18, 235), outline=CLAY + (170,), width=3)
        img.paste(plate, (MARGIN, y), plate)
        d.text((MARGIN + 44, y + 42), "项目地址", font=sans(28, bold=False), fill=FAINT)
        d.text((MARGIN + 44, y + 98), "github.com/JC-kk/ambit", font=mono(43, bold=True), fill=CLAY)
        return y + 200 + self.gap


def render(blocks, eyebrow=None, align="center"):
    img = ground()
    d = ImageDraw.Draw(img, "RGBA")

    total = sum(b.height(d) for b in blocks)
    eyebrow_h = 66 if eyebrow else 0
    if align == "center":
        y = max(150, (H - total - eyebrow_h) // 2)
    else:
        y = 170
    if eyebrow:
        d.text((MARGIN, y), eyebrow, font=sans(28, bold=False), fill=FAINT)
        y += eyebrow_h
    for b in blocks:
        y = b.draw(d, img, y)

    d.text((MARGIN, H - 76), "Ambit", font=mono(24), fill=(88, 89, 95))
    return img


# ------------------------------------------------------------------ slides

def slides():
    return [
        ("01-hook", render([
            Text("47 个 skill,18 个 subagent。", sans(52), INK, gap=22),
            Text("然后我算了一下它们的租金。", sans(52), INK, gap=76),
            Text("≈ 4,800", mono(150, bold=True), CLAY, leading=1.1, gap=6),
            Text("tokens", mono(48), DIM, gap=64),
            Text("每一轮对话都要付。\n在你打出第一个字之前。", sans(42, bold=False), DIM, gap=0),
        ])),

        ("02-why", render([
            Text("每个 skill 的名字和描述都常驻在 system prompt 里,\n好让模型知道它「可以」用什么。",
                 sans(40), INK, gap=52),
            Quote("Claude Code 自己的说法:",
                  "loaded but never invoked. Each one adds to the system prompt every turn."),
            Text("而那天下午,我其实只会用到二十个。", sans(40, bold=False), DIM, gap=44),
            Text("唯一的开关却是「卸载」。\n我不想为了让它闭嘴而丢掉它。", sans(44), INK, gap=0),
        ], eyebrow="为什么会这样")),

        ("03-idea", render([
            Text("全部留在一个地方,\n只切换每个 agent「看得见」什么。", sans(50), INK, gap=76),
            SwitchRow("Claude", CLAY, True),
            SwitchRow("Codex", BLUE, False, gap=20),
            Rule(),
            Text("关掉 = 那个 agent 不再发现它。\n不是卸载 —— 源文件一个字节都不动。",
                 sans(40, bold=False), DIM, gap=0),
        ], eyebrow="于是")),

        ("04-panel", render([
            Text("一行一个 capability,两列开关。", sans(44), INK, gap=44),
            Shot("docs/panel.png", (0.225, 0.07, 0.99, 0.44)),
            Text("颜色只代表归属:陶土是 Claude,蓝是 Codex。\n只有真的在加载时才上色。",
                 sans(37, bold=False), DIM, gap=0),
        ], eyebrow="一屏看完谁能加载什么")),

        ("05-findings", render([
            Text("两个 agent 几乎没有一处是一致的。", sans(46), INK, gap=56),
            Finding("~/.agents/skills",
                    "Codex 除了自己的目录,还会扫这里。放在这儿的东西对它无条件可见,关不掉。"),
            Finding("if (entry.isSymbolicLink()) continue",
                    "Claude 扫 subagent 时跳过 symlink,所以只能用 hard link —— 它对任何读取者都是普通文件。"),
            Finding("[agents.<name>] + role.toml",
                    "Codex 的 subagent 是 TOML,和 Claude 的 .md frontmatter 不兼容,得转换。", gap=52),
            Text("这些哪儿都没写,是读二进制加探测 CLI 一条条钉下来的",
                 sans(34, bold=False), FAINT, gap=0),
        ], eyebrow="写它的过程中挖出来的")),

        ("06-safety", render([
            Text("它碰的是你丢不起的文件,\n所以规矩写得很窄。", sans(48), INK, gap=64),
            Bullet("关掉,永不删除源文件"),
            Bullet("删一个链接前,要先证明是自己建的"),
            Bullet("改配置:备份 → 解析 → 最小改动 → 校验 → 原子写入"),
            Bullet("JSON 按文本改一个键,键序、缩进、浮点写法逐字节保留"),
            Bullet("库里的源被别的程序删了,它会告诉你,而不是悄悄消失", gap=44),
            Rule(),
            Text("52 tests 全部跑在临时目录,从不碰你真实的配置。",
                 sans(34, bold=False), DIM, gap=0),
        ], eyebrow="安全边界")),

        ("07-link", render([
            Brand(),
            Text("纯 Swift,零依赖,不联网。\n完全从个人需求出发做的。", sans(44, bold=False), INK, gap=38),
            Text("如果你也有同样的问题,\n欢迎来把这个设计做得更好。", sans(44, bold=False), DIM, gap=66),
            LinkBox(),
            Text("MIT · Releases 里有编译好的 .dmg", sans(31, bold=False), FAINT, gap=0),
        ])),
    ]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    out = os.path.join(root, "promo")
    os.makedirs(out, exist_ok=True)
    for name, img in slides():
        path = os.path.join(out, f"{name}.png")
        img.convert("RGB").save(path, quality=95)
        print("wrote", os.path.relpath(path, root))


if __name__ == "__main__":
    main()
