#!/usr/bin/env python3
"""
Godot Debug Helper
==================
Runs Godot with full debugging output and captures all warnings, errors, and diagnostics.

FEATURES:
    🔍 Captures ALL output from Godot (errors, warnings, GDScript issues)
    📊 Categorizes and counts different types of issues
    🎨 Color-coded terminal output
    💾 Saves complete log to file
    📈 Provides detailed summary statistics
    ⏱️ Configurable timeout
    🔎 Filter output by pattern

QUICK START:
    # Run with GUI and show summary (default behavior)
    python3 scripts/debug_godot.py --summary

    # Quick check for specific issues
    python3 scripts/debug_godot.py --filter "COLLISION" --timeout 20
    python3 scripts/debug_godot.py --filter "STATIC_CALLED" --timeout 20

    # Headless mode for automated testing (30 seconds)
    python3 scripts/debug_godot.py --headless --timeout 30 --summary

    # Full verbose session with GUI
    python3 scripts/debug_godot.py --verbose

OPTIONS:
    --headless          Run Godot in headless mode (no GUI)
    --verbose           Show all output in real-time
    --filter PATTERN    Only show lines matching PATTERN
    --summary           Show summary of warnings/errors only
    --timeout SECONDS   Maximum runtime in seconds (default: 60)
    --output FILE       Save output to FILE (default: logs/godot_debug.log)

WHAT IT DETECTS:
    ❌ All ERROR messages
    ⚠️ All WARNING messages
    🔄 Entity spawn collisions
    🆔 Invalid UID warnings
    ⚡ Static function call warnings
    📝 GDScript warnings by file

OUTPUT:
    1. Terminal: Color-coded, categorized output
    2. Log File: Complete timestamped output (logs/godot_debug.log)
    3. Summary: Counts and examples of each issue type

EXAMPLES:
    # Run with GUI and show summary
    python3 scripts/debug_godot.py --summary

    # Run headless for 30 seconds
    python3 scripts/debug_godot.py --headless --timeout 30

    # Verbose output with filter
    python3 scripts/debug_godot.py --verbose --filter "ERROR"

    # Find all static warnings
    python3 scripts/debug_godot.py --filter "STATIC_CALLED" --timeout 20

    # Save to custom location with timestamp
    python3 scripts/debug_godot.py --output "logs/debug_$(date +%Y%m%d_%H%M%S).log"

    # Automated CI testing
    python3 scripts/debug_godot.py --headless --timeout 45 --summary

TIPS:
    - Use --headless for automated testing
    - Use --summary to avoid overwhelming output
    - Increase --timeout if testing long gameplay sessions
    - Use --filter to focus on specific issues
    - Check the log file for complete details and backtraces
"""

import subprocess
import sys
import os
import re
import argparse
from datetime import datetime
from pathlib import Path
from collections import defaultdict

class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    ERROR = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

class GodotDebugger:
    def __init__(self, args):
        self.args = args
        self.project_root = Path(__file__).parent.parent
        self.cat_dir = self.project_root / "cat"
        self.output_file = self.project_root / args.output

        # Statistics
        self.stats = {
            'errors': [],
            'warnings': [],
            'gdscript_warnings': defaultdict(list),
            'static_warnings': [],
            'collision_errors': [],
            'uid_warnings': [],
        }

        # Ensure logs directory exists
        self.output_file.parent.mkdir(parents=True, exist_ok=True)

    def run(self):
        """Main execution"""
        print(f"{Colors.HEADER}{Colors.BOLD}=== Godot Debug Runner ==={Colors.ENDC}")
        print(f"Project: {self.cat_dir}")
        print(f"Output: {self.output_file}")
        print(f"Mode: {'Headless' if self.args.headless else 'GUI'}")
        print(f"Timeout: {self.args.timeout}s\n")

        # Build Godot command
        cmd = self._build_command()

        # Run Godot and capture output
        try:
            print(f"{Colors.OKCYAN}Starting Godot...{Colors.ENDC}\n")
            self._run_godot(cmd)
        except KeyboardInterrupt:
            print(f"\n{Colors.WARNING}Interrupted by user{Colors.ENDC}")
        except subprocess.TimeoutExpired:
            print(f"\n{Colors.WARNING}Timeout reached ({self.args.timeout}s){Colors.ENDC}")

        # Show summary
        if self.args.summary or not self.args.verbose:
            self._print_summary()

    def _build_command(self):
        """Build Godot command with appropriate flags"""
        cmd = ["godot", "--path", str(self.cat_dir)]

        if self.args.headless:
            cmd.append("--headless")

        # Always add verbose flag for maximum output
        cmd.extend(["--verbose"])

        return cmd

    def _run_godot(self, cmd):
        """Run Godot and process output"""
        with open(self.output_file, 'w') as f:
            # Write header
            f.write(f"=== Godot Debug Log ===\n")
            f.write(f"Time: {datetime.now().isoformat()}\n")
            f.write(f"Command: {' '.join(cmd)}\n")
            f.write(f"{'=' * 80}\n\n")

            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1
            )

            try:
                for line in process.stdout:
                    # Write to file
                    f.write(line)
                    f.flush()

                    # Process line
                    self._process_line(line.rstrip())

                    # Show in terminal if verbose or matches filter
                    if self._should_show_line(line):
                        self._print_line(line.rstrip())

                process.wait(timeout=self.args.timeout)
            except subprocess.TimeoutExpired:
                process.kill()
                raise

    def _process_line(self, line):
        """Analyze line and categorize warnings/errors"""
        # Error patterns
        if "ERROR:" in line or line.strip().startswith("E "):
            self.stats['errors'].append(line)

            # Collision errors
            if "COLLISION!" in line:
                self.stats['collision_errors'].append(line)

        # Warning patterns
        if "WARNING:" in line or line.strip().startswith("W "):
            self.stats['warnings'].append(line)

            # UID warnings
            if "invalid UID" in line:
                self.stats['uid_warnings'].append(line)

        # GDScript static warnings
        if "STATIC_CALLED_ON_INSTANCE" in line:
            self.stats['static_warnings'].append(line)
            match = re.search(r'([\w_]+\.gd):\d+', line)
            if match:
                filename = match.group(1)
                self.stats['gdscript_warnings'][filename].append(line)

        # Other GDScript warnings
        gdscript_warning_pattern = re.compile(r'(SHADOWED_VARIABLE|UNUSED_VARIABLE|UNREACHABLE_CODE)')
        if gdscript_warning_pattern.search(line):
            match = re.search(r'([\w_]+\.gd):\d+', line)
            if match:
                filename = match.group(1)
                self.stats['gdscript_warnings'][filename].append(line)

    def _should_show_line(self, line):
        """Determine if line should be shown in terminal"""
        if self.args.verbose:
            return True

        if self.args.filter:
            return self.args.filter.lower() in line.lower()

        # Only show warnings and errors if not verbose
        return any(keyword in line for keyword in ['ERROR:', 'WARNING:', 'STATIC_CALLED_ON_INSTANCE', 'COLLISION'])

    def _print_line(self, line):
        """Print line with appropriate coloring"""
        if "ERROR:" in line or line.strip().startswith("E "):
            print(f"{Colors.ERROR}{line}{Colors.ENDC}")
        elif "WARNING:" in line or line.strip().startswith("W "):
            print(f"{Colors.WARNING}{line}{Colors.ENDC}")
        elif "STATIC_CALLED_ON_INSTANCE" in line:
            print(f"{Colors.OKCYAN}{line}{Colors.ENDC}")
        else:
            print(line)

    def _print_summary(self):
        """Print summary statistics"""
        print(f"\n{Colors.HEADER}{Colors.BOLD}=== Summary ==={Colors.ENDC}")
        print(f"{Colors.ERROR}Errors: {len(self.stats['errors'])}{Colors.ENDC}")
        print(f"{Colors.WARNING}Warnings: {len(self.stats['warnings'])}{Colors.ENDC}")

        if self.stats['collision_errors']:
            print(f"\n{Colors.ERROR}{Colors.BOLD}Entity Spawn Collisions: {len(self.stats['collision_errors'])}{Colors.ENDC}")
            print(f"  (Entities spawned on same tile - should be fixed now)")

        if self.stats['uid_warnings']:
            print(f"\n{Colors.WARNING}{Colors.BOLD}Invalid UID Warnings: {len(self.stats['uid_warnings'])}{Colors.ENDC}")
            for warning in self.stats['uid_warnings'][:5]:  # Show first 5
                print(f"  {warning}")
            if len(self.stats['uid_warnings']) > 5:
                print(f"  ... and {len(self.stats['uid_warnings']) - 5} more")

        if self.stats['static_warnings']:
            print(f"\n{Colors.OKCYAN}{Colors.BOLD}Static Function Warnings: {len(self.stats['static_warnings'])}{Colors.ENDC}")
            for warning in self.stats['static_warnings'][:5]:
                print(f"  {warning}")
            if len(self.stats['static_warnings']) > 5:
                print(f"  ... and {len(self.stats['static_warnings']) - 5} more")

        if self.stats['gdscript_warnings']:
            print(f"\n{Colors.OKCYAN}{Colors.BOLD}GDScript Warnings by File:{Colors.ENDC}")
            for filename, warnings in sorted(self.stats['gdscript_warnings'].items()):
                print(f"  {filename}: {len(warnings)} warnings")

        print(f"\n{Colors.OKGREEN}Full log saved to: {self.output_file}{Colors.ENDC}")
        print(f"{Colors.OKGREEN}Review the log file for complete details.{Colors.ENDC}\n")

def main():
    parser = argparse.ArgumentParser(
        description='Run Godot with full debugging output and capture all diagnostics',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run with GUI and show summary
  python3 scripts/debug_godot.py --summary

  # Run headless for 30 seconds
  python3 scripts/debug_godot.py --headless --timeout 30

  # Verbose output with filter
  python3 scripts/debug_godot.py --verbose --filter "ERROR"

  # Save to custom location
  python3 scripts/debug_godot.py --output custom_debug.log
        """
    )

    parser.add_argument('--headless', action='store_true',
                       help='Run Godot in headless mode (no GUI)')
    parser.add_argument('--verbose', action='store_true',
                       help='Show all output in real-time')
    parser.add_argument('--filter', type=str,
                       help='Only show lines matching PATTERN')
    parser.add_argument('--summary', action='store_true',
                       help='Show summary of warnings/errors only')
    parser.add_argument('--timeout', type=int, default=60,
                       help='Maximum runtime in seconds (default: 60)')
    parser.add_argument('--output', type=str, default='logs/godot_debug.log',
                       help='Save output to FILE (default: logs/godot_debug.log)')

    args = parser.parse_args()

    debugger = GodotDebugger(args)
    debugger.run()

if __name__ == '__main__':
    main()
