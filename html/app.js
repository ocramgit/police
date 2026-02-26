'use strict';

// ── Estado ─────────────────────────────────────────────────────
let roundActive = false;
let myRole = null;
let roundDuration = 900;
let lockSeconds = 30;
let timerEl, ringEl, timerSub, roleBadge, roleIcon, roleLabel;
let phaseLabelEl, robberCountEl, robberNumEl;
let waveBadge, waveIcon, waveLabel;
let dangerBar, dangerIcon, dangerText;
let actionHint, heliCooldownEl, heliBarEl, heliTimerEl;
let borderWarnEl, spikeCountEl, keybindsPanel, keybindsList;
let killFeed;
let timerInterval = null;
let lockTimer = null;
let remainingTime = 0;

// ── Init ───────────────────────────────────────────────────────
window.addEventListener('load', () => {
    timerEl = document.getElementById('timer-text');
    ringEl = document.getElementById('ring-fill');
    timerSub = document.getElementById('timer-sub');
    roleBadge = document.getElementById('role-badge');
    roleIcon = document.getElementById('role-icon');
    roleLabel = document.getElementById('role-label');
    phaseLabelEl = document.getElementById('phase-label');
    robberCountEl = document.getElementById('robber-count');
    robberNumEl = document.getElementById('robber-num');
    waveBadge = document.getElementById('wave-badge');
    waveIcon = document.getElementById('wave-icon');
    waveLabel = document.getElementById('wave-label');
    dangerBar = document.getElementById('danger-bar');
    dangerIcon = document.getElementById('danger-icon');
    dangerText = document.getElementById('danger-text');
    actionHint = document.getElementById('action-hint');
    heliCooldownEl = document.getElementById('heli-cooldown');
    heliBarEl = document.getElementById('heli-bar');
    heliTimerEl = document.getElementById('heli-timer');
    borderWarnEl = document.getElementById('border-warn');
    spikeCountEl = document.getElementById('spike-count');
    keybindsPanel = document.getElementById('keybinds-panel');
    keybindsList = document.getElementById('keybinds-list');
    killFeed = document.getElementById('kill-feed');
});

// ── NUI Message Handler ────────────────────────────────────────
window.addEventListener('message', (e) => {
    const d = e.data;
    if (!d || !d.action) return;

    switch (d.action) {

        // ── Abrir HUD
        case 'open': {
            roundActive = true;
            myRole = d.role;
            roundDuration = d.roundDuration || 900;
            lockSeconds = d.lockSeconds || 30;
            remainingTime = roundDuration;

            document.body.className = myRole;
            document.getElementById('hud').classList.remove('hidden');

            if (myRole === 'cop') {
                roleIcon.textContent = '🚓';
                roleLabel.textContent = 'POLÍCIA';
                actionHint.classList.remove('hidden');
                robberCountEl.classList.remove('hidden');
                buildKeybinds([
                    { key: 'G', label: 'Algemar' },
                    { key: 'H', label: 'Heli Apoio' },
                    { key: 'K', label: 'Spike Strip' },
                    { key: 'J', label: 'Drone' },
                ]);
            } else {
                roleIcon.textContent = '🔪';
                roleLabel.textContent = 'LADRÃO';
                actionHint.classList.add('hidden');
                buildKeybinds([{ key: '/flip', label: 'Endireitar carro' }]);
            }

            waveBadge.classList.add('hidden');
            phaseLabelEl.textContent = myRole === 'cop' ? 'A AGUARDAR LIBERTAÇÃO...' : 'EM FUGA!';

            // Countdown da round
            startRoundTimer();

            // Lock countdown visual
            if (myRole === 'cop') {
                let lock = lockSeconds;
                phaseLabelEl.textContent = `CONGELADO — ${lock}s`;
                lockTimer = setInterval(() => {
                    lock--;
                    if (lock <= 0) {
                        clearInterval(lockTimer);
                        lockTimer = null;
                    } else {
                        phaseLabelEl.textContent = `CONGELADO — ${lock}s`;
                    }
                }, 1000);
            }
            break;
        }

        // ── Fechar HUD
        case 'close': {
            roundActive = false;
            myRole = null;
            document.body.className = '';
            document.getElementById('hud').classList.add('hidden');
            document.getElementById('admin-ui').classList.add('hidden');
            keybindsPanel.classList.add('hidden');
            waveBadge.classList.add('hidden');
            dangerBar.classList.add('hidden');
            if (heliCooldownEl) heliCooldownEl.classList.add('hidden');
            if (borderWarnEl) borderWarnEl.classList.add('hidden');
            clearInterval(timerInterval);
            clearInterval(lockTimer);
            break;
        }

        // ── Cop libertado
        case 'released': {
            if (lockTimer) { clearInterval(lockTimer); lockTimer = null; }
            phaseLabelEl.textContent = 'EM CAÇA!';
            break;
        }

        // ── Abrir Admin UI
        case 'openAdminUI': {
            document.getElementById('admin-ui').classList.remove('hidden');
            break;
        }

        // ── Wave update
        case 'waveUpdate': {
            waveBadge.classList.remove('hidden');
            waveBadge.className = 'wave-' + (d.color || 'blue');
            waveIcon.textContent = '⚡';
            waveLabel.textContent = 'ONDA ' + d.wave + ': ' + d.label;
            break;
        }

        // ── Robbers count
        case 'updateRobbers': {
            robberNumEl.textContent = d.count;
            break;
        }

        // ── Danger indicator
        case 'danger': {
            dangerBar.className = '';
            if (d.level === 0) {
                dangerBar.classList.add('hidden');
            } else if (d.level === 1) {
                dangerBar.classList.add('level-1');
                dangerIcon.textContent = '⚠️';
                dangerText.textContent = 'INIMIGO PRÓXIMO';
                document.getElementById('hud').classList.remove('pulsing');
            } else {
                dangerBar.classList.add('level-2');
                dangerIcon.textContent = '🚨';
                dangerText.textContent = 'PERIGO IMINENTE!';
                document.getElementById('hud').classList.add('pulsing');
            }
            break;
        }

        // ── Kill Feed
        case 'killFeed': {
            addKillFeed(d.feedType, d.actor, d.victim);
            break;
        }

        // ── Heli cooldown bar (cop)
        case 'heliCooldown': {
            if (!heliCooldownEl) break;
            if (d.remaining <= 0) {
                heliCooldownEl.classList.add('hidden');
            } else {
                heliCooldownEl.classList.remove('hidden');
                const pct = (d.remaining / d.total) * 100;
                if (heliBarEl) heliBarEl.style.width = pct + '%';
                if (heliTimerEl) heliTimerEl.textContent = d.remaining + 's';
            }
            break;
        }

        // ── Border warning
        case 'borderWarn': {
            if (!borderWarnEl) break;
            if (d.near) {
                borderWarnEl.classList.remove('hidden');
            } else {
                borderWarnEl.classList.add('hidden');
            }
            break;
        }

        // ── Spike count (cop)
        case 'spikeCount': {
            if (!spikeCountEl) break;
            spikeCountEl.textContent = '🚨 Spikes: ' + d.count;
            spikeCountEl.classList.toggle('empty', d.count <= 0);
            break;
        }
    }
});

// ── Timer ──────────────────────────────────────────────────────
function startRoundTimer() {
    clearInterval(timerInterval);
    remainingTime = roundDuration;
    const CIRCUMFERENCE = 213.63;

    timerInterval = setInterval(() => {
        if (!roundActive) { clearInterval(timerInterval); return; }
        remainingTime = Math.max(0, remainingTime - 1);

        const mins = Math.floor(remainingTime / 60);
        const secs = remainingTime % 60;
        timerEl.textContent = mins + ':' + String(secs).padStart(2, '0');

        const pct = remainingTime / roundDuration;
        ringEl.style.strokeDashoffset = CIRCUMFERENCE * (1 - pct);

        // Cor do anel: verde→amarelo→vermelho nos últimos 60s
        if (remainingTime < 60) ringEl.style.stroke = '#ef4444';
        else if (remainingTime < 180) ringEl.style.stroke = '#f59e0b';
    }, 1000);
}

// ── Keybinds panel ─────────────────────────────────────────────
function buildKeybinds(binds) {
    keybindsList.innerHTML = '';
    binds.forEach(b => {
        const row = document.createElement('div');
        row.className = 'kb-row';
        row.innerHTML = `<kbd>${b.key}</kbd><span>${b.label}</span>`;
        keybindsList.appendChild(row);
    });
    keybindsPanel.classList.remove('hidden');
}

// ── Kill Feed ──────────────────────────────────────────────────
function addKillFeed(type, actor, victim) {
    const item = document.createElement('div');
    item.className = 'kf-item';
    if (type === 'arrest') { item.classList.add('kf-arrest'); item.textContent = `🔒 ${actor} algemou ${victim}`; }
    else if (type === 'kill') { item.classList.add('kf-kill'); item.textContent = `💀 ${victim} foi eliminado`; }
    else if (type === 'oob') { item.classList.add('kf-oob'); item.textContent = `🚫 ${victim} saiu da zona`; }
    killFeed.appendChild(item);
    setTimeout(() => {
        item.classList.add('kf-fade');
        setTimeout(() => item.remove(), 500);
    }, 5000);
}

// ── Admin UI ───────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    // +/− buttons
    document.querySelectorAll('.adj-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const target = document.getElementById(btn.dataset.target);
            if (!target) return;
            const delta = parseInt(btn.dataset.delta);
            const min = parseInt(target.min) || 0;
            const max = parseInt(target.max) || 9999;
            const val = Math.min(max, Math.max(min, parseInt(target.value || 0) + delta));
            target.value = val;
            if (target.id === 'input-lock') {
                document.getElementById('lock-hint').textContent = val + ' segundos';
            }
        });
    });

    // Waves toggle
    const wOn = document.getElementById('waves-on');
    const wOff = document.getElementById('waves-off');
    if (wOn && wOff) {
        wOn.addEventListener('click', () => { wOn.classList.add('active'); wOff.classList.remove('active'); });
        wOff.addEventListener('click', () => { wOff.classList.add('active'); wOn.classList.remove('active'); });
    }

    // Start button
    const btnStart = document.getElementById('btn-start');
    if (btnStart) {
        btnStart.addEventListener('click', () => {
            const numCops = parseInt(document.getElementById('input-cops').value) || 2;
            const lockSecs = parseInt(document.getElementById('input-lock').value) || 30;
            const waves = document.getElementById('waves-on').classList.contains('active');
            fetch('https://police/policia:submitConfig', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ numCops, lockSecs, waveMode: waves })
            });
            document.getElementById('admin-ui').classList.add('hidden');
        });
    }

    // Cancel button
    const btnCancel = document.getElementById('btn-cancel');
    if (btnCancel) {
        btnCancel.addEventListener('click', () => {
            fetch('https://police/policia:closeAdminUI', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            document.getElementById('admin-ui').classList.add('hidden');
        });
    }
});
