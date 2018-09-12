import jester, strutils, strformat, os, ospaths, osproc, times, json, uri, tables, cgi
import zip/zipfiles

const
  temp_folder* = getTempDir() / "hackpad"   ## Temporary folder used for temporary files at runtime, etc.
  strip_cmd*  = "strip --strip-all"         ## Linux Bash command to strip the compiled binary executables.
  upx_cmd*    = "upx --best --ultra-brute"  ## Linux Bash command to compress the compiled binary executables.
  sha_cmd*    = "sha1sum --tag"             ## Linux Bash command to checksum the compiled binary executables.
  html_template = static_read("index.html") ## Main Index HTML Template for the pad.
  html_download = static_read("downloads.html") ## HTML Template for Downloads.
  linux_args* = "" ## Linux Bash command line extra parameters for CrossCompilation on demand, for target Linux.
  windows_args* = "--gcc.exe:/usr/bin/x86_64-w64-mingw32-gcc --gcc.linkerexe:/usr/bin/x86_64-w64-mingw32-gcc"  ## Windows Bash command line extra parameters for CrossCompilation on demand, for target Windows.
createDir(temp_folder)
type CrossCompileResult = tuple[
  win, winzip, winsha, lin, linzip, linsha, doc, doczip, logs, jsf, jszip, jssha: string]  ## Tuple with full path string to binaries and SHA1 Sum of binaries.

proc crosscompile*(code, target, opt, release, gc, app, ssls, threads: string): CrossCompileResult =
  ## Receives code as string and crosscompiles and generates HTML Docs, Strips and ZIPs.
  var win, winzip, winsha, lin, linzip, linsha, doc, doczip, logs, jsf, jszip, jssha: string
  if countLines(code.strip) >= 1:
    let
      temp_file_nim = temp_folder / "hackpad" & $epochTime().int & ".nim"
      temp_file_bin = temp_file_nim.replace(".nim", "")
      temp_file_exe = temp_file_nim.replace(".nim", ".exe")
      temp_file_html = temp_file_nim.replace(".nim", ".html")
      temp_file_js = temp_file_nim.replace(".nim", ".js")
    writeFile(temp_file_nim,  code)
    var
      output: string
      exitCode: int
    # Linux Compilation.
    (output, exitCode) = execCmdEx(fmt"nim {target} {release} {opt} {gc} {app} {ssls} {threads} {linux_args} --out:{temp_file_bin} {temp_file_nim}")
    logs &= output
    if exitCode == 0:
      (output, exitCode) = execCmdEx(fmt"{strip_cmd} {temp_file_bin}")
      logs &= output
      if exitCode == 0:
        lin = splitPath(temp_file_bin).tail
        (output, exitCode) = execCmdEx(fmt"{sha_cmd} {temp_file_bin}")
        logs &= output
        if exitCode == 0:
          linsha = output
          var z: ZipArchive
          discard z.open(temp_file_bin & ".zip", fmWrite)
          z.addFile(temp_file_bin)
          z.close
          linzip = splitPath(temp_file_bin & ".zip").tail
    # Windows Compilation.
    (output, exitCode) = execCmdEx(fmt"nim {target} {release} {opt} {gc} {app} {ssls} {threads} --cpu:amd64 --os:windows {windows_args} --out:{temp_file_exe} {temp_file_nim}")
    logs &= output
    if exitCode == 0:
      (output, exitCode) = execCmdEx(fmt"{strip_cmd} {temp_file_exe}")
      logs &= output
      if exitCode == 0:
        win = splitPath(temp_file_exe).tail
        (output, exitCode) = execCmdEx(fmt"{sha_cmd} {temp_file_exe}")
        logs &= output
        if exitCode == 0:
          winsha = output
          var z: ZipArchive
          discard z.open(temp_file_exe & ".zip", fmWrite)
          z.addFile(temp_file_exe)
          z.close
          winzip = splitPath(temp_file_exe & ".zip").tail
    # JavaScript Compilation.
    (output, exitCode) = execCmdEx(fmt"nim js -d:nodejs {release} {opt} --out:{temp_file_js} {temp_file_nim}")
    logs &= output
    if exitCode == 0:
      jsf = splitPath(temp_file_js).tail
      (output, exitCode) = execCmdEx(fmt"{sha_cmd} {temp_file_js}")
      logs &= output
      if exitCode == 0:
        jssha = output
        var z: ZipArchive
        discard z.open(temp_file_js & ".zip", fmWrite)
        z.addFile(temp_file_js)
        z.close
        jszip = splitPath(temp_file_js & ".zip").tail
    # HTML Docs.
    (output, exitCode) = execCmdEx(fmt"nim doc --out:{temp_file_html} {temp_file_nim}")
    logs &= output
    if exitCode == 0:
      doc = splitPath(temp_file_html).tail
      var z: ZipArchive
      discard z.open(temp_file_html & ".zip", fmWrite)
      z.addFile(temp_file_html)
      z.close
      doczip = splitPath(temp_file_html & ".zip").tail
  let resultaditos: CrossCompileResult = (
    win: win, winzip: winzip, winsha: winsha.strip, lin: lin, linzip: linzip,
    linsha: linsha.strip, doc: doc, doczip: doczip, logs: logs, jsf: jsf,
    jszip: jszip, jssha: jssha)
  result = resultaditos

proc parseResponseBody(body: string): Table[string, string] =
  ## Parse the Body string of the HTTP Response.
  result = initTable[string, string]()
  for res in body.strip.split("&"):
    let r = res.split("=")
    result[r[0]] = r[1]

routes:
  get "/":  ## Shows the main index for code editing and actions.
    resp html_template

  post "/compile":  ## Compiles the source code.
    setStaticDir(request, temp_folder)
    let
      args = parseResponseBody(request.body)
      target = args["target"]
      code = decodeUrl(args["code"])
      opt = decodeUrl(args["opt"])
      release = decodeUrl(args["release"])
      gc = decodeUrl(args["gc"])
      app = decodeUrl(args["app"])
      ssls = if args.hasKey("ssl"): "-d:ssl" else: ""
      threads = if args.hasKey("threads"): "-d:threads" else: ""
      strips = if args.hasKey("strip"): true else: false
      x = crosscompile(code, target, opt, release, gc, app, ssls, threads)

    resp html_download & fmt"""
    <div id="downloadsframe"> <b>Windows</b><br>
      <a href="{x.win}" title="{x.win}">Windows Executable</a>
      <a href="{x.winzip}" title="{x.winzip}">Zipped Windows Executable</a><br>
      <small>{x.winsha}</small>
      <hr> <b>Linux</b><br>
      <a href="{x.lin}" title="{x.lin}">Linux Executable</a>
      <a href="{x.linzip}" title="{x.linzip}">Zipped Linux Executable</a><br>
      <small>{x.linsha}</small>
      <hr> <b>JavaScript</b><br>
      <a href="{x.jsf}" title="{x.jsf}" target="_blank">JavaScript Executable</a>
      <a href="{x.jszip}" title="{x.jszip}">Zipped JavaScript Executable</a><br>
      <small>{x.jssha}</small>
      <hr> <b>Documentation</b><br>
      <a href="{x.doc}" title="{x.doc}" target="_blank">HTML Self-Documentation</a>
      <a href="{x.doczip}" title="{x.doczip}">Zipped HTML Self-Documentation</a><br>
    </div>
    <details open > <summary>Log</summary>
      <textarea id="log" title="CrossCompilation Logs (Read-Only)" readonly >
      {request.headers.table} {x.logs}
      </textarea>
    </details><br><button title="Go Back" onclick="history.back()">Back</button></body>
    """  # TODO: Add Android support, install https://aur.archlinux.org/packages/android-sdk-ndk-symlink/.
