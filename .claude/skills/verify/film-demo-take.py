#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Film one language's take for the site demo video.

  film-demo-take.py phone   LANG --udid U --out TAKE_DIR
  film-demo-take.py glasses LANG --udid U --out TAKE_DIR

Then scripts/cut-demo-take TAKE_DIR base-LANG.mp4 cuts the two halves into
the uncaptioned base that scripts/build-demo-videos --base-dir captions.

phone    PreviewUITests/testRecordDemo on an iPhone 17 Pro Max simulator
         (1320x2868), recorded with simctl. Writes phone.mp4, phone.beats,
         phone.log. Resets the app's store first: no earlier conversation,
         the "demo" host back on Solarized Light running top.
glasses  DemoHostUITests/testGlassesFootage on a simulator from
         scripts/make-glasses-simulator. Records the external display and
         screenshots the phone while top runs, because simctl records one
         display at a time. Writes glasses.mp4, phone-shots/, glasses.beats,
         glasses.log.

The tests read every label they tap from Localizable.xcstrings via L_*
variables; L_PROMPT is the question put to the assistant, written here per
language so it answers in that language.

Needs the verify harness built (add_uitest_target.rb, add_scheme.rb,
build-for-testing with -derivedDataPath matching --derived-data), and the
filming host in TEST_RUNNER_DEMO_HOST / TEST_RUNNER_DEMO_PASSWORD. The host
must already be in the app as "demo" with password credentials and its key
accepted: run DemoHostUITests/testReviewerLogin once in English with
TEST_RUNNER_DEMO_LABEL=demo. The phone simulator also needs the assistant set
up once (see the verify skill). Typed text, the password included, lands in
XCUITest's log, so the logs this writes are scrubbed of it.
"""
import argparse
import json
import os
import pathlib
import re
import shlex
import signal
import sqlite3
import subprocess
import sys
import threading
import time

REPO = pathlib.Path(__file__).resolve().parents[3]
BUNDLE = "John-Hancock.pockterm"

LOCALES = {"en": "en_US", "es": "es_ES", "fr": "fr_FR", "it": "it_IT", "el": "el_GR",
           "ru": "ru_RU", "uk": "uk_UA", "ar": "ar_SA", "he": "he_IL", "hi": "hi_IN",
           "te": "te_IN", "ja": "ja_JP", "ko": "ko_KR", "zh-Hans": "zh_CN",
           "zh-Hant": "zh_TW"}
PROMPTS = {
    "en": "What is using the most memory?",
    "es": "¿Qué está usando más memoria?",
    "fr": "Qu'est-ce qui consomme le plus de mémoire ?",
    "it": "Cosa sta usando più memoria?",
    "el": "Τι χρησιμοποιεί την περισσότερη μνήμη;",
    "ru": "Что занимает больше всего памяти?",
    "uk": "Що займає найбільше пам’яті?",
    "ar": "ما الذي يستخدم أكبر قدر من الذاكرة؟",
    "he": "מה צורך הכי הרבה זיכרון?",
    "hi": "सबसे ज़्यादा मेमोरी क्या इस्तेमाल कर रहा है?",
    "te": "ఎక్కువ మెమరీని ఏది వాడుతోంది?",
    "ja": "一番メモリを使っているのは何？",
    "ko": "메모리를 가장 많이 사용하는 것은 무엇인가요?",
    "zh-Hans": "什么占用的内存最多？",
    "zh-Hant": "什麼佔用的記憶體最多？",
}
LABELS = {"L_THEME": "Terminal Theme", "L_FILES": "Browse Files", "L_ASSISTANT": "AI Assistant",
          "L_HIDE": "Dismiss Keyboard", "L_SEND": "Send", "L_RUN": "Run", "L_DONE": "Done",
          "L_MINIMIZE": "Minimize", "L_STOP": "Stop generating", "L_DENY": "Deny",
          "L_GLASSES_SIZE": "Text Size on Glasses"}


def test_env(lang):
    cat = json.loads((REPO / "pockterm/Localizable.xcstrings").read_text())["strings"]
    env = {"SHOT_LANG": lang, "SHOT_LOCALE": LOCALES[lang], "L_HOST": "demo",
           "L_PROMPT": PROMPTS[lang], "DEMO_LABEL": "demo"}
    for var, key in LABELS.items():
        env[var] = key if lang == "en" else \
            cat[key]["localizations"][lang]["stringUnit"]["value"]
    return {f"TEST_RUNNER_{k}": v for k, v in env.items()}


def run_test(udid, test, log, derived, extra_env, timeout=900):
    """xcodebuild test-without-building, stopped a few seconds after the suite
    reports: it tends to hang there for minutes after the test is done."""
    env = dict(os.environ, **extra_env)
    with open(log, "wb") as out:
        p = subprocess.Popen(
            ["xcodebuild", "test-without-building", "-project", str(REPO / "pockterm.xcodeproj"),
             "-scheme", "pocktermUI", "-destination", f"platform=iOS Simulator,id={udid}",
             "-derivedDataPath", str(derived), f"-only-testing:pocktermUITests/{test}"],
            stdout=out, stderr=subprocess.STDOUT, env=env, cwd=REPO)
        start = time.time()
        while p.poll() is None:
            text = pathlib.Path(log).read_bytes()
            if b"Test Suite 'Selected tests' passed" in text or \
               b"Test Suite 'Selected tests' failed" in text:
                time.sleep(8)
                break
            if time.time() - start > timeout:
                print(f"  {test}: no result after {timeout} s", file=sys.stderr)
                break
            time.sleep(2)
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()


def scrub(log):
    """Removes the typed password (XCUITest logs typed text, cut short)."""
    pw = os.environ.get("TEST_RUNNER_DEMO_PASSWORD", "")
    text = pathlib.Path(log).read_text(errors="replace")
    if len(pw) >= 6:
        text = re.sub(re.escape(pw[:6]) + r"[^'\s]*", "<redacted>", text)
    pathlib.Path(log).write_text(text)
    return text


def result(text, test):
    for line in text.splitlines():
        if f"{test.split('/')[1]}]' " in line and ("passed" in line or "failed" in line):
            return line.strip()
    return f"{test}: no result"


class Recorder:
    """simctl io recordVideo, stopped with SIGINT so the file is finalised."""

    def __init__(self, udid, out, display):
        self.p = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264",
                                   f"--display={display}", "--force", str(out)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        for line in self.p.stderr:
            if "Recording started" in line:
                break

    def stop(self):
        self.p.send_signal(signal.SIGINT)
        self.p.wait(30)


def prepare_simulator(udid, appearance):
    """What every take assumes about the simulator, set each time because it
    costs nothing: the English cut's look (light phone, dark glasses phone,
    9:41), no autocorrection rewriting a French or Spanish question as it is
    typed, and the multilingual keyboard's first-run card marked as seen (the
    Hindi keyboard otherwise covers the keyboard area with it, in English)."""
    run = lambda *a: subprocess.run(["xcrun", "simctl", *a], capture_output=True)
    run("ui", udid, "appearance", appearance)
    run("status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi",
        "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active",
        "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100")
    for key in ("KeyboardAutocorrection", "KeyboardPrediction", "KeyboardCheckSpelling",
                "KeyboardShowPredictionBar", "KeyboardAutocapitalization"):
        run("spawn", udid, "defaults", "write", "com.apple.Preferences", key, "-bool", "NO")
    run("spawn", udid, "defaults", "write", "com.apple.Preferences",
        "DidShowContinuousPathIntroduction", "-bool", "YES")
    run("spawn", udid, "defaults", "write", "com.apple.keyboard.preferences",
        "MultilingualKeyboardTip", "-bool", "YES")


def reset_store(udid):
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    time.sleep(1)
    cont = subprocess.check_output(["xcrun", "simctl", "get_app_container", udid, BUNDLE,
                                    "data"]).decode().strip()
    db = sqlite3.connect(pathlib.Path(cont) / "Library/Application Support/default.store")
    db.execute("DELETE FROM ZASSISTANTMESSAGERECORD")
    n = db.execute("UPDATE ZHOST SET ZTHEMEID='solarized-light', ZFONTSIZE=0, "
                   "ZSTARTUPSNIPPET='top' WHERE ZLABEL='demo'").rowcount
    db.commit()
    db.close()
    if n != 1:
        sys.exit("expected one host labelled demo in the app; set it up first")


def beats(text, out):
    lines = [l for l in text.splitlines() if l.startswith("BEAT|")]
    out.write_text("\n".join(lines) + "\n")
    return lines


def phone(args, env):
    prepare_simulator(args.udid, "light")
    reset_store(args.udid)
    rec = Recorder(args.udid, args.out / "phone.mp4", "internal")
    time.sleep(2)
    log = args.out / "phone.log"
    try:
        run_test(args.udid, "PreviewUITests/testRecordDemo", log, args.derived_data, env)
        time.sleep(1)
    finally:
        rec.stop()
    text = scrub(log)
    print(" ", result(text, "PreviewUITests/testRecordDemo"))
    for line in beats(text, args.out / "phone.beats"):
        print("  " + line)


def glasses(args, env):
    prepare_simulator(args.udid, "dark")
    subprocess.run(["xcrun", "simctl", "terminate", args.udid, BUNDLE], capture_output=True)
    time.sleep(1)
    shots = args.out / "phone-shots"
    shots.mkdir(exist_ok=True)
    for old in shots.glob("*.png"):
        old.unlink()
    log = args.out / "glasses.log"
    log.write_text("")
    done = threading.Event()

    def screenshots():
        # Only while top runs on the glasses: from the typing beat to the end.
        while not done.is_set() and b"BEAT|glasses-type|" not in log.read_bytes():
            time.sleep(1)
        while not done.is_set() and b"BEAT|glasses-end|" not in log.read_bytes():
            t = time.time()
            tmp = shots / "tmp.png"
            if subprocess.run(["xcrun", "simctl", "io", args.udid, "screenshot",
                               "--display=internal", str(tmp)],
                              capture_output=True).returncode == 0:
                tmp.rename(shots / f"{t:.3f}.png")

    rec = Recorder(args.udid, args.out / "glasses.mp4", "external")
    loop = threading.Thread(target=screenshots)
    loop.start()
    time.sleep(2)
    try:
        run_test(args.udid, "DemoHostUITests/testGlassesFootage", log, args.derived_data, env)
        time.sleep(1)
    finally:
        done.set()
        loop.join()
        rec.stop()
    text = scrub(log)
    print(" ", result(text, "DemoHostUITests/testGlassesFootage"))
    for line in beats(text, args.out / "glasses.beats"):
        print("  " + line)
    print(f"  {len(list(shots.glob('*.png')))} phone screenshots")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("kind", choices=["phone", "glasses"])
    ap.add_argument("lang", choices=sorted(LOCALES))
    ap.add_argument("--udid", required=True)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--derived-data", required=True, type=pathlib.Path)
    args = ap.parse_args()
    for var in ("TEST_RUNNER_DEMO_HOST", "TEST_RUNNER_DEMO_PASSWORD"):
        if not os.environ.get(var):
            sys.exit(f"{var} is not set")
    args.out.mkdir(parents=True, exist_ok=True)
    env = test_env(args.lang)
    print(f"{args.kind} take, {args.lang}: " + " ".join(
        f"{k[12:]}={shlex.quote(v)}" for k, v in env.items() if k.startswith("TEST_RUNNER_L_")))
    (phone if args.kind == "phone" else glasses)(args, env)


if __name__ == "__main__":
    main()
