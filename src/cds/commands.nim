import os, json, strutils, terminal, posix, strformat
import ./types, ./storage, ./rawMode

proc handleConfigureCommand*(config: AppConfig, paths: var JsonNode,
    alias: string, command: string) =

  if alias.len == 0:
    raise newException(AppError, "Alias cannot be empty")

  if not paths.hasKey(alias):
    raise newException(AppError, "Alias not found: " & alias)

  var entry = parseDirectoryEntry(paths[alias])
  entry.commands.add(command)

  paths[alias] = toJson(entry)
  saveStorage(config, paths)
  echo "Added command '", command, "' to alias '", alias, "'"

proc clearScreen() =
  stdout.write "\x1b[2J\x1b[H"

proc clearLine() =
  stdout.write "\r\x1b[2K"

proc flushOut() =
  stdout.flushFile()

proc padRight(s: string, width: int): string =
  if s.len >= width:
    s
  else:
    s & repeat(' ', width - s.len)

proc findMatch(items: seq[(string, string)], q: string): int =
  if q.len == 0:
    return -1
  let qLower = q.toLowerAscii()
  for i, (name, _) in items:
    if name.toLowerAscii().contains(qLower):
      return i
  return -1

proc renderList(
  items: seq[(string, string)],
  selected: int,
  query: string,
  scrollOffset: int, 
  limit: int, 
  title: string = "CDS Saved Paths (↑↓ move, Enter open, q quit)"
) =
  clearScreen()
  echo title

  stdout.write("\r\x1b[2K")
  if query.len > 0:
    stdout.write("Search: " & query & "\n")
  else:
    stdout.write("\n")

  var maxAlias = 0
  for (a, _) in items:
    if a.len > maxAlias:
      maxAlias = a.len
  if maxAlias < 8:
    maxAlias = 8
  let aliasWidth = maxAlias

  let endIndex = min(scrollOffset + limit, items.len)

  if scrollOffset > 0:
    stdout.write("  ↑ ...\n")
  else:
    stdout.write("\n") 

  for i in scrollOffset ..< endIndex:
    let item = items[i]
    let (name, path) = item
    clearLine()

    if i == selected:
      stdout.write("> ")
      stdout.write("\x1b[7m") 
      stdout.write(padRight(name, aliasWidth) & " -> " & path)
      stdout.write("\x1b[0m")
    else:
      stdout.write("  " & padRight(name, aliasWidth) & " -> " & path)

    stdout.write "\n"

  if endIndex < items.len:
    stdout.write("  ↓ ...\n")

  let rowsRendered = endIndex - scrollOffset
  for k in 0 ..< (limit - rowsRendered):
    stdout.write("\n")

  flushOut()

proc handleListCommand*(paths: JsonNode): string =
  if paths.len == 0:
    echo "No saved paths found."
    return ""

  var items: seq[(string, string)] = @[]
  for k, v in paths:
    let entry = parseDirectoryEntry(v)
    items.add((k, entry.path))

  var selected = 0
  var query = ""
  var scrollOffset = 0 

  enableRawMode()
  defer: disableRawMode()

  var listHeight = terminalHeight() - 5 
  if listHeight < 5: listHeight = 5 

  renderList(items, selected, query, scrollOffset, listHeight)

  while true:

    listHeight = terminalHeight() - 5
    if listHeight < 5: listHeight = 5

    var buf: array[3, char]
    discard read(0, addr buf[0], 3)

    if buf[0] == 'Q' or (buf[0] == '\x1b' and buf[1] == '\0'):
      clearScreen()
      return ""

    if buf[0] == '\n' or buf[0] == '\r':
      clearScreen()
      return items[selected][0]

    var needRender = false

    if buf[0] == '\x1b' and buf[1] == '[':
      case buf[2]
      of 'A': 
        if selected > 0:
          dec selected

          if selected < scrollOffset:
            scrollOffset = selected
          needRender = true
      of 'B': 
        if selected < items.len - 1:
          inc selected

          if selected >= scrollOffset + listHeight:
            scrollOffset = selected - listHeight + 1
          needRender = true
      else:
        discard

    elif buf[0].ord == 127: 
      if query.len > 0:
        query.setLen(query.len - 1)
        let m = findMatch(items, query)
        if m >= 0:
          selected = m

          scrollOffset = max(0, selected - (listHeight div 2))
        else:
            selected = 0
            scrollOffset = 0
        needRender = true

    elif buf[0].isAlphaNumeric():
      query.add(buf[0])
      let m = findMatch(items, query)
      if m >= 0:
        selected = m

        scrollOffset = max(0, selected - (listHeight div 2))
      needRender = true

    if needRender:
       renderList(items, selected, query, scrollOffset, listHeight)

proc handleSaveCommand*(config: AppConfig, paths: var JsonNode, alias: string) =
  if alias.len == 0:
    raise newException(AppError, "Alias cannot be empty")

  let targetPath = getCurrentDir()
  validateDirectory(targetPath)

  var entry: DirectoryEntry
  entry.path = targetPath
  entry.commands = @[]

  paths[alias] = toJson(entry)
  saveStorage(config, paths)
  echo "Saved path '", alias, "' -> ", targetPath

proc handleJumpCommand*(paths: JsonNode, alias: string): string =
  if not paths.hasKey(alias):
    raise newException(AppError, "Alias not found: " & alias)

  let entry = parseDirectoryEntry(paths[alias])
  validateDirectory(entry.path)

  var resultStr = entry.path
  if entry.commands.len > 0:
    resultStr &= "|CDS_COMMANDS|" & entry.commands.join("|CDS_SEP|")

  stderr.writeLine("CDS_RESULT:" & resultStr)
  return ""
