/* ──────────────────────────────────────────────
   Policia Minigame – NUI Controller
   ────────────────────────────────────────────── */

// ── Referências DOM ─────────────────────────────────────────

const adminUI = document.getElementById('admin-ui');
const inputCops = document.getElementById('input-cops');
const inputLock = document.getElementById('input-lock');
const lockHint = document.getElementById('lock-hint');
const wavesOnBtn = document.getElementById('waves-on');
const wavesOffBtn = document.getElementById('waves-off');
const btnStart = document.getElementById('btn-start');
const btnCancel = document.getElementById('btn-cancel');

const hud = document.getElementById('hud');
const roleIcon = document.getElementById('role-icon');
const roleLabel = document.getElementById('role-label');
const phaseLabel = document.getElementById('phase-label');
const timerText = document.getElementById('timer-text');
const timerSub = document.getElementById('timer-sub');
const ringFill = document.getElementById('ring-fill');
const robberCount = document.getElementById('robber-count');
const robberNum = document.getElementById('robber-num');
const dangerBar = document.getElementById('danger-bar');
const dangerText = document.getElementById('danger-text');
const actionHint = document.getElementById('action-hint');
const waveBadge = document.getElementById('wave-badge');
const waveLabel = document.getElementById('wave-label');
const waveIcon = document.getElementById('wave-icon');
const killFeed = document.getElementById('kill-feed');

const CIRCUMFERENCE = 213.63;

let totalSeconds = 0;
let currentSeconds = 0;
let intervalId = null;
let currentRole = null;
let savedRoundDuration = 900;
let waveModeSelected = true;

// ── Admin UI Logic ───────────────────────────────────────────

// Botões +/− dos campos numéricos
document.querySelectorAll('.adj-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const target = document.getElementById(btn.dataset.target);
        if (!target) return;
        const delta = parseInt(btn.dataset.delta, 10);
        const min = parseInt(target.min, 10) || 1;
        const max = parseInt(target.max, 10) || 999;
        let val = parseInt(target.value, 10) + delta;
        val = Math.min(Math.max(val, min), max);
        target.value = val;
        if (target === inputLock) updateLockHint(val);
    });
});

function updateLockHint(secs) {
    secs = parseInt(secs, 10) || 30;
    lockHint.textContent = secs < 60
        ? secs + ' segundos'
        : Math.floor(secs / 60) + 'm ' + (secs % 60 ? (secs % 60) + 's' : '');
}

inputLock.addEventListener('input', () => updateLockHint(inputLock.value));

// Toggle Ondas
wavesOnBtn.addEventListener('click', () => {
    waveModeSelected = true;
    wavesOnBtn.classList.add('active');
    wavesOffBtn.classList.remove('active');
});
wavesOffBtn.addEventListener('click', () => {
    waveModeSelected = false;
    wavesOffBtn.classList.add('active');
    wavesOnBtn.classList.remove('active');
});

// Iniciar Ronda
btnStart.addEventListener('click', () => {
    const numCops = parseInt(inputCops.value, 10) || 1;
    const lockSecs = parseInt(inputLock.value, 10) || 30;
    fetch(`https://${GetParentResourceName()}/policia:submitConfig`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ numCops, lockSecs, waveMode: waveModeSelected })
    });
    adminUI.classList.add('hidden');
});

// Cancelar
btnCancel.addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/policia:closeAdminUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
    adminUI.classList.add('hidden');
});

// ── Utilitários ──────────────────────────────
function pad(n) { return String(Math.floor(n)).padStart(2, '0'); }

function formatTime(secs) {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return m > 0 ? `${m}:${pad(s)}` : `${s}s`;
}

function setRingProgress(remaining, total) {
    if (total <= 0) { ringFill.style.strokeDashoffset = 0; return; }
    const offset = CIRCUMFERENCE * (1 - remaining / total);
    ringFill.style.strokeDashoffset = offset;
}

function stopTimer() {
    if (intervalId) { clearInterval(intervalId); intervalId = null; }
}

// ── Temporizador ──────────────────────────────

function startTimer(seconds, sub, onEnd) {
    stopTimer();
    currentSeconds = seconds;
    totalSeconds = seconds;
    timerSub.textContent = sub;
    timerText.textContent = formatTime(currentSeconds);
    setRingProgress(currentSeconds, totalSeconds);
    hud.classList.remove('pulsing');

    intervalId = setInterval(() => {
        currentSeconds--;
        timerText.textContent = formatTime(Math.max(currentSeconds, 0));
        setRingProgress(Math.max(currentSeconds, 0), totalSeconds);
        if (currentSeconds <= 10) hud.classList.add('pulsing');
        if (currentSeconds <= 0) {
            stopTimer();
            if (onEnd) onEnd();
        }
    }, 1000);
}

function startLockPhase(lockSecs, roundDuration) {
    startTimer(lockSecs, 'TEMPO ATÉ SER LIBERTADO', () => {
        phaseLabel.textContent = '⚠️ LIBERTO! VAI À CAÇA!';
        timerText.textContent = '!';
        setTimeout(() => startHuntPhase(roundDuration), 1500);
    });
    phaseLabel.textContent = 'PRESO — AGUARDA LIBERTAÇÃO';
}

function startHuntPhase(duration) {
    startTimer(duration, 'TEMPO RESTANTE DA RONDA', () => { });
    phaseLabel.textContent = 'RONDA EM CURSO!';
}

// ── Perigo ────────────────────────────────────

function setDanger(level) {
    dangerBar.classList.remove('hidden', 'level-1', 'level-2');
    if (level === 0) {
        dangerBar.classList.add('hidden');
    } else if (level === 1) {
        dangerBar.classList.add('level-1');
        dangerText.textContent = 'INIMIGO PRÓXIMO';
        dangerBar.classList.remove('hidden');
    } else {
        dangerBar.classList.add('level-2');
        dangerText.textContent = 'PERIGO IMEDIATO!';
        dangerBar.classList.remove('hidden');
    }
}

// ── Wave Badge ────────────────────────────────

const waveColorMap = {
    blue: 'wave-blue',
    yellow: 'wave-yellow',
    orange: 'wave-orange',
    red: 'wave-red',
};

function setWave(waveNum, label, color) {
    waveBadge.classList.remove('hidden', 'wave-yellow', 'wave-orange', 'wave-red');
    waveIcon.textContent = '⚡';
    waveLabel.textContent = `ONDA ${waveNum}  ·  ${label}`;
    const cls = waveColorMap[color] || '';
    if (cls) waveBadge.classList.add(cls);
}

// ── Kill Feed ─────────────────────────────────

const kfIcons = {
    arrest: '🔒',
    kill: '💀',
    oob: '🚫',
};

const kfMessages = {
    arrest: (a, v) => `${a} algemou ${v}`,
    kill: (a, v) => `${v} foi eliminado`,
    oob: (a, v) => `${v} saiu da zona`,
};

let kfActiveItems = 0;
const MAX_KF = 4;

function addKillFeedItem(feedType, actor, victim) {
    // Remover o mais antigo se já tiver 4
    if (kfActiveItems >= MAX_KF) {
        const oldest = killFeed.lastElementChild;
        if (oldest) oldest.remove();
        kfActiveItems--;
    }

    const icon = kfIcons[feedType] || '⚡';
    const msg = kfMessages[feedType] ? kfMessages[feedType](actor, victim) : `${actor} → ${victim}`;

    const el = document.createElement('div');
    el.className = `kf-item kf-${feedType}`;
    el.innerHTML = `<span>${icon}</span><span>${msg}</span>`;
    killFeed.prepend(el);
    kfActiveItems++;

    setTimeout(() => {
        el.classList.add('kf-fade');
        setTimeout(() => {
            el.remove();
            kfActiveItems = Math.max(0, kfActiveItems - 1);
        }, 500);
    }, 5000);
}

// ── Mensagens do Lua ──────────────────────────

window.addEventListener('message', function (event) {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        case 'openAdminUI': {
            // Reset dos campos para defaults
            inputCops.value = 2;
            inputLock.value = 30;
            updateLockHint(30);
            waveModeSelected = true;
            wavesOnBtn.classList.add('active');
            wavesOffBtn.classList.remove('active');
            adminUI.classList.remove('hidden');
            break;
        }

        case 'open': {
            currentRole = data.role;
            savedRoundDuration = data.roundDuration || 900;
            document.body.classList.remove('cop', 'robber');
            document.body.classList.add(data.role);

            if (data.role === 'cop') {
                roleIcon.textContent = '🚓';
                roleLabel.textContent = 'POLÍCIA';
                actionHint.classList.remove('hidden');
                if (data.lockSeconds > 0) {
                    startLockPhase(data.lockSeconds, savedRoundDuration);
                } else {
                    startHuntPhase(savedRoundDuration);
                }
            } else {
                roleIcon.textContent = '🔪';
                roleLabel.textContent = 'LADRÃO';
                actionHint.classList.add('hidden');
                if (data.lockSeconds > 0) {
                    startLockPhase(data.lockSeconds, savedRoundDuration);
                } else {
                    startHuntPhase(savedRoundDuration);
                }
            }

            robberCount.classList.remove('hidden');
            hud.classList.remove('hidden');
            break;
        }

        case 'released': {
            stopTimer();
            phaseLabel.textContent = '🚨 LIBERTO! À CAÇA!';
            timerText.textContent = '!';
            hud.classList.add('pulsing');
            setTimeout(() => startHuntPhase(savedRoundDuration), 1500);
            break;
        }

        case 'updateRobbers': {
            robberNum.textContent = data.count;
            break;
        }

        case 'danger': {
            setDanger(data.level || 0);
            break;
        }

        case 'waveUpdate': {
            setWave(data.wave, data.label, data.color || 'blue');
            break;
        }

        case 'killFeed': {
            addKillFeedItem(data.feedType, data.actor || '', data.victim || '');
            break;
        }

        case 'close': {
            stopTimer();
            setDanger(0);
            hud.classList.add('hidden');
            waveBadge.classList.add('hidden');
            document.body.classList.remove('cop', 'robber');
            robberCount.classList.add('hidden');
            actionHint.classList.add('hidden');
            currentRole = null;
            // Limpar kill feed
            killFeed.innerHTML = '';
            kfActiveItems = 0;
            break;
        }
    }
});
