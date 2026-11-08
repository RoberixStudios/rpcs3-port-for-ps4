param(
    # Default tool locations are folders next to this checkout.
    [string]$Sdk = [IO.Path]::GetFullPath("$PSScriptRoot/../../RoberixUSB/tools/OpenOrbis/PS4Toolchain").Replace('\', '/'),
    [string]$Llvm = [IO.Path]::GetFullPath("$PSScriptRoot/../../ps4-usb-pad/tools/llvm-mingw-20240619-ucrt-x86_64/bin").Replace('\', '/'),
    [string]$Bash = 'C:/Program Files/Git/usr/bin/bash.exe',
    [string]$Make = "$PSScriptRoot/.build-tools/usr/bin/make.exe",
    [int]$Jobs = 4,
    [switch]$ConfigureOnly
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'deps/ffmpeg'
$revision = '239f2c733de417201d7ad3b3b8b0d9b63285b2b1' # FFmpeg n8.1.1

# CMake/Ninja may request the multi-output FFmpeg rule from more than one
# dependency edge. Serialize checkout so two PowerShell processes cannot race
# while creating the same source directory.
$checkoutMutex = [System.Threading.Mutex]::new($false, 'Local\RPCS3PS4FFmpegCheckout')
$checkoutLock = $false
try {
    $checkoutLock = $checkoutMutex.WaitOne([TimeSpan]::FromMinutes(10))
    if (!$checkoutLock) { throw 'Timed out waiting for the FFmpeg checkout lock' }

    if (!(Test-Path (Join-Path $source 'configure'))) {
        # A previous interrupted clone or an empty directory is not a usable
        # checkout. Recreate this generated dependency directory cleanly.
        if (Test-Path -LiteralPath $source) {
            Remove-Item -LiteralPath $source -Recurse -Force
        }
        & git -c credential.interactive=never -c http.sslBackend=openssl clone --depth 1 --branch n8.1.1 https://github.com/FFmpeg/FFmpeg.git $source
        if ($LASTEXITCODE) { throw 'FFmpeg checkout failed' }
    }

    $actual = & git -C $source rev-parse HEAD
    if ($LASTEXITCODE -or $actual -ne $revision) { throw "Unexpected FFmpeg revision: $actual" }
}
finally {
    if ($checkoutLock) { $checkoutMutex.ReleaseMutex() }
    $checkoutMutex.Dispose()
}
foreach ($library in 'libavcodec', 'libavutil', 'libavformat', 'libswscale', 'libswresample') {
    $original = Join-Path $PSScriptRoot "../3rdparty/ffmpeg/include/$library/version.h"
    $selected = Join-Path $source "$library/version.h"
    $expected = (Select-String -Path $original -Pattern '^#define LIB[A-Z]+_VERSION_(MAJOR|MINOR|MICRO)\s+\d+').Line
    $found = (Select-String -Path $selected -Pattern '^#define LIB[A-Z]+_VERSION_(MAJOR|MINOR|MICRO)\s+\d+').Line
    if (($expected -join "`n") -ne ($found -join "`n")) { throw "FFmpeg header version mismatch: $library" }
}
$repo = (Resolve-Path "$PSScriptRoot/..").Path.Replace('\', '/')
$sdkPath = (Resolve-Path $Sdk).Path.Replace('\', '/')
$llvmPath = (Resolve-Path $Llvm).Path.Replace('\', '/')
$linker = "$repo/ps4-port/.build-abi/ps4-port/rpcs3-ps4-ld.exe"
if (!(Test-Path $linker)) { throw 'Build the rpcs3_ps4_linker target first' }
New-Item -ItemType Directory -Force "$source/.ps4-tools" | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)
function Write-ToolFile([string]$Name, [string]$Content) {
    [System.IO.File]::WriteAllText("$source/.ps4-tools/$Name", $Content.Replace("`r`n", "`n"), $utf8)
}
$cflags = @"
--target=x86_64-pc-freebsd12-elf
-fPIC
-mcx16
-D__ORBIS__
-D__PS4__
-D_BSD_SOURCE=1
-D_POSIX_C_SOURCE=200809L
-isystem "$sdkPath/include"
-I "$repo/../orbis-compat/include"
"@
Write-ToolFile 'cflags.rsp' $cflags
Write-ToolFile 'ldflags.rsp' @"
-fuse-ld="$linker"
-nostdlib
-pie
-Wl,-m,elf_x86_64
-Wl,-T,"$sdkPath/link.x"
-Wl,--eh-frame-hdr
-Wl,--no-dynamic-linker
-L "$sdkPath/lib"
"@
Write-ToolFile 'cc' "#!/usr/bin/env bash`nexec '$llvmPath/clang.exe' @.ps4-tools/cflags.rsp `"`$@`"`n"
Write-ToolFile 'ld' "#!/usr/bin/env bash`nexec '$llvmPath/clang.exe' @.ps4-tools/cflags.rsp @.ps4-tools/ldflags.rsp `"`$@`" '$sdkPath/lib/crt1.o'`n"
foreach ($tool in 'ar', 'ranlib', 'nm', 'strip') {
    Write-ToolFile $tool "#!/usr/bin/env bash`nexec '$llvmPath/llvm-$tool.exe' `"`$@`"`n"
}
Write-ToolFile 'hostcc' "#!/usr/bin/env bash`nexec '$llvmPath/clang.exe' `"`$@`"`n"
# 0.33: the second decoder/demuxer lines and the pcm_mulaw/pcm_f32be encoders bring the component set closer to the
# PC build. cellRec selects pcm_mulaw/pcm_f32be (video_encoder fails without them); media_utils (cellSearch, cellMusic)
# opens flac/ogg/opus/wma/ac3/mp2/mkv/ts files. All are plain C in this tree (opus needs libswresample, built below);
# no external library. x86asm stays off: no NASM/yasm on this machine, so the SIMD bodies cannot be assembled.
$build = @'
#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:$PATH"
chmod +x .ps4-tools/{cc,ld,ar,ranlib,nm,strip,hostcc}
./configure --enable-cross-compile --target-os=freebsd --arch=x86_64 --cpu=btver2 \
  --cc=./.ps4-tools/cc --ld=./.ps4-tools/ld --ar=./.ps4-tools/ar \
  --ranlib=./.ps4-tools/ranlib --nm=./.ps4-tools/nm --strip=./.ps4-tools/strip \
  --host-cc=./.ps4-tools/hostcc --disable-x86asm --enable-pic \
  --disable-shared --enable-static --disable-programs --disable-doc --disable-autodetect \
  --disable-everything --disable-network --enable-runtime-cpudetect \
  --enable-decoder=aac,aac_latm,atrac3,atrac3p,atrac9,mp3,pcm_s16le,pcm_s8,h264,mpeg4,mpeg2video,mjpeg,mjpegb \
  --enable-decoder=flac,vorbis,opus,alac,wmav1,wmav2,ac3,eac3,mp1,mp2,mp3float,pcm_s16be,pcm_s24le,pcm_f32le \
  --enable-encoder=pcm_s16le,ac3,aac,ffv1,mpeg4,mjpeg,pcm_mulaw,pcm_f32be \
  --enable-muxer=avi,h264,mjpeg,mp4 \
  --enable-demuxer=h264,m4v,mp3,mpegvideo,mpegps,mjpeg,mov,avi,aac,pmp,oma,pcm_s16le,pcm_s8,wav \
  --enable-demuxer=ogg,flac,asf,matroska,mpegts,ac3 \
  --enable-parser=h264,mpeg4video,mpegaudio,mpegvideo,mjpeg,aac,aac_latm,ac3,flac,vorbis,opus \
  --enable-protocol=file --enable-bsf=mjpeg2jpeg --extra-libs='-lc -lm -lkernel'
if [[ "${RPCS3_PS4_CONFIGURE_ONLY:-0}" != 1 ]]; then
  "$RPCS3_PS4_MAKE" -j"$RPCS3_PS4_JOBS" V=1 SHELL="$RPCS3_PS4_BASH" \
    libavcodec/libavcodec.a libavutil/libavutil.a libavformat/libavformat.a \
    libswscale/libswscale.a libswresample/libswresample.a
fi
'@
Write-ToolFile 'build.sh' $build
if (!(Test-Path $Make)) { throw 'Run ps4-port/prepare-make.ps1 to prepare MSYS GNU Make' }
$env:RPCS3_PS4_MAKE = (Resolve-Path $Make).Path.Replace('\', '/')
$env:RPCS3_PS4_BASH = '/usr/bin/bash'
$env:RPCS3_PS4_JOBS = "$Jobs"
$env:RPCS3_PS4_CONFIGURE_ONLY = [int]$ConfigureOnly.IsPresent
$previousPath = $env:PATH
$env:PATH = "$(Split-Path $Bash);$env:PATH"
Push-Location $source
try {
    & $Bash .ps4-tools/build.sh
    if ($LASTEXITCODE) { throw 'PS4 FFmpeg build failed; see deps/ffmpeg/ffbuild/config.log' }
} finally { Pop-Location; $env:PATH = $previousPath }
