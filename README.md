# Agentforce Workshop Practitioner

Proyecto Salesforce en **modo manifest** preparado para el workshop de
Agentforce Practitioner. Sirve como punto de partida para construir, desplegar y
probar agentes con **Agent Builder 2.0 (NextGen Authoring)** contra una org
Salesforce.

El repositorio nace vacío de metadata a propósito: trae la estructura y el
manifest configurados, y la metadata se va incorporando durante el workshop.

---

## Requisitos

| Herramienta | Versión mínima | Comprobación |
|---|---|---|
| Salesforce CLI (`sf`) | 2.128 | `sf --version` |
| Git | 2.30 | `git --version` |
| Salesforce Extension Pack | 67.x | Solo si usas VS Code / Cursor |

La org destino necesita **Agentforce habilitado** (Einstein Generative AI +
Agentforce Platform) para poder desplegar agentes.

---

## Org del workshop

| Dato | Valor |
|---|---|
| Username | `trailsignup.462cfe9e6ac813@salesforce.com` |
| Org ID | `00Dg800000HPeWjEAL` |
| Alias CLI | `agentforce-workshop` |
| Edición | Enterprise Edition (trial) |
| Login URL | `https://login.salesforce.com` |
| Caducidad | **7 de octubre de 2026** |

---

## Puesta en marcha

```bash
git clone https://github.com/mgalnaresmilano/Agent-Force-Workshop-Practitioner.git
cd Agent-Force-Workshop-Practitioner

# Autenticar la org y fijarla como destino por defecto del proyecto
sf org login web --alias agentforce-workshop \
  --instance-url https://login.salesforce.com --set-default
```

En la pantalla de login usa el username `trailsignup.462cfe9e6ac813@salesforce.com`.

> La ventana de login OAuth **caduca a los ~2 minutos**. Si ves
> `AuthTimeoutError`, simplemente vuelve a lanzar el comando.

Verifica que la conexión funciona:

```bash
sf data query --query "SELECT Name FROM Organization" --target-org agentforce-workshop
```

Si usas VS Code o Cursor, **recarga la ventana** después del primer clone
(`Cmd+Shift+P` → *Developer: Reload Window*). La extensión de Salesforce solo se
activa si encuentra `sfdx-project.json` al abrir el workspace, así que no verás
la org en la barra de estado hasta que recargues.

---

## Estructura

```
.
├── force-app/main/default/   # Metadata del proyecto (vacío al inicio)
├── manifest/package.xml      # Manifest de retrieve/deploy — API v66.0
├── sfdx-project.json         # force-app como packageDirectory por defecto
├── .forceignore              # Excluye profiles y settings del control de versiones
└── .gitignore
```

Los agentes de Agent Builder 2.0 viven en
`force-app/main/default/aiAuthoringBundles/<NombreAgente>/`, con un fichero
`.agent` (Agent Script) y su `.bundle-meta.xml`.

---

## Comandos habituales

```bash
# Traer metadata de la org al repo
sf project retrieve start --manifest manifest/package.xml --target-org agentforce-workshop

# Desplegar todo el manifest
sf project deploy start --manifest manifest/package.xml --target-org agentforce-workshop

# Desplegar un único agente (recomendado durante el desarrollo)
sf project deploy start \
  --source-dir force-app/main/default/aiAuthoringBundles/MiAgente \
  --target-org agentforce-workshop --wait 10

# Probar un agente en modo conversación
sf agent preview --api-name MiAgente --target-org agentforce-workshop
```

---

## Sobre el manifest

`manifest/package.xml` declara **59 tipos de metadata** con wildcard `*`, en
API **v66.0** (Spring '26). Todos han sido validados contra la org con
`sf org list metadata-types`, de modo que un `retrieve` no falla con
`INVALID_TYPE`.

Cubre Apex, LWC, Flows, objetos y campos, layouts y FlexiPages, permisos,
plus los tipos de Agentforce del path NGA: `AiAuthoringBundle`,
`GenAiPlannerBundle`, `GenAiPlugin`, `GenAiFunction`, `GenAiPromptTemplate`,
`Bot` y `BotVersion`.

Quedan deliberadamente fuera:

- **`Settings` y `StandardValueSet`** — no admiten wildcard `*`; hay que
  enumerar cada miembro explícitamente.
- **Tipos de OmniStudio** (`OmniScript`, `OmniDataTransform`, …) — requieren el
  paquete gestionado instalado.
- **`ContextMapping`, `DocumentClause`, `GenAiPlanner`** — los dos primeros
  necesitan Revenue Cloud habilitado; `GenAiPlanner` es el path legacy,
  sustituido por `GenAiPlannerBundle`.

Si habilitas alguna de esas features en la org, añade el tipo correspondiente al
manifest.

---

## Notas

- Usa siempre el **alias** (`--target-org agentforce-workshop`), nunca el
  username, en los comandos del CLI.
- El `target-org` por defecto se guarda en `.sf/config.json` y
  `.sfdx/sfdx-config.json`, ambos ignorados por git: cada persona autentica su
  propia org sin pisar la de los demás.
- Nunca subas al repo `access_token` ni session IDs.
