#!/usr/bin/env python3
"""Read a soak event log (SOAK_LOG=file love . --soak, tests/soak_log.lua)
and print the usual answers: freight and bay fill, order waits and expiries,
shortages, factories, NPC money by role, deaths.

  python3 tools/soaklog/report.py soak.jsonl            all sections
  python3 tools/soaklog/report.py soak.jsonl --item composites
  python3 tools/soaklog/report.py soak.jsonl --section money
"""
import json, sys, collections, statistics, argparse

def q(xs, f):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, max(0, int(len(xs) * f)))] if xs else 0

def load(path):
    ev = collections.defaultdict(list)
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            ev[r.get('ev')].append(r)
    return ev

def hours(t):
    return '%.1fh' % (t / 3600)

def section(title):
    print('\n== ' + title)

def freight(ev, item=None):
    section('Freight runs')
    takes = [r for r in ev['take'] if r.get('kind') == 'transport']
    if not takes:
        print('  none'); return
    fill = [r['m3'] / r['hold'] for r in takes if r.get('hold')]
    print('  %d runs, %.0f m3 carried' % (len(takes), sum(r.get('m3', 0) for r in takes)))
    print('  m3 per run  p25 %.1f  p50 %.1f  p75 %.1f  p90 %.1f' % tuple(q([r.get('m3', 0) for r in takes], f) for f in (.25, .5, .75, .9)))
    print('  bay filled  p25 %.0f%%  p50 %.0f%%  p75 %.0f%%  p90 %.0f%%' % tuple(100 * q(fill, f) for f in (.25, .5, .75, .9)))
    stops = collections.Counter(r.get('stops', 1) for r in takes)
    print('  stops per run: ' + ', '.join('%d stop%s %d' % (k, '' if k == 1 else 's', v) for k, v in sorted(stops.items())))
    waits = [r['wait'] for r in takes if r.get('wait') is not None]
    print('  order wait before a hauler took it  p50 %.0fs  p90 %.0fs  max %.0fs' % (q(waits, .5), q(waits, .9), max(waits or [0])))
    jobs = collections.Counter('%s:%s' % (r.get('role'), r.get('kind')) for r in ev['take'])
    print('  jobs taken: ' + ', '.join('%s %d' % kv for kv in jobs.most_common(12)))

def orders(ev, item=None):
    section('Freight orders by good (posted, taken, left the board untaken)')
    posted = [r for r in ev['order'] if r.get('kind') == 'transport' and (not item or r.get('item') == item)]
    by = collections.defaultdict(list)
    for r in posted:
        by[r.get('item')].append(r)
    gone = collections.defaultdict(list)
    for r in ev['gone']:
        gone[r.get('item')].append(r)
    rows = sorted(by.items(), key=lambda kv: -sum(r.get('m3') or 0 for r in kv[1]))
    print('  %-22s %6s %8s %7s %7s %6s %9s %s' % ('good', 'orders', 'm3', 'p50 n', 'p50 m3', 'gone', 'gone age', 'posted by'))
    for it, rs in rows[:25]:
        g = gone.get(it, [])
        scopes = collections.Counter(r.get('scope') for r in rs)
        print('  %-22s %6d %8.0f %7.0f %7.1f %6d %8.0fs %s' % (it, len(rs), sum(r.get('m3') or 0 for r in rs), q([r.get('n') or 0 for r in rs], .5),
              q([r.get('m3') or 0 for r in rs], .5), len(g), q([x['age'] for x in g], .5), dict(scopes)))

def deliveries(ev, item=None):
    section('Deliveries')
    d = [r for r in ev['hist'] if r.get('kind') == 'freight_delivered']
    by = collections.defaultdict(lambda: [0, 0, 0])
    for r in d:
        res = r.get('result') or {}
        it = res.get('item')
        if item and it != item:
            continue
        b = by[it]; b[0] += 1; b[1] += res.get('amount') or 0; b[2] += res.get('payment') or 0
    for it, (n, amt, pay) in sorted(by.items(), key=lambda kv: -kv[1][2])[:20]:
        print('  %-22s %5d drops %9.0f units %10.0f cr' % (it, n, amt, pay))

def shortages(ev, item=None):
    section('Shortages (station snapshots under half their target, and empty)')
    stock = ev['stock']
    if not stock:
        print('  none'); return
    times = sorted(set(r['t'] for r in stock))
    under = collections.Counter(); empty = collections.Counter(); seen = collections.Counter()
    last = {}
    for r in stock:
        for it, (n, tg, price) in (r.get('goods') or {}).items():
            if item and it != item:
                continue
            if tg > 0:
                seen[it] += 1
                if n < tg / 2: under[it] += 1
                if n <= 0: empty[it] += 1
            if r['t'] == times[-1]:
                last.setdefault(it, []).append((r['station'], n, tg))
    print('  %-22s %8s %8s %8s' % ('good', 'under', 'empty', 'of'))
    for it, n in under.most_common(20):
        print('  %-22s %8d %8d %8d' % (it, n, empty[it], seen[it]))
    if item and item in last:
        print('  at the end:')
        for st, n, tg in sorted(last[item]):
            print('    %-28s %6.0f / %.0f' % (st, n, tg))
    if item:
        print('  over time (total stock / total target):')
        for t in times:
            n = tg = 0
            for r in stock:
                if r['t'] == t and item in (r.get('goods') or {}):
                    g = r['goods'][item]; n += g[0]; tg += g[1]
            print('    %6s %8.0f / %.0f' % (hours(t), n, tg))

def plants(ev, item=None):
    section('Factories waiting on inputs (status at each snapshot, share of snapshots)')
    st = collections.defaultdict(collections.Counter)
    for r in ev['plant']:
        for recipe, s in (r.get('status') or {}).items():
            if item and item not in recipe:
                continue
            key = '%s %s' % (r.get('station', '').replace('station:', ''), recipe)
            s = (s or '?').split(':')[0] if not str(s).startswith('Waiting') else s
            st[key][s] += 1
    rows = []
    for key, c in st.items():
        total = sum(c.values()); idle = sum(v for k, v in c.items() if str(k).startswith('Waiting'))
        if idle:
            rows.append((idle / total, key, c, total))
    for share, key, c, total in sorted(rows, reverse=True)[:25]:
        print('  %-44s %s' % (key, ', '.join('%s %d%%' % (k, 100 * v / total) for k, v in c.most_common(3))))

def money(ev, item=None):
    section('NPC money by role (whole run)')
    snaps = collections.defaultdict(list)
    for r in ev['npc']:
        snaps[r['npc']].append(r)
    keys = ['freightEarnings', 'salvageEarnings', 'miningEarnings', 'wageEarnings', 'bountyEarnings', 'rareEarnings', 'fuelSpent', 'suppliesSpent', 'dockFees']
    role = collections.defaultdict(lambda: collections.defaultdict(float))
    for npc, rs in snaps.items():
        rs.sort(key=lambda r: r['t'])
        a, b = rs[0], rs[-1]
        g = role[b.get('role') or '?']
        g['n'] += 1
        g['credits'] += b.get('credits') or 0
        g['broke'] += 1 if (b.get('credits') or 0) < 100 else 0
        for k in keys:
            g[k] += (b.get(k) or 0) - (a.get(k) or 0)
    print('  %-9s %4s %6s %9s  %s' % ('role', 'n', 'broke', 'mean cr', 'earned (+) and spent (-) over the run, all ships of the role'))
    for name, g in sorted(role.items(), key=lambda kv: -kv[1]['n']):
        parts = []
        for k in keys:
            v = g[k]
            if v and k != 'fuelSpent':
                label = {'suppliesSpent': 'supplies', 'dockFees': 'docking'}.get(k, k.replace('Earnings', ''))
                parts.append('%s %+.0f' % (label, -v if k in ('suppliesSpent', 'dockFees') else v))
                if k == 'suppliesSpent' and g['fuelSpent']:
                    parts[-1] += ' (fuel %.0f of it)' % g['fuelSpent']
        income = sum(g[k] for k in keys if k.endswith('Earnings'))
        parts.append('net %+.0f' % (income - g['suppliesSpent'] - g['dockFees']))
        print('  %-9s %4d %6d %9.0f  %s' % (name, g['n'], g['broke'], g['credits'] / max(1, g['n']), ', '.join(parts)))
    section('Broke NPCs over time (under 100 cr), by role, and what the broke ones are doing')
    by_t = collections.defaultdict(collections.Counter); doing = collections.defaultdict(collections.Counter)
    for r in ev['npc']:
        if (r.get('credits') or 0) < 100:
            by_t[r['t']][r.get('role')] += 1
            doing[r.get('role')]['%s/%s' % (r.get('task') or 'no task', r.get('status') or '-')] += 1
    for t in sorted(by_t):
        print('  %6s %s' % (hours(t), dict(by_t[t].most_common())))
    for name, c in doing.items():
        print('  %-9s %s' % (name, ', '.join('%s %d' % kv for kv in c.most_common(6))))

def deaths(ev, item=None):
    section('Deaths')
    d = ev['death']
    print('  %d ships lost, %.0f m3 of cargo with them' % (len(d), sum(r.get('cargo') or 0 for r in d)))
    for field in ('role', 'task', 'killerRole', 'area'):
        c = collections.Counter(str(r.get(field)) for r in d)
        print('  by %-10s %s' % (field, ', '.join('%s %d' % kv for kv in c.most_common(10))))
    c = collections.Counter('%s>%s' % (r.get('killerRole'), r.get('role')) for r in d)
    print('  killer>victim %s' % ', '.join('%s %d' % kv for kv in c.most_common(10)))

SECTIONS = {'freight': freight, 'orders': orders, 'deliveries': deliveries, 'shortages': shortages, 'plants': plants, 'money': money, 'deaths': deaths}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('log')
    ap.add_argument('--item')
    ap.add_argument('--section', choices=sorted(SECTIONS))
    a = ap.parse_args()
    ev = load(a.log)
    end = max((r['t'] for rs in ev.values() for r in rs), default=0)
    print('soak log %s: %s of game time, %s' % (a.log, hours(end), ', '.join('%s %d' % (k, len(v)) for k, v in sorted(ev.items()))))
    for name, fn in SECTIONS.items():
        if not a.section or a.section == name:
            fn(ev, a.item)

if __name__ == '__main__':
    main()
