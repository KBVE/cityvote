#!/usr/bin/env python3
"""
Rust ⇄ Godot build synchroniser.

Rebuilds the GDExtension for host (macOS) and WebAssembly targets while keeping
the Godot plugin binaries under `cat/addons/godo/bin/` up to date. The script
mirrors the existing `rust/sync.sh` workflow, adds per-target build directories
to avoid Cargo locking, and wires in compiler caching (sccache/ccache) when
available. When both targets are requested the WASM build runs quietly in the
background so the native build stays responsive.
"""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional


class SyncError(RuntimeError):
    """Raised when one of the build steps fails."""


def run_command(
    command: List[str],
    *,
    cwd: Path,
    env: Dict[str, str],
    description: str,
    quiet: bool = False,
    log_file: Optional[Path] = None,
) -> None:
    """
    Run a command, streaming output to the terminal unless quiet=True.
    Optionally mirror output to a log file. Raises SyncError on failure.
    """
    print(f"→ {description}")
    log_handle = None
    try:
        if log_file:
            log_file.parent.mkdir(parents=True, exist_ok=True)
            log_handle = log_file.open("a", encoding="utf-8")
            log_handle.write(f"\n=== {description} @ {datetime.now().isoformat()} ===\n")

        process = subprocess.Popen(
            command,
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        assert process.stdout is not None  # silences mypy/pyright

        for line in process.stdout:
            if not quiet:
                print(line, end="")
            if log_handle:
                log_handle.write(line)

        return_code = process.wait()
    except FileNotFoundError as exc:
        raise SyncError(f"{description} failed; command not found: {command[0]}") from exc
    finally:
        if log_handle:
            log_handle.flush()
            log_handle.close()

    if return_code != 0:
        raise SyncError(f"{description} failed with exit code {return_code}")


def configure_cache(env: Dict[str, str], enable: bool) -> None:
    """Detect sccache/ccache and configure RUSTC_WRAPPER if requested."""
    if not enable:
        print("⚙ Cache: disabled by user.")
        return

    for tool in ("sccache", "ccache"):
        path = shutil.which(tool)
        if path:
            env["RUSTC_WRAPPER"] = path
            print(f"⚙ Cache: using {tool} via RUSTC_WRAPPER={path}")
            if tool == "sccache":
                subprocess.run([path, "--start-server"], check=False)
            return

    print("⚙ Cache: no sccache/ccache found in PATH, continuing without caching.")


def terminate_godot() -> None:
    """Attempt to terminate any running Godot editor processes."""
    try:
        result = subprocess.run(
            ["pkill", "-9", "Godot"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode == 0:
            print("✓ Terminated existing Godot processes.")
        else:
            print("ℹ No running Godot processes found (or unable to terminate).")
    except FileNotFoundError:
        print("⚠ 'pkill' not available; skipping Godot termination step.")


def create_plugin_structure(plugin_dir: Path) -> None:
    """Ensure the expected plugin bin directories are present."""
    (plugin_dir / "bin" / "debug").mkdir(parents=True, exist_ok=True)
    (plugin_dir / "bin" / "release").mkdir(parents=True, exist_ok=True)


def copy_artifact(src: Path, dest: Path) -> bool:
    """Copy an artifact if it exists; returns True when copied."""
    if not src.exists():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    print(f"  ✓ {src.name} → {dest}")
    return True


def finish_macos_binary(binary: Path) -> None:
    """Remove quarantine bit and re-sign the dylib on macOS."""
    if sys.platform != "darwin":
        return
    subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(binary)], check=False)
    subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=False)


def copy_native_artifacts(target_dir: Path, plugin_dir: Path) -> None:
    """Copy host platform binaries into the plugin."""
    debug_dest = plugin_dir / "bin" / "debug"
    release_dest = plugin_dir / "bin" / "release"

    if copy_artifact(target_dir / "debug" / "libgodo.dylib", debug_dest / "libgodo.dylib"):
        finish_macos_binary(debug_dest / "libgodo.dylib")
    if copy_artifact(target_dir / "release" / "libgodo.dylib", release_dest / "libgodo.dylib"):
        finish_macos_binary(release_dest / "libgodo.dylib")

    copy_artifact(target_dir / "debug" / "libgodo.so", debug_dest / "libgodo.so")
    copy_artifact(target_dir / "release" / "libgodo.so", release_dest / "libgodo.so")
    copy_artifact(target_dir / "debug" / "godo.dll", debug_dest / "godo.dll")
    copy_artifact(target_dir / "release" / "godo.dll", release_dest / "godo.dll")


def copy_wasm_artifacts(target_dir: Path, plugin_dir: Path) -> None:
    """Locate the generated WASM files and copy them into the plugin."""
    wasm_debug_candidates = [
        target_dir / "wasm32-unknown-emscripten" / "dev-wasm" / "godo.wasm",
        target_dir / "wasm32-unknown-emscripten" / "debug" / "godo.wasm",
    ]
    wasm_release = target_dir / "wasm32-unknown-emscripten" / "release" / "godo.wasm"

    debug_dest = plugin_dir / "bin" / "debug" / "godo.wasm"
    release_dest = plugin_dir / "bin" / "release" / "godo.wasm"

    for candidate in wasm_debug_candidates:
        if copy_artifact(candidate, debug_dest):
            break

    copy_artifact(wasm_release, release_dest)


def archive_godot_logs(log_file: Path, archive_file: Path, archive_limit: int = 100_000) -> None:
    """Archive the previous Godot log if present and trim the archive."""
    if archive_file.exists():
        try:
            with archive_file.open("r", encoding="utf-8") as handle:
                line_count = sum(1 for _ in handle)
            if line_count > archive_limit:
                print(f"ℹ Log archive exceeds {archive_limit} lines; resetting.")
                archive_file.write_text("", encoding="utf-8")
        except OSError:
            pass

    if log_file.exists() and log_file.stat().st_size > 0:
        try:
            with archive_file.open("a", encoding="utf-8") as archive, log_file.open(
                "r", encoding="utf-8"
            ) as current:
                archive.write(f"----- Archived on {datetime.now():%Y-%m-%d %H:%M:%S} -----\n")
                shutil.copyfileobj(current, archive)
                archive.write("\n")
        except OSError:
            pass
    log_file.write_text("", encoding="utf-8")


def restart_godot(afk_dir: Path, log_file: Path) -> None:
    """Launch the Godot editor in the background and tee output into logs."""
    godot_path = shutil.which("godot")
    if not godot_path:
        print("⚠ 'godot' CLI not found; please start the editor manually.")
        return

    print("Launching Godot editor in the background...")
    log_handle = log_file.open("a", encoding="utf-8")
    try:
        subprocess.Popen(
            [godot_path, "--editor", "--path", str(afk_dir)],
            cwd=str(afk_dir),
            stdout=log_handle,
            stderr=subprocess.STDOUT,
        )
        print(f"✓ Godot editor launched (logs → {log_file}).")
    except Exception as exc:  # pragma: no cover - defensive
        print(f"⚠ Unable to launch Godot: {exc}")
        log_handle.close()
        raise


def build_mac(
    env: Dict[str, str],
    rust_dir: Path,
    target_dir: Path,
    plugin_dir: Path,
) -> None:
    """Build debug and release dylibs and copy them into the plugin."""
    run_command(
        ["cargo", "build"],
        cwd=rust_dir,
        env=env,
        description="Building macOS debug",
    )
    run_command(
        ["cargo", "build", "--release"],
        cwd=rust_dir,
        env=env,
        description="Building macOS release",
    )
    copy_native_artifacts(target_dir, plugin_dir)
    print("✓ macOS binaries ready.")


def build_wasm(
    env: Dict[str, str],
    rust_dir: Path,
    target_dir: Path,
    plugin_dir: Path,
    quiet: bool,
    log_file: Path,
) -> None:
    """Build WASM artifacts (debug + release) and copy them into the plugin."""
    if not shutil.which("emcc"):
        print("⚠ emcc not found; skipping WASM build.")
        return

    debug_env = env.copy()
    debug_env.update(
        {
            "CARGO_PROFILE_DEV_DEBUG": "false",
            "CARGO_PROFILE_DEV_OPT_LEVEL": "s",
            "CARGO_PROFILE_DEV_STRIP": "debuginfo",
            "CARGO_PROFILE_DEV_PANIC": "abort",
            "CARGO_PROFILE_DEV_LTO": "thin",
            "CARGO_PROFILE_DEV_CODEGEN_UNITS": "1",
            "CARGO_PROFILE_DEV_INCREMENTAL": "false",
        }
    )

    run_command(
        ["cargo", "+nightly", "build", "-Zbuild-std=std,panic_abort", "--target", "wasm32-unknown-emscripten"],
        cwd=rust_dir,
        env=debug_env,
        description="Building WASM debug",
        quiet=quiet,
        log_file=log_file,
    )

    run_command(
        [
            "cargo",
            "+nightly",
            "build",
            "-Zbuild-std=std,panic_abort",
            "--target",
            "wasm32-unknown-emscripten",
            "--release",
        ],
        cwd=rust_dir,
        env=env,
        description="Building WASM release",
        quiet=quiet,
        log_file=log_file,
    )

    copy_wasm_artifacts(target_dir, plugin_dir)
    print("✓ WASM binaries copied.")


def run_wasm_background(
    env: Dict[str, str],
    rust_dir: Path,
    target_dir: Path,
    plugin_dir: Path,
    log_file: Path,
) -> threading.Thread:
    """Execute the WASM workflow in a background thread."""
    result: Dict[str, Optional[Exception]] = {"error": None}

    def worker() -> None:
        try:
            build_wasm(
                env=env,
                rust_dir=rust_dir,
                target_dir=target_dir,
                plugin_dir=plugin_dir,
                quiet=True,
                log_file=log_file,
            )
        except Exception as exc:
            result["error"] = exc

    thread = threading.Thread(target=worker, name="wasm-build", daemon=True)
    thread.result = result  # type: ignore[attr-defined]
    thread.start()
    return thread


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build and sync the Rust GDExtension binaries for Godot.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--mac",
        action="store_true",
        help="Build macOS artifacts only (combine with --wasm to build both).",
    )
    parser.add_argument(
        "--wasm",
        action="store_true",
        help="Build WASM artifacts only (combine with --mac to build both).",
    )
    parser.add_argument(
        "--no-background-wasm",
        action="store_true",
        help="Run WASM build in the foreground even when building macOS.",
    )
    parser.add_argument(
        "--cache",
        dest="cache",
        action="store_true",
        help="Enable sccache/ccache if available.",
    )
    parser.add_argument(
        "--no-cache",
        dest="cache",
        action="store_false",
        help="Disable compiler cache usage.",
    )
    parser.add_argument(
        "--skip-godot-restart",
        action="store_true",
        help="Do not relaunch the Godot editor after syncing binaries.",
    )
    parser.set_defaults(cache=True)

    args = parser.parse_args()

    # Determine which targets to build.
    targets = set()
    if args.mac:
        targets.add("mac")
    if args.wasm:
        targets.add("wasm")
    if not targets:
        targets = {"mac", "wasm"}

    project_root = Path(__file__).resolve().parent.parent
    rust_dir = project_root / "rust"
    afk_dir = project_root / "cat"
    plugin_dir = afk_dir / "addons" / "godo"

    target_dirs = {
        "mac": rust_dir / "target-mac",
        "wasm": rust_dir / "target-wasm",
    }

    base_env = os.environ.copy()
    rustup_bin = Path.home() / ".cargo" / "bin"
    path_entries = [entry for entry in base_env.get("PATH", "").split(os.pathsep) if entry]
    if rustup_bin.exists() and str(rustup_bin) not in path_entries:
        base_env["PATH"] = os.pathsep.join([str(rustup_bin)] + path_entries)

    cargo_env = Path.home() / ".cargo" / "env"
    if cargo_env.exists():
        try:
            result = subprocess.run(
                ["bash", "-lc", f'source {shlex.quote(str(cargo_env))} >/dev/null 2>&1 && env'],
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            )
            for line in result.stdout.splitlines():
                if "=" not in line:
                    continue
                key, _, value = line.partition("=")
                base_env[key] = value
        except subprocess.CalledProcessError:
            pass

    configure_cache(base_env, enable=args.cache)

    print("======================================")
    print("Godo GDExtension Build & Sync (Python)")
    print("======================================")
    print(f"Project root: {project_root}")
    print(f"Rust crate:   {rust_dir}")
    print(f"Plugin dir:   {plugin_dir}")
    print(f"Targets:      {', '.join(sorted(targets))}")
    print("")

    terminate_godot()
    create_plugin_structure(plugin_dir)

    threads: List[threading.Thread] = []
    run_wasm_sync = False
    wasm_thread: Optional[threading.Thread] = None
    wasm_env: Optional[Dict[str, str]] = None
    wasm_log = rust_dir / "logs" / "wasm_build.log"

    if "wasm" in targets:
        wasm_env = base_env.copy()
        wasm_env["CARGO_TARGET_DIR"] = str(target_dirs["wasm"])
        if "mac" in targets and not args.no_background_wasm:
            print("Starting WASM build in the background (logs → rust/logs/wasm_build.log).")
            wasm_thread = run_wasm_background(
                env=wasm_env,
                rust_dir=rust_dir,
                target_dir=target_dirs["wasm"],
                plugin_dir=plugin_dir,
                log_file=wasm_log,
            )
            threads.append(wasm_thread)
        else:
            run_wasm_sync = True
    else:
        print("Skipping WASM build.")

    if "mac" in targets:
        mac_env = base_env.copy()
        mac_env["CARGO_TARGET_DIR"] = str(target_dirs["mac"])
        try:
            build_mac(mac_env, rust_dir, target_dirs["mac"], plugin_dir)
        except SyncError as exc:
            print(f"✗ macOS build failed: {exc}")
            sys.exit(1)
    else:
        print("Skipping macOS build.")

    if run_wasm_sync and wasm_env is not None:
        try:
            build_wasm(
                env=wasm_env,
                rust_dir=rust_dir,
                target_dir=target_dirs["wasm"],
                plugin_dir=plugin_dir,
                quiet=False,
                log_file=wasm_log,
            )
        except SyncError as exc:
            print(f"✗ WASM build failed: {exc}")
            sys.exit(1)

    for thread in threads:
        thread.join()
        result = getattr(thread, "result", None)
        if isinstance(result, dict) and result.get("error"):
            print(f"✗ Background WASM build failed: {result['error']}")
            sys.exit(1)

    log_file = rust_dir / "logs.txt"
    archive_file = rust_dir / "logs_archive.txt"
    archive_godot_logs(log_file, archive_file)

    if not args.skip_godot_restart:
        restart_godot(afk_dir, log_file)

    print("")
    print("======================================")
    print("✓ Sync complete!")
    print("======================================")


if __name__ == "__main__":
    main()
