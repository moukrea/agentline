#!/usr/bin/env python3
"""Record docs/demo.gif: the real status line (claude/statusline.sh) in a
simulated Claude Code screen, walking through the configuration options.

Every frame is the renderer's actual output for a fixed sample session and a
pinned clock; only captions and crossfades are added. Ultracode animations run
at one frame per second, like in Claude Code.

    tools/record-demo.py [--fonts DIR] [--emoji-font FILE] [--caption-font FILE]
                         [--caption-bold-font FILE] [--out docs/demo.gif]

DIR (default ~/.local/share/fonts) holds JuliaMono-{Regular,Bold,RegularItalic}.ttf
and SymbolsNerdFontMono-Regular.ttf. Needs Pillow, ffmpeg, jq, Noto Sans for the
captions and the bitmap (CBDT) build of Noto Color Emoji: FreeType cannot draw
the COLRv1 build some distributions ship (Fedora's Noto-COLRv1.ttf). Fonts not
given are looked up in DIR, the usual system paths and fontconfig.

automodel is never called: the routed scene passes its answers in
AGENTLINE_AUTOMODEL_JSON.
"""
import argparse, functools, json, os, re, shutil, subprocess, sys, tempfile, unicodedata
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOW = 1790000000
PAGE, CLAY, MUTED = (11, 13, 14), (215, 119, 87), (127, 135, 125)
# The simulated terminal: dark by default, light for AGENTLINE_THEME=light.
TERM = {'dark': dict(bg=(17, 19, 20), fg=(217, 223, 211), muted=(127, 135, 125), border=(48, 54, 52),
                     rule=(70, 76, 72), accent=(175, 135, 255), cursor=(217, 223, 211)),
        'light': dict(bg=(250, 250, 246), fg=(40, 40, 50), muted=(110, 110, 125), border=(205, 207, 200),
                      rule=(200, 202, 206), accent=(120, 80, 210), cursor=(40, 40, 50))}
# 122 columns at 10.5 px: the full layout still fits (with the sample's
# smaller counters below), and the GIF stays under 800 px, narrower than
# GitHub's README column (~830 px), so it is shown 1:1, never scaled down.
SIZE, MAXCOLS, ROWS = 10.5, 122, 9
STYLES = ['capsule', 'smooth', 'blocks', 'line', 'segments', 'braille', 'ramp', 'dots', 'bars', 'squares', 'pie', 'none']

ap = argparse.ArgumentParser()
ap.add_argument('--fonts', default=os.path.expanduser('~/.local/share/fonts'))
ap.add_argument('--emoji-font', help='Noto Color Emoji, bitmap (CBDT) build')
ap.add_argument('--caption-font', help='Noto Sans Regular, or the variable Noto Sans')
ap.add_argument('--caption-bold-font', help='Noto Sans Bold (default: the caption font, Bold instance)')
ap.add_argument('--out', default=os.path.join(ROOT, 'docs', 'demo.gif'))
args = ap.parse_args()

def fc_files(pattern):
    """The font files fontconfig lists for a pattern."""
    try:
        out = subprocess.run(['fc-list', '-f', '%{file}\n', pattern], capture_output=True, text=True).stdout
    except OSError:
        return []
    return sorted(set(out.split()))

def find_font(what, given, names, ok=lambda path: True, hint=''):
    dirs = [args.fonts, '/usr/share/fonts/truetype/noto', '/usr/share/fonts/noto', '/usr/share/fonts/google-noto',
            '/usr/share/fonts/google-noto-vf', '/usr/share/fonts/google-noto-color-emoji-fonts',
            '/usr/local/share/fonts', os.path.expanduser('~/Library/Fonts'), '/Library/Fonts']
    tried = [given] if given else [os.path.join(d, n) for n, _ in names for d in dirs]
    if not given:
        tried += [f for _, family in names if family for f in fc_files(family)]
    for path in tried:
        if os.path.isfile(path) and ok(path):
            return path
    sys.exit(f'record-demo: no usable {what}; tried: {", ".join(tried)}{hint}')

def draws_emoji(path):
    try:
        im = Image.new('RGBA', (160, 160))
        ImageDraw.Draw(im).text((0, 0), '🔥', font=ImageFont.truetype(path, 109), embedded_color=True)
        return im.getbbox() is not None
    except OSError:
        return False

def caption_font(path, bold):
    f = ImageFont.truetype(path, 17)
    if bold and 'bold' not in os.path.basename(path).lower():
        try: f.set_variation_by_name('Bold')    # variable Noto Sans
        except (OSError, ValueError): pass
    return f

F = {k: ImageFont.truetype(os.path.join(args.fonts, f), SIZE) for k, f in
     [('r', 'JuliaMono-Regular.ttf'), ('b', 'JuliaMono-Bold.ttf'), ('i', 'JuliaMono-RegularItalic.ttf'),
      ('nerd', 'SymbolsNerdFontMono-Regular.ttf')]}
EMOJI = ImageFont.truetype(find_font('Noto Color Emoji (bitmap build)', args.emoji_font,
                                     [('NotoColorEmoji.ttf', 'Noto Color Emoji')], draws_emoji,
                                     '. Get the bitmap build, e.g. https://github.com/googlefonts/noto-emoji/'
                                     'raw/v2.047/fonts/NotoColorEmoji.ttf, and pass --emoji-font'), 109)
CAPTION_FONT = find_font('Noto Sans', args.caption_font,
                         [('NotoSans-Regular.ttf', 'Noto Sans:style=Regular'), ('NotoSans[wght].ttf', None)])
CAPTION_BOLD = os.path.join(os.path.dirname(CAPTION_FONT), 'NotoSans-Bold.ttf')
CAPTION_BOLD = args.caption_bold_font or (CAPTION_BOLD if os.path.isfile(CAPTION_BOLD) else CAPTION_FONT)
CAP, CAPB = caption_font(CAPTION_FONT, False), caption_font(CAPTION_BOLD, True)
CW = F['r'].getlength('M')
LH = round(SIZE * 1.42)
PAD, TOP = 4, 64
W = int(PAD * 2 + MAXCOLS * CW + 16) + 1
H = TOP + ROWS * LH + 24 + PAD

# ── the real renderer ─────────────────────────────────────────────────────
BASE = json.load(open(os.path.join(ROOT, 'lib', 'sample.json')))
BASE.update(cwd='/home/you/src/billing', session_id='agentline-demo', session_name='Billing refactor')
BASE['workspace'] = {'current_dir': '/home/you/src/billing', 'project_dir': '/home/you/src/billing'}
BASE['cost'].update(total_cost_usd=4.1, total_duration_ms=2520000, total_lines_added=63, total_lines_removed=4)
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
    elif name == 'tomorrow':   # the 5-hour window resets tomorrow morning
        p['rate_limits']['five_hour']['resets_at'] = NOW + 83940
    elif name == 'jev':   # a session on automodel's custom model: Claude Code only knows "Jev (auto)"
        p.update(session_id='agentline-demo-jev', model={'id': 'jev', 'display_name': 'Jev (auto)'})
        p['effort'] = {'level': 'medium'}
    return p

def routed(model, label, effort, confidence, state='routed', mode='', flash='', pin='', issue='', claude_effort=''):
    """automodel's `statusline --json` answer for the jev session."""
    return json.dumps(dict(v=1, routed=True, alias='jev', model=model, label=label, effort=effort, mode=mode,
                           state=state, confidence=confidence, pin=pin, issue=issue, flash=flash, budget='',
                           claude_effort=claude_effort, text=''))

# The installer's defaults on a machine with a Nerd Font.
DEFAULT = dict(GLYPHS='nerd', BAR='capsule', COMPACT_STYLE='pie', EFFORT_STYLE='dots', ULTRA_EFFECT='violet',
               BRANCH_ICON='auto', RESET_ICON='auto', THEME='dark', LAYOUT='two', AUTOMODEL='off',
               SEGMENTS='dir git session meta model effort route ctx 5h 7d cache cost lines')

@functools.lru_cache(maxsize=None)
def render(cols, scen, frame, opts):
    env = {k: v for k, v in os.environ.items()   # nothing from this machine's Claude Code or agentline
           if not k.startswith(('AGENTLINE_', 'CLAUDE_', 'AUTOMODEL_'))}
    env.update(HOME='/home/you', TZ='UTC', COLUMNS=str(cols), AGENTLINE_CONFIG='/dev/null', AGENTLINE_NOW=str(NOW),
               AGENTLINE_FRAME=str(frame), AGENTLINE_DEMO_GIT='feat/export 2 1 3 1 0 1',
               XDG_RUNTIME_DIR=tempfile.gettempdir())
    env.update({'AGENTLINE_' + k: v for k, v in opts})
    out = subprocess.run(['bash', os.path.join(ROOT, 'claude', 'statusline.sh')], input=json.dumps(scenario(scen)),
                         capture_output=True, text=True, env=env).stdout
    return tuple(out.rstrip('\n').split('\n'))

# ── ANSI → pixels ─────────────────────────────────────────────────────────
SGR = re.compile(r'\x1b\[([0-9;]*)m')

def parse(line, fg0):
    st = dict(fg=fg0, bg=None, bold=False, italic=False, dim=False, strike=False)
    cells, pos = [], 0
    for m in SGR.finditer(line + '\x1b[m'):
        for ch in line[pos:m.start()]:
            cells.append((ch, dict(st)))
        pos = m.end()
        codes = [int(c) for c in m.group(1).split(';') if c] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0: st.update(fg=fg0, bg=None, bold=False, italic=False, dim=False, strike=False)
            elif c == 1: st['bold'] = True
            elif c == 2: st['dim'] = True
            elif c == 3: st['italic'] = True
            elif c == 9: st['strike'] = True
            elif c == 29: st['strike'] = False
            elif c == 22: st.update(bold=False, dim=False)
            elif c == 39: st['fg'] = fg0
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

def draw_line(img, d, x0, y, line, term):
    x = x0
    for ch, st in parse(line, term['fg']):
        fg, bgc = st['fg'], st['bg'] or term['bg']
        if st['dim']: fg = mix(fg, bgc, 0.5)
        span = 2 if wide(ch) else 1
        if st['bg']: d.rectangle([x, y, x + CW * span - 0.01, y + LH - 0.01], fill=st['bg'])
        o = ord(ch)
        if ch == ' ': pass
        elif block(d, ch, x, y, fg, bgc): pass
        elif 0x1F000 <= o < 0xF0000 or ch in '⏳⌛⚡':   # emoji, not the Nerd private-use plane
            e = emoji(ch, round(LH * 0.82)); img.paste(e, (round(x + (CW * 2 - e.width) / 2), round(y + (LH - e.height) / 2)), e)
        else:
            f = F['nerd'] if 0xE000 <= o <= 0xF8FF or o >= 0xF0000 else F['b' if st['bold'] else 'i' if st['italic'] else 'r']
            d.text((x + (CW * span) / 2, y + LH / 2), ch, font=f, fill=fg, anchor='mm')
        if st['strike']: d.line([x, y + LH / 2, x + CW * span, y + LH / 2], fill=fg, width=1)
        x += CW * span

def screen(cols=MAXCOLS, scen='session', frame=0, caption=('', '', ''), **opts):
    o = dict(DEFAULT); o.update(opts)
    status = render(cols, scen, frame, tuple(sorted(o.items())))
    t = TERM[o['THEME']]
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
    tw = cols * CW + 16
    d.rounded_rectangle([PAD, TOP, PAD + tw, TOP + ROWS * LH + 24], radius=10, fill=t['bg'], outline=t['border'])
    x0, y = PAD + 8, TOP + 12
    sgr = lambda c: '\x1b[38;2;%d;%d;%dm' % c
    rule = sgr(t['rule']) + '─' * cols
    for line in [f'{sgr(t["fg"])}⏺\x1b[m Exported the billing report as CSV and updated its tests.', '',
                 rule, sgr(t['muted']) + '❯\x1b[m \x1b[48;2;%d;%d;%dm \x1b[m' % t['cursor'], rule,
                 *['  ' + l for l in status],
                 f'  {sgr(t["accent"])}⏵⏵ accept edits on{sgr(t["muted"])} (shift+tab to cycle)\x1b[m']:
        draw_line(img, d, x0, y, line, t); y += LH
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
show(screen(caption=('AGENTLINE_EFFORT_STYLE', 'dots', 'default')), 700)
# Not a setting: the terminal gets narrower and the layout adapts.
for c in range(MAXCOLS, 67, -2):
    hold(screen(cols=c, caption=('Terminal width', f'{c} columns', 'the layout adapts')), 45)
hold(screen(cols=68, caption=('Terminal width', '68 columns', 'the layout adapts')), 900)
for s_ in STYLES:
    show(screen(cols=68, COMPACT_STYLE=s_, caption=('AGENTLINE_COMPACT_STYLE', s_, 'gauges on narrow terminals')), 520)
show(screen(cols=68, caption=('AGENTLINE_COMPACT_STYLE', 'pie', 'default')), 400)
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
show(screen(scen='tomorrow', caption=('Live state · usage', 'resets tomorrow', 'the day and local time, not only the duration')), 2000)
for effect, n in [('violet', 6), ('rainbow', 6), ('plain', 1)]:
    cap = ('AGENTLINE_ULTRA_EFFECT', effect, ('default · ' if effect == 'violet' else '') + 'in an ultracode session · 1 frame per second')
    fade(screen(scen='ultra', frame=0, ULTRA_EFFECT=effect, caption=cap))
    for f in range(n):
        hold(screen(scen='ultra', frame=f, ULTRA_EFFECT=effect, caption=cap), 1000 if n > 1 else 1300)
# automodel routes each prompt of a "Jev" session; agentline shows what it picked.
jev = lambda **kw: dict(scen='jev', AUTOMODEL='auto', **kw)
opus = routed('opus-5.5', 'Opus 5.5', 'xhigh', 0.86)
show(screen(**jev(AUTOMODEL_JSON=opus), caption=('With automodel', 'routed session',
            'the model and effort picked, and how sure the router is')), 2400)
cap = ('With automodel · next prompt', 'rerouted', 'flagged for a few seconds')
fade(screen(**jev(AUTOMODEL_JSON=routed('sonnet-5', 'Sonnet 5', 'medium', 0.74, flash='switched')), caption=cap))
hold(screen(**jev(AUTOMODEL_JSON=routed('sonnet-5', 'Sonnet 5', 'medium', 0.74, flash='switched')), caption=cap), 1800)
hold(screen(**jev(AUTOMODEL_JSON=routed('sonnet-5', 'Sonnet 5', 'medium', 0.74)), caption=cap), 900)
show(screen(**jev(AUTOMODEL_JSON=routed('opus-5.5', 'Opus 5.5', 'medium', 0.82, claude_effort='xhigh')),
            caption=('With automodel', 'real effort', "what Claude Code shows is struck through")), 2200)
cap = ('With automodel', 'ultracode', 'picked by the router, drawn with AGENTLINE_ULTRA_EFFECT · 1 frame per second')
for f in range(4):
    am = routed('opus-5.5', 'Opus 5.5', 'xhigh', 0.91, mode='ultracode', flash='switched' if f < 2 else '')
    im = screen(**jev(frame=f, AUTOMODEL_JSON=am), caption=cap)
    if f == 0: fade(im)
    hold(im, 1000)
show(screen(**jev(THEME='light', AUTOMODEL_JSON=opus), caption=('AGENTLINE_THEME', 'light', 'for light terminal backgrounds')), 1800)
show(screen(**jev(LAYOUT='one', AUTOMODEL_JSON=opus),
            caption=('AGENTLINE_LAYOUT', 'one', 'or your own: "dir git | model route; ctx 5h 7d | cost"')), 1800)
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
