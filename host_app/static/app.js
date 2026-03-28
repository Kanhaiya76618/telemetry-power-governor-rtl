const connDot = document.getElementById('connDot');
const connText = document.getElementById('connText');
const ack = document.getElementById('ack');

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
};

const stateNames = ['SLEEP', 'LOW_POWER', 'ACTIVE', 'TURBO'];

function decodeState(v) {
  return stateNames[v] || `S${v}`;
}

function stateFromGrant(grant) {
  return decodeState(grant);
}

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

function pushPoint(state) {
  const t = new Date().toLocaleTimeString();
  const labels = trendChart.data.labels;
  labels.push(t);
  trendChart.data.datasets[0].data.push(state.efficiency || 0);
  trendChart.data.datasets[1].data.push(state.temp_a || 0);
  trendChart.data.datasets[2].data.push(state.temp_b || 0);
  while (labels.length > 40) {
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

  fields.grantA.textContent = state.grant_a ?? 0;
  fields.grantB.textContent = state.grant_b ?? 0;
  fields.clkEnA.textContent = state.clk_en_a ?? 0;
  fields.clkEnB.textContent = state.clk_en_b ?? 0;

  fields.eff.textContent = state.efficiency ?? 0;
  fields.budget.textContent = state.current_budget ?? 0;
  fields.headroom.textContent = state.budget_headroom ?? 0;
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
}

let ws;
function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);

  ws.onopen = () => {
    setConnection(true);
    ws.send('hello');
  };

  ws.onmessage = (ev) => {
    try {
      const state = JSON.parse(ev.data);
      render(state);
      ws.send('tick');
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
});

connectWs();
pollFallback();
