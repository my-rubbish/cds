when defined(macosx):
  import termios
else:
  import posix

var original: Termios

proc enableRawMode*() =

  if tcgetattr(0, original.addr) != 0:
    quit("tcgetattr failed")

  var raw = original
  raw.c_lflag = raw.c_lflag and not(ICANON or ECHO or ISIG)
  raw.c_iflag = raw.c_iflag and not(ICRNL)
  raw.c_oflag = raw.c_oflag and not(OPOST)

  raw.c_cc[VMIN] = char(1)
  raw.c_cc[VTIME] = char(0)

  if tcsetattr(0, TCSAFLUSH, raw.addr) != 0:
    quit("tcsetattr failed")

proc disableRawMode*() =

  discard tcsetattr(0, TCSAFLUSH, original.addr)
