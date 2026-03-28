const connDot = document.getElementById('connDot');
const connText = document.getElementById('connText');
const ack = document.getElementById('ack');
const themeToggle = document.getElementById('themeToggle');
const themeIcon = document.getElementById('themeIcon');

const fields = {
  stateA: document.getElementById('stateA'),
  stateB: document.getElementById('stateB'),
  grantA: document.getElementById('grantA'),
  grantB: document.getElementById('grantB'),
  clkEnA: document.getElementById('clkEnA'),
  clkEnB: document.getElementById('clkEnB'),
  eff: document.getElementById('eff'),
  budget: document.getElementById('budget'),
  headroom: document.getElementById('headroom'),
  frame: document.getElementById('frame'),
  tempA: document.getElementById('tempA'),
  tempB: document.getElementById('tempB'),
  actA: document.getElementById('actA'),
  actB: document.getElementById('actB'),
  stallA: document.getElementById('stallA'),
  stallB: document.getElementById('stallB'),
  reqA: document.getElementById('reqA'),
  reqB: document.getElementById('reqB'),
  phase: document.getElementById('phase'),
  mode: document.getElementById('mode'),
  alarmA: document.getElementById('alarmA'),
  alarmB: document.getElementById('alarmB'),
  eff2: document.getElementById('eff2'),
  budget2: document.getElementById('budget2'),
  headroom2: document.getElementById('headroom2'),
};

const stateNames = ['SLEEP', 'LOW_POWER', 'ACTIVE', 'TURBO'];

function decodeState(v) {
  return stateNames[v] || `S${v}`;
}

function stateFromGrant(grant) {
  return decodeState(grant);
}

const stateClassMap = { SLEEP: 'sleep', LOW_POWER: 'low', ACTIVE: 'active', TURBO: 'turbo' };

const chartCtx = document.getElementById('trendChart');
const trendChart = new Chart(chartCtx, {
  type: 'line',
  data: {
    labels: [],
    datasets: [
      { label: 'Efficiency', data: [], borderColor: '#00c9a7', tension: 0.22 },
      { label: 'Temp A', data: [], borderColor: '#ffa94d', tension: 0.22 },
      { label: 'Temp B', data: [], borderColor: '#ff6f61', tension: 0.22 },
    ]
  },
  options: {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    scales: {
      x: { ticks: { color: '#8fb0bd' }, grid: { color: 'rgba(255,255,255,0.07)' } },
      y: { ticks: { color: '#8fb0bd' }, grid: { color: 'rgba(255,255,255,0.07)' } },
    },
    plugins: {
      legend: { labels: { color: '#cfe5ee' } }
    }
  }
});

// apply simple gradient fills for a more modern look
try {
  const ctx = chartCtx.getContext('2d');
  const g0 = ctx.createLinearGradient(0, 0, 0, 300);
  g0.addColorStop(0, 'rgba(0,201,167,0.26)');
  g0.addColorStop(1, 'rgba(0,201,167,0.02)');
  const g1 = ctx.createLinearGradient(0, 0, 0, 300);
  g1.addColorStop(0, 'rgba(255,169,77,0.20)');
  g1.addColorStop(1, 'rgba(255,169,77,0.02)');
  const g2 = ctx.createLinearGradient(0, 0, 0, 300);
  g2.addColorStop(0, 'rgba(255,111,97,0.18)');
  g2.addColorStop(1, 'rgba(255,111,97,0.02)');
  trendChart.data.datasets[0].backgroundColor = g0;
  trendChart.data.datasets[0].borderWidth = 2;
  trendChart.data.datasets[0].fill = true;
  trendChart.data.datasets[1].backgroundColor = g1;
  trendChart.data.datasets[1].borderWidth = 2;
  trendChart.data.datasets[1].fill = true;
  trendChart.data.datasets[2].backgroundColor = g2;
  trendChart.data.datasets[2].borderWidth = 2;
  trendChart.data.datasets[2].fill = true;
  trendChart.update();
} catch (e) {
  // ignore if gradients fail
}

function pushPoint(state) {
  const t = new Date().toLocaleTimeString();
  const labels = trendChart.data.labels;
  labels.push(t);
  trendChart.data.datasets[0].data.push(state.efficiency || 0);
  trendChart.data.datasets[1].data.push(state.temp_a || 0);
  trendChart.data.datasets[2].data.push(state.temp_b || 0);
  while (labels.length > 60) {
    labels.shift();
    trendChart.data.datasets.forEach(ds => ds.data.shift());
  }
  trendChart.update();
}

function updateAlarm(el, on, title) {
  el.classList.toggle('on', !!on);
  el.textContent = `${title}: ${on ? 'ON' : 'OFF'}`;
}

function setConnection(online) {
  connDot.classList.toggle('online', online);
  connDot.classList.toggle('offline', !online);
  connText.textContent = online ? 'Connected' : 'Disconnected';
}

function render(state) {
  setConnection(!!state.connected);

  fields.stateA.textContent = stateFromGrant(state.grant_a || 0);
  fields.stateB.textContent = stateFromGrant(state.grant_b || 0);

  // add nice class to the pill to visually show state
  try {
    const sA = fields.stateA.textContent || 'SLEEP';
    const sB = fields.stateB.textContent || 'SLEEP';
    Object.values(stateClassMap).forEach(c => fields.stateA.classList.remove(c));
    Object.values(stateClassMap).forEach(c => fields.stateB.classList.remove(c));
    fields.stateA.classList.add(stateClassMap[sA] || 'sleep');
    fields.stateB.classList.add(stateClassMap[sB] || 'sleep');
  } catch (e) {}

  fields.grantA.textContent = state.grant_a ?? 0;
  fields.grantB.textContent = state.grant_b ?? 0;
  fields.clkEnA.textContent = state.clk_en_a ?? 0;
  fields.clkEnB.textContent = state.clk_en_b ?? 0;

  fields.eff.textContent = state.efficiency ?? 0;
  fields.budget.textContent = state.current_budget ?? 0;
  fields.headroom.textContent = state.budget_headroom ?? 0;
  // mirror metrics into right column
  if (fields.eff2) fields.eff2.textContent = state.efficiency ?? 0;
  if (fields.budget2) fields.budget2.textContent = state.current_budget ?? 0;
  if (fields.headroom2) fields.headroom2.textContent = state.budget_headroom ?? 0;
  fields.frame.textContent = state.frame_counter ?? 0;

  fields.tempA.textContent = state.temp_a ?? 0;
  fields.tempB.textContent = state.temp_b ?? 0;
  fields.actA.textContent = state.act_a ?? 0;
  fields.actB.textContent = state.act_b ?? 0;
  fields.stallA.textContent = state.stall_a ?? 0;
  fields.stallB.textContent = state.stall_b ?? 0;
  fields.reqA.textContent = state.req_a ?? 0;
  fields.reqB.textContent = state.req_b ?? 0;
  fields.phase.textContent = state.phase ?? 0;
  fields.mode.textContent = state.host_mode ? 'host' : 'internal';

  updateAlarm(fields.alarmA, state.alarm_a, 'Alarm A');
  updateAlarm(fields.alarmB, state.alarm_b, 'Alarm B');

  pushPoint(state);

  // small highlight animation for metrics
  try {
    const els = [fields.eff, fields.budget, fields.headroom];
    els.forEach(el => { if (!el) return; el.animate([{ transform: 'translateY(-6px)' }, { transform: 'translateY(0)' }], { duration: 260, easing: 'cubic-bezier(.2,.9,.2,1)' }); });
  } catch (e) {}
}

/* THEME HANDLING */
function applyTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  try { localStorage.setItem('pwrgov-theme', t); } catch (e) {}
  if (themeIcon) themeIcon.textContent = t === 'light' ? '☀️' : '🌙';
}

// initialize theme from localStorage or system
try {
  const saved = localStorage.getItem('pwrgov-theme');
  const preferLight = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches;
  applyTheme(saved || (preferLight ? 'light' : 'dark'));
} catch (e) { applyTheme('dark'); }

if (themeToggle) {
  themeToggle.addEventListener('click', () => {
    const cur = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    applyTheme(cur);
  });
}

/* 3D tilt for cards */
function initTilt() {
  const cards = document.querySelectorAll('.card');
  cards.forEach(card => {
    let raf = null;
    let last = null;

    function onFrame() {
      if (!last) { raf = null; return; }
      const e = last; last = null; raf = null;
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const px = (x / rect.width) - 0.5;
      const py = (y / rect.height) - 0.5;
      const rotY = (px * 18).toFixed(2);
      const rotX = (-py * 10).toFixed(2);
      const s = 1.02;
      card.style.transform = `perspective(900px) rotateX(${rotX}deg) rotateY(${rotY}deg) scale(${s})`;
      card.style.boxShadow = `${-rotY/2}px ${rotX/2}px 34px rgba(6,20,26,0.48), 0 12px 40px rgba(2,6,10,0.35)`;
    }

    card.addEventListener('pointermove', (ev) => { last = ev; if (!raf) raf = requestAnimationFrame(onFrame); }, { passive: true });
    card.addEventListener('pointerleave', () => { if (raf) { cancelAnimationFrame(raf); raf = null; } card.style.transform = ''; card.style.boxShadow = ''; });
  });
}

// small staggered entrance
function entranceAnimate() {
  const cards = Array.from(document.querySelectorAll('.card'));
  cards.forEach((c, i) => { c.style.opacity = 0; c.style.transform += ' translateY(8px)'; setTimeout(()=>{ c.style.transition = 'opacity .45s ease, transform .55s cubic-bezier(.2,.9,.2,1)'; c.style.opacity = 1; c.style.transform = c.style.transform.replace(' translateY(8px)',''); }, 60 * i); });
}

let ws;
function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);

  ws.onopen = () => {
    setConnection(true);
  };

  ws.onmessage = (ev) => {
    try {
      const state = JSON.parse(ev.data);
      render(state);
    } catch (e) {
      console.error(e);
    }
  };

  ws.onclose = () => {
    setConnection(false);
    setTimeout(connectWs, 1500);
  };
}

async function pollFallback() {
  try {
    const res = await fetch('/api/state');
    if (res.ok) {
      const state = await res.json();
      setConnection(true);
      render(state);
    }
  } catch (_e) {
    setConnection(false);
  }
}

setInterval(() => {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    pollFallback();
  }
}, 1200);

const form = document.getElementById('ctrlForm');
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) { submitBtn.disabled = true; submitBtn.textContent = 'Sending...'; }
  const payload = {
    mode: document.getElementById('modeSelect').value,
    host_use_ext_budget: document.getElementById('extBudgetSelect').value === 'true',
    budget: Number(document.getElementById('budgetInput').value),
    req_a: Number(document.getElementById('reqAInput').value),
    req_b: Number(document.getElementById('reqBInput').value),
    temp_a: Number(document.getElementById('tempAInput').value),
    temp_b: Number(document.getElementById('tempBInput').value),
    act_a: document.getElementById('actAToggle').checked,
    stall_a: document.getElementById('stallAToggle').checked,
    act_b: document.getElementById('actBToggle').checked,
    stall_b: document.getElementById('stallBToggle').checked,
  };

  try {
    const res = await fetch('/api/control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const out = await res.json();
    ack.textContent = JSON.stringify(out, null, 2);
  } catch (err) {
    ack.textContent = `control send failed: ${err}`;
  }
  if (submitBtn) { submitBtn.disabled = false; submitBtn.textContent = 'Send Control Command'; }
});

connectWs();
pollFallback();
initTilt();
entranceAnimate();
