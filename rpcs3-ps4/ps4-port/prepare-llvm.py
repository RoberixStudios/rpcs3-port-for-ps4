"""Prepare the pinned RPCS3 LLVM source for the OpenOrbis libc/kernel boundary.

The SDK uses musl POSIX headers and the Orbis kernel, not a FreeBSD userspace.
Keep every architecture-independent compiler implementation unchanged; adapt
only OS discovery, thread metadata and process symbol lookup. Reapply from the verified source archive
so rerunning preparation is deterministic rather than stacking substitutions.
"""
from pathlib import Path
import hashlib
import json
import re
import tarfile

ROOT = Path(__file__).resolve().parent
COMMIT = "ca7933e47d3a3451d81e72ac174dcb5aa28b59d1"
ARCHIVE_SHA256 = "9dd0aba32a0c2b9e8e808e9b67502cc977f22220f67268bbfd937fa07e5ee6ce"
name = "llvm-project-" + COMMIT
archive = ROOT / "deps" / (name + ".tar.gz")
source = ROOT / "deps" / name
with archive.open("rb") as f:
    if hashlib.file_digest(f, "sha256").hexdigest() != ARCHIVE_SHA256:
        raise RuntimeError("The pinned LLVM source archive hash does not match")

manifest = {"commit": COMMIT, "archive_sha256": ARCHIVE_SHA256, "files": {}}
with tarfile.open(archive, "r:gz") as tf:
    for relative in ("llvm/lib/Support/Unix/Threading.inc", "llvm/lib/Support/Unix/Path.inc", "llvm/lib/Support/Unix/Process.inc", "llvm/lib/Support/Unix/DynamicLibrary.inc"):
        original = tf.extractfile(name + "/" + relative).read()
        text = original.decode()
        # Do not select FreeBSD sysctl/kinfo_proc/aux-vector/statfs APIs merely
        # because the compiler target is FreeBSD. Use LLVM's POSIX implementations.
        text = text.replace("defined(__FreeBSD__)", "(defined(__FreeBSD__) && !defined(RPCS3_PS4))")
        text = text.replace("defined(__FreeBSD_kernel__)", "(defined(__FreeBSD_kernel__) && !defined(RPCS3_PS4))")
        if relative.endswith("Threading.inc"):
            text = text.replace("#ifndef __FreeBSD__", "#if !defined(__FreeBSD__) || defined(RPCS3_PS4)")
            text = text.replace('#include <pthread.h>', '#include <pthread.h>\n#ifdef RPCS3_PS4\n#include <orbis/libkernel.h>\n#include <unistd.h>\n#endif', 1)
            text = text.replace('uint64_t llvm::get_threadid() {\n#if defined(__APPLE__)',
                'uint64_t llvm::get_threadid() {\n#if defined(RPCS3_PS4)\n  return uint64_t(scePthreadGetthreadid());\n#elif defined(__APPLE__)')
            text = text.replace('static constexpr uint32_t get_max_thread_name_length_impl() {\n#if defined(PTHREAD_MAX_NAMELEN_NP)',
                'static constexpr uint32_t get_max_thread_name_length_impl() {\n#if defined(RPCS3_PS4)\n  return 32;\n#elif defined(PTHREAD_MAX_NAMELEN_NP)', 1)
            text = text.replace('static int computeHostNumHardwareThreads() {\n#if ',
                'static int computeHostNumHardwareThreads() {\n#if defined(RPCS3_PS4)\n  return std::max(1L, sysconf(_SC_NPROCESSORS_ONLN));\n#elif ', 1)
            text = text.replace('#if defined(HAVE_PTHREAD_SET_NAME_NP) && HAVE_PTHREAD_SET_NAME_NP',
                '#if defined(RPCS3_PS4)\n  scePthreadRename(scePthreadSelf(), NameStr.data());\n#elif defined(HAVE_PTHREAD_SET_NAME_NP) && HAVE_PTHREAD_SET_NAME_NP', 1)
            text = text.replace('  Name.clear();\n\n#if ',
                '  Name.clear();\n\n#if defined(RPCS3_PS4)\n  char buffer[32]{};\n  if (scePthreadGetname(scePthreadSelf(), buffer) == 0)\n    Name.append(buffer, buffer + strlen(buffer));\n#elif ', 1)
        elif relative.endswith("Path.inc"):
            text = text.replace('#if defined(__NetBSD__) || defined(__DragonFly__) || defined(__GNU__) ||',
                '#if defined(RPCS3_PS4) || defined(__NetBSD__) || defined(__DragonFly__) || defined(__GNU__) ||', 1)
            anchor = '  auto BypassSandbox = sandbox::scopedDisable();\n\n#if defined(__APPLE__)'
            if text.count(anchor) != 1:
                raise RuntimeError("LLVM executable discovery changed")
            text = text.replace(anchor, '  auto BypassSandbox = sandbox::scopedDisable();\n\n#if defined(RPCS3_PS4)\n  return "/app0/eboot.bin";\n#elif defined(__APPLE__)', 1)
            text = text.replace('return !!(STATVFS_F_FLAG(Vfs) & MNT_LOCAL);',
                '#ifdef RPCS3_PS4\n  // All filesystems mounted in the application sandbox are local.\n  return true;\n#else\n  return !!(STATVFS_F_FLAG(Vfs) & MNT_LOCAL);\n#endif', 1)
        elif relative.endswith("Process.inc"):
            # No terminal belongs to a PS4 application. The SDK ioctl header
            # intentionally does not offer a usable winsize request.
            text = text.replace('#if defined(HAVE_SYS_IOCTL_H) && !defined(__sun__)',
                '#if defined(HAVE_SYS_IOCTL_H) && !defined(__sun__) && defined(TIOCGWINSZ)', 1)
            text = text.replace('Expected<unsigned> Process::getPageSize() {\n#if defined(HAVE_GETAUXVAL)',
                'Expected<unsigned> Process::getPageSize() {\n#if defined(RPCS3_PS4)\n  static const long page_size = ::sysconf(_SC_PAGESIZE);\n#elif defined(HAVE_GETAUXVAL)', 1)
        else:
            anchor = '#if defined(HAVE_DLOPEN)'
            if text.count(anchor) != 1:
                raise RuntimeError("LLVM process symbol support changed")
            native = '''#if defined(RPCS3_PS4)
#include <llvm_ps4_process.hpp>

static llvm::sys::ps4::process_symbols &PS4ProcessSymbols() {
  static llvm::sys::ps4::process_symbols Process;
  return Process;
}

DynamicLibrary::HandleSet::~HandleSet() {
  DynamicLibrary::SearchOrder = DynamicLibrary::SO_Linker;
}

void *DynamicLibrary::HandleSet::DLOpen(const char *File, std::string *Err) {
  if (File) {
    if (Err) *Err = "LLVM cannot load named shared libraries through OpenOrbis libc";
    return &DynamicLibrary::Invalid;
  }
  auto &Process = PS4ProcessSymbols();
  return Process.refresh(Err) ? static_cast<void *>(&Process) : &DynamicLibrary::Invalid;
}

void DynamicLibrary::HandleSet::DLClose(void *) {
  // The process namespace borrows PRX handles owned by the application/kernel.
}

void *DynamicLibrary::HandleSet::DLSym(void *Handle, const char *Symbol) {
  auto &Process = PS4ProcessSymbols();
  return Handle == &Process ? Process.find(Symbol) : nullptr;
}

#elif defined(HAVE_DLOPEN)'''
            text = text.replace(anchor, native, 1)
        updated = text.encode()
        dest = source / relative
        if dest.read_bytes() != updated:
            dest.write_bytes(updated)
        manifest["files"][relative] = {"original_sha256": hashlib.sha256(original).hexdigest(),
            "prepared_sha256": hashlib.sha256(updated).hexdigest()}
manifest["port_helpers"] = {"compat/llvm_ps4_process.hpp":
    hashlib.sha256((ROOT / "compat/llvm_ps4_process.hpp").read_bytes()).hexdigest()}
output = ROOT / ".build-native-package" / "llvm-source-preparation.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(manifest, indent=2) + "\n")
print("Prepared pinned LLVM OS support:", output)
