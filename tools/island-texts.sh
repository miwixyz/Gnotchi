#!/bin/sh
# island-texts.sh — liest die Texte/Beschreibungen der Gnotchi-Insel über die Bedienungshilfen (Sichttest
# 0.2.0, ohne Bildschirmfoto-Recht). Gibt nur feste Beschriftungen der Insel aus; bei Musik stünde auch der
# Titel darin → Ausgabe nicht ins Repo schreiben (G16).
osascript <<'OSA' 2>&1
tell application "System Events"
  if not (exists process "Gnotchi") then return "KEIN_PROZESS"
  tell process "Gnotchi"
    set out to ""
    repeat with w in windows
      set out to out & "[" & (subrole of w as text) & " " & (item 1 of (size of w as list)) & "x" & (item 2 of (size of w as list)) & "] "
      try
        repeat with e in (entire contents of w)
          try
            set d to description of e
            if d is not missing value and d is not "" then set out to out & d & " | "
          end try
        end repeat
      end try
    end repeat
    return out
  end tell
end tell
OSA
