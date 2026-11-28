<!-- Generated from docs/configure/compositors/sway.md by tools/sync-skill-docs.py. Do not edit. -->

# Sway

Configuration is stored in `~/.config/sway`. The main file is `config`, which includes modular files from `configDir/`:

- `variables` - modifier keys and default applications
- `input` - keyboard and touchpad settings
- `output` - display and monitor configurations
- `layout` - window borders and gaps
- `autostart` - startup processes
- `window-rules` - floating window rules and assignments
- `keybinds` - keybindings for compositor actions and shell controls

## Autostart

The shell daemon and clipboard history are launched from `configDir/autostart`:

```ini
exec wl-paste --type text --watch cliphist store
exec wl-paste --type image --watch cliphist store
exec taurusd start
```

`taurusd start` also starts the audio engine.

## Keybindings

Shell overlays and controls are bound in `configDir/keybinds` using `exec taurus msg toggle <module>`:

- `launcher` - application launcher (`$mod+D`)
- `system` - system control panel (`$mod+B`)
- `clipboard` - clipboard history (`$mod+C`)
- `music` - media player (`$mod+M`)
- `wallpaper` - wallpaper selector (`$mod+W`)
- `calendar` - calendar popout (`$mod+S`)
- `network` - network connections (`$mod+N`)
- `volume` - audio popout (`$mod+V`)
- `settings` - cheat sheet for keybindings (`$mod+H`)

Workspace switching is routed through the shell to update bar indicators:

```ini
bindsym $mod+1 exec taurus msg workspace 1
bindsym $mod+Shift+1 exec taurus msg workspace 1 move
# ... up to workspace 10 ($mod+0)
```

Quick utility actions:
- Lock screen: `$mod+L exec taurus lock`
- Reload shell: `$mod+R exec taurus reload`
- Bar autohide: `$mod+A exec taurus msg bar autohide`
- Screenshots: `Print exec taurus screenshot` (add `--edit` or `--full`)
- Brightness: `XF86MonBrightnessDown` and `XF86MonBrightnessUp`
- Volume: `XF86AudioLowerVolume`, `XF86AudioRaiseVolume`, and `XF86AudioMute`

## Mouse wheel and border color

Mouse wheel (with `$mod`): the main wheel switches workspaces and the thumb wheel (for example on an MX Master) moves focus left and right. Sway wraps around at the ends. The focused border follows the theme: Taurus applies `client.focused` / `client.unfocused` at runtime on every color change, so a `swaymsg reload` resets them until the next change.
