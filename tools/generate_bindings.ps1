param(
    [string]$Source = "src_zig/main.zig",
    [string]$Output = "ffi_bindings.lua"
)

$ErrorActionPreference = "Stop"
$zig = Get-Content -Raw $Source
$typeMap = @{
    "u32" = "uint32_t"
    "u64" = "uint64_t"
    "u8" = "uint8_t"
    "i32" = "int32_t"
    "usize" = "size_t"
    "f32" = "float"
    "bool" = "bool"
    "c_int" = "int"
}

function Convert-Type([string]$type) {
    $type = $type.Trim()
    if ($type.StartsWith("?[*]")) { return (Convert-Type $type.Substring(4)) + "*" }
    if ($type.StartsWith("[*]")) { return (Convert-Type $type.Substring(3)) + "*" }
    if ($type.StartsWith("const ")) { return "const " + (Convert-Type $type.Substring(6)) }
    if ($type.StartsWith("?*")) { return (Convert-Type $type.Substring(2)) + "*" }
    if ($type.StartsWith("*const ")) { return "const " + (Convert-Type $type.Substring(7)) + "*" }
    if ($type.StartsWith("*")) { return (Convert-Type $type.Substring(1)) + "*" }
    if ($typeMap.ContainsKey($type)) { return $typeMap[$type] }
    return $type
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("typedef struct EngineContext EngineContext;")
$lines.Add("")

$structMatches = [regex]::Matches($zig, 'pub const (\w+) = extern struct \{(?<body>.*?)\};', [System.Text.RegularExpressions.RegexOptions]::Singleline)
foreach ($match in $structMatches) {
    $name = $match.Groups[1].Value
    $lines.Add("typedef struct {")
    foreach ($field in [regex]::Matches($match.Groups["body"].Value, '(\w+):\s*([\w]+),')) {
        $lines.Add("    $(Convert-Type $field.Groups[2].Value) $($field.Groups[1].Value);")
    }
    $lines.Add("} $name;")
}
$lines.Add("")

$functionMatches = [regex]::Matches($zig, 'export fn (\w+)\((?<args>[^)]*)\)\s*(?<return>[?*\[\]\w ]+)\s*\{', [System.Text.RegularExpressions.RegexOptions]::Singleline)
foreach ($match in $functionMatches) {
    $args = [System.Collections.Generic.List[string]]::new()
    foreach ($arg in $match.Groups["args"].Value.Split(',')) {
        if ([string]::IsNullOrWhiteSpace($arg)) { continue }
        $parts = $arg.Trim().Split(':', 2)
        $args.Add("$(Convert-Type $parts[1]) $($parts[0].Trim())")
    }
    $returnType = Convert-Type $match.Groups["return"].Value
    $lines.Add("$returnType $($match.Groups[1].Value)($($args -join ', '));")
}

$contents = "return [[`n$($lines -join "`n")`n]]`n"
[System.IO.File]::WriteAllText($Output, $contents, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated $Output from $Source"
