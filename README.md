# DGASMC · Gmail Dashboard Email

Dashboard intern pentru gestionarea emailurilor Gmail — DGASMC București, Serviciul Stimulent Financiar Adulți cu Handicap.

## Funcții principale

- **Inbox Gmail** — ultimele N zile, filtru label/citit/categorie, statistici sesiune
- **Picker tip document** — click atașament → popup selectare tip → redenumire automată `ZZ.LL.AAAA_Nume_Prenume_TipDoc.ext`
- **OCR Vision** — extrage CNP, Nume, Prenume, Adresă din imagini/PDF cu Claude AI
- **Registru 43/2026** — înregistrare Google Sheets cu nr. automat, confirmare email, viewer cu pre-selecție rând
- **Templates** — răspunsuri predefinite cu variabile, import .docx, save/edit
- **Reply / Email nou** — compunere, atașamente locale, draft Gmail
- **Merge PDF** — combinare atașamente multiple (pdf-lib)
- **Analytics** (`/bi`) — dashboard BI Sheets
- **Aprobare mobilă** (`/approve`) — interfață phone pentru Claude Code

## Fișiere

| Fișier | Rol |
|---|---|
| `index.html` | Aplicație completă (~3000 linii vanilla JS, zero framework) |
| `dashboard-bi.html` | Dashboard Analytics (Chart.js) |
| `server.ps1` | Server HTTP PowerShell localhost:8080 |
| `run.bat` | Pornire dublu-click |

## Instalare rapidă

1. Copiază folderul pe Windows 10/11
2. Dublu-click `run.bat`
3. Introdu Client ID Google la prima rulare → Conectează Gmail

### Creare Client ID Google
1. `console.cloud.google.com` → Proiect nou
2. Library → `Gmail API` + `Google Sheets API` → Enable
3. OAuth consent screen → External → Save
4. Credentials → + Create → OAuth 2.0 Client ID → Web app
   - JS Origins: `http://localhost:8080`
5. Copiază Client ID

### API Key Anthropic (OCR — opțional)
⚙ Setări → câmpul Anthropic API Key → `sk-ant-...`

## Configurare Google Sheets

```javascript
// index.html ~linia 586
const SHEETS_ID = '1xFTA80PFIlByy29dBTNfcgeJn9FOXmeEOLCi18Gy6hs';
const SHEET_NAME = 'Registru E mail 43 2026';
```

**Coloane Registru:** A=Nr.crt | B=Luna | C=Ziua | D=Anul | E=Data | G=Indicativ(formulă) | H=Nume | I=Prenume | J=Nume Prenume | L=Conținut | M=CNP | N=Sector | O=Operator | Q=Email | R=Obs | T=Status | U=Data trimiterii | Y=Atașament

**Sheet "Options" col A** = lista tipuri documente pentru picker (sau hardcodat în `DOC_OPTIONS` ~linia 2024)

## Redenumire atașamente

Format: `ZZ.LL.AAAA_Nume_Prenume_TipDocument.ext`

Exemplu: `01.04.2026_Tascau_Cristina_CI.pdf`

1. Click chip atașament → picker popup
2. Selectează tip (CI, CH, Extras cont, etc.)
3. Redenumit automat; la Registru → pre-bifat

## Stack tehnic

```
Frontend:  HTML5 + CSS3 + Vanilla JS
Auth:      Google OAuth2 Implicit Flow
APIs:      Gmail v1, Sheets v4, Anthropic Messages v1
PDF:       pdf-lib@1.17.1 (CDN)
Server:    PowerShell HttpListener (fără Node.js)
```

## Transfer desktop

Copiază 4 fișiere: `index.html`, `server.ps1`, `dashboard-bi.html`, `run.bat`  
Dublu-click `run.bat`. Client ID se reintroduce o singură dată.

> Dacă Windows blochează: click-dreapta run.bat → Run as Administrator

*DGASMC intern — dezvoltat cu Claude Code (claude-sonnet-4-6)*
