# 🎮 Roblox Party

![Build](https://img.shields.io/badge/build-passing-brightgreen)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Status](https://img.shields.io/badge/state-development-yellow)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

> Sistema modular de minijuegos estilo **Mario Party**, diseñado para **Roblox Studio** con soporte completo para **Rojo + VS Code + GitHub**, **partidas simultáneas** y **torneos de hasta 32 jugadores**.

---

## 🧭 Índice

1. [Descripción General](#-descripción-general)
2. [Funcionamiento](#-funcionamiento)
3. [Estructura del Proyecto](#-estructura-del-proyecto)
4. [Servicios Principales](#-servicios-principales)
5. [Modo Torneo](#-modo-torneo)
6. [Variables Globales](#-variables-globales)
7. [Añadir Nuevos Minijuegos](#-añadir-nuevos-minijuegos)
8. [Configuración del Entorno (Rojo + VSCode + GitHub)](#-configuración-del-entorno-rojo--vscode--github)
9. [Scripts Auxiliares](#-scripts-auxiliares)
10. [Estado del Proyecto](#-estado-del-proyecto)
11. [Licencia](#-licencia)

---

## 🎯 Descripción General

**Roblox Party** es una experiencia de Roblox en la que hasta **32 jugadores** pueden competir en una serie de **minijuegos aleatorios**.  
El sistema permite:

- Varias **partidas simultáneas** en un mismo servidor.  
- **Torneos automáticos** con rotación de jugadores.  
- **Fácil integración** de nuevos minijuegos mediante módulos.  
- **Arquitectura escalable y mantenible** con Rojo, VSCode y GitHub.

---

## ⚙️ Funcionamiento

1. Los jugadores aparecen en el **Lobby**.  
2. Al entrar en la **zona de inicio**, se unen a una sesión.  
3. Cuando hay suficientes jugadores (o tras un timeout), la partida inicia.  
4. Se seleccionan **5 minijuegos aleatorios** (configurable).  
5. Cada minijuego otorga puntos al top 3.  
6. El jugador con más puntos al final **gana la partida**.  
7. El servidor puede correr **múltiples partidas al mismo tiempo**, cada una con su propio `sessionId`.

---

## 🧩 Estructura del Proyecto

Roblox Party/
├─ ReplicatedStorage/
│ └─ Game/
│ ├─ Config/ → Variables globales y catálogo de minijuegos
│ ├─ Net/ → RemoteEvents y RemoteFunctions
│ ├─ Shared/ → Tipos y utilidades comunes
│ ├─ UI/ → GUIs modulares (HUD, Scoreboard, etc.)
│ └─ Minigames/ → Módulos de minijuegos independientes
│ ├─ Templates/ → Plantilla base para nuevos minijuegos
│ └─ [MinigameName]/ → Controlador + assets
│
├─ ServerScriptService/
│ └─ GameServer/
│ ├─ Bootstrap.server.lua → Arranque principal del servidor
│ ├─ Services/ → Lógica global (Matchmaking, Scoring, etc.)
│ └─ Controllers/ → Controladores por sesión y torneo
│
├─ ServerStorage/
│ └─ Maps/ → LobbyMap + mapas de minijuegos
│
├─ StarterPlayer/
│ └─ StarterPlayerScripts/ → Scripts cliente (UIController, NetClient, etc.)
│
└─ Rojo/
└─ default.project.json → Configuración de sincronización Rojo

markdown
Copiar código

> 🔹 Cada carpeta es modular y versionable.  
> 🔹 El proyecto puede ser reconstruido automáticamente con los scripts PowerShell y Rojo incluidos.

---

## 🧠 Servicios Principales

| Servicio | Rol | Descripción |
|-----------|-----|-------------|
| **MatchmakingService** | 🔁 | Agrupa jugadores y crea nuevas sesiones. |
| **SessionService** | 🧩 | Controla partidas independientes (8 jugadores). |
| **MinigameService** | 🎲 | Selecciona y ejecuta los minijuegos. |
| **ScoringService** | 🏅 | Asigna puntos y rankings. |
| **TournamentService** | 🏆 | Maneja torneos con hasta 32 jugadores. |
| **HeatAllocator** | ♻️ | Rota jugadores entre heats (subgrupos). |
| **PlayerDataService** | 💾 | Maneja datos temporales por sesión. |
| **IntegrityService** | 🧱 | Seguridad y validación básica. |

---

## 🏆 Modo Torneo

- Hasta **32 jugadores** participando al mismo tiempo.  
- Se dividen en **heats** de 8 o 4 personas según el minijuego.  
- Cada minijuego se juega por heats **en paralelo o por oleadas**.  
- Entre minijuegos, los jugadores se **reorganizan aleatoriamente** (evitando repetir rivales).  
- Los puntos acumulados definen el ranking final o bracket.

### Estructura Interna del Torneo
TournamentController
│
├─ Rondas: [Minigame_1 .. Minigame_N]
│ ├─ Heat_1 → SessionController
│ ├─ Heat_2 → SessionController
│ └─ ...
│
└─ Leaderboard Global (ScoringService)

markdown
Copiar código

---

## 🌍 Variables Globales (`GlobalConfig.lua`)

| Variable | Descripción | Valor por defecto |
|-----------|-------------|-------------------|
| `MAX_PLAYERS_PER_SESSION` | Jugadores por partida | `8` |
| `SESSION_TIMEOUT_TO_START` | Tiempo máximo de espera (s) | `45` |
| `ROUNDS_PER_MATCH` | Minijuegos por partida | `5` |
| `POINTS_RULES` | Puntos otorgados al top 3 | `{ first=5, second=3, third=1 }` |
| `PARALLEL_SESSIONS_LIMIT` | Partidas simultáneas máximas | `4` |
| `TOURNAMENT_MAX_PLAYERS` | Máximo de jugadores por torneo | `32` |
| `HEAT_SIZES` | Tamaños de heat válidos | `{8,4}` |
| `MINIGAMES_PER_TOURNAMENT` | Minijuegos por torneo | `5` |
| `UI_THEME` | Paleta base para interfaces | Blanco (RGB 255,255,255) |

---

## 🎲 Añadir Nuevos Minijuegos

1. Duplica la carpeta `/ReplicatedStorage/Game/Minigames/Templates/`.
2. Renómbrala con tu minijuego (`ButtonMash`, `ObstacleRun`, etc.).
3. Implementa en `GameController.lua`:
   - `GetMeta()` → id, nombre, peso, jugadores recomendados.  
   - `Setup(context)` → crea el mapa en `context.mountFolder`.  
   - `Start()` → inicia la lógica del juego.  
   - `GetResults()` → retorna un ranking `{ placement = {...} }`.  
   - `Teardown()` → limpia objetos.
4. Crea su mapa en `ServerStorage/Maps/MinigameMaps/[Nombre]Map`.
5. Regístralo en `MinigameCatalog.lua`.

> ✅ Cada minijuego es independiente y se puede testear aislado.

---

## 💻 Configuración del Entorno (Rojo + VSCode + GitHub)

### 1️⃣ Inicializar el Proyecto
```powershell
git init
git branch -M main
rojo serve Rojo\default.project.json
2️⃣ Conectar con Roblox Studio
Abre el plugin de Rojo en Roblox Studio.

Haz clic en Connect al servidor local (localhost:34872).

La estructura aparecerá automáticamente en Studio.

3️⃣ Sincronizar con GitHub
powershell
Copiar código
gh repo create RobloxParty --source=. --public --push
git add .
git commit -m "chore: estructura base"
git push -u origin main
🧰 Scripts Auxiliares
🔹 Crear estructura completa (PowerShell)
Usa el script robloxparty_setup.ps1 para generar todo el árbol, módulos y .gitignore automáticamente.

🔹 Crear remotos y mapas en Roblox Studio (Command Bar)
Ejecuta este snippet en la Command Bar:

lua
Copiar código
local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local function ensure(parent, className, name)
	local inst = parent:FindFirstChild(name)
	if inst and inst.ClassName == className then return inst end
	if inst and inst.ClassName ~= className then inst:Destroy() end
	inst = Instance.new(className); inst.Name = name; inst.Parent = parent
	return inst
end
local GameFolder = ensure(RS, "Folder", "Game")
local NetFolder = ensure(GameFolder, "Folder", "Net")
local RemoteEvents = ensure(NetFolder, "Folder", "RemoteEvents")
local RemoteFunctions = ensure(NetFolder, "Folder", "RemoteFunctions")
ensure(RemoteEvents, "RemoteEvent", "MatchmakingEvent")
ensure(RemoteEvents, "RemoteEvent", "SessionEvent")
ensure(RemoteEvents, "RemoteEvent", "TournamentEvent")
ensure(RemoteEvents, "RemoteEvent", "UIEvent")
ensure(RemoteFunctions, "RemoteFunction", "QueryFunction")
ensure(SS, "Folder", "Maps")
ensure(SS.Maps, "Model", "LobbyMap")
ensure(SS.Maps, "Folder", "MinigameMaps")
ensure(SS.Maps.MinigameMaps, "Model", "ExampleMinigameMap")
ensure(workspace, "Folder", "Sessions")
print("✅ Remotos y mapas verificados.")
📊 Estado del Proyecto
Módulo	Estado	Descripción
Estructura Base (Rojo)	✅	Sincronización completa
Módulos Stub (Servicios/UI)	✅	Todos creados
Minijuego de Ejemplo	✅	Implementación mínima
Lobby / Matchmaking	🔄	En desarrollo
Modo Torneo	🔄	En desarrollo
Sistema de Puntuación Real	⏳	Pendiente
Publicación en Roblox	⏳	Pendiente

⚡ Filosofía del Proyecto
Modularidad, escalabilidad y legibilidad primero.
Cada parte del sistema debe poder evolucionar sin romper las demás.
El proyecto está diseñado para que cualquier IA o desarrollador humano pueda:

Entender los contratos de los módulos.

Modificar minijuegos o servicios sin dependencias ocultas.

Escalar el proyecto con facilidad.

🪪 Licencia
MIT License

kotlin
Copiar código
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files...
🧠 Modo lectura para IA / ChatGPT
Si una IA analiza este README, debe entender:

Que cada carpeta refleja un contenedor lógico de Roblox.

Que cada ModuleScript está diseñado para independencia funcional.

Que las sesiones, torneos y minijuegos se comunican mediante RemoteEvents declarados en ReplicatedStorage/Game/Net.

Que el flujo general es: Lobby → Matchmaking → Session → Minigames → Scoring → Results.

Que el archivo GlobalConfig.lua centraliza todas las constantes ajustables.

Que la sincronización y versionado se manejan con Rojo, Git y VSCode.

✨ Creado por Alan — “La Organización” Project