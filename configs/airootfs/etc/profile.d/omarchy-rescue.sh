# Omarchy Rescue: every interactive rescue login lands in the shared "rescue"
# tmux session, the same one omarchy-rescue-share serves to a phone.

if grep -qw omarchy.rescue /proc/cmdline 2>/dev/null; then
  export OMARCHY_RESCUE=1

  case $- in
  *i*)
    if [ -z "$TMUX" ]; then
      # Detaching returns 0 and logs out, so autologin brings the session back.
      tmux -f /usr/share/omarchy-rescue/tmux.conf new-session -A -s rescue && exit
    elif [ -z "$(tmux show-options -gqv @omarchy-rescue-welcomed)" ]; then
      tmux set-option -g @omarchy-rescue-welcomed 1
      omarchy-rescue welcome
    fi
    ;;
  esac
fi
