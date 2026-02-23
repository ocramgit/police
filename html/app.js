/* ──────────────────────────────────────────────
   Policia Minigame – NUI Controller
   ────────────────────────────────────────────── */

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

const CIRCUMFERENCE = 213.63;

let totalSeconds = 0;
let currentSeconds = 0;
let intervalId = null;
let currentRole = null;

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

// ── Mensagens do Lua ──────────────────────────

window.addEventListener('message', function (event) {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        case 'open': {
            currentRole = data.role;
            document.body.classList.remove('cop', 'robber');
            document.body.classList.add(data.role);

            if (data.role === 'cop') {
                roleIcon.textContent = '🚓';
                roleLabel.textContent = 'POLÍCIA';
                actionHint.classList.remove('hidden');
                if (data.lockSeconds > 0) {
                    startLockPhase(data.lockSeconds, data.roundDuration);
                } else {
                    startHuntPhase(data.roundDuration);
                }
            } else {
                roleIcon.textContent = '🔪';
                roleLabel.textContent = 'LADRÃO';
                actionHint.classList.add('hidden');
                startHuntPhase(data.roundDuration);
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
            setTimeout(() => startHuntPhase(totalSeconds || 300), 1500);
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

        case 'close': {
            stopTimer();
            setDanger(0);
            hud.classList.add('hidden');
            document.body.classList.remove('cop', 'robber');
            robberCount.classList.add('hidden');
            actionHint.classList.add('hidden');
            currentRole = null;
            break;
        }
    }
});
