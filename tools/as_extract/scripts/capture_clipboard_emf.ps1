#Requires -Version 5.1
<#
.SYNOPSIS
  Capture CF_ENHMETAFILE from clipboard (AS Copy) and import into stroke JSON.
#>
param(
    [string]$OutEmf = '',
    [string]$OutJson = '',
    [string]$Id = 'cylinder.from_as_clipboard_emf'
)

$ErrorActionPreference = 'Stop'

if ($OutEmf -eq '') {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutEmf = Join-Path (Join-Path $PSScriptRoot '..\out\captures') ("clipboard_$stamp.emf")
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutEmf) | Out-Null

$pinvoke = @'
using System;
using System.Runtime.InteropServices;
public static class EmfClip {
  public const uint CF_ENHMETAFILE = 14;
  [DllImport("user32.dll")] public static extern bool OpenClipboard(IntPtr h);
  [DllImport("user32.dll")] public static extern bool CloseClipboard();
  [DllImport("user32.dll")] public static extern bool IsClipboardFormatAvailable(uint fmt);
  [DllImport("user32.dll")] public static extern IntPtr GetClipboardData(uint fmt);
  [DllImport("gdi32.dll")] public static extern uint GetEnhMetaFileBits(IntPtr hemf, uint cb, byte[] data);
  [DllImport("gdi32.dll")] public static extern IntPtr CopyEnhMetaFile(IntPtr hemf, string path);
  [DllImport("gdi32.dll")] public static extern bool DeleteEnhMetaFile(IntPtr hemf);
}
'@
Add-Type -TypeDefinition $pinvoke -ErrorAction SilentlyContinue

if (-not [EmfClip]::OpenClipboard([IntPtr]::Zero)) {
    throw 'OpenClipboard failed. Close apps locking the clipboard and retry.'
}
try {
    if (-not [EmfClip]::IsClipboardFormatAvailable([EmfClip]::CF_ENHMETAFILE)) {
        throw 'Clipboard has no CF_ENHMETAFILE. In AS: select assembled symbol, Ctrl+C, then re-run.'
    }
    $hemf = [EmfClip]::GetClipboardData([EmfClip]::CF_ENHMETAFILE)
    if ($hemf -eq [IntPtr]::Zero) { throw 'GetClipboardData returned null HEMF.' }
    $copy = [EmfClip]::CopyEnhMetaFile($hemf, $OutEmf)
    if ($copy -eq [IntPtr]::Zero) { throw "CopyEnhMetaFile failed for $OutEmf" }
    [EmfClip]::DeleteEnhMetaFile($copy) | Out-Null
}
finally {
    [EmfClip]::CloseClipboard() | Out-Null
}

$len = (Get-Item -LiteralPath $OutEmf).Length
if ($len -lt 64) { throw "Clipboard EMF too small ($len bytes)" }
Write-Host "Saved clipboard EMF -> $OutEmf ($len bytes)"

$import = Join-Path $PSScriptRoot 'import_emf.ps1'
if ($OutJson -eq '') {
    & $import -EmfPath $OutEmf -Id $Id
}
else {
    & $import -EmfPath $OutEmf -OutJson $OutJson -Id $Id
}
