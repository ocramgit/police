# 🚨 Polícia vs Ladrões — QBCore Minijogo

> Minijogo de perseguição **Polícia vs Ladrões** para servidores FiveM com framework **QBCore**.  
> Versão `2.0.0` — suporte a múltiplas zonas, ondas progressivas de caos, power-ups, HUD glassmorphism e UI de administração.

---

## 📁 Estrutura do Projeto

```
Policia/
├── fxmanifest.lua        # Manifesto do recurso FiveM
├── config.lua            # Toda a configuração editável
├── server/
│   └── main.lua          # Lógica de servidor (rondas, detenções, kill feed, helisuporte)
├── client/
│   └── main.lua          # Lógica de cliente (spawn, caos, power-ups, HUD, zona visual)
└── html/
    ├── index.html         # Estrutura da UI (NUI)
    ├── style.css          # Estilo glassmorphism (Outfit font)
    └── app.js             # Lógica da NUI (referenciado mas não incluído no repo)
```

---

## ⚙️ Dependências

| Dependência | Uso |
|---|---|
| `qb-core` | Framework principal (jogadores, inventário, notificações) |
| `qb-inventory` | ItemBox de feedback ao receber itens |
| `qb-vehiclekeys` *(opcional)* | Atribuição automática de chaves do veículo spawnado |

---

## 🚀 Instalação

1. Copia a pasta `Policia` para `resources/[local]/` no teu servidor.
2. Adiciona ao `server.cfg`:
   ```
   ensure Policia
   ```
3. Confirma que `qb-core` está a correr antes deste recurso.
4. Garante que o item `handcuffs` existe no `QBCore.Shared.Items` (usado para algemar).

---

## 🎮 Como Jogar

### Iniciar uma Ronda

| Método | Detalhe |
|---|---|
| Comando in-game | `/comecarpolicia` — requer permissão `god` ou `admin` — abre a **UI de Administração** |
| Consola do servidor | `/comecarpolicia <numCops> <lockSecs>` — inicia diretamente |
| Encerrar | `/terminarpolicia` — cancela a ronda ativa |

### UI de Administração
Ao usar `/comecarpolicia` in-game abre um painel glassmorphism onde configuras:
- **Nº de polícias** (mín. 1, máx. jogadores − 1)
- **Freeze inicial em segundos** (tempo que os cops ficam presos antes de poder perseguir)
- **Modo Ondas** ON/OFF (ativa/desativa o sistema de caos progressivo)

---

## 🗺️ Zonas Disponíveis

Uma zona é **sorteada aleatoriamente** a cada ronda. Cada zona tem spawns próprios para cops e ladrões, além de centro e raio da área de jogo.

| # | Nome | Coordenadas (centro) | Raio |
|---|---|---|---|
| 1 | 🏙️ Centro da Cidade | (200, -900, 30) | 1100 m |
| 2 | ✈️ Aeroporto | (-1050, -2900, 13) | 900 m |
| 3 | 🏖️ Sandy Shores | (1850, 3700, 33) | 850 m |
| 4 | ⛰️ Paleto Bay | (-265, 6235, 31) | 800 m |
| 5 | 🏭 Zona Industrial (La Mesa) | (800, -1900, 26) | 700 m |

A zona é visualmente marcada por:
- **Blip de raio** no mapa (verde).
- **Muro de marcadores cilíndricos** (72 pilares) laranja dentro / vermelho fora, apenas renderizado até ~350 m de distância do jogador.

---

## 👮 Mecânicas da Polícia

### Spawn e Veículo
- Recebe um carro de polícia aleatório da lista (`police`, `police2`, `police3`, `police4`, `fbi`, `sheriff`).
- Veículo é totalmente upgradado (todos os mods ao máximo).
- **Pneus invencíveis** nos veículos da polícia.
- Chaves atribuídas automaticamente via `qb-vehiclekeys`.

### Freeze Inicial
- Os cops ficam **congelados** (posição + veículo bloqueados, todos os controlos desativados) durante o período de lock definido.
- Ao fim do tempo, recebem notificação e são libertados.

### Ferramentas Exclusivas
| Tecla | Ação |
|---|---|
| **G** | Tentar **algemar** o ladrão mais próximo (alcance: 3.5 m a pé, 6 m se no carro) |
| **H** | Solicitar **helicóptero de apoio** (cooldown: 120 s, duração: 20 s) |

#### Helisuporte
- O servidor calcula o ladrão mais próximo do cop e envia a localização ao cliente.
- Spawn de helicóptero na altitude configurada (`heliAlt = 80 m`) sobre a posição do ladrão.
- Ilumina o alvo com holofote durante `heliDuration` segundos.

### Armas
- Pistola (`weapon_pistol`) com 60 munições.
- `handcuffs` (item de inventário).
- Pode obter **armas pesadas** via power-up (ver abaixo).

---

## 🔪 Mecânicas do Ladrão

### Spawn e Veículo
- Recebe um carro civil aleatório (`blista`, `issi2`, `prairie`, `rhapsody`, `ingot`).
- Veículo upgradado (mods ao máximo).
- **Pneus normais** (vulneráveis a spike strips e tiros).
- O ladrão começa com **faca** (`weapon_knife`) — sem munições.

### Eliminação
O ladrão é eliminado se:
1. **Algemado** por um cop a pé ou arrastado do carro.
2. **Morto** pelo caos NPC — o cliente detecta morte e reporta ao servidor (`policia:robberDied`).
3. **Saiu da zona** — após 15 s de aviso, e sem regressar, é eliminado pelo servidor (`policia:outOfBounds`).

### Condições de Vitória
- **Polícia vence**: todos os ladrões detidos ou eliminados.
- **Ladrões vencem**: tempo de ronda esgota (15 minutos por defeito).

---

## 🌊 Sistema de Ondas Progressivas (Modo Caos)

Ativo apenas se **Modo Ondas = ON**. Para o **ladrão**, cada minuto de jogo (a partir do 8º segundo) escala a ameaça:

| Minuto | Onda | Descrição |
|---|---|---|
| 0 | – | Zona calma — 20 s para escapar |
| 1 | Perseguição Leve | Aviso de que o caos está a chegar |
| 2 | Carros Rápidos 🔵 | 1 carro leve de perseguição |
| 3 | Carros Pesados 🟡 | SUV/muscle cars agressivos |
| 4 | Polícia Pesada 🟡 | Múltiplos carros, tanques blindados sem armas |
| 5 | Blindados 🟠 | Tanques + helicópteros de apoio |
| 6 | Blindados + Helis 🟠 | Mais tanques armados (Rhino, Khanjali, APC) |
| 7 | Tanques ARMADOS 🔴 | Helicópteros kamikaze |
| 8 | Aviões de Carga 🔴 | Titan/Cargoplane a baixa altitude |
| 9 | Camiões + Helis 🔴 | Camiões + helis a disparar |
| 10 | Autocarros + Tanques 🔴 | Autocarros, riot police, mais tanques |
| 11 | CAOS MÁXIMO 🔴 | Tudo o anterior em simultâneo |
| 12+ | 🌋 CIDADE TOTAL | **City Rage** — todos os NPCs civis atacam o ladrão a golpes de bastão |

### Elementos fixos de Caos (ativos para todos desde o início)
- **Tráfego extremo**: density ×10 para veículos, ×5 para peds.
- **Roadblocks NPC**: 25 barricadas com carros de polícia frozen, 3-5 barreiras físicas, cones e 2 SWAT armados por ponto (os SWAT atacam só o ladrão).
- **Rampas de veículos**: até 80 rampas spawn-adas nas estradas dentro da zona.
- Limpeza automática de entidades > 350 m do jogador a cada 20 s.
- Cap de 30 entidades de caos simultâneas antes de pausar spawns.

---

## ⚡ System de Power-Ups

12 power-ups distribuídos aleatoriamente pela zona (entre 20%-80% do raio). Respawn em **25 segundos** após serem apanhados. Visíveis como props 3D animados (flutuam + rodam) com pilar de luz e círculo pulsante no chão.

### Power-Ups do Ladrão 🔴
| Ícone | Nome | Efeito |
|---|---|---|
| 🔧 | Reparação Total | Repara carro + restaura vida |
| ⚡ | NITRO BOOST | +60% velocidade por 12 s |
| 👻 | GHOST MODE | Semi-invisível + invencível por 8 s |
| 💣 | EMP BLAST | Desliga todos os veículos num raio de 60 m por 10 s |
| 🌀 | TELEPORT ALEATÓRIO | Teletransporta o carro para ponto aleatório dentro da zona |

### Power-Ups da Polícia 🔵
| Ícone | Nome | Efeito |
|---|---|---|
| 🔫 | Arma PESADA | Dá aleatoriamente: Combat MG / Sniper Rifle / RPG com ammo infinita |
| 🚨 | SPIKE STRIP | Coloca uma faixa de pregos à frente (auto-remove ao fim de 45 s) |

### Power-Ups para Ambos 🟡
| Ícone | Nome | Efeito |
|---|---|---|
| ❤️ | Vida + Colete | Vida máxima + 100 colete |
| 💨 | SUPER SALTO | Super jump ativo por 20 s |
| 🔥 | CARRO EM CHAMAS | Neon laranja no carro + +30% velocidade por 15 s |

---

## 🖥️ HUD & UI (NUI)

### HUD Principal (canto superior direito)
- **Role Badge**: cor azul (cop) ou vermelha (ladrão).
- **Wave Badge**: indica a onda atual com cor progressiva (azul → amarelo → laranja → vermelho pulsante).
- **Phase Label**: mostra se o cop está a aguardar libertação ou em jogo.
- **Robber Count**: número de ladrões restantes (visível para cops).
- **Timer em anel SVG**: countdown circular com cor baseada no role, atualiza por segundo.
- **Danger Bar**: aparece quando inimigo (player ou NPC) está próximo (nível 1: amarelo, nível 2: vermelho pulsante).
- **Action Hint**: indica as teclas `G` e `H` (apenas cops).

### Kill Feed (canto inferior esquerdo)
Mensagens animadas para:
- 🔒 **Detenção** (`kf-arrest`) — azul
- 💀 **Kill** (`kf-kill`) — vermelho
- 🚫 **Out of Bounds** (`kf-oob`) — amarelo

### Keybinds Panel (canto inferior direito)
Lista de teclas disponíveis para o role atual.

### UI de Administração (modal central)
Glassmorphism com backdrop blur. Campos com botões +/− para ajuste de valores.

---

## 📡 Eventos de Rede

### Servidor → Cliente
| Evento | Descrição |
|---|---|
| `policia:assignRole` | Atribui role, carro, spawn, arma, lockSecs, waveMode |
| `policia:setupZone` | Envia coordenadas e nome da zona |
| `policia:releasePolice` | Descongela os cops |
| `policia:sendClue` | Envia posições de todos os jogadores (a cada `clueInterval` s) |
| `policia:endRound` | Termina a ronda no cliente |
| `policia:killFeed` | Transmite evento de kill feed |
| `policia:youWereArrested` | Notifica o ladrão que foi apanhado |
| `policia:forceLeaveVehicle` | Força o ladrão a sair do carro antes de ser algemado |
| `policia:spawnHeli` | Instrui o cop a spawnar heli de apoio |
| `policia:openAdminUI` | Abre a UI de configuração no cliente |

### Cliente → Servidor
| Evento | Descrição |
|---|---|
| `policia:tryArrest` | Cop tenta algemar (tecla G) |
| `policia:robberDied` | Ladrão morreu |
| `policia:outOfBounds` | Saiu da zona |
| `policia:requestHeli` | Cop pede helisuporte (tecla H) |
| `policia:startFromUI` | Iniciar ronda a partir da UI |

---

## 🔧 Configuração (`config.lua`)

### Temporizadores
| Variável | Valor padrão | Descrição |
|---|---|---|
| `clueInterval` | 20 s | Intervalo entre pistas de localização |
| `roundDuration` | 900 s (15 min) | Duração máxima da ronda |
| `blipDuration` | 18 s | Duração dos blips de pista no mapa |
| `outOfBoundsWarnSecs` | 15 s | Aviso antes de eliminar por saída de zona |

### Veículos
| Variável | Valor padrão |
|---|---|
| `policeCars` | `police`, `police2`, `police3`, `police4`, `fbi`, `sheriff` |
| `robberCars` | `blista`, `issi2`, `prairie`, `rhapsody`, `ingot` |

### Armas
| Variável | Valor padrão |
|---|---|
| `policeWeapon` | `weapon_pistol` |
| `policeAmmo` | 60 |
| `robberWeapon` | `weapon_knife` |
| `robberAmmo` | 0 |
| `handcuffsItem` | `handcuffs` |

### Mecânicas
| Variável | Valor padrão | Descrição |
|---|---|---|
| `arrestRange` | 3.5 m | Alcance de algemagem a pé |
| `alertRange` | 80.0 m | Alcance do indicador de perigo no HUD |
| `roadblockCount` | 25 | Número de roadblocks NPC por ronda |

### Helicóptero de Apoio
| Variável | Valor padrão |
|---|---|
| `cooldown` | 120 s |
| `duration` | 20 s |
| `heliAlt` | 80 m |

### Permissões e Mínimos
| Variável | Valor padrão |
|---|---|
| `allowedGroups` | `{ 'god', 'admin' }` |
| `minPlayers` | 2 |

---

## 🐛 Problemas Conhecidos / Limitações Atuais

- `app.js` não está incluído no repositório (ficheiro da NUI em falta — **crítico para a UI**).
- Os roadblocks são spawnados apenas no cliente local (não são sincronizados entre jogadores via OneSync).
- O sistema de ondas (caos progressivo) só afeta o cliente local do ladrão — outros ladrões não vêem as mesmas entidades.
- A deteção de morte do ladrão (`policia:robberDied`) depende do cliente detetar `IsPedDeadOrDying` — pode falhar em casos de lag.
- O `cleanupChaos` percorre `FindFirstVehicle/FindNextVehicle` que trabalha apenas em entidades locais.

---

## 🗺️ Próximos Passos Sugeridos

### Prioridade Alta
- [ ] **Recuperar/criar `html/app.js`** — a NUI não funciona sem este ficheiro.
- [ ] **Sincronização de entidades de caos via OneSync** — atualmente os NPCs e veículos de caos são client-side e não são visíveis para outros jogadores.
- [ ] **Deteção de morte robusta** — usar eventos de saúde no servidor em vez de polling client-side.

### Mecânicas Novas
- [ ] **Scoreboard final** — mostrar stats da ronda (detenções, kills, tempo sobrevivido).
- [ ] **Sistema de pontos / XP** — recompensar jogadores com QBCore money ou XP.
- [ ] **Mais zonas** — adicionar Vinewood Hills, Porto de LS, Chumash, etc.
- [ ] **Modo FFA** — ladrões vs ladrões (sem cops), o último a sobreviver ganha.
- [ ] **Respawn limitado para ladrões** — em vez de eliminação direta, dar X vidas.
- [ ] **Skins distintas** — forçar outfit de polícia/ladrão ao atribuir role.
- [ ] **Missão de objetivo** — ladrão tem de chegar a um ponto de extração em vez de apenas sobreviver.

### Qualidade de Vida
- [ ] **Balancear véiculo do ladrão** — opção de escolher veículo antes do início.
- [ ] **Cooldown visual no HUD** para o helisuporte (barra ou timer).
- [ ] **Mapa de zonas** na UI admin para escolher zona manualmente.
- [ ] **Internacionalização** — extrair strings para ficheiro de locale.
- [ ] **Testes** — validar que `handcuffs` existe nos items do servidor antes de iniciar.

---

## 📝 Changelog

| Versão | Nota |
|---|---|
| `2.0.0` | Múltiplas zonas sorteadas, poder-ups, ondas progressivas completas, HUD glassmorphism, UI de admin |
| `1.x` | Sistema base cops vs robbers com zona única e waves simples |
