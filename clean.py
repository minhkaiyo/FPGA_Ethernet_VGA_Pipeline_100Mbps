# -*- coding: utf-8 -*-
import os
import shutil
import glob
import sys

def clean_workspace(project_dir=None):
    if project_dir is None:
        project_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Use standard print but handle potential encoding issues on Windows consoles
    def safe_print(msg):
        try:
            print(msg)
        except UnicodeEncodeError:
            # Fallback to ascii representation if console doesn't support unicode
            try:
                print(msg.encode(sys.stdout.encoding, errors='replace').decode(sys.stdout.encoding))
            except Exception:
                print(msg.encode('ascii', errors='ignore').decode('ascii'))

    safe_print("=" * 60)
    safe_print("  CLEANING PROJECT WORKSPACE - FPGA ETHERNET VGA PIPELINE")
    safe_print("=" * 60)
    safe_print(f"Target directory: {project_dir}\n")

    cleaned_files = []
    
    # 1. Delete single temporary files
    single_files = ["vsim.wlf", "transcript", "modelsim.ini"]
    for file_name in single_files:
        file_path = os.path.join(project_dir, file_name)
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
                safe_print(f"  [x] Deleted file: {file_name}")
                cleaned_files.append(file_name)
            except Exception as e:
                safe_print(f"  [!] Error deleting {file_name}: {e}")

    # 2. Delete ModelSim temporary wlft* files
    wlft_pattern = os.path.join(project_dir, "wlft*")
    for file_path in glob.glob(wlft_pattern):
        file_name = os.path.basename(file_path)
        try:
            os.remove(file_path)
            safe_print(f"  [x] Deleted temp file: {file_name}")
            cleaned_files.append(file_name)
        except Exception as e:
            safe_print(f"  [!] Error deleting temp file {file_name}: {e}")

    # 3. Delete work directory (ModelSim compilation database)
    work_dir = os.path.join(project_dir, "work")
    if os.path.exists(work_dir) and os.path.isdir(work_dir):
        try:
            shutil.rmtree(work_dir)
            safe_print("  [x] Deleted compilation directory: work/")
            cleaned_files.append("work/")
        except Exception as e:
            safe_print(f"  [!] Error deleting work/ directory: {e}")

    safe_print("\n" + "=" * 60)
    if cleaned_files:
        safe_print(f"  Success! Cleaned up {len(cleaned_files)} clutter items.")
    else:
        safe_print("  Workspace is already neat and pristine!")
    safe_print("=" * 60)
    return cleaned_files

if __name__ == "__main__":
    clean_workspace()
