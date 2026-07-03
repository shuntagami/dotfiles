#!/usr/bin/env python3
"""VFR動画を音声同期を保ったままRIFE補間でCFR化する。

各実フレームのPTSを読み取り、目標fpsグリッド上の本来の時刻位置に配置。
欠けているスロットだけをRIFE(v4.6)の任意タイムステップ補間で生成する。
音声は無劣化コピーし、mux後にstart_timeのズレを測定して自動補正する。

使い方:
  python3 vfr_sync_rife.py INPUT [INPUT...] [-o OUTDIR] [--fps N] [--crf 18]
                           [--workers 3] [--suffix _sync] [--keep-temp]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIFE_BIN = os.path.join(SKILL_DIR, "bin", "rife-ncnn-vulkan")
RIFE_MODEL = os.path.join(SKILL_DIR, "bin", "rife-v4.6")

AUDIO_START_TOLERANCE = 0.005  # 秒。これ以内なら同期OKとみなす


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def probe(path):
    out = run(["ffprobe", "-v", "error", "-show_streams", "-show_format",
               "-of", "json", path]).stdout
    d = json.loads(out)
    v = next((s for s in d["streams"] if s["codec_type"] == "video"), None)
    a = next((s for s in d["streams"] if s["codec_type"] == "audio"), None)
    return d["format"], v, a


def get_pts(path):
    out = run(["ffprobe", "-v", "error", "-select_streams", "v:0",
               "-show_entries", "packet=pts_time", "-of", "csv=p=0", path]).stdout
    return sorted(float(l) for l in out.splitlines() if l.strip())


def audio_start(path):
    _, _, a = probe(path)
    return float(a.get("start_time", 0)) if a else None


def color_args(v):
    args = []
    for probe_key, opt in [("color_space", "-colorspace"),
                           ("color_primaries", "-color_primaries"),
                           ("color_transfer", "-color_trc")]:
        val = v.get(probe_key)
        if val and val != "unknown":
            args += [opt, val]
    return args


def process(input_path, outdir, fps_override, crf, workers, keep_temp):
    name = os.path.splitext(os.path.basename(input_path))[0]
    fmt, v, a = probe(input_path)
    if v is None:
        print(f"[{name}] 映像ストリームがありません。スキップ")
        return False

    num, den = v["r_frame_rate"].split("/")
    nominal = float(num) / float(den)
    fps = fps_override or round(nominal)
    if fps <= 0 or fps > 240:
        fps = 30

    pts = get_pts(input_path)
    origin = pts[0]
    n_slots = round((pts[-1] - origin) * fps) + 1
    avg_fps = (len(pts) - 1) / (pts[-1] - origin) if pts[-1] > origin else fps
    print(f"[{name}] 表記{nominal:.4g}fps 実測平均{avg_fps:.2f}fps "
          f"実フレーム{len(pts)} → グリッド{n_slots}スロット@{fps}fps")

    # 実フレームを最寄りスロットへ割当(衝突時は誤差が小さい方を採用)
    slot_map = {}
    for i, p in enumerate(pts, start=1):
        k = min(n_slots - 1, max(0, round((p - origin) * fps)))
        err = abs((p - origin) - k / fps)
        if k not in slot_map or err < slot_map[k][1]:
            slot_map[k] = (i, err)
    real_slots = sorted(slot_map)
    missing = n_slots - len(real_slots)
    print(f"[{name}] 配置{len(real_slots)}枚(衝突棄却{len(pts)-len(real_slots)}) "
          f"欠損{missing}スロットを補間")

    workdir = tempfile.mkdtemp(prefix=f"vfr_sync_{name}_")
    real_dir = os.path.join(workdir, "real")
    slot_dir = os.path.join(workdir, "slots")
    os.makedirs(real_dir)
    os.makedirs(slot_dir)
    try:
        # 全フレーム抽出(タイムスタンプ保持デコード順)
        run(["ffmpeg", "-y", "-v", "error", "-i", input_path,
             "-fps_mode", "passthrough",
             os.path.join(real_dir, "%06d.png")])
        n_extracted = len(os.listdir(real_dir))
        if n_extracted != len(pts):
            print(f"[{name}] 警告: 抽出枚数{n_extracted} != パケット数{len(pts)}。"
                  "少ない方に合わせます")

        for k in real_slots:
            idx = slot_map[k][0]
            if idx <= n_extracted:
                os.link(os.path.join(real_dir, f"{idx:06d}.png"),
                        os.path.join(slot_dir, f"{k:06d}.png"))
        placed = sorted(int(f[:6]) for f in os.listdir(slot_dir))

        # 補間計画: 中間はRIFE、両端の欠損は最近傍複製
        jobs, copies = [], []
        placed_set = set(placed)
        prev = None
        nxt_iter = iter(placed)
        nxt = next(nxt_iter, None)
        for k in range(n_slots):
            if k in placed_set:
                prev = k
                if nxt is not None and k >= nxt:
                    nxt = next(nxt_iter, None)
                continue
            while nxt is not None and nxt < k:
                nxt = next(nxt_iter, None)
            if prev is None:
                copies.append((nxt, k))
            elif nxt is None:
                copies.append((prev, k))
            else:
                jobs.append((prev, nxt, k, (k - prev) / (nxt - prev)))
        for src, k in copies:
            shutil.copy(os.path.join(slot_dir, f"{src:06d}.png"),
                        os.path.join(slot_dir, f"{k:06d}.png"))

        done = [0]

        def rife(job):
            a_, b_, k, s = job
            subprocess.run(
                [RIFE_BIN,
                 "-0", os.path.join(slot_dir, f"{a_:06d}.png"),
                 "-1", os.path.join(slot_dir, f"{b_:06d}.png"),
                 "-o", os.path.join(slot_dir, f"{k:06d}.png"),
                 "-m", RIFE_MODEL, "-s", f"{s:.6f}"],
                check=True, capture_output=True)
            done[0] += 1
            if done[0] % 100 == 0:
                print(f"[{name}] RIFE {done[0]}/{len(jobs)}", flush=True)

        with ThreadPoolExecutor(max_workers=workers) as ex:
            list(ex.map(rife, jobs))
        n_final = len(os.listdir(slot_dir))
        assert n_final == n_slots, f"スロット数不一致 {n_final} != {n_slots}"

        # 組み立て: 映像エンコードは1回だけ。音声muxはcopyなので補正のやり直しが安い
        os.makedirs(outdir, exist_ok=True)
        out_path = os.path.join(outdir, f"{name}{ARGS.suffix}.mp4")
        video_only = os.path.join(workdir, "video_only.mp4")
        vcmd = ["ffmpeg", "-y", "-v", "error",
                "-framerate", str(fps), "-start_number", "0",
                "-i", os.path.join(slot_dir, "%06d.png"),
                "-c:v", "libx264", "-crf", str(crf), "-preset", "medium",
                "-pix_fmt", "yuv420p"] + color_args(v) + [video_only]
        run(vcmd)

        def mux(audio_offset):
            cmd = ["ffmpeg", "-y", "-v", "error"]
            if origin > 0.002:
                cmd += ["-itsoffset", f"{origin:.6f}"]
            cmd += ["-i", video_only]
            if a is not None:
                if abs(audio_offset) > 0.0005:
                    cmd += ["-itsoffset", f"{audio_offset:.6f}"]
                cmd += ["-i", input_path, "-map", "0:v", "-map", "1:a",
                        "-c:v", "copy", "-c:a", "copy"]
            else:
                cmd += ["-map", "0:v", "-c:v", "copy"]
            cmd += ["-movflags", "+faststart", out_path]
            run(cmd)

        mux(0.0)
        if a is not None:
            orig_a = float(a.get("start_time", 0))
            new_a = audio_start(out_path)
            if abs(new_a - orig_a) > 0.001:
                print(f"[{name}] 音声start_time補正 {new_a:.4f}→{orig_a:.4f}")
                mux(orig_a - new_a)

        ok = verify(input_path, out_path, name, a is not None)
        return ok
    finally:
        if keep_temp:
            print(f"[{name}] 作業ディレクトリ保持: {workdir}")
        else:
            shutil.rmtree(workdir, ignore_errors=True)


def verify(orig, out, name, has_audio):
    def stats(path):
        fmt, v, a = probe(path)
        num, den = v["avg_frame_rate"].split("/")
        return {
            "duration": float(fmt["duration"]),
            "v_frames": int(v.get("nb_frames", 0)),
            "v_fps": float(num) / float(den) if float(den) else 0,
            "a_start": float(a["start_time"]) if a else None,
            "a_dur": float(a["duration"]) if a else None,
            "a_frames": int(a["nb_frames"]) if a else None,
        }

    o, n = stats(orig), stats(out)
    print(f"[{name}] 検証: duration {o['duration']:.3f}→{n['duration']:.3f}s  "
          f"映像 {o['v_frames']}枚/{o['v_fps']:.2f}fps → {n['v_frames']}枚/{n['v_fps']:.2f}fps")
    ok = True
    if has_audio:
        d_start = abs(n["a_start"] - o["a_start"])
        print(f"[{name}] 音声: start {o['a_start']:.4f}→{n['a_start']:.4f} (差{d_start*1000:.1f}ms)  "
              f"duration差{abs(n['a_dur']-o['a_dur'])*1000:.1f}ms  "
              f"フレーム数 {o['a_frames']}→{n['a_frames']}")
        if d_start > AUDIO_START_TOLERANCE or n["a_frames"] != o["a_frames"]:
            print(f"[{name}] ✗ 音声同期の検証に失敗")
            ok = False
    if ok:
        print(f"[{name}] ✓ 検証OK → {out}")
    return ok


def main():
    global ARGS
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("-o", "--outdir", default=None,
                    help="出力先(既定: 各入力と同じ場所の vfr_sync_out/)")
    ap.add_argument("--fps", type=int, default=None,
                    help="目標fps(既定: 表記r_frame_rateを四捨五入)")
    ap.add_argument("--crf", type=int, default=18)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--suffix", default="_sync")
    ap.add_argument("--keep-temp", action="store_true")
    ARGS = ap.parse_args()

    if not os.path.exists(RIFE_BIN):
        sys.exit(f"RIFEバイナリが見つかりません: {RIFE_BIN}")

    results = {}
    for path in ARGS.inputs:
        if not os.path.exists(path):
            print(f"見つかりません: {path}")
            results[path] = False
            continue
        outdir = ARGS.outdir or os.path.join(os.path.dirname(os.path.abspath(path)),
                                             "vfr_sync_out")
        try:
            results[path] = process(path, outdir, ARGS.fps, ARGS.crf,
                                    ARGS.workers, ARGS.keep_temp)
        except Exception as e:
            print(f"[{os.path.basename(path)}] エラー: {e}")
            results[path] = False

    n_ok = sum(results.values())
    print(f"\n完了: {n_ok}/{len(results)} 件成功")
    for p, ok in results.items():
        print(f"  {'✓' if ok else '✗'} {os.path.basename(p)}")
    sys.exit(0 if n_ok == len(results) else 1)


if __name__ == "__main__":
    main()
