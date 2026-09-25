# Fonts for agentline

**Recommended: [JuliaMono](https://github.com/cormullion/juliamono), with
[Symbols Nerd Font Mono](https://github.com/ryanoasis/nerd-fonts) as fallback.**

Claude Code draws its interface with about 50 symbols (`⏺ ⎿ ⏵ ⏸ ✶ ✻ ✽ ✔ ✗ ⚠ ◉ ❯ …`).
89 free monospace fonts were compared against those symbols and this status line.
JuliaMono is the only one that covers all of them. Iosevka, Iosevka Term and Adwaita
Mono miss one rarely used symbol (`⎯`). Popular fonts (JetBrains Mono, Fira Code,
Cascadia, Hack, Meslo, Monaspace…) miss 9 or more, and your terminal draws those
with whatever fallback font it finds.

JuliaMono has no icons, so Nerd glyphs (`--glyphs nerd`) come from Symbols Nerd
Font Mono. Both fonts are free for any use: JuliaMono is under the SIL Open Font
License 1.1, the Nerd Fonts symbols under MIT (the icon sets inside are MIT,
Apache 2.0, OFL or CC BY 4.0).

Install them:

```sh
# macOS
brew install --cask font-juliamono font-symbols-only-nerd-font

# Linux
mkdir -p ~/.local/share/fonts && cd ~/.local/share/fonts
curl -fLO https://github.com/cormullion/juliamono/releases/latest/download/JuliaMono-ttf.tar.gz
tar xzf JuliaMono-ttf.tar.gz && rm JuliaMono-ttf.tar.gz
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz
tar xJf NerdFontsSymbolsOnly.tar.xz SymbolsNerdFontMono-Regular.ttf && rm NerdFontsSymbolsOnly.tar.xz
fc-cache -f
```

Then set JuliaMono as the terminal font, with Symbols Nerd Font Mono as fallback:

| Terminal | Setting |
|---|---|
| Ghostty | `font-family = JuliaMono` then `font-family = Symbols Nerd Font Mono` |
| kitty | `font_family JuliaMono` and `symbol_map U+E000-U+F8FF,U+F0000-U+FFFFD Symbols Nerd Font Mono` |
| WezTerm | `font = wezterm.font_with_fallback { 'JuliaMono', 'Symbols Nerd Font Mono' }` |
| Alacritty, GNOME Terminal, iTerm2 | JuliaMono; Nerd symbols come from the system's font fallback |
| VS Code | `"terminal.integrated.fontFamily": "JuliaMono, 'Symbols Nerd Font Mono'"` |

## Checking

Run `agentline configure`: the glyph line at the top of the Look section shows
Nerd icons. If you see icons rather than empty boxes or question marks, your
terminal font draws them.
