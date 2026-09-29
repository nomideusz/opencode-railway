# ~/.bashrc — persisted on the Railway volume. Edit freely.
[ -z "$PS1" ] && return
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=vim
alias ll='ls -alF'
PS1='\[\e[1;32m\]\u@opencode\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
# `oc` = the OpenCode terminal UI attached to the server the web UI uses:
# same sessions, same history, in whatever directory you run it from.
oc() { opencode attach http://127.0.0.1:4096 --dir "$PWD" "$@"; }
[ -f ~/.motd ] && cat ~/.motd
