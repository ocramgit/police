/* ──────────────────────────────────────────────
   Policia Minigame – NUI Controller
   Comunica com client/main.lua via postMessage
   ────────────────────────────────────────────── */

const hud         = document.getElementById('hud');
const roleIcon    = document.getElementById('role-icon');
const roleLabel   = document.getElementById('role-label');
const phaseLabel  = document.getElementById('phase-label');
const timerText   = document.getElementById('timer-text');
const timerSub    = document.getElementById('timer-sub');
const ringFill    = document.getElementById('ring-fill');

const CIRCUMFERENCE = 213.63; // 2π × 34 (raio do SVG)

let totalSeconds   = 0;
let currentSeconds = 0;
let isLockPhase    = false;
let lockSeconds    = 0;
let intervalId     = null;

// ── Utilitários ──────────────────────────────

function pad(n) { return String(Math.floor(n)).padStart(2, '0'); }

function formatTime(secs) {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return m > 0 ? `${m}:${pad(s)}` : `${s}s`;
}

function setRingProgress(remaining, total) {
    if (total <= 0) { ringFill.style.strokeDashoffset = 0; return; }
    const ratio  = remaining / total;
    const offset = CIRCUMFERENCE * (1 - ratio);
    ringFill.style.strokeDashoffset = offset;
}

function stopTimer() {
    if (intervalId) { clearInterval(intervalId); intervalId = null; }
}

// ── Fases ────────────────────────────────────

function startLockPhase(secs) {
    stopTimer();
    isLockPhase    = true;
    currentSeconds = secs;
    totalSeconds   = secs;

    phaseLabel.textContent = 'PRESO — AGUARDA LIBERTAÇÃO';
    timerSub.textContent   = 'TEMPO ATÉ SER LIBERTADO';
    hud.classList.remove('pulsing');

    intervalId = setInterval(() => {
        currentSeconds--;
        timerText.textContent = formatTime(currentSeconds);
        setRingProgress(currentSeconds, totalSeconds);

        if (currentSeconds <= 10) hud.classList.add('pulsing');
        if (currentSeconds <= 0) {
            stopTimer();
            transitionToHuntPhase();
        }
    }, 1000);

    timerText.textContent = formatTime(currentSeconds);
    setRingProgress(currentSeconds, totalSeconds);
}

function startHuntPhase(roundDuration) {
    stopTimer();
    isLockPhase    = false;
    currentSeconds = roundDuration;
    totalSeconds   = roundDuration;

    phaseLabel.textContent = 'RONDA EM CURSO!';
    timerSub.textContent   = 'TEMPO RESTANTE DA RONDA';
    hud.classList.remove('pulsing');

    intervalId = setInterval(() => {
        currentSeconds--;
        timerText.textContent = formatTime(currentSeconds);
        setRingProgress(currentSeconds, totalSeconds);

        if (currentSeconds <= 30) hud.classList.add('pulsing');
        if (currentSeconds <= 0) stopTimer();
    }, 1000);

    timerText.textContent = formatTime(currentSeconds);
    setRingProgress(currentSeconds, totalSeconds);
}

function transitionToHuntPhase() {
    // Chamado automaticamente quando o lockdown termina (polícia)
    phaseLabel.textContent = '⚠️ LIBERTO! VAI À CAÇA!';
    timerText.textContent  = '!';
    hud.classList.add('pulsing');
    setTimeout(() => {
        startHuntPhase(totalSeconds > 0 ? totalSeconds : 300);
    }, 2000);
}

// ── Listener de mensagens do Lua ─────────────

window.addEventListener('message', function(event) {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {

        case 'open': {
            // Limpar classes de papel anteriores
            document.body.classList.remove('cop', 'robber');

            if (data.role === 'cop') {
                document.body.classList.add('cop');
                roleIcon.textContent  = '🚓';
                roleLabel.textContent = 'POLÍCIA';

                if (data.lockSeconds > 0) {
                    startLockPhase(data.lockSeconds);
                } else {
                    startHuntPhase(data.roundDuration);
                }
            } else {
                document.body.classList.add('robber');
                roleIcon.textContent  = '🔪';
                roleLabel.textContent = 'LADRÃO';
                startHuntPhase(data.roundDuration);
            }

            hud.classList.remove('hidden');
            break;
        }

        case 'released': {
            // Polícia libertada — mostrar mensagem e ir para fase de caça
            stopTimer();
            phaseLabel.textContent = '🚨 LIBERTO! À CAÇA!';
            timerText.textContent  = '!';
            hud.classList.add('pulsing');
            setTimeout(() => startHuntPhase(totalSeconds || 300), 1500);
            break;
        }

        case 'close': {
            stopTimer();
            hud.classList.add('hidden');
            document.body.classList.remove('cop', 'robber');
            break;
        }
    }
});
