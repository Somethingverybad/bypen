// Интерфейс Бупеня на Windows и Linux. Состояние — GET /api/state раз в секунду,
// команды — POST /api/*. Токен этого запуска — в хеше адреса.
"use strict";
const TOKEN = location.hash.slice(1);
const $ = (id) => document.getElementById(id);
let S = null;          // последний снимок
let sheet = null;      // "settings" | "log" | null
let themeMenu = false;

async function call(path, body) {
  const r = await fetch("/api/" + path, {
    method: body === undefined ? "GET" : "POST",
    headers: { "X-Bypen": TOKEN, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

function bytes(b) {
  if (b >= 1 << 30) return (b / 1073741824).toFixed(1) + " ГБ";
  if (b >= 1 << 20) return (b / 1048576).toFixed(1) + " МБ";
  return Math.round(b / 1024) + " КБ";
}

function phase(s) {
  const st = s.status.state;
  if (!s.running || st === "stopped") return "off";
  if (st === "starting" || st === "switching") return "busy";
  if (st === "error" || s.status.failures > 0) return "trouble";
  return s.status.lastProbeMs == null ? "checking" : "on";
}

function render() {
  if (!S) return;
  document.body.dataset.theme = S.settings.appearance === "light" ? "light" : "dark";
  $("login").classList.toggle("hidden", S.loggedIn);
  $("main").classList.toggle("hidden", !S.loggedIn);
  $("loginVer").textContent = "Бупень " + S.version + " · " + S.platform;
  if (!S.loggedIn) {
    const waiting = !!S.awaitingBot;
    $("loginForm").classList.toggle("hidden", waiting);
    $("loginLinks").classList.toggle("hidden", waiting);
    $("botWait").classList.toggle("hidden", !waiting);
    if (waiting) $("botWaitText").textContent = "Бот «" + S.awaitingBot + "» прислал вам сообщение. Нажмите в нём «Да, это я» — на телефоне или в WYX на компьютере.";
    $("loginError").classList.toggle("hidden", !S.error);
    $("loginError").textContent = S.error || "";
    $("loginBtn").disabled = S.busy;
    $("loginBtn").textContent = S.busy ? "Отправляю…" : (withPassword ? "Войти" : "Войти через WYX");
    return;
  }
  const p = phase(S);
  document.body.classList.toggle("on", p === "on");
  const big = $("big");
  big.className = "big " + (p === "busy" ? "checking" : p);
  big.disabled = p === "busy";
  const title = { off: "Подключить", busy: S.status.state === "switching" ? "Меняю узел…" : "Подключаю…", checking: "Проверяю…", on: "Защищено", trouble: "Нет ответа" }[p];
  $("bigTitle").textContent = title;
  big.setAttribute("aria-label", title);
  $("symPower").classList.toggle("hidden", p !== "off");
  $("symHalf").classList.toggle("hidden", !(p === "busy" || p === "checking"));
  $("symOn").classList.toggle("hidden", p !== "on");
  $("symWarn").classList.toggle("hidden", p !== "trouble");

  const dot = { on: "ok", trouble: "bad", off: "idle" }[p] || "busy";
  $("dot").className = "dot " + dot;
  const mode = S.status.mode === "proxy" ? "системный прокси" : "сеть WYX";
  $("stateText").textContent = { on: "Трафик идёт через " + mode, trouble: "Узел не отвечает, ищу другой", checking: "Туннель поднят, проверяю связь", busy: "Секунду…", off: "Не подключено" }[p];
  const cols = $("cols");
  let items;
  if (S.running) {
    cols.className = "cols run";
    items = [["Узел", S.status.nodeName || "—"], ["Задержка", S.status.lastProbeMs != null ? S.status.lastProbeMs + " мс" : "…"], ["Трафик", "↑" + bytes(S.status.up) + " ↓" + bytes(S.status.down)]];
  } else {
    cols.className = "cols idle";
    const pref = S.settings.preferredNode && S.nodes.find((n) => n.id === S.settings.preferredNode);
    items = [["Аккаунт", S.username ? "@" + S.username : "—"], ["Узлов", S.nodes.length ? S.nodes.filter((n) => n.ok).length + " из " + S.nodes.length : "—"], ["Выбор", pref ? pref.name : "авто"]];
  }
  cols.innerHTML = items.map(([l, v]) => `<div class="col"><div class="l">${esc(l)}</div><div class="v" title="${esc(v)}">${esc(v)}</div></div>`).join("");
  const err = (S.running && S.status.failures > 0 && S.status.lastError) || S.status.lastError && !S.running && S.status.lastError || S.error || S.profileNote || "";
  $("cardError").classList.toggle("hidden", !err);
  $("cardError").textContent = err;
  const up = $("updateCard");
  if (S.update) {
    up.classList.remove("hidden");
    up.innerHTML = `Есть обновление ${esc(S.update.version)}. ${esc(S.update.notes || "")} <a id="getUpdate">Скачать</a>`;
    $("getUpdate").onclick = () => call("open", { url: S.update.url });
  } else up.classList.add("hidden");
  if (sheet === "settings") renderSettings();
}

// ---- настройки ----
const CHECK = '<svg class="check" viewBox="0 0 57.88 41.72" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M2 23.17L18.55 39.72L55.88 2"/></svg>';
const toggle = (on, key) => `<button class="toggle ${on ? "on" : ""}" data-toggle="${key}" aria-pressed="${on}"></button>`;

// «full:x» → «= x», зона без точки → «.ru», домен — как есть.
const dlabel = (e) => e.startsWith("full:") ? "= " + e.slice(5) : (e.includes(".") ? e : "." + e);

function renderSettings() {
  const s = S.settings;
  // настройки перерисовываются раз в секунду — поле «свой адрес» не должно терять набранное
  const inp = $("directInput");
  const keep = inp ? { v: inp.value, f: document.activeElement === inp, p: inp.selectionStart } : null;
  const d = S.direct;
  const ruOn = d ? d.ru : true;
  const n = d ? d.ruCount : 0;
  const custom = (d ? d.custom : []).map((e) => `<div class="divider"></div><div class="row"><span class="grow">${esc(dlabel(e))}</span><button class="tool" data-direct-del="${esc(e)}">убрать</button></div>`).join("");
  const nodes = S.nodes.map((n) => {
    const cur = S.running && S.status.nodeId === n.id;
    const sub = (n.kind === "reality" ? "Reality" : "XHTTP") + " • " + (n.ok ? (n.rtt_ms != null ? n.rtt_ms + " мс" : "жив") : "не отвечает из Москвы");
    return `<div class="divider"></div><div class="row click" data-node="${esc(n.id)}"><span class="dot ${n.ok ? "ok" : "bad"}"></span><div class="grow"><div>${esc(n.name)}</div><div class="node-sub">${esc(sub)}</div></div>${cur ? '<span class="accent">●</span>' : s.preferredNode === n.id ? CHECK : ""}</div>`;
  }).join("");
  const minutes = [[30, "30 мин"], [60, "1 ч"], [120, "2 ч"], [240, "4 ч"]].map(([m, l]) => `<button class="chip ${s.rotateMinutes === m ? "sel" : ""}" data-minutes="${m}">${l}</button>`).join("");
  $("sheetBody").innerHTML = `
  <div class="sec"><div class="sec-title">Оформление</div><div class="card settings-card">
    <div class="row click" id="themeRow"><span class="grow">Тема</span><span class="accent">${s.appearance === "light" ? "Мята светлая" : "Мята тёмная"}</span><span class="val">⌄</span></div>
    ${themeMenu ? `<div class="divider"></div><div class="row click" data-theme-set="dark"><span class="grow">Мята тёмная</span>${s.appearance !== "light" ? CHECK : ""}</div><div class="divider"></div><div class="row click" data-theme-set="light"><span class="grow">Мята светлая</span>${s.appearance === "light" ? CHECK : ""}</div>` : ""}
  </div></div>
  <div class="sec"><div class="sec-title">Режим</div><div class="card settings-card">
    <div class="row ${S.running ? "" : "click"}" data-mode="tun"><span class="grow">TUN — весь трафик</span>${s.tun ? CHECK : ""}</div><div class="divider"></div>
    <div class="row ${S.running ? "" : "click"}" data-mode="proxy"><span class="grow">Системный прокси</span>${!s.tun ? CHECK : ""}</div>
  </div><div class="sec-foot">${s.tun ? "Виртуальный сетевой интерфейс: через туннель идут все программы. При подключении один раз попросит права администратора." : "HTTP и SOCKS-прокси в настройках системы. Программы, которые прокси не читают, идут напрямую. Прав администратора не нужно."}${S.running ? " Сменить режим можно после отключения." : ""}</div></div>
  <div class="sec"><div class="sec-title">Переключение</div><div class="card settings-card">
    <div class="row"><span class="grow">Переключать узел, если не отвечает</span>${toggle(s.autoSwitch, "autoSwitch")}</div><div class="divider"></div>
    <div class="row"><span class="grow">Менять узел в простое</span>${toggle(s.rotateIdle, "rotateIdle")}</div>
    ${s.rotateIdle ? `<div class="divider"></div><div class="row"><span class="grow">Не чаще чем</span><span class="seg">${minutes}</span></div>` : ""}
  </div><div class="sec-foot">В простое (меньше 300 КБ за 10 минут) трафик уводится на другой живой узел, чтобы не идти всё время в одну точку</div></div>
  <div class="sec"><div class="sec-title">Напрямую, мимо VPN</div><div class="card settings-card">
    <div class="row"><span class="grow">Российские сайты</span><button class="toggle ${ruOn ? "on" : ""}" data-direct-ru aria-pressed="${ruOn}"></button></div>${custom}
    <div class="divider"></div><div class="row"><input id="directInput" class="inline-field grow" placeholder="example.com, .ru или =точный.адрес" autocapitalize="off" spellcheck="false"><button class="tool accent" id="directAdd">добавить</button></div>
    <div class="divider"></div><div class="row click" id="directShare"><span class="grow accent">Поделиться по логину WYX</span><span class="val">➤</span></div>
  </div><div class="sec-foot">${S.directError ? `<span class="danger">${esc(S.directError)}</span><br>` : ""}${S.directNote ? `${esc(S.directNote)}<br>` : ""}Российские — зоны .ru, .su, .рф${n > 4 ? ` и ещё ${n - 4} адресов из списка сети WYX` : ""}. Свои: example.com — вместе с поддоменами, .ru — вся зона, =example.com — только этот адрес. Хранится в аккаунте WYX — действует на всех устройствах.${S.directPending ? ` <br>Применится после переподключения — <a id="directReconnect">переподключить</a>.` : ""}</div></div>
  <div class="sec"><div class="sec-title">Узел <button class="tool" id="refreshNodes">обновить</button></div><div class="card settings-card">
    <div class="row click" data-node=""><span class="grow">Автоматически</span>${s.preferredNode ? "" : CHECK}</div>${nodes}
  </div><div class="sec-foot">Выбранный узел становится первым; если он не отвечает, приложение всё равно уйдёт на другой</div></div>
  <div class="sec"><div class="sec-title">Аккаунт</div><div class="card settings-card">
    <div class="row"><span class="grow">Пользователь</span><span class="val">${S.username ? "@" + esc(S.username) : "—"}</span></div>
    ${S.uuidPrefix ? `<div class="divider"></div><div class="row"><span class="grow">Ключ доступа</span><span class="val">${esc(S.uuidPrefix)}…</span></div>` : ""}
    <div class="divider"></div><div class="row click danger" id="logout">Выйти</div>
  </div></div>
  <div class="sec"><div class="sec-title">О приложении</div><div class="card settings-card">
    <div class="row"><span class="grow">Версия</span><span class="val">${esc(S.version)} · ${esc(S.platform)}</span></div><div class="divider"></div>
    <div class="row"><span class="grow">Ядро Xray</span><span class="val">${esc(S.xray)}</span></div><div class="divider"></div>
    <div class="row click danger" id="quitApp">Выйти из Бупеня</div>
  </div></div>`;
  const ni = $("directInput");
  if (keep && ni) { ni.value = keep.v; if (keep.f) { ni.focus(); ni.setSelectionRange(keep.p, keep.p); } }
  ni.onkeydown = (e) => { if (e.key === "Enter") { e.preventDefault(); $("directAdd").click(); } };
}

async function saveDirect(direct) {
  try { await call("direct/save", { direct }); } catch (_) {}
  await refresh();
}

$("sheetBody").addEventListener("click", async (e) => {
  const t = e.target.closest("[data-toggle],[data-minutes],[data-node],[data-mode],[data-theme-set],#themeRow,#logout,#quitApp,#refreshNodes,[data-direct-ru],[data-direct-del],#directAdd,#directReconnect,#directShare");
  if (!t || sheet !== "settings") return;
  const s = S.settings;
  const cur = S.direct ? S.direct.custom : [];
  if (t.dataset.directRu !== undefined) return saveDirect({ ru: !(S.direct ? S.direct.ru : true) });
  if (t.dataset.directDel !== undefined) return saveDirect({ custom: cur.filter((x) => x !== t.dataset.directDel) });
  if (t.id === "directAdd") {
    const v = $("directInput").value.trim();
    if (!v) return;
    await call("direct/save", { direct: { custom: cur.concat([v]) } }).catch(() => {});
    await refresh();
    if (!S.directError) $("directInput").value = "";
    return;
  }
  if (t.id === "directReconnect") { await call("direct/reconnect", {}); return refresh(); }
  if (t.id === "directShare") {
    const u = prompt("Поделиться настройками «напрямую»\nНик в WYX — бот «Бупень» пришлёт человеку ваши настройки, он сам решит, принять ли их:");
    if (u && u.trim()) { await call("direct/share", { username: u.trim() }).catch(() => {}); }
    return refresh();
  }
  if (t.dataset.toggle) await call("settings", { settings: { [t.dataset.toggle]: !s[t.dataset.toggle] } });
  else if (t.dataset.minutes) await call("settings", { settings: { rotateMinutes: +t.dataset.minutes } });
  else if (t.dataset.node !== undefined) await call("select", { node: t.dataset.node || null });
  else if (t.dataset.mode) { if (!S.running) await call("settings", { settings: { tun: t.dataset.mode === "tun" } }); }
  else if (t.dataset.themeSet) { themeMenu = false; await call("settings", { settings: { appearance: t.dataset.themeSet } }); }
  else if (t.id === "themeRow") themeMenu = !themeMenu;
  else if (t.id === "refreshNodes") await call("refresh", {});
  else if (t.id === "logout") { if (confirm("Выйти из аккаунта? VPN будет отключён.")) { await call("logout", {}); closeSheet(); } }
  else if (t.id === "quitApp") { if (!S.running || confirm("Отключить VPN и закрыть Бупень?")) await call("quit", {}); }
  await refresh();
});

// ---- журнал ----
async function renderLog() {
  const r = await call("log");
  const atBottom = $("sheetBody").scrollTop + $("sheetBody").clientHeight >= $("sheetBody").scrollHeight - 30;
  $("sheetBody").innerHTML = `<div class="logtext">${esc(r.log || "Пока пусто.")}${r.xray ? `<h4>— ядро Xray —</h4>${esc(r.xray)}` : ""}</div>`;
  if (atBottom) $("sheetBody").scrollTop = $("sheetBody").scrollHeight;
}

function openSheet(kind) {
  sheet = kind;
  $("sheetWrap").classList.remove("hidden");
  $("sheetTitle").textContent = kind === "log" ? "Журнал" : "Настройки";
  $("sheetTools").innerHTML = kind === "log" ? '<button class="tool" id="copyLog">Копировать</button><button class="tool danger" id="clearLog">Очистить</button>' : "";
  if (kind === "log") {
    $("copyLog").onclick = async () => { const r = await call("log"); navigator.clipboard?.writeText((r.log || "") + "\n\n" + (r.xray || "")); };
    $("clearLog").onclick = async () => { await call("log/clear", {}); renderLog(); };
    renderLog().then(() => { $("sheetBody").scrollTop = $("sheetBody").scrollHeight; });
  } else { call("direct/load", {}).catch(() => {}); renderSettings(); }
}
function closeSheet() { sheet = null; themeMenu = false; $("sheetWrap").classList.add("hidden"); }

$("openLog").onclick = () => openSheet("log");
$("openSettings").onclick = () => openSheet("settings");
$("statusCard").onclick = () => openSheet("log");
$("closeSheet").onclick = closeSheet;
$("sheetWrap").addEventListener("click", (e) => { if (e.target === $("sheetWrap")) closeSheet(); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeSheet(); });

$("big").onclick = async () => {
  if (!S) return;
  if (S.running) await call("disconnect", {});
  else await call("connect", {});
  setTimeout(refresh, 150);
};

// Вход: ник → бот «Бупень» спрашивает в WYX → «Да». Пароль — мелкой ссылкой.
let withPassword = false;
$("pwToggle").onclick = () => {
  withPassword = !withPassword;
  $("p").classList.toggle("hidden", !withPassword);
  $("loginHint").classList.toggle("hidden", withPassword);
  $("pwToggle").textContent = withPassword ? "Войти через WYX" : "Войти паролем";
  render();
};
$("noAccount").onclick = () => call("wyx/download", {}).catch(() => {});
$("botCancel").onclick = async () => { try { await call("login/cancel", {}); } catch (_) {} refresh(); };

$("loginForm").onsubmit = async (e) => {
  e.preventDefault();
  const u = $("u").value.trim(), p = $("p").value;
  if (!u || (withPassword && !p)) return;
  $("loginBtn").disabled = true;
  $("loginBtn").textContent = "Отправляю…";
  try {
    if (withPassword) await call("login", { username: u, password: p });
    else await call("login/wyx", { username: u });
  } catch (_) {}
  $("p").value = "";
  refresh();
};

async function refresh() {
  try { S = await call("state"); render(); } catch (_) {}
  if (sheet === "log") renderLog().catch(() => {});
}

setInterval(refresh, 1000);
setInterval(() => document.body.classList.toggle("drift"), 11000);
refresh();
