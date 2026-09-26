# Watches a playtest by agents: one line when something needs attention (an
# agent finished or stopped, a diary went quiet, a browser seat died) and a
# status line every 15 minutes. Its output is meant for a monitor.
#
#   python3 -u tools/agent_playtest/watch.py <run dir>
import json
import os
import subprocess
import sys
import time

run = sys.argv[1]
cast = json.load(open(os.path.join(run, 'cast.json')))
people = [(cast['dm']['key'], 'DM ' + cast['dm']['name'])] + [(p['key'], p['name']) for p in cast['players']]
names = {key: (cast['dm']['name'] if key == cast['dm']['key'] else label) for key, label in people}


def alive(key):
    return subprocess.run(['pgrep', '-f', f'{names[key]} \\(playtest\\)'], capture_output=True).returncode == 0


def size_mb(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total // (1024 * 1024)


# (the agents' logs carry every screenshot: a run is watched for size too)
was, stale, seatwarn, sizewarn, tick = {}, set(), False, False, 0
while True:
    now = time.time()
    hm = time.strftime('%H:%M')
    status = [hm]
    for key, label in people:
        on = alive(key)
        d = os.path.join(run, key, 'diary.md')
        lines = sum(1 for _ in open(d)) if os.path.exists(d) else 0
        age = int((now - os.path.getmtime(d)) / 60) if os.path.exists(d) else 0
        shots = os.path.join(run, key, 'shots')
        count = len(os.listdir(shots)) if os.path.isdir(shots) else 0
        review = os.path.exists(os.path.join(run, key, 'review.md'))
        if was.get(key) and not on:
            # (and the two lists that come after the review: improvements, favourites)
            lacking = [f for f in ('improvements.md', 'favorites.md') if not os.path.exists(os.path.join(run, key, f))]
            print(f"{hm} {label} {'finished' if review else 'STOPPED without a review'}{(' — no ' + ', '.join(lacking)) if review and lacking else ''}", flush=True)
        if on and age >= 15 and key not in stale:
            print(f"{hm} {label}'s diary has been quiet for {age} min", flush=True)
            stale.add(key)
        if age < 15:
            stale.discard(key)
        was[key] = on
        if on:
            status.append(f'{label}: {lines} diary lines, {count} shots')
    pids = open(os.path.join(run, 'seats.pids')).read().split()
    up = sum(1 for p in pids if subprocess.run(['kill', '-0', p], capture_output=True).returncode == 0)
    if up < len(pids) and not seatwarn:
        print(f'{hm} only {up} of {len(pids)} browser seats are running', flush=True)
        seatwarn = True
    mb = size_mb(run) if tick % 5 == 0 else None
    if mb is not None and mb > 5000 and not sizewarn:
        print(f'{hm} the run folder is {mb} MB', flush=True)
        sizewarn = True
    if tick and tick % 15 == 0:
        print(' | '.join(status) + (f' | {mb} MB' if mb is not None else ''), flush=True)
    tick += 1
    time.sleep(60)
