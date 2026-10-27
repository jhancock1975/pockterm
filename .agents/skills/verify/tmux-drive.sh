#!/bin/bash
# Runs ON THE MAC, started from pockterm's SSH session. Attaches a tmux session
# running emacs, while a background driver pokes emacs with the redraw-heavy
# actions from the bug report (save, page, save again).
SOCK=v; SESSION=v; FILE=/tmp/verify-probe.txt
python3 -c "
open('$FILE','w').write(''.join('line %03d the quick brown fox jumps over the lazy dog\n' % i for i in range(1,201)))
"
rm -f "$FILE~"
/opt/homebrew/bin/tmux -L $SOCK kill-server 2>/dev/null
(
  sleep 7
  /opt/homebrew/bin/tmux -L $SOCK send-keys -t $SESSION "hello"
  sleep 2
  /opt/homebrew/bin/tmux -L $SOCK send-keys -t $SESSION C-x C-s      # the reported trigger
  sleep 5
  for i in 1 2 3 4 5 6; do /opt/homebrew/bin/tmux -L $SOCK send-keys -t $SESSION C-v; sleep 0.4; done
  sleep 5
  /opt/homebrew/bin/tmux -L $SOCK send-keys -t $SESSION " more"
  sleep 1
  /opt/homebrew/bin/tmux -L $SOCK send-keys -t $SESSION C-x C-s
  sleep 4
) &
exec /opt/homebrew/bin/tmux -L $SOCK -f /dev/null new-session -s $SESSION \
     "/opt/homebrew/bin/emacs -nw -Q $FILE"
