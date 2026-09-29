# Calendario do curso 2026-27 con votación

Contido do paquete:

- `index.html` · o calendario completo (unha soa páxina, sen build).
- `config.js` · onde pos a URL e a clave do teu Supabase.
- `supabase.sql` · as táboas e funcións da votación anónima (un voto por dispositivo) e da versión do profesorado. Todo o que crea empeza por `ccc_` (3 táboas e 13 funcións), así que non choca con nada do teu proxecto nin toca outras táboas.

## Poñelo en marcha (uns 10 minutos)

1. **Supabase.** Abre o proxecto onde queiras gardar isto → *SQL Editor* → pega o contido de `supabase.sql`.
   Antes de executar, cambia `CAMBIA_ESTA_CLAVE` por unha clave túa (é a clave de administración).
   Preme *Run*. Só crea 3 táboas moi pequenas e as funcións, todas con prefixo `ccc_`. Se probaras antes unha versión que usaba o prefixo `cal_`, o final do script ten un bloque comentado para borrar aquilo (é unha instalación nova: terás que volver publicar a versión do profesorado).
2. **Config.** En *Project Settings → API* copia a *Project URL* e a chave *anon public* e pégaas en `config.js`.
3. **Vercel.** *Add New → Project* e sube esta carpeta (ou un repositorio de GitHub con estes ficheiros).
   Non hai que configurar build: é unha web estática.
4. Abre a URL de Vercel. Esa é a **vista de administración**: as túas edicións gárdanse no teu navegador.

## Usalo

- **Versión do profesorado.** En *Axustes → Versión para o profesorado* preme *Publicar*. Compartes a ligazón `…/?ver=1`, que é só de lectura e non pide conta. Cada vez que cambies datas, volve premer *Publicar*.
- **Votación.** En *Propostas e votación*, entra coa clave. Elixe cando abre (agora ou programado) e cando pecha (a man, en X minutos ou a unha hora exacta), e preme *Crear votación*. Sae un QR, un código de 4 díxitos e unha ligazón para pegar no chat da videochamada.
  - Dende que abre até que pecha, calquera con a ligazón pode votar. Se abren a páxina antes da hora, quedan esperando e actualízase soa.
  - Mentres corre podes *Pechar agora*, estender o peche (+2 / +5 min), quitar o peche automático, ou abrir antes se estaba programada. Cando está pechada podes *Reabrir*.
  - Podes decidir se os resultados os ven tamén quen vota ao pechar.

## Que se ve e que non

- Non se piden nomes. Cada **dispositivo** (navegador) pode votar unha vez por ronda.
- Quen organiza ve **cantos** votos hai, nunca **quen** votou nin **que** votou cada quen. O voto vai á urna sen nome, sen data e sen identificador do dispositivo; o dispositivo só queda marcado como «xa votou». Ao pechar, a urna barállase.
- Límite: como non hai nome, quen use outro navegador, unha ventá privada ou borre os datos do navegador podería votar dúas veces. Compara o total de votos cos asistentes á reunión.
- Un voto non se pode cambiar despois de enviado (non hai forma de atopalo). Se hai un erro, abre unha nova votación.
- Quen teña acceso directo á base de datos coa clave de servizo de Supabase é un administrador técnico e podería intentar reconstruír relacións por outras vías. Para un claustro, o deseño protexe fronte ao uso normal.

## Notas

- Se non enches `config.js`, a web funciona igual pero sen votación en liña nin versión publicada.
- A clave "anon" é pública por deseño; as táboas non teñen políticas de acceso e só se pode chamar ás funcións de `supabase.sql`.
