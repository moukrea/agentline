#!/usr/bin/env python3
"""Record docs/demo.gif: the real status line (claude/statusline.sh) in a
simulated Claude Code screen, walking through the configuration options.

Every frame is the renderer's actual output for a fixed sample session and a
pinned clock; only captions and crossfades are added. Ultracode animations run
at one frame per second, like in Claude Code.

    tools/record-demo.py --fonts DIR [--out docs/demo.gif]

DIR holds JuliaMono-{Regular,Bold,RegularItalic}.ttf and
SymbolsNerdFontMono-Regular.ttf. Needs Pillow, ffmpeg and Noto Color Emoji.
"""
import argparse, functools, json, os, re, shutil, subprocess, tempfile, unicodedata
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOW = 1790000000
EMOJI_FONT = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'
CAPTION_FONT = '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf'
CAPTION_BOLD = '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'
BG, FG, PAGE = (17, 19, 20), (217, 223, 211), (11, 13, 14)
CLAY, MUTED, BORDER = (215, 119, 87), (127, 135, 125), (48, 54, 52)
SIZE, MAXCOLS, ROWS = 15, 150, 9
STYLES = ['capsule', 'smooth', 'blocks', 'line', 'segments', 'braille', 'ramp', 'dots', 'bars', 'squares', 'pie', 'none']

ap = argparse.ArgumentParser()
ap.add_argument('--fonts', required=True)
ap.add_argument('--out', default=os.path.join(ROOT, 'docs', 'demo.gif'))
args = ap.parse_args()

F = {k: ImageFont.truetype(os.path.join(args.fonts, f), SIZE) for k, f in
     [('r', 'JuliaMono-Regular.ttf'), ('b', 'JuliaMono-Bold.ttf'), ('i', 'JuliaMono-RegularItalic.ttf'),
      ('nerd', 'SymbolsNerdFontMono-Regular.ttf')]}
EMOJI = ImageFont.truetype(EMOJI_FONT, 109)
CAP = ImageFont.truetype(CAPTION_FONT, 17)
CAPB = ImageFont.truetype(CAPTION_BOLD, 17)
CW = F['r'].getlength('M')
LH = round(SIZE * 1.42)
PAD, TOP = 22, 64
W = int(PAD * 2 + MAXCOLS * CW + 24)
H = TOP + ROWS * LH + 24 + PAD

# ── the real renderer ─────────────────────────────────────────────────────
BASE = json.load(open(os.path.join(ROOT, 'lib', 'sample.json')))
BASE.update(cwd='/home/you/projects/billing', session_id='agentline-demo')
BASE['workspace'] = {'current_dir': '/home/you/projects/billing', 'project_dir': '/home/you/projects/billing'}
BASE['prompt_cache']['expires_at'] = NOW + BASE['prompt_cache']['expires_at']
for r in BASE['rate_limits'].values():
    r['resets_at'] += NOW
TRANSCRIPT = os.path.join(tempfile.mkdtemp(), 'ultra.jsonl')
open(TRANSCRIPT, 'w').write('{"type":"attachment","attachment":{"type":"ultra_effort_enter"}}\n')

def scenario(name):
    p = json.loads(json.dumps(BASE))
    if name == 'limits':
        p['context_window']['current_usage'] = {'input_tokens': 880000}
        p['rate_limits'] = {'five_hour': {'used_percentage': 64, 'resets_at': NOW + 9000},
                            'seven_day': {'used_percentage': 81, 'resets_at': NOW + 200000}}
    elif name == 'expiring':
        p['prompt_cache']['expires_at'] = NOW + 230
    elif name == 'cold':
        p['prompt_cache'].update(warm=False, expires_at=0)
    elif name == 'ultra':
        p.update(session_id='agentline-demo-ultra', transcript_path=TRANSCRIPT)
        p['effort'] = {'level': 'xhigh'}
    elif name.startswith('effort:'):
        p['effort'] = {'level': name[7:]}
    return p

# The installer's defaults on a machine with a Nerd Font.
DEFAULT = dict(GLYPHS='nerd', BAR='capsule', COMPACT_STYLE='ramp', EFFORT_STYLE='auto', ULTRA_EFFECT='rainbow',
               BRANCH_ICON='auto', RESET_ICON='auto',
               SEGMENTS='dir git session meta model effort ctx 5h 7d cache cost lines')

@functools.lru_cache(maxsize=None)
def render(cols, scen, frame, opts):
    env = dict(os.environ, HOME='/home/you', COLUMNS=str(cols), AGENTLINE_CONFIG='/dev/null', AGENTLINE_NOW=str(NOW),
               AGENTLINE_FRAME=str(frame), AGENTLINE_DEMO_GIT='feat/billing-export 2 1 3 1 0 1',
               XDG_RUNTIME_DIR=tempfile.gettempdir())
    env.update({'AGENTLINE_' + k: v for k, v in opts})
    out = subprocess.run(['bash', os.path.join(ROOT, 'claude', 'statusline.sh')], input=json.dumps(scenario(scen)),
                         capture_output=True, text=True, env=env).stdout
    return tuple(out.rstrip('\n').split('\n'))

# ── ANSI → pixels ─────────────────────────────────────────────────────────
SGR = re.compile(r'\x1b\[([0-9;]*)m')

def parse(line):
    st = dict(fg=FG, bg=None, bold=False, italic=False, dim=False)
    cells, pos = [], 0
    for m in SGR.finditer(line + '\x1b[m'):
        for ch in line[pos:m.start()]:
            cells.append((ch, dict(st)))
        pos = m.end()
        codes = [int(c) for c in m.group(1).split(';') if c] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0: st.update(fg=FG, bg=None, bold=False, italic=False, dim=False)
            elif c == 1: st['bold'] = True
            elif c == 2: st['dim'] = True
            elif c == 3: st['italic'] = True
            elif c == 22: st.update(bold=False, dim=False)
            elif c == 39: st['fg'] = FG
            elif c in (38, 48) and i + 4 < len(codes) and codes[i + 1] == 2:
                st['fg' if c == 38 else 'bg'] = tuple(codes[i + 2:i + 5]); i += 4
            i += 1
    return cells

def wide(ch):
    return unicodedata.east_asian_width(ch) in 'WF'

@functools.lru_cache(maxsize=None)
def emoji(ch, h):
    im = Image.new('RGBA', (160, 160))
    ImageDraw.Draw(im).text((0, 0), ch, font=EMOJI, embedded_color=True)
    im = im.crop(im.getbbox() or (0, 0, 1, 1))
    s = h / im.height
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)

def mix(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))

EIGHTHS = '▏▎▍▌▋▊▉'
def block(d, ch, x, y, colour, bgc):
    """Block elements, drawn like xterm's WebGL renderer: exact cell fractions."""
    w, h = CW, LH
    if ch == '█': d.rectangle([x, y, x + w - 0.01, y + h - 0.01], fill=colour); return True
    if ch in EIGHTHS: d.rectangle([x, y, x + w * (EIGHTHS.index(ch) + 1) / 8 - 0.01, y + h - 0.01], fill=colour); return True
    if ch in '▁▂▃▄▅▆▇':
        f = ('▁▂▃▄▅▆▇'.index(ch) + 1) / 8
        d.rectangle([x, y + h * (1 - f), x + w - 0.01, y + h - 0.01], fill=colour); return True
    if ch == '\ue0b6':   # rounded caps: half-disks the full height of the cell
        d.pieslice([x, y, x + 2 * w, y + h - 0.01], 90, 270, fill=colour); return True
    if ch == '\ue0b4':
        d.pieslice([x - w, y, x + w, y + h - 0.01], 270, 90, fill=colour); return True
    if ch in '░▒▓':
        d.rectangle([x, y, x + w - 0.01, y + h - 0.01], fill=mix(bgc, colour, {'░': .25, '▒': .5, '▓': .75}[ch])); return True
    return False

def draw_line(img, d, x0, y, line):
    x = x0
    for ch, st in parse(line):
        fg, bgc = st['fg'], st['bg'] or BG
        if st['dim']: fg = mix(fg, bgc, 0.5)
        span = 2 if wide(ch) else 1
        if st['bg']: d.rectangle([x, y, x + CW * span - 0.01, y + LH - 0.01], fill=st['bg'])
        o = ord(ch)
        if ch == ' ': pass
        elif block(d, ch, x, y, fg, bgc): pass
        elif o >= 0x1F000 or ch in '⏳⌛⚡':
            e = emoji(ch, round(LH * 0.82)); img.paste(e, (round(x + (CW * 2 - e.width) / 2), round(y + (LH - e.height) / 2)), e)
        else:
            f = F['nerd'] if 0xE000 <= o <= 0xF8FF or o >= 0xF0000 else F['b' if st['bold'] else 'i' if st['italic'] else 'r']
            d.text((x + (CW * span) / 2, y + LH / 2), ch, font=f, fill=fg, anchor='mm')
        x += CW * span

def screen(cols=MAXCOLS, scen='session', frame=0, caption=('', '', ''), **opts):
    o = dict(DEFAULT); o.update(opts)
    l1, l2 = render(cols, scen, frame, tuple(sorted(o.items())))
    img = Image.new('RGB', (W, H), PAGE)
    d = ImageDraw.Draw(img)
    # Caption: what is being shown.
    # Settings show their exact config variable ("AGENTLINE_X = value");
    # anything else says what it is (a live state, the terminal width).
    label, value, note = (caption + ('',))[:3]
    x = PAD
    if label.startswith('AGENTLINE_'):
        key = ImageFont.truetype(os.path.join(args.fonts, 'JuliaMono-Regular.ttf'), 16)
        keyb = ImageFont.truetype(os.path.join(args.fonts, 'JuliaMono-Bold.ttf'), 16)
        d.text((x, 26), label + ' = ', font=key, fill=MUTED); x += key.getlength(label + ' = ')
        d.text((x, 26), value, font=keyb, fill=CLAY); x += keyb.getlength(value)
    else:
        d.text((x, 24), label, font=CAP, fill=MUTED); x += CAP.getlength(label + '  ')
        d.text((x, 24), value, font=CAPB, fill=CLAY); x += CAPB.getlength(value)
    if note: d.text((x + 14, 24), note, font=CAP, fill=MUTED)
    # Terminal window, as wide as the simulated terminal.
    tw = cols * CW + 24
    d.rounded_rectangle([PAD, TOP, PAD + tw, TOP + ROWS * LH + 24], radius=10, fill=BG, outline=BORDER)
    x0, y = PAD + 12, TOP + 12
    rule = '\x1b[38;2;70;76;72m' + '─' * cols
    for line in [f'\x1b[38;2;217;223;211m⏺\x1b[m Exported the billing report as CSV and updated its tests.', '',
                 rule, '\x1b[38;2;127;135;125m❯\x1b[m \x1b[48;2;217;223;211m \x1b[m', rule,
                 '  ' + l1, '  ' + l2, '  \x1b[38;2;175;135;255m⏵⏵ accept edits on\x1b[38;2;127;135;125m (shift+tab to cycle)\x1b[m']:
        draw_line(img, d, x0, y, line); y += LH
    return img

# ── timeline ──────────────────────────────────────────────────────────────
frames = []   # (image, milliseconds)
def hold(img, ms): frames.append((img, ms))
def fade(img, steps=4, ms=45):
    prev = frames[-1][0]
    for k in range(1, steps + 1):
        frames.append((Image.blend(prev, img, k / (steps + 1)), ms))
def show(img, ms): fade(img); hold(img, ms)

hold(screen(caption=('agentline', 'default settings')), 1800)
# Session state, not a setting: the effort level set in Claude Code.
for lvl in ['low', 'medium', 'high', 'xhigh', 'max']:
    show(screen(scen='effort:' + lvl, caption=('Live state · reasoning effort', lvl, 'set with /effort in Claude Code')), 650)
show(screen(caption=('agentline', 'default settings')), 500)
for s_ in STYLES:
    show(screen(BAR=s_, caption=('AGENTLINE_BAR', s_)), 600)
show(screen(caption=('AGENTLINE_BAR', 'capsule', 'default')), 500)
for s_ in STYLES:
    show(screen(EFFORT_STYLE=s_, caption=('AGENTLINE_EFFORT_STYLE', s_)), 520)
show(screen(caption=('AGENTLINE_EFFORT_STYLE', 'auto', 'default: same style as the bars')), 700)
# Not a setting: the terminal gets narrower and the layout adapts.
for c in range(MAXCOLS, 67, -2):
    hold(screen(cols=c, caption=('Terminal width', f'{c} columns', 'the layout adapts')), 45)
hold(screen(cols=68, caption=('Terminal width', '68 columns', 'the layout adapts')), 900)
for s_ in STYLES:
    show(screen(cols=68, COMPACT_STYLE=s_, caption=('AGENTLINE_COMPACT_STYLE', s_, 'gauges on narrow terminals')), 520)
show(screen(cols=68, caption=('AGENTLINE_COMPACT_STYLE', 'ramp', 'default')), 400)
for c in range(68, MAXCOLS + 1, 2):
    hold(screen(cols=c, caption=('Terminal width', f'{c} columns', 'the layout adapts')), 35)
hold(screen(caption=('Terminal width', f'{MAXCOLS} columns', 'the layout adapts')), 700)
show(screen(GLYPHS='unicode', caption=('AGENTLINE_GLYPHS', 'unicode', 'any font; capsule falls back to smooth')), 1400)
show(screen(caption=('AGENTLINE_GLYPHS', 'nerd', 'default with a Nerd Font')), 1000)
for b_ in ['octicon', 'powerline', 'devicon', 'unicode']:
    show(screen(BRANCH_ICON=b_, caption=('AGENTLINE_BRANCH_ICON', b_)), 560)
show(screen(caption=('AGENTLINE_BRANCH_ICON', 'auto', 'default: octicon with Nerd glyphs')), 500)
for r_ in ['octicon', 'mdi-history', 'mdi-progress-clock', 'mdi-refresh', 'unicode']:
    show(screen(RESET_ICON=r_, caption=('AGENTLINE_RESET_ICON', r_)), 560)
show(screen(caption=('AGENTLINE_RESET_ICON', 'auto', 'default: octicon with Nerd glyphs')), 500)
# Session states, animated at one frame per second like in Claude Code.
cap = ('Live state · usage', 'near the limits', 'red warning: the limit is reached before it resets, at this pace')
fade(screen(scen='limits', frame=0, caption=cap))
for f in range(4):
    hold(screen(scen='limits', frame=f, caption=cap), 1000)
cap = ('Live state · prompt cache', 'expiring soon')
fade(screen(scen='expiring', frame=0, caption=cap))
for f in range(3):
    hold(screen(scen='expiring', frame=f, caption=cap), 1000)
show(screen(scen='cold', caption=('Live state · prompt cache', 'cold', 'the next turn re-reads the context')), 1400)
for effect, n in [('rainbow', 6), ('violet', 6), ('plain', 1)]:
    cap = ('AGENTLINE_ULTRA_EFFECT', effect, 'in an ultracode session · 1 frame per second')
    fade(screen(scen='ultra', frame=0, ULTRA_EFFECT=effect, caption=cap))
    for f in range(n):
        hold(screen(scen='ultra', frame=f, ULTRA_EFFECT=effect, caption=cap), 1000 if n > 1 else 1300)
segs = DEFAULT['SEGMENTS'].split()
for gone in ['session', 'cost', 'lines', 'cache', 'meta']:
    segs.remove(gone)
    show(screen(SEGMENTS=' '.join(segs), caption=('AGENTLINE_SEGMENTS', '"' + ' '.join(segs) + '"')), 800)
show(screen(caption=('agentline configure', 'to pick yours, with a live preview')), 2600)

# ── encode ────────────────────────────────────────────────────────────────
tmp = tempfile.mkdtemp()
with open(os.path.join(tmp, 'list.txt'), 'w') as lst:
    for i, (im, ms) in enumerate(frames):
        name = os.path.join(tmp, f'{i:05d}.png'); im.save(name)
        lst.write(f"file '{name}'\nduration {ms / 1000:.3f}\n")
    lst.write(f"file '{name}'\n")
os.makedirs(os.path.dirname(args.out), exist_ok=True)
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', os.path.join(tmp, 'list.txt'),
                '-vf', 'split[a][b];[a]palettegen=stats_mode=diff:max_colors=256[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle',
                '-fps_mode', 'vfr', '-loop', '0', args.out], check=True)
shutil.rmtree(tmp)
total = sum(ms for _, ms in frames) / 1000
print(f'{args.out}: {len(frames)} frames, {total:.0f} s, {os.path.getsize(args.out) // 1024} KB, {W}x{H}')
