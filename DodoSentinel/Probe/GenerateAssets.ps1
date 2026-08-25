[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'Media\hl')
)

$width = 128
$height = 64
$contentWidth = 125
$groups = 4
$positions = 5
$cellWidth = [int]($contentWidth / $positions)
$cellHeight = [int]($height / $groups)

[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

foreach ($group in 1..$groups) {
    foreach ($position in 1..$positions) {
        $header = [byte[]]::new(18)
        $header[2] = 2                 # Uncompressed true-colour TGA.
        $header[12] = $width -band 0xff
        $header[13] = ($width -shr 8) -band 0xff
        $header[14] = $height -band 0xff
        $header[15] = ($height -shr 8) -band 0xff
        $header[16] = 32               # BGRA.
        $header[17] = 0x28             # Top-left origin, 8 alpha bits.

        $pixels = [byte[]]::new($width * $height * 4)
        $left = ($position - 1) * $cellWidth
        $right = $position * $cellWidth - 1
        $top = ($group - 1) * $cellHeight
        $bottom = $group * $cellHeight - 1

        for ($y = $top; $y -le $bottom; $y++) {
            for ($x = $left; $x -le $right; $x++) {
                $onBorder = ($x -lt $left + 2) -or ($x -gt $right - 2) -or
                    ($y -lt $top + 2) -or ($y -gt $bottom - 2)
                $offset = ($y * $width + $x) * 4

                $pixels[$offset] = 0       # Blue
                $pixels[$offset + 1] = 204 # Green
                $pixels[$offset + 2] = 255 # Red
                $pixels[$offset + 3] = if ($onBorder) { 255 } else { 38 }
            }
        }

        $fileBytes = [byte[]]::new($header.Length + $pixels.Length)
        [System.Array]::Copy($header, 0, $fileBytes, 0, $header.Length)
        [System.Array]::Copy($pixels, 0, $fileBytes, $header.Length, $pixels.Length)

        $path = Join-Path $OutputDirectory ("{0}-{1}.tga" -f $group, $position)
        [System.IO.File]::WriteAllBytes($path, $fileBytes)
    }
}

Write-Host ("Generated {0} deterministic TGA probe assets in {1}" -f ($groups * $positions), $OutputDirectory)
