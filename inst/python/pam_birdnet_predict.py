#!/usr/bin/env python3
"""Run a custom BirdNET classifier on one batch of audio files for pamflow.

Uses the `birdnet` Python package (tested against 0.2.16, API < 0.3). pamflow
starts this script in a separate process, once per batch of files, so a crash
or a corrupt file cannot take down the R session.

Inputs
    --files   text file, one audio path per line (UTF-8)
    --model   custom classifier (.tflite)      --labels  its labels file
Outputs
    --out     CSV of detections: input, start_time, end_time, species_name,
              confidence (times in seconds from the start of the file)
    --status  CSV with one row per input file: input, ok, message
Exit status
    0  the batch ran (individual files may still be marked not ok)
    2  nothing could be run (model could not be loaded, bad arguments, ...)

Assumptions: input paths are absolute or resolvable from the working
directory; the labels file has one species per line, in model output order.
"""
import argparse
import csv
import sys
import time
import traceback
from pathlib import Path

EXIT_OK = 0
EXIT_FATAL = 2
FALLBACK_AUDIO_SUFFIXES = {".WAV", ".FLAC", ".MP3", ".OGG"}


def kill_children_with_me():
    """Windows only: make every process started from here die when this one does.

    The birdnet package starts worker processes. If this process is terminated
    (for example because the R call was interrupted), Windows would leave the
    workers running. A job object with the "kill on close" flag ends them all
    when this process exits. Best effort: any problem is ignored.
    """
    if sys.platform != "win32":
        return
    try:
        import ctypes
        from ctypes import wintypes

        class BasicLimits(ctypes.Structure):
            _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64),
                        ("PerJobUserTimeLimit", ctypes.c_int64),
                        ("LimitFlags", wintypes.DWORD),
                        ("MinimumWorkingSetSize", ctypes.c_size_t),
                        ("MaximumWorkingSetSize", ctypes.c_size_t),
                        ("ActiveProcessLimit", wintypes.DWORD),
                        ("Affinity", ctypes.c_size_t),
                        ("PriorityClass", wintypes.DWORD),
                        ("SchedulingClass", wintypes.DWORD)]

        class IoCounters(ctypes.Structure):
            _fields_ = [(name, ctypes.c_uint64) for name in (
                "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
                "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]

        class ExtendedLimits(ctypes.Structure):
            _fields_ = [("BasicLimitInformation", BasicLimits),
                        ("IoInfo", IoCounters),
                        ("ProcessMemoryLimit", ctypes.c_size_t),
                        ("JobMemoryLimit", ctypes.c_size_t),
                        ("PeakProcessMemoryUsed", ctypes.c_size_t),
                        ("PeakJobMemoryUsed", ctypes.c_size_t)]

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.CreateJobObjectW.restype = wintypes.HANDLE
        kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        kernel32.SetInformationJobObject.restype = wintypes.BOOL
        kernel32.SetInformationJobObject.argtypes = [
            wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
        kernel32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        kernel32.GetCurrentProcess.restype = wintypes.HANDLE

        job = kernel32.CreateJobObjectW(None, None)
        if not job:
            return
        limits = ExtendedLimits()
        limits.BasicLimitInformation.LimitFlags = 0x2000   # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        info_class = 9                                      # JobObjectExtendedLimitInformation
        if not kernel32.SetInformationJobObject(job, info_class, ctypes.byref(limits),
                                                ctypes.sizeof(limits)):
            return
        if kernel32.AssignProcessToJobObject(job, kernel32.GetCurrentProcess()):
            kill_children_with_me.handle = job              # keep the handle open until exit
    except Exception:
        pass


def build_parser():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--model", required=True, help="custom classifier .tflite")
    p.add_argument("--labels", required=True, help="labels file for the classifier")
    p.add_argument("--files", help="text file with one audio path per line")
    p.add_argument("--out", help="detections CSV to write")
    p.add_argument("--status", help="per-file status CSV to write")
    p.add_argument("--version", default="2.4", help="BirdNET model version (default 2.4)")
    p.add_argument("--min-confidence", type=float, default=0.1)
    p.add_argument("--overlap", type=float, default=0.0, help="seconds of overlap")
    p.add_argument("--fmin", type=int, default=0, help="bandpass low edge, Hz")
    p.add_argument("--fmax", type=int, default=15000, help="bandpass high edge, Hz")
    p.add_argument("--batch-size", type=int, default=1)
    p.add_argument("--n-workers", type=int, default=None,
                   help="worker processes (default: chosen by the birdnet package)")
    p.add_argument("--n-producers", type=int, default=1)
    p.add_argument("--top-k", type=int, default=0,
                   help="keep at most this many species per 3 s segment; 0 = no limit")
    p.add_argument("--sigmoid-sensitivity", type=float, default=1.0)
    p.add_argument("--device", default="CPU")
    p.add_argument("--skip-validity-check", action="store_true",
                   help="skip the (slow) model/labels consistency check")
    p.add_argument("--check", action="store_true",
                   help="only load the model and report versions, then exit")
    return p


def is_audio_file(path):
    """True if `path` is an existing file in a format the birdnet package reads."""
    p = Path(path)
    if not p.is_file():
        return False
    try:
        from birdnet.utils.helper import is_supported_audio_file
        return bool(is_supported_audio_file(p))
    except ImportError:
        return p.suffix.upper() in FALLBACK_AUDIO_SUFFIXES


def load_model(args):
    import birdnet
    return birdnet.load_custom(
        "acoustic", args.version, "tf", args.model, args.labels,
        check_validity=not args.skip_validity_check)


def read_file_list(path):
    with open(path, encoding="utf-8") as fh:
        return [line.strip() for line in fh if line.strip()]


def write_status(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["input", "ok", "message"])
        w.writerows(rows)


def write_detections(path, records, lookup):
    """Write detections; `lookup` maps absolute path -> the path as given to us."""
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["input", "start_time", "end_time", "species_name", "confidence"])
        for rec in records:
            absolute = str(rec["input"])
            w.writerow([lookup.get(absolute, absolute),
                        f"{float(rec['start_time']):.3f}",
                        f"{float(rec['end_time']):.3f}",
                        str(rec["species_name"]),
                        f"{float(rec['confidence']):.6f}"])


def run_batch(args):
    requested = read_file_list(args.files)
    rows = {}          # input as given -> (ok, message)
    runnable = []
    for given in requested:
        if is_audio_file(given):
            runnable.append(given)
        else:
            rows[given] = (False, "file missing or not a supported audio format")

    lookup = {str(Path(g).absolute()): g for g in runnable}
    records = []
    t0 = time.time()
    if runnable:
        model = load_model(args)
        result = model.predict(
            [Path(g) for g in runnable],
            top_k=None if args.top_k <= 0 else args.top_k,
            n_producers=args.n_producers,
            n_workers=args.n_workers,
            batch_size=args.batch_size,
            overlap_duration_s=args.overlap,
            bandpass_fmin=args.fmin,
            bandpass_fmax=args.fmax,
            apply_sigmoid=True,
            sigmoid_sensitivity=args.sigmoid_sensitivity,
            default_confidence_threshold=args.min_confidence,
            device=args.device,
            show_stats=None)
        failed = {str(Path(p).absolute()) for p in result.get_unprocessed_files()}
        for absolute, given in lookup.items():
            if absolute in failed:
                rows[given] = (False, "audio could not be processed (unreadable or corrupt)")
            else:
                rows[given] = (True, "")
        records = result.to_structured_array()

    write_detections(args.out, records, lookup)
    write_status(args.status, [(g, rows[g][0], rows[g][1]) for g in requested])
    print(f"PAMBATCH files={len(requested)} runnable={len(runnable)} "
          f"detections={len(records)} seconds={time.time() - t0:.1f}")


def main(argv=None):
    args = build_parser().parse_args(argv)
    kill_children_with_me()
    try:
        if args.check:
            from importlib import metadata
            load_model(args)
            try:
                version = metadata.version("birdnet")
            except metadata.PackageNotFoundError:
                version = "unknown"
            print(f"PAMCHECK birdnet={version} python={sys.version.split()[0]}")
            return EXIT_OK
        for needed in ("files", "out", "status"):
            if getattr(args, needed) is None:
                print(f"error: --{needed} is required unless --check is given",
                      file=sys.stderr)
                return EXIT_FATAL
        run_batch(args)
        return EXIT_OK
    except Exception:
        traceback.print_exc()
        return EXIT_FATAL


if __name__ == "__main__":   # required: the birdnet workers start with "spawn"
    sys.exit(main())
