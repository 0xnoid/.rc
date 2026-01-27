# zsh style history
## Improve multi-line command history
shopt -s cmdhist
## Append commands to history file instead of overwrite, safer for multisession
shopt -s histappend
## Append history immediately after command
PROMPT_COMMAND='history -a'
## History size
HISTSIZE=1000
HISTFILESIZE=2000
# Ignore duplicates, ignore commands starting with space
export HISTCONTROL=erasedups:ignoredups:ignorespace
