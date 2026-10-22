# Atom Plasma: the shell side of the rice. Sourced by ~/.zshrc after `starship init zsh`.
#
# - colours: ~/.config/zsh/rice-colors.zsh (rice.py writes it from the wallpaper palette: templates/shell.zsh)
#   is read now and again at the first prompt after it changes, so an open shell follows a re-theme the way
#   starship (it reads its config at every prompt) and Konsole (rice.py swaps its profile) already do
# - transient prompt: once a command is entered, its two-line frame shrinks to one line (time, folder, ❯),
#   so the scrollback reads as a list of commands and only the live prompt carries the frame
# - in Konsole, shell integration marks (OSC 133: where each prompt, command line and output starts), so a
#   click in the command line moves the cursor there (profile SemanticInputClick)
# - ls is eza (icons, folders first; `\ls` is the plain one), ll the long view with git flags, lt a tree
# - fzf: Ctrl+R history, Ctrl+T files, Alt+C folders (fd; previews with bat and eza). Tab stays zsh's own.
# - bat follows the terminal's colours

zmodload -F zsh/stat b:zstat
autoload -Uz add-zle-hook-widget

# ---- colours
typeset -g _rice_colors=$HOME/.config/zsh/rice-colors.zsh _rice_colors_seen=
typeset -g _rice_fzf_opts="--height=45% --layout=reverse --border=rounded --info=inline-right \
--prompt='❯ ' --pointer='▌' --marker='✓' --separator='─' --scrollbar='│'"
_rice_colors_load() {
    local -a t
    zstat -A t +mtime -- $_rice_colors 2>/dev/null || return 0
    [[ $t[1] == $_rice_colors_seen ]] && return 0
    _rice_colors_seen=$t[1]
    source $_rice_colors
    export FZF_DEFAULT_OPTS="$_rice_fzf_opts --color=$RICE_FZF_COLORS"
}
_rice_colors_load

# ---- shell integration marks for Konsole (OSC 133): A prompt, B command line, C output, D;status done
typeset -g _rice_mark_a= _rice_mark_b=
if [[ -n $KONSOLE_VERSION ]]; then
    _rice_mark_a=$'%{\e]133;A\a%}' _rice_mark_b=$'%{\e]133;B\a%}'
    _rice_osc_preexec() { print -n -- $'\e]133;C\a' }
    preexec_functions+=(_rice_osc_preexec)
fi

# ---- transient prompt
typeset -g _rice_prompt="$_rice_mark_a$PROMPT$_rice_mark_b" _rice_rprompt=$RPROMPT
_rice_transient() {
    [[ $CONTEXT == start ]] || return 0     # not the continuation lines of a multi-line command
    local ok=${RICE_OK:-blue}
    (( ${STARSHIP_CMD_STATUS:-0} )) && ok=${RICE_ERR:-red}
    PROMPT=$'\n'"$_rice_mark_a%F{${RICE_TIME:-8}}%D{%H:%M}%f %F{${RICE_DIR:-7}}%1~%f %B%F{$ok}❯%f%b $_rice_mark_b"
    RPROMPT=
    zle .reset-prompt
}
add-zle-hook-widget line-finish _rice_transient

_rice_precmd() {
    # starship's own precmd ran first: it has the last command's status
    [[ -n $_rice_mark_a && -n ${STARSHIP_CMD_STATUS+x} ]] && print -n -- "\e]133;D;$STARSHIP_CMD_STATUS\a"
    PROMPT=$_rice_prompt RPROMPT=$_rice_rprompt
    _rice_colors_load
}
precmd_functions+=(_rice_precmd)
PROMPT=$_rice_prompt

# ---- ls: eza
if (( $+commands[eza] )); then
    alias ls='eza --icons=auto --group-directories-first'
    alias la='eza -a --icons=auto --group-directories-first'
    alias ll='eza -la --header --git --icons=auto --group-directories-first --time-style=relative'
    alias lt='eza --tree --level=2 --icons=auto --group-directories-first --git-ignore'
fi

# ---- fzf: history, files, folders
if [[ -r /usr/share/fzf/key-bindings.zsh ]] && (( $+commands[fzf] )); then
    if (( $+commands[fd] )); then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
        export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
    fi
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null'"
    export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons=always --color=always {}'"
    source /usr/share/fzf/key-bindings.zsh
fi

export BAT_THEME=ansi
