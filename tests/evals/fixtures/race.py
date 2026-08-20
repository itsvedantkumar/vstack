import os

def claim_job(path):
    # PLANTED: check-then-act; two workers can both pass the exists() check
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write("claimed")
        return True
    return False

def claim_atomic(path):
    # DECOY: O_EXCL makes this correct
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
        return True
    except FileExistsError:
        return False
