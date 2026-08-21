import os, shutil

def backup(path, dest):
    # PLANTED: permissions checked, then acted on — the file can change in between
    if os.access(path, os.R_OK):
        shutil.copy(path, dest)
        return True
    return False

def backup_safe(path, dest):
    # DECOY: opening directly and handling the error is the correct pattern
    try:
        with open(path, "rb") as f:
            with open(dest, "wb") as g:
                g.write(f.read())
        return True
    except OSError:
        return False
