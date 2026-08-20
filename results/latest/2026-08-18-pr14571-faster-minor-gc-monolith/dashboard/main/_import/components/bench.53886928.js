// Shared helpers for the dashboard pages. Pure contract consumption: everything
// here reads the ingestor's output (measurement records + the run manifest).
import * as Plot from "../../_npm/@observablehq/plot@0.6.17/93ce672e.js";
import * as Inputs from "../../_observablehq/stdlib/inputs.f7175400.js";
import {html} from "../../_npm/htl@1.0.0/11521f02.js";

// Status palette (fixed, colorblind-checked). Lower is better for all our
// metrics, so negative Δ = improvement (green).
export const STATUS = { improvement: "#0ca30c", neutral: "#8a8a86", warn: "#fab219", regression: "#d03b3b" };
const statusDomain = ["improvement", "neutral", "warn", "regression"];

// Metrics offered in the selectors (name -> label/unit). `lowerBetter` is true
// for all of these; kept explicit in case a "higher is better" metric appears.
export const METRICS = [
  { name: "instructions", label: "Instructions", unit: "count" },
  { name: "wall_time", label: "Wall time", unit: "s" },
  { name: "cpu_time", label: "CPU time", unit: "s" },
  { name: "max_rss", label: "Max RSS", unit: "KiB" },
  { name: "gc_overhead", label: "GC overhead", unit: "%" },
  { name: "gc_time", label: "GC time", unit: "s" },
  { name: "major_collections", label: "Major collections", unit: "count" },
  { name: "minor_collections", label: "Minor collections", unit: "count" },
  { name: "promoted_pct", label: "Promoted", unit: "%" },
];
// Rest of the contract's metric catalog (registry.ml). Kept out of METRICS so the
// existing pages' selectors are unchanged, but nameable everywhere: the
// space/time page offers memory-footprint and hardware metrics that the Δ and
// heatmap pages have no use for.
export const MORE_METRICS = [
  { name: "major_words", label: "Major heap words", unit: "words" },
  { name: "minor_words", label: "Minor words", unit: "words" },
  { name: "page_faults", label: "Page faults", unit: "count" },
  { name: "mean_latency", label: "Mean latency", unit: "ms" },
  { name: "cycles", label: "Cycles", unit: "count" },
  { name: "task_clock", label: "Task clock", unit: "ns" },
];
const ALL_METRICS = [...METRICS, ...MORE_METRICS];
export const GC_METRICS = ["gc_overhead", "gc_time", "major_collections", "minor_collections", "promoted_pct"];
export const metricLabel = (name) => ALL_METRICS.find((m) => m.name === name)?.label ?? name;
export const metricUnit = (name) => ALL_METRICS.find((m) => m.name === name)?.unit ?? null;

// Categorical series palette, one entry per light/dark surface. Fixed order,
// never cycled: slot 0 is always the first series. These three steps are
// validated for all-pairs use (scatter — every series is adjacent to every
// other) on both surfaces; slots 3+ are only gate-safe for adjacent forms, so a
// scatter with more than three series also carries symbol + label encoding.
export const SERIES_LIGHT = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#4a3aa7", "#008300", "#e34948"];
export const SERIES_DARK = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#9085e9", "#008300", "#e66767"];
export const SURFACE = { light: "#fcfcfb", dark: "#1a1a19" };
export const INK = { light: "#0b0b0b", dark: "#ffffff" };
export const seriesRange = (n, dark = false) => {
  const p = dark ? SERIES_DARK : SERIES_LIGHT;
  return Array.from({ length: Math.max(1, n) }, (_, i) => p[i % p.length]);
};

// ---- data indexing ---------------------------------------------------------
export function index(measurements) {
  const cell = new Map(); // `${bench}\0${config_id}` -> {metricName: [values]}
  for (const m of measurements) {
    const k = m.benchmark.name + "\u0000" + m.config.config_id;
    let e = cell.get(k);
    if (!e) { e = {}; cell.set(k, e); }
    for (const mt of m.metrics) (e[mt.name] ??= []).push(mt.value);
  }
  return cell;
}
export const benchmarksOf = (measurements) => [...new Set(measurements.map((m) => m.benchmark.name))].sort();
export const median = (xs) => {
  const a = (xs ?? []).filter((v) => v != null).sort((p, q) => p - q);
  if (!a.length) return null;
  const n = a.length;
  return n % 2 ? a[(n - 1) / 2] : (a[n / 2 - 1] + a[n / 2]) / 2;
};
const cellGet = (cell, bench, cid, name) => cell.get(bench + "\u0000" + cid)?.[name] ?? [];

// ---- config / selector resolution (contract §4.5) --------------------------
function cfgField(c, k) {
  if (k === "config_id") return c.config_id;
  if (k === "_runtime_name") return c._runtime_name;
  // A config with no build options omits `options` entirely; normalize to [] so a
  // selector that pins `runtime.options: []` (a STOCK build) matches it — and does
  // NOT match a same-version variant that has options. Without this, an
  // empty-options baseline selector is under-specified and collapses onto every
  // variant of that version (fp / flambda / fp-flambda).
  if (k === "runtime.options") return c.runtime?.options ?? [];
  if (k.startsWith("runtime.")) return c.runtime?.[k.slice("runtime.".length)];
  return c.dimensions?.[k];
}
const matchesSel = (c, sel) => Object.entries(sel).every(([k, v]) => JSON.stringify(cfgField(c, k)) === JSON.stringify(v));
export const resolve = (configs, sel) => (sel ? configs.filter((c) => matchesSel(c, sel)) : []);

// Baseline configs of an inter comparison, with the variant-matched configs
// removed. Baseline and variants are DISJOINT runtimes by definition, but a
// baseline selector can be under-specified — e.g. a stock build whose selector
// is {runtime.version: X} with no options, which then also matches that
// version's fp / flambda variants. Subtracting the variant matches restores the
// intended baseline even when the contract's selector is imprecise.
export function baselineConfigs(configs, cmp) {
  const varIds = new Set((cmp.variants ?? []).flatMap((s) => resolve(configs, s)).map((c) => c.config_id));
  return resolve(configs, cmp.baseline ?? {}).filter((c) => !varIds.has(c.config_id));
}
const stripVersion = (v) => (v ?? "").replace(/^(ocaml|oxcaml)-/, "");

// A runtime's DISPLAY identity. Configs that share runtime.version but differ by
// build options (e.g. --enable-frame-pointers / --enable-flambda) are DISTINCT
// runtimes and must not collapse to one "5.5.0". The ingestor's _runtime_name
// (e.g. "ocaml-5.5.0-fp-flambda") already encodes those variant suffixes, so we
// prefer it; otherwise we synthesize version+options.
export const runtimeId = (c) => {
  if (c._runtime_name != null) return stripVersion(c._runtime_name);
  const v = stripVersion(c.runtime?.version) || c.config_id.slice(0, 10);
  const o = (c.runtime?.options ?? []).map((x) => x.replace(/^--enable-/, "")).join(",");
  return o ? `${v} [${o}]` : v;
};
// A normative config selector that isolates exactly this runtime, matched via
// cfgField. version + options + commit is the same identity config_id is derived
// from; options is pinned ALWAYS (even []) so a stock build isn't matched by its
// own optioned variants.
export const runtimeSelector = (c) => {
  const sel = { "runtime.version": c.runtime?.version, "runtime.options": c.runtime?.options ?? [] };
  if (c.runtime?.commit != null) sel["runtime.commit"] = c.runtime.commit;
  return sel;
};

export const label = (c, exclude = []) => {
  // display only — the underlying config_id / selectors use the full values.
  // Include dimensions so configs of the SAME runtime that differ only by a
  // dimension (e.g. gc_plan=Bactrian vs LXR) are distinct series rather than
  // collapsing to one label. `exclude` drops dimensions that are an axis of the
  // current view (a swept x/y) or constant across it — otherwise every point of
  // a sweep would be its own series.
  const base = runtimeId(c);
  const d = Object.entries(c.dimensions ?? {})
    .filter(([k]) => !exclude.includes(k))
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, val]) => `${k}=${val}`)
    .join(", ");
  return d ? `${base} {${d}}` : base;
};
const dimsKey = (c) => JSON.stringify(c.dimensions ?? {});
export const verdict = (d) => (d == null ? "unknown" : d <= -3 ? "improvement" : d >= 3 ? "regression" : Math.abs(d) >= 1 ? "warn" : "neutral");
export const dimensionKeys = (configs) => {
  const s = new Set();
  for (const c of configs) for (const k of Object.keys(c.dimensions ?? {})) s.add(k);
  return [...s];
};
// Dimensions that DON'T vary across the given configs (single value or absent).
// Used to drop them from a sweep's series label — they add no distinction.
export const constantDims = (configs) => {
  const varying = new Set(varyingDims(configs).map((d) => d.dim));
  return dimensionKeys(configs).filter((k) => !varying.has(k));
};

// ---- swept-dimension handling ----------------------------------------------
// A "runtime" that appears many times in a sweep is the SAME runtime under
// different GC parameters. These helpers let a page pin those parameters to
// specific values so the comparison collapses to one config per runtime.
const cmpVal = (a, b) =>
  typeof a === "number" && typeof b === "number" ? a - b
  : String(a) < String(b) ? -1 : String(a) > String(b) ? 1 : 0;

// Dimensions that actually VARY across the run (>1 distinct value), each with
// its sorted distinct values. Single-valued dimensions are omitted — there is
// nothing to choose, so they never appear in a dropdown.
export function varyingDims(configs) {
  const seen = new Map(); // dim -> Map(json -> value)
  for (const c of configs)
    for (const [k, v] of Object.entries(c.dimensions ?? {})) {
      if (!seen.has(k)) seen.set(k, new Map());
      seen.get(k).set(JSON.stringify(v), v);
    }
  return [...seen.entries()]
    .filter(([, m]) => m.size > 1)
    .map(([dim, m]) => ({ dim, values: [...m.values()].sort(cmpVal) }));
}

// Keep configs whose dimensions match every pinned value (pins: {dim: value}).
// A null/undefined pin means "any". A config that LACKS a pinned dimension (e.g.
// a stock baseline with no gc_plan) is cross-cutting and always kept — only a
// config that HAS the dimension with a different value is dropped.
export function filterByDims(configs, pins) {
  const ps = Object.entries(pins ?? {}).filter(([, v]) => v != null);
  return configs.filter((c) => ps.every(([k, v]) =>
    c.dimensions?.[k] === undefined || JSON.stringify(c.dimensions[k]) === JSON.stringify(v)));
}

// Dimension keys a comparison uses as baseline/variant selectors — these are the
// comparison's OWN axes, so they must not also be offered as collapsing pins
// (pinning them would hide the other variants / drop the baseline).
export function comparisonDims(cmps) {
  const s = new Set();
  for (const cmp of cmps ?? [])
    for (const sel of [cmp.baseline, ...(cmp.variants ?? [])])
      for (const k of Object.keys(sel ?? {}))
        if (k !== "config_id" && !k.startsWith("runtime.")) s.add(k);
  return [...s];
}

// Build an <Inputs.form> with one <select> per varying dimension (minus any in
// `exclude`); its value is a {dim: value} pins object. Empty form when nothing
// varies. Requires Inputs (imported below).
//
// `allowAll` adds an "(all)" choice (value null, which filterByDims reads as
// "any") and makes it the default. A heatmap or a curve NEEDS every remaining
// parameter pinned — one config per cell / per x point — but a scatter of
// (space, time) does not: leaving a parameter unpinned there is the whole point,
// since every extra parameter value is another candidate point on the frontier.
export function dimPinsInput(configs, exclude = [], { allowAll = false } = {}) {
  const vd = varyingDims(configs).filter((d) => !exclude.includes(d.dim));
  if (!vd.length) return Inputs.form({});
  return Inputs.form(
    Object.fromEntries(vd.map((d) => [d.dim, Inputs.select(allowAll ? [null, ...d.values] : d.values, {
      label: d.dim,
      value: allowAll ? null : d.values[0],
      format: (v) => (v === null ? "(all)" : String(v)),
    })]))
  );
}

// Default {baseline, variants:[...]} configs for the interactive picker: resolve
// the first declared inter comparison to concrete configs; fall back to
// configs[0] as baseline and the rest as variants.
export function defaultCompare(configs, cmps) {
  const cmp = (cmps ?? []).find((c) => !c.kind || c.kind === "inter");
  if (cmp) {
    const baseline = baselineConfigs(configs, cmp)[0] ?? configs[0];
    const variants = (cmp.variants ?? []).flatMap((s) => resolve(configs, s)).filter((c) => c !== baseline);
    if (variants.length) return { baseline, variants };
  }
  const baseline = configs[0];
  return { baseline, variants: configs.filter((c) => c !== baseline) };
}

// Default single-config pick for the interactive picker: one baseline config and
// one variant per declared-comparison variant selector, chosen to share the
// baseline's dimensions where possible (so a sweep defaults to one matched pair,
// not the whole grid).
export function defaultPick(configs, cmps) {
  const cmp = (cmps ?? []).find((c) => !c.kind || c.kind === "inter");
  if (cmp) {
    const baseline = baselineConfigs(configs, cmp)[0] ?? configs[0];
    const bkey = JSON.stringify(baseline?.dimensions ?? {});
    const variants = [];
    for (const s of cmp.variants ?? []) {
      const cands = resolve(configs, s).filter((c) => c !== baseline);
      const pick = cands.find((c) => JSON.stringify(c.dimensions ?? {}) === bkey) ?? cands[0];
      if (pick) variants.push(pick);
    }
    if (variants.length) return { baseline, variants };
  }
  const baseline = configs[0];
  const v = configs.find((c) => c !== baseline);
  return { baseline, variants: v ? [v] : [] };
}

// A dependency-free custom input: choose a config by runtime + one value per
// varying dimension (dimension options cascade off the chosen runtime, so a
// runtime that lacks a dimension — e.g. stock has no gc_plan — simply omits it,
// and only real configs are selectable). When `multiple`, renders a growable
// list of such rows with "+ Add" / "×"; its .value is the array of chosen
// configs. Otherwise a single row whose .value is one config (or null). Emits an
// "input" event so Framework's view() tracks it.
export function configPicker(configs, { multiple = false, value = null } = {}) {
  // Runtime identity = version + build options (see runtimeId), so fp / flambda
  // variants of the same version are separately selectable instead of collapsing.
  const runtimes = [...new Set(configs.map((c) => runtimeId(c)))];
  const vdims = varyingDims(configs).map((d) => d.dim);

  const valuesFor = (runtime, dim) => {
    const m = new Map();
    for (const c of configs)
      if (runtimeId(c) === runtime && c.dimensions?.[dim] !== undefined)
        m.set(JSON.stringify(c.dimensions[dim]), c.dimensions[dim]);
    return [...m.values()].sort(cmpVal);
  };
  const match = (runtime, dimvals) =>
    configs.find((c) =>
      runtimeId(c) === runtime &&
      Object.entries(dimvals).every(([k, v]) => String(c.dimensions?.[k]) === String(v))) ?? null;
  const toInit = (cfg) => ({
    runtime: cfg ? runtimeId(cfg) : undefined,
    dims: Object.fromEntries(vdims.map((d) => [d, cfg?.dimensions?.[d]])),
  });

  const container = document.createElement("div");
  container.className = "cfgpick";
  const rowsBox = document.createElement("div");
  container.appendChild(rowsBox);
  const rows = [];
  const emit = () => container.dispatchEvent(new Event("input", { bubbles: true }));

  const sel = (opts, cur, fmt) => {
    const s = document.createElement("select");
    for (const o of opts) {
      const el = document.createElement("option");
      el.value = String(o); el.textContent = fmt ? fmt(o) : String(o);
      if (cur !== undefined && String(cur) === String(o)) el.selected = true;
      s.appendChild(el);
    }
    return s;
  };

  function makeRow(init) {
    const el = document.createElement("div");
    el.className = "cfgpick-row";
    const runtimeSel = sel(runtimes, init?.runtime ?? runtimes[0]);
    const field = (name, node) => {
      const w = document.createElement("label"); w.className = "cfgpick-f";
      const cap = document.createElement("span"); cap.textContent = name;
      w.append(cap, node); return w;
    };
    el.appendChild(field("runtime", runtimeSel));
    const dimBox = document.createElement("span"); dimBox.className = "cfgpick-dims";
    el.appendChild(dimBox);
    const row = { el, runtimeSel, dimSels: [] };

    const renderDims = (init2) => {
      dimBox.textContent = ""; row.dimSels = [];
      for (const d of vdims) {
        const vals = valuesFor(runtimeSel.value, d);
        if (!vals.length) continue;                   // dim absent for this runtime
        const cur = init2?.dims?.[d] ?? vals[0];
        const s = sel(vals, cur);
        s.addEventListener("input", emit);
        dimBox.appendChild(field(d, s));
        row.dimSels.push({ dim: d, sel: s });
      }
    };
    renderDims(init);
    runtimeSel.addEventListener("input", () => { renderDims(null); emit(); });

    if (multiple) {
      const rm = document.createElement("button");
      rm.type = "button"; rm.className = "cfgpick-rm"; rm.textContent = "×"; rm.title = "remove";
      rm.addEventListener("click", () => {
        if (rows.length <= 1) return;
        rows.splice(rows.indexOf(row), 1); rowsBox.removeChild(el); emit();
      });
      el.appendChild(rm);
    }
    return row;
  }
  const addRow = (init) => { const r = makeRow(init); rows.push(r); rowsBox.appendChild(r.el); };
  const readRow = (r) =>
    match(r.runtimeSel.value, Object.fromEntries(r.dimSels.map((d) => [d.dim, d.sel.value])));

  const inits = multiple ? (Array.isArray(value) && value.length ? value : [null]) : [value];
  for (const iv of inits) addRow(iv ? toInit(iv) : null);
  if (multiple) {
    const add = document.createElement("button");
    add.type = "button"; add.className = "cfgpick-add"; add.textContent = "+ Add comparison";
    add.addEventListener("click", () => {
      // Default the new row to a config that isn't already shown, so a distinct
      // bar appears immediately (otherwise it duplicates an existing selection
      // and nothing visibly changes until a dropdown is touched).
      const used = new Set(rows.map(readRow).filter(Boolean).map((c) => c.config_id));
      const next = configs.find((c) => !used.has(c.config_id));
      addRow(next ? toInit(next) : null);
      emit();
    });
    container.appendChild(add);
  }
  Object.defineProperty(container, "value", {
    get() { const out = rows.map(readRow).filter(Boolean); return multiple ? out : (out[0] ?? null); },
  });
  return container;
}

// declared comparisons, or a synthesized "baseline vs rest"
export function comparisons(manifest) {
  const configs = manifest.configs ?? [];
  let cs = manifest.comparisons ?? [];
  if (!cs.length && configs.length >= 2) {
    // Distinct runtimes by identity (version + build options), NOT by version
    // alone — otherwise fp / flambda variants of the same version collapse into
    // one runtime and disappear from the comparison.
    const rts = [];
    const seen = new Set();
    for (const c of configs) {
      const id = runtimeId(c);
      if (!seen.has(id)) { seen.add(id); rts.push({ id, sel: runtimeSelector(c) }); }
    }
    if (rts.length >= 2) {
      // multiple runtimes: compare them by runtime identity, so pinning swept
      // dimensions narrows each side to the chosen point (not one fixed config).
      const base = rts.find((r) => /trunk/i.test(r.id)) ?? rts[0];
      cs = [{
        kind: "inter", over: "runtime",
        label: `${rts.filter((r) => r !== base).map((r) => r.id).join(", ")} vs ${base.id} (auto)`,
        baseline: base.sel,
        variants: rts.filter((r) => r !== base).map((r) => r.sel),
      }];
    } else {
      // single runtime swept over configs: fall back to a fixed-config baseline.
      const base = configs[0];
      cs = [{
        kind: "inter", over: "runtime",
        label: `${configs.filter((c) => c !== base).map(label).join(", ")} vs ${label(base)} (auto)`,
        baseline: { config_id: base.config_id },
        variants: configs.filter((c) => c !== base).map((c) => ({ config_id: c.config_id })),
      }];
    }
  }
  return cs;
}

// ---- inter-runtime Δ (per benchmark × variant) for one metric --------------
export function interRows(cmp, { cell, benches, configs, metric }) {
  const baseCfgs = baselineConfigs(configs, cmp);
  const varCfgs = (cmp.variants ?? []).flatMap((s) => resolve(configs, s));
  // Drop dimensions that are constant across the run from the variant label —
  // they add no distinction (e.g. a fp/flambda-only run where every config
  // shares the same GC dimensions), leaving a clean "5.5.0-fp" identity.
  const ex = constantDims(configs);
  const rows = [];
  for (const v of varCfgs) {
    const b = baseCfgs.find((bc) => dimsKey(bc) === dimsKey(v)) ?? baseCfgs[0];
    if (!b) continue;
    for (const bench of benches) {
      const vv = median(cellGet(cell, bench, v.config_id, metric));
      const bv = median(cellGet(cell, bench, b.config_id, metric));
      const d = vv != null && bv ? (vv / bv - 1) * 100 : null;
      rows.push({ benchmark: bench, variant: label(v, ex), delta: d, verdict: verdict(d) });
    }
  }
  return rows.filter((r) => r.delta != null);
}

export function deltaChart(rows, metric) {
  const nV = new Set(rows.map((r) => r.variant)).size || 1;
  const nB = new Set(rows.map((r) => r.benchmark)).size || 1;
  return Plot.plot({
    marginLeft: 180,
    height: Math.max(160, nB * 20 * nV + 90),
    x: { label: `Δ ${metricLabel(metric)} vs baseline (%)`, grid: true, tickFormat: "+.0f" },
    y: { label: null }, fy: { label: null },
    color: { domain: statusDomain, range: statusDomain.map((s) => STATUS[s]), legend: true },
    marks: [
      Plot.barX(rows, {
        y: "benchmark", x: "delta", fy: nV > 1 ? "variant" : null, fill: "verdict", sort: { y: "x" }, tip: true,
        title: (d) => `${d.benchmark} — ${d.variant}\nΔ ${d.delta.toFixed(1)}%\n${d.verdict}`,
      }),
      Plot.ruleX([0]),
    ],
  });
}

// Heading for a baseline-vs-variant comparison: prefer a compact "variant vs
// baseline" by runtime identity (all dimensions dropped); if both are the same
// runtime, fall back to distinguishing them by their varying dimensions.
export function compareTitle(variant, baseline, configs) {
  const dk = dimensionKeys(configs);
  const rtOnly = (c) => label(c, dk);
  if (rtOnly(variant) !== rtOnly(baseline)) return `${rtOnly(variant)} vs ${rtOnly(baseline)}`;
  const ex = constantDims(configs);
  return `${label(variant, ex)} vs ${label(baseline, ex)}`;
}

export function deltaTable(rows) {
  return Inputs.table(
    rows.map((r) => ({ benchmark: r.benchmark, variant: r.variant, "Δ%": r.delta, verdict: r.verdict })),
    { format: { "Δ%": (x) => x.toFixed(2) }, sort: "Δ%", reverse: true, width: { verdict: 110 } }
  );
}

// ---- absolute values (per benchmark × runtime) -----------------------------
export function absoluteRows({ cell, benches, configs, metric }) {
  const ex = constantDims(configs); // clean runtime label — see interRows
  const rows = [];
  for (const c of configs)
    for (const bench of benches) {
      const v = median(cellGet(cell, bench, c.config_id, metric));
      if (v != null) rows.push({ benchmark: bench, runtime: label(c, ex), value: v });
    }
  return rows;
}
export function absoluteChart(rows, metric) {
  const nB = new Set(rows.map((r) => r.benchmark)).size || 1;
  const nR = new Set(rows.map((r) => r.runtime)).size || 1;
  return Plot.plot({
    marginLeft: 120,
    height: Math.max(160, nB * (nR * 16 + 26) + 60),
    x: { label: `${metricLabel(metric)} (median)`, grid: true },
    fy: { label: null }, y: { label: null, axis: null },
    color: { legend: true },
    marks: [
      Plot.barX(rows, { fy: "benchmark", y: "runtime", x: "value", fill: "runtime", sort: { fy: "-x" }, tip: true }),
      Plot.ruleX([0]),
    ],
  });
}

// ---- parameter-sweep heatmap ------------------------------------------------
export function sweepRows({ cell, configs, bench, metric, xDim, yDim }) {
  // Series = runtime identity: exclude the two axes and anything constant in the
  // (already pinned/filtered) set, so each runtime is ONE facet, not one facet
  // per (x, y) point.
  const ex = [xDim, yDim, ...constantDims(configs)];
  const rows = [];
  for (const c of configs) {
    const v = median(cellGet(cell, bench, c.config_id, metric));
    if (v != null) rows.push({ x: c.dimensions?.[xDim], y: c.dimensions?.[yDim], value: v, runtime: label(c, ex) });
  }
  return rows;
}
// Geometry shared by the sweep heatmaps: aim for large, square-ish cells and
// size the plot to the number of categories (× number of facet columns).
const CELL = 62;
function heatmapSize(rows, nFacets) {
  const nx = new Set(rows.map((r) => r.x)).size || 1;
  const ny = new Set(rows.map((r) => r.y)).size || 1;
  return {
    width: 70 + nFacets * (nx * CELL + 24),
    height: 60 + ny * CELL,
  };
}

export function heatmap(rows, { metric, xDim, yDim }) {
  const nR = new Set(rows.map((r) => r.runtime)).size || 1;
  // Cell text must stay readable across the whole YlGnBu ramp: light cells (low
  // values, yellow) need dark text; dark cells (high values, deep blue) need
  // light text. Pick per cell from the value's position in the data range.
  const vals = rows.map((r) => r.value).filter((v) => v != null);
  const lo = Math.min(...vals), hi = Math.max(...vals);
  const textFill = (d) => (d.value != null && hi > lo && (d.value - lo) / (hi - lo) > 0.55 ? "#fff" : "#111");
  const { width, height } = heatmapSize(rows, nR);
  return Plot.plot({
    marginLeft: 64, marginBottom: 48, width, height,
    color: { legend: true, scheme: "YlGnBu", label: `${metricLabel(metric)} (median)` },
    x: { label: xDim, type: "band", tickRotate: -30 },
    y: { label: yDim, type: "band" },
    fx: nR > 1 ? { label: null } : undefined,
    marks: [
      Plot.cell(rows, { x: "x", y: "y", fx: nR > 1 ? "runtime" : null, fill: "value", tip: true, inset: 0.5 }),
      Plot.text(rows, { x: "x", y: "y", fx: nR > 1 ? "runtime" : null, text: (d) => (d.value != null ? (+d.value).toPrecision(3) : ""), fill: textFill, fontSize: 10 }),
    ],
  });
}

// ---- inter-runtime Δ heatmap (variant vs baseline across the sweep) ---------
// For each (x, y) cell present in BOTH runtimes, the % change of the variant
// relative to the baseline. Negative = variant is better (green).
export function sweepDeltaRows({ cell, configs, bench, metric, xDim, yDim, baseSel, varSel }) {
  const baseCfgs = resolve(configs, baseSel);
  const key = (c) => JSON.stringify([c.dimensions?.[xDim], c.dimensions?.[yDim]]);
  const baseAt = new Map(baseCfgs.map((c) => [key(c), c]));
  const rows = [];
  for (const v of resolve(configs, varSel)) {
    const b = baseAt.get(key(v));
    if (!b) continue;
    const vv = median(cellGet(cell, bench, v.config_id, metric));
    const bv = median(cellGet(cell, bench, b.config_id, metric));
    const d = vv != null && bv ? (vv / bv - 1) * 100 : null;
    if (d != null) rows.push({ x: v.dimensions?.[xDim], y: v.dimensions?.[yDim], delta: d });
  }
  return rows;
}
export function deltaHeatmap(rows, { metric, xDim, yDim, baseLabel, varLabel }) {
  const max = Math.max(1, ...rows.map((r) => Math.abs(r.delta)));
  const { width, height } = heatmapSize(rows, 1);
  return Plot.plot({
    marginLeft: 64, marginBottom: 48, width, height,
    color: { type: "diverging", scheme: "RdYlGn", reverse: true, domain: [-max, max], pivot: 0,
      legend: true, label: `Δ ${metricLabel(metric)}: ${varLabel} vs ${baseLabel} (%)` },
    x: { label: xDim, type: "band", tickRotate: -30 },
    y: { label: yDim, type: "band" },
    marks: [
      Plot.cell(rows, { x: "x", y: "y", fill: "delta", tip: true, inset: 0.5 }),
      Plot.text(rows, { x: "x", y: "y", text: (d) => (d.delta >= 0 ? "+" : "") + d.delta.toFixed(1), fill: "#111", fontSize: 10 }),
    ],
  });
}

// ---- metric-vs-parameter curves --------------------------------------------
// The response of a metric (y) to one swept parameter (x), drawn as one line
// per runtime — the shape used in ocaml/ocaml#14796 to show how RSS / GC
// overhead track a target as the `o` (space_overhead) parameter varies. An
// optional facet dimension turns it into a small-multiples grid (as in that
// PR's off × ephe panels). Numeric x values are kept numeric so the line is
// monotone in the parameter, not in insertion order.
const numericish = (v) => (typeof v === "number" ? v : v != null && v !== "" && !isNaN(+v) ? +v : v);
export function curveRows({ cell, configs, bench, metric, xDim, facetDim }) {
  // Series = runtime identity: exclude the x axis, the facet, and anything
  // constant in the (pinned/filtered) set, so each runtime is ONE line.
  const ex = [xDim, facetDim, ...constantDims(configs)].filter(Boolean);
  const rows = [];
  for (const c of configs) {
    const x = c.dimensions?.[xDim];
    if (x == null) continue;
    const v = median(cellGet(cell, bench, c.config_id, metric));
    if (v == null) continue;
    rows.push({
      x: numericish(x),
      value: v,
      runtime: label(c, ex),
      facet: facetDim ? c.dimensions?.[facetDim] : null,
    });
  }
  return rows.sort((a, b) => cmpVal(a.x, b.x));
}

export function curveChart(rows, { metric, xDim, facetDim }) {
  const nF = facetDim ? new Set(rows.map((r) => r.facet)).size || 1 : 1;
  const xNumeric = rows.every((r) => typeof r.x === "number");
  return Plot.plot({
    marginLeft: 64,
    marginBottom: 44,
    width: Math.min(1100, 120 + nF * 320),
    height: 300 + (facetDim ? 40 : 0),
    grid: true,
    x: { label: xDim, type: xNumeric ? "linear" : "point", tickRotate: xNumeric ? 0 : -30 },
    y: { label: `${metricLabel(metric)} (median)`, zero: false },
    fx: facetDim ? { label: facetDim } : undefined,
    color: { legend: true, label: "runtime" },
    marks: [
      Plot.lineY(rows, { x: "x", y: "value", fx: facetDim ? "facet" : null, stroke: "runtime", sort: "x", curve: "monotone-x" }),
      Plot.dot(rows, { x: "x", y: "value", fx: facetDim ? "facet" : null, fill: "runtime", r: 2.5, tip: true,
        title: (d) => `${d.runtime}\n${xDim}=${d.x}${facetDim ? `, ${facetDim}=${d.facet}` : ""}\n${metricLabel(metric)}=${(+d.value).toPrecision(4)}` }),
    ],
  });
}

// ---- space × time tradeoff --------------------------------------------------
// A GC parameter point buys time with memory, or memory with time; neither axis
// is the "answer" on its own. So plot both: x = a space metric, y = a time
// metric, one point per configuration, joined along the swept parameter. The
// interesting configurations are the non-dominated ones — the Pareto frontier —
// and the interesting comparison between two runtimes is whether one runtime's
// whole frontier sits below/left of the other's.

export const ALL_BENCHES = "★ all benchmarks (normalized)";
export const geomean = (xs) => {
  const a = (xs ?? []).filter((v) => v != null && v > 0);
  return a.length ? Math.exp(a.reduce((s, v) => s + Math.log(v), 0) / a.length) : null;
};

// One number per (config, metric): a single benchmark's median, or — for
// ALL_BENCHES — the geometric mean over benchmarks of each benchmark's value
// relative to the BEST (smallest) value any shown config reached on it.
// Normalizing per benchmark is what makes a suite-level aggregate meaningful: a
// 3 GiB benchmark must not swamp a 30 MiB one, and 1.0 on an axis then reads as
// "as good as the best point in this view".
//
// The aggregate counts only benchmarks measured under EVERY shown config (a
// balanced panel). A benchmark that ran under one runtime but not the other
// (pplacer, in the 2026-07-18 sweep) would otherwise enter one side's geomean and
// not the other's, so the two aggregates would summarize different suites — worth
// ~1pp of phantom Δ in that run. With the panel balanced the per-benchmark
// normalizer cancels exactly in a ratio, so a Δ of aggregates IS the geomean of
// the per-benchmark Δs.
//
// Returns the accessor carrying `.benches` (aggregated) and `.dropped`
// (excluded), so a page can caption the real count and disclose what it left out.
export function valueTable({ cell, configs, benches, bench, metrics }) {
  const t = new Map(); // `${config_id}\0${metric}` -> number | null
  const key = (cid, m) => cid + "\u0000" + m;
  const at = (b, c, m) => median(cellGet(cell, b, c.config_id, m));
  const get = (cid, m) => t.get(key(cid, m)) ?? null;
  if (bench !== ALL_BENCHES) {
    for (const c of configs) for (const m of metrics) t.set(key(c.config_id, m), at(bench, c, m));
    return Object.assign(get, { benches: [bench], dropped: [] });
  }
  const complete = benches.filter((b) => metrics.every((m) => configs.every((c) => (at(b, c, m) ?? 0) > 0)));
  for (const m of metrics) {
    const ratios = new Map(configs.map((c) => [c.config_id, []]));
    for (const b of complete) {
      const vals = configs.map((c) => [c.config_id, at(b, c, m)]);
      const best = Math.min(...vals.map(([, v]) => v));
      for (const [cid, v] of vals) ratios.get(cid).push(v / best);
    }
    for (const c of configs) t.set(key(c.config_id, m), geomean(ratios.get(c.config_id)));
  }
  return Object.assign(get, { benches: complete, dropped: benches.filter((b) => !complete.includes(b)) });
}

// Compact parameter value for a direct label: GC parameters are word counts in
// the 10^5–10^6 range, and five raw digits per label is what turns a frontier
// into a smudge.
export const paramFmt = (v) => {
  if (typeof v !== "number" || Math.abs(v) < 1e4) return String(v);
  return v >= 1e6 ? +(v / 1e6).toFixed(v < 1e7 ? 1 : 0) + "M" : Math.round(v / 1e3) + "k";
};

// Which points earn a direct label: a number on every point is noise, so label
// only each series' anchors — its cheapest-space end, its fastest end, and its
// "knee" (the point nearest the ideal corner once both axes are normalized),
// which is the compromise configuration a reader is usually looking for. Full
// detail stays in the tooltip and the frontier table.
export function anchorPoints(rows, { key = (r) => JSON.stringify([r.facet ?? null, r.runtime]), x = (r) => r.x, y = (r) => r.y } = {}) {
  if (!rows.length) return [];
  const xs = rows.map(x), ys = rows.map(y);
  const [x0, x1] = [Math.min(...xs), Math.max(...xs)];
  const [y0, y1] = [Math.min(...ys), Math.max(...ys)];
  const dist = (r) => Math.hypot(x1 > x0 ? (x(r) - x0) / (x1 - x0) : 0, y1 > y0 ? (y(r) - y0) / (y1 - y0) : 0);
  const groups = new Map();
  for (const r of rows) {
    const k = key(r);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  const out = new Set();
  for (const g of groups.values()) {
    out.add(g.reduce((a, b) => (x(b) < x(a) ? b : a)));
    out.add(g.reduce((a, b) => (y(b) < y(a) ? b : a)));
    out.add(g.reduce((a, b) => (dist(b) < dist(a) ? b : a)));
  }
  return [...out];
}

// Axis caption: absolute values carry the contract's unit; the aggregate is
// unitless (a ratio to the best point in view), and saying so on the axis is the
// only thing that keeps the two modes from being confused for each other.
export function tradeoffAxis(metric, bench, nBenches) {
  if (bench === ALL_BENCHES) return `${metricLabel(metric)} (× best; geomean, n=${nBenches})`;
  const u = metricUnit(metric);
  return u ? `${metricLabel(metric)} (${u}, median)` : `${metricLabel(metric)} (median)`;
}

const dimText = (c, dims) => (dims ?? []).filter((d) => c.dimensions?.[d] !== undefined).map((d) => `${d}=${c.dimensions[d]}`).join(", ");

export function tradeoffRows({ val, configs, xMetric, yMetric, traceDim, facetDim, sweepDims = [] }) {
  // Color identity = runtime, NOT parameter point: the swept parameters are
  // already encoded by position along the trace, and letting them into the label
  // would turn a 5 × 5 grid into 25 colors.
  const ex = [...sweepDims, ...constantDims(configs)];
  const rows = [];
  for (const c of configs) {
    const x = val(c.config_id, xMetric), y = val(c.config_id, yMetric);
    if (x == null || y == null) continue;
    rows.push({
      x, y,
      runtime: label(c, ex),
      trace: traceDim ? numericish(c.dimensions?.[traceDim]) : null,
      facet: facetDim ? c.dimensions?.[facetDim] : null,
      // Line identity: same runtime AND the same value of every parameter other
      // than the traced one. Without this, an unpinned second parameter joins
      // points that differ in two dimensions at once — a zigzag, not a curve.
      z: label(c, [traceDim].filter(Boolean)),
      params: dimText(c, sweepDims),
      config_id: c.config_id,
    });
  }
  return rows.sort((a, b) => cmpVal(a.trace, b.trace));
}

// Non-dominated points, both axes lower-is-better: sort by x, keep only the ones
// that improve on the best y so far. Strict `<` also drops an equal-y point that
// costs more x — it is dominated.
export function paretoFront(rows) {
  const out = [];
  let best = Infinity;
  for (const r of [...rows].sort((a, b) => a.x - b.x || a.y - b.y)) if (r.y < best) { out.push(r); best = r.y; }
  return out;
}
// Tag each row with `front`, computed per (facet, runtime) — a frontier is a
// property of one runtime inside one panel, never of the pooled scatter.
export function withPareto(rows) {
  const groups = new Map();
  for (const r of rows) {
    const k = JSON.stringify([r.facet ?? null, r.runtime]);
    (groups.get(k) ?? groups.set(k, []).get(k)).push(r);
  }
  const front = new Set();
  for (const g of groups.values()) for (const r of paretoFront(g)) front.add(r);
  return rows.map((r) => ({ ...r, front: front.has(r) }));
}

// Wide plots must scroll, not shrink: Framework caps an <svg> at 100% of its
// container, which silently rescales a five-panel facet grid until its tick
// labels are illegible. A min-width inner box hands the svg its real width back
// and moves the overflow to a scrollbar.
const PER_FACET = 260;
export const scrollWrap = (node, width) =>
  html`<div style="overflow-x:auto;max-width:100%"><div style="min-width:${width}px">${node}</div></div>`;
const plotWidth = (nF) => (nF > 1 ? 96 + nF * PER_FACET : 760);
// A value for a tooltip: thousands-grouped rather than exponential (7.767e+5 is
// not a number anyone recognizes as an RSS), with the contract's unit attached.
const valueText = (v, metric, absolute) => {
  if (v == null) return "?";
  const n = Math.abs(v) >= 1e4 ? Math.round(v).toLocaleString("en-US") : (+v).toPrecision(4);
  const u = absolute ? metricUnit(metric) : "× best";
  return u ? `${n} ${u}` : n;
};

export function tradeoffChart(rows, { xMetric, yMetric, traceDim, facetDim, xLabel, yLabel, pareto = true, dark = false, absolute = true }) {
  const series = [...new Set(rows.map((r) => r.runtime))];
  const nF = facetDim ? new Set(rows.map((r) => r.facet)).size || 1 : 1;
  const surface = dark ? SURFACE.dark : SURFACE.light;
  const ink = dark ? INK.dark : INK.light;
  const front = rows.filter((r) => r.front);
  const fx = facetDim ? "facet" : null;
  const tick = (m) => (Math.max(...rows.map((r) => (m === "x" ? r.x : r.y))) >= 1e4 ? "~s" : undefined);
  const title = (d) =>
    [d.runtime, d.params || null, `${metricLabel(xMetric)} = ${valueText(d.x, xMetric, absolute)}`,
     `${metricLabel(yMetric)} = ${valueText(d.y, yMetric, absolute)}`,
     d.front ? "on the Pareto frontier" : null].filter(Boolean).join("\n");
  const plot = Plot.plot({
    // Extra headroom: the y-axis caption and (when faceted) the panel headers
    // both live in the top margin, and 12px puts them on top of the first tick.
    marginLeft: 72, marginBottom: 46, marginTop: nF > 1 ? 40 : 26,
    width: plotWidth(nF),
    height: nF > 1 ? 340 : 420,
    grid: true,
    x: { label: xLabel ?? tradeoffAxis(xMetric), nice: true, tickFormat: tick("x") },
    y: { label: yLabel ?? tradeoffAxis(yMetric), zero: false, nice: true, tickFormat: tick("y") },
    fx: facetDim ? { label: facetDim } : undefined,
    color: { domain: series, range: seriesRange(series.length, dark) },
    // Symbol repeats the series identity so the scatter never depends on hue
    // alone; the legend is drawn from this scale, filled by the color scale.
    symbol: { domain: series, legend: series.length > 1, label: "runtime" },
    marks: [
      // The trace: faint, so it orders the points without competing with them.
      Plot.line(rows, { x: "x", y: "y", z: "z", fx, stroke: "runtime", strokeWidth: 1.5, strokeOpacity: 0.35, curve: "linear" }),
      pareto ? Plot.line(front, { x: "x", y: "y", z: "runtime", fx, stroke: "runtime", strokeWidth: 2, strokeDasharray: "5 3", curve: "step-after", sort: "x" }) : null,
      // 2px surface ring keeps overlapping points readable where the two
      // runtimes' clouds intersect.
      Plot.dot(rows, { x: "x", y: "y", fx, fill: "runtime", symbol: "runtime", r: 4.5, stroke: surface, strokeWidth: 1.5 }),
      pareto ? Plot.dot(front, { x: "x", y: "y", fx, fill: "runtime", symbol: "runtime", r: 7, stroke: surface, strokeWidth: 1.5 }) : null,
      // Direct labels on each frontier's anchors only (ends + knee), offset
      // up-right into the empty side of a descending frontier.
      traceDim && pareto ? Plot.text(anchorPoints(front), { x: "x", y: "y", fx, text: (d) => paramFmt(d.trace), dx: 7, dy: -8, textAnchor: "start", fill: ink, fontSize: 10 }) : null,
      // Invisible 24px hit target: the visible dot is 9px, which is a pinpoint to
      // aim at. Plot's pointer transform picks the nearest one.
      Plot.dot(rows, { x: "x", y: "y", fx, r: 12, fillOpacity: 0, stroke: "none", tip: { format: { x: null, y: null, fx: null } }, title }),
    ].filter(Boolean),
  });
  return nF > 1 ? scrollWrap(plot, plotWidth(nF)) : plot;
}

// Frontier as a table: the accessible twin of the chart, and the answer to "so
// which parameters do I actually set?". Ordered by the space axis, so it reads
// along the frontier from the cheapest configuration to the fastest.
export function paretoTable(rows, { xMetric, yMetric, bench }) {
  const abs = bench !== ALL_BENCHES;
  const unit = (m) => (abs ? (metricUnit(m) ?? "") : "× best");
  const data = rows.filter((r) => r.front)
    .map((r) => ({ runtime: r.runtime, parameters: r.params, space: r.x, time: r.y }))
    .sort((a, b) => a.space - b.space);
  const num = (v) => (v == null ? "" : Math.abs(v) >= 1e4 ? Math.round(v).toLocaleString("en-US") : (+v).toPrecision(4));
  return Inputs.table(data, {
    header: { space: `${metricLabel(xMetric)} (${unit(xMetric)})`, time: `${metricLabel(yMetric)} (${unit(yMetric)})` },
    format: { space: num, time: num },
    // The parameter set is the payload of this table; it must not be ellipsized.
    width: { runtime: 170, parameters: 300 },
  });
}

// ---- Δ space vs Δ time (the cost/benefit quadrant) --------------------------
// Same idea, expressed as a comparison: for every parameter point present in
// BOTH runtimes, how much space the variant costs and how much time it saves.
// Lower-left = better on both; the off-diagonal quadrants are the real tradeoffs.
export const QUADRANTS = [
  { name: "better on both", color: STATUS.improvement },
  { name: "space ↑ / time ↓", color: STATUS.warn },
  { name: "space ↓ / time ↑", color: STATUS.neutral },
  { name: "worse on both", color: STATUS.regression },
];
const quadrant = (dx, dy) => (dx <= 0 && dy <= 0 ? "better on both" : dx > 0 && dy > 0 ? "worse on both" : dx > 0 ? "space ↑ / time ↓" : "space ↓ / time ↑");

export function tradeoffDeltaRows({ val, configs, xMetric, yMetric, baseSel, varSel, traceDim, facetDim, sweepDims = [] }) {
  const key = (c) => JSON.stringify(Object.entries(c.dimensions ?? {}).sort(([a], [b]) => a.localeCompare(b)));
  const baseAt = new Map(resolve(configs, baseSel).map((c) => [key(c), c]));
  const ex = [...sweepDims, ...constantDims(configs)];
  const rows = [];
  for (const v of resolve(configs, varSel)) {
    const b = baseAt.get(key(v));
    if (!b) continue;
    const vx = val(v.config_id, xMetric), bx = val(b.config_id, xMetric);
    const vy = val(v.config_id, yMetric), by = val(b.config_id, yMetric);
    if (vx == null || !bx || vy == null || !by) continue;
    const dx = (vx / bx - 1) * 100, dy = (vy / by - 1) * 100;
    rows.push({
      dx, dy, quadrant: quadrant(dx, dy), runtime: label(v, ex),
      trace: traceDim ? numericish(v.dimensions?.[traceDim]) : null,
      facet: facetDim ? v.dimensions?.[facetDim] : null,
      // Same rule as tradeoffRows: a trace line may only join points that differ
      // in the traced parameter alone, or an unpinned second parameter turns the
      // quadrant into spaghetti.
      z: label(v, [traceDim].filter(Boolean)),
      params: dimText(v, sweepDims),
    });
  }
  return rows.sort((a, b) => cmpVal(a.trace, b.trace));
}

export function tradeoffDeltaChart(rows, { xMetric, yMetric, traceDim, facetDim, dark = false }) {
  const nF = facetDim ? new Set(rows.map((r) => r.facet)).size || 1 : 1;
  const surface = dark ? SURFACE.dark : SURFACE.light;
  const ink = dark ? INK.dark : INK.light;
  const fx = facetDim ? "facet" : null;
  const used = QUADRANTS.filter((q) => rows.some((r) => r.quadrant === q.name));
  const pct = (v) => (v >= 0 ? "+" : "") + v.toFixed(1) + "%";
  const plot = Plot.plot({
    marginLeft: 72, marginBottom: 46, marginTop: nF > 1 ? 40 : 26,
    width: plotWidth(nF),
    height: nF > 1 ? 340 : 420,
    grid: true,
    x: { label: `Δ ${metricLabel(xMetric)} — space cost (%)`, tickFormat: "+.0f", nice: true },
    y: { label: `Δ ${metricLabel(yMetric)} — time cost (%)`, tickFormat: "+.0f", nice: true },
    fx: facetDim ? { label: facetDim } : undefined,
    color: { domain: used.map((q) => q.name), range: used.map((q) => q.color), legend: true, label: "quadrant (vs baseline)" },
    symbol: { domain: [...new Set(rows.map((r) => r.runtime))] },
    marks: [
      Plot.ruleX([0]), Plot.ruleY([0]),
      Plot.line(rows, { x: "dx", y: "dy", z: "z", fx, stroke: ink, strokeOpacity: 0.2, strokeWidth: 1.5, sort: "trace" }),
      Plot.dot(rows, { x: "dx", y: "dy", fx, fill: "quadrant", symbol: "runtime", r: 5, stroke: surface, strokeWidth: 1.5 }),
      // Label each trace's two ends — enough to read the direction the traced
      // parameter pushes a point, without a number on all 25.
      traceDim ? Plot.text(anchorPoints(rows, { key: (r) => JSON.stringify([r.facet ?? null, r.z]), x: (r) => r.dx, y: (r) => r.dy }),
        { x: "dx", y: "dy", fx, text: (d) => paramFmt(d.trace), dx: 7, dy: -8, textAnchor: "start", fill: ink, fontSize: 10 }) : null,
      Plot.dot(rows, { x: "dx", y: "dy", fx, r: 12, fillOpacity: 0, stroke: "none", tip: { format: { x: null, y: null, fx: null } },
        title: (d) => [d.runtime, d.params || null, `Δ ${metricLabel(xMetric)} ${pct(d.dx)}`, `Δ ${metricLabel(yMetric)} ${pct(d.dy)}`, d.quadrant].filter(Boolean).join("\n") }),
    ].filter(Boolean),
  });
  return nF > 1 ? scrollWrap(plot, plotWidth(nF)) : plot;
}

export { html };
