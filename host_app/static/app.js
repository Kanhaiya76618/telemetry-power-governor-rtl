const connDot = document.getElementById('connDot');
const connText = document.getElementById('connText');
const ack = document.getElementById('ack');
const themeToggle = document.getElementById('themeToggle');
const themeIcon = document.getElementById('themeIcon');

function el(id) {
  return document.getElementById(id);
}

const fields = {
  stateA: el('stateA'),
  stateB: el('stateB'),
  grantA: el('grantA'),
  grantB: el('grantB'),
  clkEnA: el('clkEnA'),
  clkEnB: el('clkEnB'),
  eff: el('eff'),
  budget: el('budget'),
  headroom: el('headroom'),
  frame: el('frame'),
  tempA: el('tempA'),
  tempB: el('tempB'),
  actA: el('actA'),
  actB: el('actB'),
  stallA: el('stallA'),
  stallB: el('stallB'),
  reqA: el('reqA'),
  reqB: el('reqB'),
  phase: el('phase'),
  mode: el('mode'),
  alarmA: el('alarmA'),
  alarmB: el('alarmB'),
  eff2: el('eff2'),
  budget2: el('budget2'),
  headroom2: el('headroom2'),
  serialPort: el('serialPort'),
};

const modeSelect = el('modeSelect');
const extBudgetSelect = el('extBudgetSelect');
const budgetInput = el('budgetInput');
const reqAInput = el('reqAInput');
const reqBInput = el('reqBInput');
const tempAInput = el('tempAInput');
const tempBInput = el('tempBInput');
const actAToggle = el('actAToggle');
const stallAToggle = el('stallAToggle');
const actBToggle = el('actBToggle');
const stallBToggle = el('stallBToggle');

const scenarioSelect = el('scenarioSelect');
const runScenarioBtn = el('runScenarioBtn');
const stopScenarioBtn = el('stopScenarioBtn');
const scenarioStatus = el('scenarioStatus');
const scenarioSummary = el('scenarioSummary');
const scenarioExplain = el('scenarioExplain');
const modeExplain = el('modeExplain');
const tbExplainList = el('tbExplainList');
const runSimBtn = el('runSimBtn');
const refreshSimTestsBtn = el('refreshSimTestsBtn');
const simStatus = el('simStatus');
const simCatalog = el('simCatalog');
const simResults = el('simResults');

const navBtns = document.querySelectorAll('.nav-btn');
const leftCol = document.querySelector('.left-col');
const rightCol = document.querySelector('.right-col');

const stateNames = ['SLEEP', 'LOW_POWER', 'ACTIVE', 'TURBO'];
const stateClassMap = { SLEEP: 'sleep', LOW_POWER: 'low', ACTIVE: 'active', TURBO: 'turbo' };

let ws = null;
let pendingState = null;
let renderQueued = false;
let formDirty = false;
let lastTrendFrame = -1;
let lastTrendPushMs = 0;
let scenarioRunning = false;
let simRunning = false;
let scenarioMetaByName = {};
let simCatalogCache = [];
const fieldLockUntil = {};

const ctrlIds = ['modeSelect', 'extBudgetSelect', 'budgetInput', 'reqAInput', 'reqBInput', 'tempAInput', 'tempBInput', 'actAToggle', 'stallAToggle', 'actBToggle', 'stallBToggle'];

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v));
}

function toFiniteNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function escapeHtml(input) {
  return String(input)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function lockField(fieldId, ms = 2200) {
  if (!fieldId) return;
  fieldLockUntil[fieldId] = Date.now() + ms;
}

function isFieldLocked(fieldOrId) {
  const id = typeof fieldOrId === 'string' ? fieldOrId : fieldOrId && fieldOrId.id;
  if (!id) return false;
  return (fieldLockUntil[id] || 0) > Date.now();
}

function lockFieldsForPayload(payload) {
  const map = {
    mode: 'modeSelect',
    host_use_ext_budget: 'extBudgetSelect',
    budget: 'budgetInput',
    req_a: 'reqAInput',
    req_b: 'reqBInput',
    temp_a: 'tempAInput',
    temp_b: 'tempBInput',
    act_a: 'actAToggle',
    stall_a: 'stallAToggle',
    act_b: 'actBToggle',
    stall_b: 'stallBToggle',
  };
  Object.keys(map).forEach((k) => {
    if (Object.prototype.hasOwnProperty.call(payload, k)) {
      lockField(map[k], k === 'mode' ? 3000 : 2200);
    }
  });
}

function updateModeExplanation(state) {
  if (!modeExplain) return;
  if (state.host_mode) {
    modeExplain.textContent = 'Host-injected telemetry mode: control form values are written to FPGA and should reflect after command ACK.';
    return;
  }
  modeExplain.textContent = 'Internal workload_sim mode: RTL simulation logic auto-drives activity, requests, and temperatures.';
}

function updateScenarioExplain() {
  if (!scenarioExplain || !scenarioSelect) return;
  const selected = scenarioMetaByName[scenarioSelect.value];
  if (!selected) {
    scenarioExplain.textContent = 'Scenario details and mapped testbench will appear here.';
    return;
  }
  const desc = String(selected.description || '').replace(/\s+$/, '').replace(/[.]$/, '');
  const source = selected.source_testbench ? ` Source testbench: ${selected.source_testbench}.` : '';
  scenarioExplain.textContent = `${desc}.${source}`;
}

function decodeState(v) {
  return stateNames[v] || `S${v}`;
}

function toInt(input, min, max, fallback) {
  if (!input) return fallback;
  const n = Number(input.value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(n)));
}

function setIfIdle(inputEl, value) {
  if (!inputEl) return;
  if (document.activeElement === inputEl) return;
  if (isFieldLocked(inputEl)) return;
  inputEl.value = String(value);
}

function setCheckedIfIdle(inputEl, value) {
  if (!inputEl) return;
  if (document.activeElement === inputEl) return;
  if (isFieldLocked(inputEl)) return;
  inputEl.checked = !!value;
}

function makeLineChart(canvasId, datasets) {
  const target = el(canvasId);
  if (!target || typeof Chart === 'undefined') return null;
  try {
    return new Chart(target, {
      type: 'line',
      data: {
        labels: [],
        datasets,
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        normalized: true,
        scales: {
          x: {
            ticks: { color: '#8fb0bd' },
            grid: { color: 'rgba(255,255,255,0.06)' },
          },
          y: {
            ticks: { color: '#8fb0bd' },
            grid: { color: 'rgba(255,255,255,0.06)' },
          },
        },
        plugins: {
          legend: { labels: { color: '#cfe5ee' } },
        },
      },
    });
  } catch (err) {
    console.error(`Chart init failed for ${canvasId}`, err);
    return null;
  }
}

function makeVerifyChart() {
  const target = el('verifyChart');
  if (!target || typeof Chart === 'undefined') return null;
  try {
    return new Chart(target, {
      type: 'line',
      data: {
        labels: [],
        datasets: [
          { label: 'Grant A', data: [], borderColor: '#4fc3f7', tension: 0.15, pointRadius: 0, yAxisID: 'yCtl' },
          { label: 'Grant B', data: [], borderColor: '#81c784', tension: 0.15, pointRadius: 0, yAxisID: 'yCtl' },
          { label: 'Budget', data: [], borderColor: '#ffd54f', tension: 0.15, pointRadius: 0, yAxisID: 'yCtl' },
          { label: 'Efficiency', data: [], borderColor: '#ef5350', tension: 0.15, pointRadius: 0, yAxisID: 'yEff' },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        normalized: true,
        interaction: {
          mode: 'index',
          intersect: false,
        },
        layout: {
          padding: {
            top: 10,
            right: 24,
            left: 6,
            bottom: 4,
          },
        },
        plugins: {
          legend: {
            position: 'top',
            labels: {
              color: '#cfe5ee',
              boxWidth: 26,
              boxHeight: 10,
              padding: 14,
            },
          },
        },
        scales: {
          x: {
            ticks: { color: '#8fb0bd', maxRotation: 0, autoSkip: true, maxTicksLimit: 10 },
            grid: { color: 'rgba(255,255,255,0.06)' },
            title: { display: true, text: 'Scenario Time (s)', color: '#8fb0bd' },
          },
          yCtl: {
            type: 'linear',
            position: 'left',
            min: 0,
            max: 7,
            ticks: { color: '#8fb0bd', stepSize: 1 },
            grid: { color: 'rgba(255,255,255,0.08)' },
            title: { display: true, text: 'Grant / Budget', color: '#8fb0bd' },
          },
          yEff: {
            type: 'linear',
            position: 'right',
            min: 0,
            max: 1023,
            ticks: { color: '#f1a0a0', stepSize: 128 },
            grid: { drawOnChartArea: false },
            title: { display: true, text: 'Efficiency', color: '#f1a0a0' },
          },
        },
      },
    });
  } catch (err) {
    console.error('Chart init failed for verifyChart', err);
    return null;
  }
}

const trendChart = makeLineChart('trendChart', [
  { label: 'Efficiency', data: [], borderColor: '#00c9a7', tension: 0.20, pointRadius: 0 },
  { label: 'Temp A', data: [], borderColor: '#ffa94d', tension: 0.20, pointRadius: 0 },
  { label: 'Temp B', data: [], borderColor: '#ff6f61', tension: 0.20, pointRadius: 0 },
]);

const verifyChart = makeVerifyChart();

function setConnection(online, labelOverride = null) {
  if (connDot) {
    connDot.classList.toggle('online', !!online);
    connDot.classList.toggle('offline', !online);
  }
  if (connText) {
    connText.textContent = labelOverride || (online ? 'Connected' : 'Disconnected');
  }
}

function updateAlarm(elm, on, title) {
  if (!elm) return;
  elm.classList.toggle('on', !!on);
  elm.textContent = `${title}: ${on ? 'ON' : 'OFF'}`;
}

function showView(v) {
  navBtns.forEach((b) => b.classList.toggle('active', b.dataset.view === v));
  if (!leftCol || !rightCol) return;
  if (v === 'dashboard') {
    leftCol.style.display = '';
    rightCol.style.display = '';
    return;
  }
  if (v === 'telemetry') {
    leftCol.style.display = '';
    rightCol.style.display = 'none';
    return;
  }
  if (v === 'controls') {
    leftCol.style.display = 'none';
    rightCol.style.display = '';
  }
}

function applyTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  try {
    localStorage.setItem('pwrgov-theme', t);
  } catch (_e) {}
  if (themeIcon) themeIcon.textContent = t === 'light' ? '☀️' : '🌙';
}

function pushTrendPoint(state) {
  if (!trendChart) return;
  const frame = state.frame_counter ?? 0;
  const now = Date.now();
  if (frame === lastTrendFrame) return;
  if (now - lastTrendPushMs < 180) return;

  lastTrendFrame = frame;
  lastTrendPushMs = now;

  const labels = trendChart.data.labels;
  labels.push(new Date().toLocaleTimeString());
  trendChart.data.datasets[0].data.push(toFiniteNumber(state.efficiency, 0));
  trendChart.data.datasets[1].data.push(toFiniteNumber(state.temp_a, 0));
  trendChart.data.datasets[2].data.push(toFiniteNumber(state.temp_b, 0));

  while (labels.length > 80) {
    labels.shift();
    trendChart.data.datasets.forEach((ds) => ds.data.shift());
  }

  try {
    trendChart.update('none');
  } catch (err) {
    console.error('trendChart update failed', err);
  }
}

function syncManualControlsFromState(state) {
  if (!modeSelect) return;
  const mode = state.host_mode ? 'host' : 'internal';
  if (!formDirty && !isFieldLocked(modeSelect) && document.activeElement !== modeSelect) {
    modeSelect.value = mode;
  }

  if (formDirty) return;
  if (mode !== 'host') return;

  setIfIdle(budgetInput, state.current_budget ?? 0);
  setIfIdle(reqAInput, state.req_a ?? 0);
  setIfIdle(reqBInput, state.req_b ?? 0);
  setIfIdle(tempAInput, state.temp_a ?? 0);
  setIfIdle(tempBInput, state.temp_b ?? 0);
  setCheckedIfIdle(actAToggle, state.act_a);
  setCheckedIfIdle(stallAToggle, state.stall_a);
  setCheckedIfIdle(actBToggle, state.act_b);
  setCheckedIfIdle(stallBToggle, state.stall_b);
}

function render(state) {
  setConnection(!!state.connected);
  updateModeExplanation(state);

  const sA = decodeState(state.grant_a || 0);
  const sB = decodeState(state.grant_b || 0);
  if (fields.stateA) fields.stateA.textContent = sA;
  if (fields.stateB) fields.stateB.textContent = sB;

  if (fields.stateA) {
    Object.values(stateClassMap).forEach((c) => fields.stateA.classList.remove(c));
    fields.stateA.classList.add(stateClassMap[sA] || 'sleep');
  }
  if (fields.stateB) {
    Object.values(stateClassMap).forEach((c) => fields.stateB.classList.remove(c));
    fields.stateB.classList.add(stateClassMap[sB] || 'sleep');
  }

  if (fields.grantA) fields.grantA.textContent = state.grant_a ?? 0;
  if (fields.grantB) fields.grantB.textContent = state.grant_b ?? 0;
  if (fields.clkEnA) fields.clkEnA.textContent = state.clk_en_a ?? 0;
  if (fields.clkEnB) fields.clkEnB.textContent = state.clk_en_b ?? 0;

  if (fields.eff) fields.eff.textContent = state.efficiency ?? 0;
  if (fields.budget) fields.budget.textContent = state.current_budget ?? 0;
  if (fields.headroom) fields.headroom.textContent = state.budget_headroom ?? 0;
  if (fields.eff2) fields.eff2.textContent = state.efficiency ?? 0;
  if (fields.budget2) fields.budget2.textContent = state.current_budget ?? 0;
  if (fields.headroom2) fields.headroom2.textContent = state.budget_headroom ?? 0;
  if (fields.frame) fields.frame.textContent = state.frame_counter ?? 0;

  if (fields.tempA) fields.tempA.textContent = state.temp_a ?? 0;
  if (fields.tempB) fields.tempB.textContent = state.temp_b ?? 0;
  if (fields.actA) fields.actA.textContent = state.act_a ?? 0;
  if (fields.actB) fields.actB.textContent = state.act_b ?? 0;
  if (fields.stallA) fields.stallA.textContent = state.stall_a ?? 0;
  if (fields.stallB) fields.stallB.textContent = state.stall_b ?? 0;
  if (fields.reqA) fields.reqA.textContent = state.req_a ?? 0;
  if (fields.reqB) fields.reqB.textContent = state.req_b ?? 0;
  if (fields.phase) fields.phase.textContent = state.phase ?? 0;
  if (fields.mode) fields.mode.textContent = state.host_mode ? 'host' : 'internal';
  if (fields.serialPort) fields.serialPort.textContent = state.serial_port || '-';

  updateAlarm(fields.alarmA, state.alarm_a, 'Alarm A');
  updateAlarm(fields.alarmB, state.alarm_b, 'Alarm B');

  syncManualControlsFromState(state);
  pushTrendPoint(state);
}

function queueRender(state) {
  pendingState = state;
  if (renderQueued) return;
  renderQueued = true;
  requestAnimationFrame(() => {
    renderQueued = false;
    if (!pendingState) return;
    render(pendingState);
    pendingState = null;
  });
}

function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);

  ws.onopen = () => setConnection(true);
  ws.onmessage = (ev) => {
    try {
      queueRender(JSON.parse(ev.data));
    } catch (e) {
      console.error(e);
    }
  };
  ws.onclose = () => {
    setConnection(false);
    setTimeout(connectWs, 1200);
  };
}

async function pollFallback() {
  try {
    const res = await fetch('/api/state');
    if (!res.ok) return;
    queueRender(await res.json());
  } catch (_e) {
    setConnection(false);
  }
}

async function sendControlPayload(payload) {
  const submitBtn = document.querySelector('#ctrlForm button[type="submit"]');
  lockFieldsForPayload(payload);
  if (submitBtn) {
    submitBtn.disabled = true;
    submitBtn.textContent = 'Sending...';
  }

  try {
    const res = await fetch('/api/control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const out = await res.json();
    if (!res.ok) {
      throw new Error(out.detail || `HTTP ${res.status}`);
    }
    if (out.state) queueRender(out.state);
    if (ack) ack.textContent = JSON.stringify(out, null, 2);
    formDirty = false;
    return out;
  } catch (err) {
    if (ack) ack.textContent = `control send failed: ${err}`;
    throw err;
  } finally {
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.textContent = 'Send Control Command';
    }
  }
}

async function loadScenarios() {
  if (!scenarioSelect) return;
  scenarioSelect.innerHTML = '';
  scenarioMetaByName = {};
  try {
    const res = await fetch('/api/scenarios');
    const data = await res.json();
    const scenarios = data.scenarios || [];
    scenarios.forEach((s) => {
      scenarioMetaByName[s.name] = s;
      const opt = document.createElement('option');
      opt.value = s.name;
      opt.textContent = `${s.name} (${s.steps} steps)`;
      opt.title = s.description;
      scenarioSelect.appendChild(opt);
    });
    updateScenarioExplain();
    if (!scenarios.length && scenarioStatus) {
      scenarioStatus.textContent = 'No scenarios available from backend.';
    }
  } catch (e) {
    if (scenarioStatus) scenarioStatus.textContent = `Scenario list failed: ${e}`;
  }
}

function renderTestbenchNotes(list) {
  if (!tbExplainList) return;
  tbExplainList.innerHTML = '';
  if (!list.length) {
    const li = document.createElement('li');
    li.textContent = 'No testbench notes returned by backend.';
    tbExplainList.appendChild(li);
    return;
  }
  list.forEach((tb) => {
    const li = document.createElement('li');
    li.textContent = `${tb.name}: ${tb.summary}`;
    li.title = tb.focus || '';
    tbExplainList.appendChild(li);
  });
}

async function loadTestbenchNotes() {
  try {
    const res = await fetch('/api/testbenches');
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    const data = await res.json();
    const list = data.testbenches || [];
    renderTestbenchNotes(list);
  } catch (e) {
    renderTestbenchNotes([]);
    if (ack) ack.textContent = `backend testbench notes unavailable: ${e}`;
  }
}

function setSimRunUi(running) {
  simRunning = !!running;
  if (runSimBtn) {
    runSimBtn.disabled = simRunning;
    runSimBtn.textContent = simRunning ? 'Running Tests...' : 'Run All RTL Tests';
  }
}

function renderSimCatalog(list) {
  if (!simCatalog) return;
  simCatalog.innerHTML = '';
  if (!list || !list.length) {
    const li = document.createElement('li');
    li.textContent = 'No simulation tests defined by backend.';
    simCatalog.appendChild(li);
    return;
  }

  list.forEach((test) => {
    const li = document.createElement('li');
    const expects = Array.isArray(test.expects) ? test.expects.join(' | ') : '';
    li.innerHTML = `<strong>${escapeHtml(test.label)}</strong> <span class="sim-kind">(${escapeHtml(test.kind)})</span><br/>${escapeHtml(test.description)}${expects ? `<br/><span class="sim-expects">Checks: ${escapeHtml(expects)}</span>` : ''}`;
    simCatalog.appendChild(li);
  });
}

function renderSimResults(out) {
  if (!simResults) return;
  simResults.innerHTML = '';

  const results = (out && out.results) || [];
  if (!results.length) {
    simResults.innerHTML = '<div class="sim-empty">No results returned.</div>';
    return;
  }

  results.forEach((r) => {
    const card = document.createElement('div');
    card.className = `sim-result ${r.passed ? 'pass' : 'fail'}`;

    const expects = Array.isArray(r.expects) ? r.expects.join(' | ') : '';
    const compileMs = r.compile && Number.isFinite(r.compile.elapsed_ms) ? r.compile.elapsed_ms : 0;
    const runMs = r.run && Number.isFinite(r.run.elapsed_ms) ? r.run.elapsed_ms : 0;
    const compileTail = r.compile && r.compile.log_tail ? r.compile.log_tail : '(no compile log)';
    const runTail = r.run && r.run.log_tail ? r.run.log_tail : '(no run log)';

    card.innerHTML = `
      <div class="sim-result-head">
        <strong>${escapeHtml(r.label || r.id)}</strong>
        <span class="sim-pill ${r.passed ? 'pass' : 'fail'}">${r.passed ? 'PASS' : 'FAIL'}</span>
      </div>
      <div class="sim-result-desc">${escapeHtml(r.description || '')}</div>
      ${expects ? `<div class="sim-expects">Expected: ${escapeHtml(expects)}</div>` : ''}
      <div class="sim-timing">compile ${compileMs} ms${r.kind === 'simulation' ? ` | run ${runMs} ms` : ''}</div>
      ${r.passed ? '<div class="sim-result-note">Behavior matched expected checks.</div>' : `<div class="sim-result-note fail-note">${escapeHtml(r.reason || 'failure')}</div>`}
      <details>
        <summary>Compiler log tail</summary>
        <pre>${escapeHtml(compileTail)}</pre>
      </details>
      ${r.kind === 'simulation' ? `<details><summary>Simulation log tail</summary><pre>${escapeHtml(runTail)}</pre></details>` : ''}
    `;

    simResults.appendChild(card);
  });
}

async function loadSimCatalog() {
  if (simStatus) simStatus.textContent = 'Loading simulation test catalog...';
  try {
    const res = await fetch('/api/sim/tests');
    const out = await res.json();
    if (!res.ok) throw new Error(out.detail || `HTTP ${res.status}`);

    simCatalogCache = out.tests || [];
    renderSimCatalog(simCatalogCache);

    if (simStatus) {
      if (out.tooling_ready) {
        const tool = out.tooling && out.tooling.iverilog ? out.tooling.iverilog : 'iverilog';
        simStatus.textContent = `Simulation tooling ready (${tool}). ${simCatalogCache.length} tests available.`;
      } else {
        simStatus.textContent = 'Icarus tooling not detected by backend. Install iverilog/vvp and restart backend.';
      }
    }
  } catch (e) {
    renderSimCatalog([]);
    if (simStatus) simStatus.textContent = `Simulation catalog load failed: ${e}`;
  }
}

async function runSimTests() {
  if (simRunning) return;
  setSimRunUi(true);
  if (simStatus) simStatus.textContent = 'Running RTL simulations with Icarus Verilog...';

  try {
    const res = await fetch('/api/sim/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ timeout_s: 25.0 }),
    });
    const out = await res.json();
    if (!res.ok) throw new Error(out.detail || `HTTP ${res.status}`);

    renderSimResults(out);
    if (simStatus) {
      simStatus.textContent = `Simulation run complete: ${out.passed}/${out.total} passed, ${out.failed} failed.`;
    }
    if (ack) {
      ack.textContent = JSON.stringify(
        {
          sim_total: out.total,
          sim_passed: out.passed,
          sim_failed: out.failed,
          elapsed_ms: out.elapsed_ms,
          tooling: out.tooling,
        },
        null,
        2,
      );
    }
  } catch (e) {
    if (simStatus) simStatus.textContent = `Simulation run failed: ${e}`;
  } finally {
    setSimRunUi(false);
  }
}

function renderScenarioTimeline(result) {
  if (!verifyChart) return;
  const timeline = Array.isArray(result.timeline) ? result.timeline : [];

  const labels = [];
  const grantA = [];
  const grantB = [];
  const budget = [];
  const effValues = [];

  timeline.forEach((p) => {
    const tMs = toFiniteNumber(p && p.t_ms, 0);
    labels.push((tMs / 1000).toFixed(1));
    grantA.push(toFiniteNumber(p && p.grant_a, 0));
    grantB.push(toFiniteNumber(p && p.grant_b, 0));
    budget.push(toFiniteNumber(p && p.current_budget, 0));
    effValues.push(toFiniteNumber(p && p.efficiency, 0));
  });

  const effPeak = effValues.length ? Math.max(...effValues, 64) : 64;
  const effAxisMax = Math.max(128, Math.ceil(effPeak / 64) * 64);

  if (verifyChart.options.scales && verifyChart.options.scales.yEff && verifyChart.options.scales.yEff.ticks) {
    verifyChart.options.scales.yEff.max = effAxisMax;
    verifyChart.options.scales.yEff.ticks.stepSize = effAxisMax <= 256 ? 32 : (effAxisMax <= 512 ? 64 : 128);
  }

  verifyChart.data.labels = labels;
  verifyChart.data.datasets[0].data = grantA;
  verifyChart.data.datasets[1].data = grantB;
  verifyChart.data.datasets[2].data = budget;
  verifyChart.data.datasets[3].data = effValues;
  try {
    verifyChart.update('none');
  } catch (err) {
    console.error('verifyChart update failed', err);
  }

  if (scenarioSummary) {
    scenarioSummary.textContent = JSON.stringify(
      {
        name: result.name,
        description: result.description,
        status: result.status || 'completed',
        points: result.points,
        sample_ms: result.sample_ms,
        final_state: result.final_state,
      },
      null,
      2,
    );
  }

  if (result.final_state) {
    queueRender(result.final_state);
  }
}

function bindQuickButtons() {
  const handlers = {
    btnToggleMode: async () => {
      if (!modeSelect) return;
      const next = modeSelect.value === 'internal' ? 'host' : 'internal';
      modeSelect.value = next;
      await sendControlPayload({ mode: next });
    },
    btnToggleExtBudget: async () => {
      if (!extBudgetSelect) return;
      const next = extBudgetSelect.value !== 'true';
      extBudgetSelect.value = next ? 'true' : 'false';
      await sendControlPayload({ host_use_ext_budget: next });
    },
    btnReqAPlus: async () => {
      if (!reqAInput) return;
      reqAInput.value = String(clamp(Number(reqAInput.value || 0) + 1, 0, 3));
      await sendControlPayload({ req_a: Number(reqAInput.value) });
    },
    btnReqAMinus: async () => {
      if (!reqAInput) return;
      reqAInput.value = String(clamp(Number(reqAInput.value || 0) - 1, 0, 3));
      await sendControlPayload({ req_a: Number(reqAInput.value) });
    },
    btnReqBPlus: async () => {
      if (!reqBInput) return;
      reqBInput.value = String(clamp(Number(reqBInput.value || 0) + 1, 0, 3));
      await sendControlPayload({ req_b: Number(reqBInput.value) });
    },
    btnReqBMinus: async () => {
      if (!reqBInput) return;
      reqBInput.value = String(clamp(Number(reqBInput.value || 0) - 1, 0, 3));
      await sendControlPayload({ req_b: Number(reqBInput.value) });
    },
    btnBudgetPlus: async () => {
      if (!budgetInput) return;
      budgetInput.value = String(clamp(Number(budgetInput.value || 0) + 1, 0, 7));
      await sendControlPayload({ budget: Number(budgetInput.value) });
    },
    btnBudgetMinus: async () => {
      if (!budgetInput) return;
      budgetInput.value = String(clamp(Number(budgetInput.value || 0) - 1, 0, 7));
      await sendControlPayload({ budget: Number(budgetInput.value) });
    },
    btnTempAPlus: async () => {
      if (!tempAInput) return;
      tempAInput.value = String(clamp(Number(tempAInput.value || 0) + 1, 0, 127));
      await sendControlPayload({ temp_a: Number(tempAInput.value) });
    },
    btnTempAMinus: async () => {
      if (!tempAInput) return;
      tempAInput.value = String(clamp(Number(tempAInput.value || 0) - 1, 0, 127));
      await sendControlPayload({ temp_a: Number(tempAInput.value) });
    },
    btnTempBPlus: async () => {
      if (!tempBInput) return;
      tempBInput.value = String(clamp(Number(tempBInput.value || 0) + 1, 0, 127));
      await sendControlPayload({ temp_b: Number(tempBInput.value) });
    },
    btnTempBMinus: async () => {
      if (!tempBInput) return;
      tempBInput.value = String(clamp(Number(tempBInput.value || 0) - 1, 0, 127));
      await sendControlPayload({ temp_b: Number(tempBInput.value) });
    },
    btnSyncState: async () => {
      const res = await fetch('/api/state');
      if (!res.ok) return;
      queueRender(await res.json());
      if (ack) ack.textContent = 'State synced';
    },
    btnResetDirty: async () => {
      formDirty = false;
      if (ack) ack.textContent = 'Form unlocked';
    },
  };

  Object.keys(handlers).forEach((id) => {
    const target = el(id);
    if (!target) return;
    target.addEventListener('click', (ev) => {
      ev.preventDefault();
      handlers[id]().catch((e) => {
        if (ack) ack.textContent = `action failed: ${e}`;
      });
    });
  });
}

if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    const cur = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    applyTheme(cur);
  });
}

try {
  const saved = localStorage.getItem('pwrgov-theme');
  const preferLight = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches;
  applyTheme(saved || (preferLight ? 'light' : 'dark'));
} catch (_e) {
  applyTheme('dark');
}

ctrlIds.forEach((id) => {
  const target = el(id);
  if (!target) return;
  target.addEventListener('input', () => {
    formDirty = true;
    lockField(id, 2600);
  });
  target.addEventListener('change', () => {
    formDirty = true;
    lockField(id, 2600);
  });
});

if (connDot) {
  connDot.addEventListener('click', () => {
    try {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close();
      } else {
        connectWs();
      }
    } catch (_e) {
      connectWs();
    }
  });
}

if (navBtns && navBtns.length) {
  navBtns.forEach((b) => {
    b.addEventListener('click', () => {
      showView(b.dataset.view || 'dashboard');
    });
  });
}
showView('dashboard');

const demoToggle = el('demoToggle');
if (demoToggle) {
  demoToggle.checked = false;
  demoToggle.disabled = true;
  demoToggle.title = 'Demo mode disabled: all dashboard data comes from backend only.';
}

const form = el('ctrlForm');
if (form) {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = {
      mode: modeSelect ? modeSelect.value : 'internal',
      host_use_ext_budget: extBudgetSelect ? extBudgetSelect.value === 'true' : false,
      budget: toInt(budgetInput, 0, 7, 4),
      req_a: toInt(reqAInput, 0, 3, 0),
      req_b: toInt(reqBInput, 0, 3, 0),
      temp_a: toInt(tempAInput, 0, 127, 30),
      temp_b: toInt(tempBInput, 0, 127, 30),
      act_a: !!(actAToggle && actAToggle.checked),
      stall_a: !!(stallAToggle && stallAToggle.checked),
      act_b: !!(actBToggle && actBToggle.checked),
      stall_b: !!(stallBToggle && stallBToggle.checked),
    };
    await sendControlPayload(payload);
  });
}

if (scenarioSelect) {
  scenarioSelect.addEventListener('change', () => {
    updateScenarioExplain();
  });
}

function setScenarioRunUi(running) {
  scenarioRunning = !!running;
  if (runScenarioBtn) {
    runScenarioBtn.disabled = scenarioRunning;
    runScenarioBtn.textContent = scenarioRunning ? 'Running...' : 'Run Scenario';
  }
  if (stopScenarioBtn) {
    stopScenarioBtn.disabled = !scenarioRunning;
  }
}

if (runScenarioBtn) {
  runScenarioBtn.addEventListener('click', async () => {
    if (scenarioRunning) return;
    const name = scenarioSelect ? scenarioSelect.value : '';
    if (!name) {
      if (scenarioStatus) scenarioStatus.textContent = 'Select a scenario first.';
      return;
    }

    setScenarioRunUi(true);
    if (scenarioStatus) scenarioStatus.textContent = `Running ${name} on FPGA...`;

    try {
      const res = await fetch('/api/scenarios/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, sample_ms: 200 }),
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.detail || `HTTP ${res.status}`);
      renderScenarioTimeline(out);
      if (scenarioStatus) {
        if (out.status === 'stopped') {
          scenarioStatus.textContent = `Stopped ${name}. Returned to internal workload_sim mode.`;
        } else {
          scenarioStatus.textContent = `Completed ${name}: ${out.points} samples captured. Returned to internal workload_sim mode.`;
        }
      }
    } catch (e) {
      if (scenarioStatus) scenarioStatus.textContent = `Scenario failed: ${e}`;
    }

    setScenarioRunUi(false);
  });
}

if (stopScenarioBtn) {
  stopScenarioBtn.addEventListener('click', async () => {
    if (!scenarioRunning) return;
    stopScenarioBtn.disabled = true;
    if (scenarioStatus) scenarioStatus.textContent = 'Stopping scenario and returning to internal workload_sim...';
    try {
      const res = await fetch('/api/scenarios/stop', {
        method: 'POST',
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.detail || `HTTP ${res.status}`);
      if (out.state) queueRender(out.state);
      if (scenarioStatus) scenarioStatus.textContent = out.message || 'Stop requested.';
    } catch (e) {
      if (scenarioStatus) scenarioStatus.textContent = `Stop request failed: ${e}`;
    } finally {
      stopScenarioBtn.disabled = !scenarioRunning;
    }
  });
}

if (runSimBtn) {
  runSimBtn.addEventListener('click', async () => {
    await runSimTests();
  });
}

if (refreshSimTestsBtn) {
  refreshSimTestsBtn.addEventListener('click', async () => {
    await loadSimCatalog();
  });
}

setInterval(() => {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    pollFallback();
  }
}, 1500);

bindQuickButtons();
connectWs();
pollFallback();
loadScenarios();
loadTestbenchNotes();
loadSimCatalog();
setScenarioRunUi(false);
setSimRunUi(false);
