# Template: rendered to ~/.config/zsh/rice-colors.zsh by ~/.config/plasma-rice/rice.py
# ({{name}} = palette colour, {{name.rgb}} = the same as r;g;b). Read by ~/.config/plasma-rice/shell/rice.zsh
# when a shell starts and again at the next prompt after each re-theme, so open shells follow the wallpaper.

# the line being typed: commands in the accent, builtins and keywords in the second accent, strings green,
# paths underlined, options quieter, comments muted, anything unknown red
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES+=(
    default                         none
    unknown-token                   'fg={{red}}'
    command                         'fg={{primary}}'
    alias                           'fg={{primary}}'
    suffix-alias                    'fg={{primary}},underline'
    global-alias                    'fg={{primary}}'
    function                        'fg={{primary}}'
    hashed-command                  'fg={{primary}}'
    arg0                            'fg={{primary}}'
    builtin                         'fg={{tertiary}}'
    reserved-word                   'fg={{tertiary}}'
    precommand                      'fg={{tertiary}},italic'
    commandseparator                'fg={{muted}}'
    autodirectory                   'fg={{on_surface}},underline'
    path                            'fg={{on_surface}},underline'
    path_prefix                     'fg={{on_surface}},underline'
    path_pathseparator              'fg={{muted}},underline'
    path_prefix_pathseparator       'fg={{muted}},underline'
    globbing                        'fg={{teal}}'
    history-expansion               'fg={{magenta}}'
    single-hyphen-option            'fg={{on_surface_variant}}'
    double-hyphen-option            'fg={{on_surface_variant}}'
    single-quoted-argument          'fg={{green}}'
    double-quoted-argument          'fg={{green}}'
    dollar-quoted-argument          'fg={{green}}'
    rc-quote                        'fg={{green}}'
    dollar-double-quoted-argument   'fg={{cyan}}'
    back-double-quoted-argument     'fg={{cyan}}'
    back-dollar-quoted-argument     'fg={{cyan}}'
    back-quoted-argument            'fg={{magenta}}'
    command-substitution-delimiter  'fg={{magenta}}'
    process-substitution-delimiter  'fg={{magenta}}'
    redirection                     'fg={{orange}}'
    named-fd                        'fg={{orange}}'
    numeric-fd                      'fg={{orange}}'
    assign                          'fg={{on_surface}}'
    comment                         'fg={{muted}},italic'
)
# the grey guess from history
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg={{muted}}'
# ↑/↓ history search: the matched part
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg={{primary_container}},fg={{on_primary_container}},bold'
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg={{red_dim}},fg={{on_primary}},bold'

# fzf (Ctrl+R history, Ctrl+T files, Alt+C folders): the chosen line on the deep accent
export RICE_FZF_COLORS='fg:{{on_surface_variant}},fg+:{{on_surface}},bg:-1,bg+:{{primary_container}},gutter:-1,hl:{{primary}},hl+:{{primary}},query:{{on_surface}},prompt:{{primary}},pointer:{{primary}},marker:{{green}},spinner:{{tertiary}},info:{{muted}},header:{{muted}},border:{{outline_variant}},label:{{on_surface_variant}},separator:{{outline_variant}},scrollbar:{{outline}}'

# eza (ls): folders in the accent, links teal, programs green, media and archives in the candy hues;
# permissions, sizes and dates quiet; git flags in their usual colours
export EZA_COLORS="reset:di=1;38;2;{{primary.rgb}}:ln=38;2;{{teal.rgb}}:or=38;2;{{red.rgb}}:ex=38;2;{{green.rgb}}:\
ur=38;2;{{yellow_dim.rgb}}:gr=38;2;{{yellow_dim.rgb}}:tr=38;2;{{yellow_dim.rgb}}:\
uw=38;2;{{red_dim.rgb}}:gw=38;2;{{red_dim.rgb}}:tw=38;2;{{red_dim.rgb}}:\
ux=38;2;{{green_dim.rgb}}:ue=38;2;{{green_dim.rgb}}:gx=38;2;{{green_dim.rgb}}:tx=38;2;{{green_dim.rgb}}:\
su=38;2;{{magenta.rgb}}:sf=38;2;{{magenta.rgb}}:xa=38;2;{{muted.rgb}}:oc=38;2;{{on_surface_variant.rgb}}:\
sn=38;2;{{on_surface_variant.rgb}}:sb=38;2;{{muted.rgb}}:df=38;2;{{on_surface_variant.rgb}}:ds=38;2;{{muted.rgb}}:\
uu=38;2;{{tertiary.rgb}}:uR=38;2;{{red.rgb}}:un=38;2;{{muted.rgb}}:gu=38;2;{{tertiary_dim.rgb}}:gR=38;2;{{red_dim.rgb}}:gn=38;2;{{muted.rgb}}:\
da=38;2;{{muted.rgb}}:hd=4;38;2;{{on_surface_variant.rgb}}:xx=38;2;{{outline.rgb}}:lp=38;2;{{teal.rgb}}:lc=38;2;{{muted.rgb}}:\
ga=38;2;{{green.rgb}}:gm=38;2;{{yellow.rgb}}:gd=38;2;{{red.rgb}}:gv=38;2;{{teal.rgb}}:gt=38;2;{{teal.rgb}}:gi=38;2;{{muted.rgb}}:gc=38;2;{{red.rgb}}:\
Gm=38;2;{{primary.rgb}}:Go=38;2;{{tertiary.rgb}}:Gc=38;2;{{green.rgb}}:Gd=38;2;{{yellow.rgb}}:\
im=38;2;{{magenta.rgb}}:vi=38;2;{{magenta.rgb}}:mu=38;2;{{cyan.rgb}}:lo=38;2;{{cyan.rgb}}:co=38;2;{{orange.rgb}}:\
do=38;2;{{blue.rgb}}:cr=38;2;{{yellow.rgb}}:tm=38;2;{{muted.rgb}}:cm=38;2;{{muted.rgb}}:bu=38;2;{{yellow.rgb}}:sc=38;2;{{on_surface.rgb}}"

# man pages (Oh My Zsh colored-man-pages): headings in the accent, arguments in the second accent,
# the status line and search hits on the deep accent
if (( ${+less_termcap} )); then
    less_termcap[md]=$'\e[1;38;2;{{primary.rgb}}m'
    less_termcap[mb]=$'\e[1;38;2;{{red.rgb}}m'
    less_termcap[us]=$'\e[4;38;2;{{tertiary.rgb}}m'
    less_termcap[so]=$'\e[1;38;2;{{on_primary_container.rgb}};48;2;{{primary_container.rgb}}m'
fi

# the shrunken prompt of entered commands (shell/rice.zsh)
typeset -g RICE_TIME='{{muted}}' RICE_DIR='{{on_surface_variant}}' RICE_OK='{{primary}}' RICE_ERR='{{red}}'
