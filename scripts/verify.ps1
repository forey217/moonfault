$ErrorActionPreference = 'Stop'
function Run([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
Set-Location (Split-Path $PSScriptRoot -Parent)
Run moon @('fmt', '--check')
Run moon @('check', '--target', 'js', '--deny-warn')
foreach ($Target in @('js', 'wasm-gc', 'wasm')) { Run moon @('test', '--target', $Target, '--deny-warn') }
Run npm @('run', 'verify')
