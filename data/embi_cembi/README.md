# Base mensual: `iso3 · mes · embi · cembi_proxy`

Script reproducible en **Stata** que arma un panel **mensual** con la mayor
cobertura de países posible, a partir de fuentes **gratuitas**.

## Qué produce

| columna       | descripción                                                                 | unidad |
|---------------|-----------------------------------------------------------------------------|--------|
| `iso3`        | código ISO-3166 alfa-3 del país                                             | —      |
| `country`     | nombre del país (según el GEM)                                              | —      |
| `region`      | región del proxy corporativo: `LATAM` / `ASIA` / `EMEA` / `EM`             | —      |
| `mes`         | mes (formato Stata `%tm`; en el CSV, `YYYY-MM`)                            | —      |
| `embi`        | **EMBI soberano** (JP Morgan EMBI+/EMBIG stripped spread), por país         | bps    |
| `cembi_proxy` | **proxy de CEMBI**: spread corporativo EM regional (ICE BofA OAS)          | bps    |

Salidas: `embi_cembi_monthly.dta` y `embi_cembi_monthly.csv`.

## Fuentes (gratuitas)

- **EMBI (soberano, por país):** World Bank *Global Economic Monitor* (GEM),
  archivo `GemDataEXTR.xlsx` — redistribuye el JP Morgan EMBI+/EMBIG por país,
  mensual. Es la fuente libre con **mayor cobertura de países**.
- **Proxy CEMBI (corporativo, regional):** *ICE BofA Emerging Markets Corporate
  Plus — Option-Adjusted Spread (OAS)* vía **FRED**:
  - `BAMLEMCBPIOAS` — agregado EM
  - `BAMLEMRLCRPILAOAS` — Latin America
  - `BAMLEMRACRPIASIAOAS` — Asia
  - `BAMLEMRECRPIEMEAOAS` — EMEA

  Se colapsan a mensual (promedio), se pasan a bps (×100) y se asignan a cada
  país según su región.

## ⚠️ Salvedad importante sobre CEMBI

**No existe una fuente gratuita de CEMBI por país.** CEMBI es un índice
propietario de J.P. Morgan; su versión desagregada por país requiere Bloomberg,
Refinitiv/Datastream o J.P. Morgan Markets. Por eso `cembi_proxy` es un spread
corporativo **regional** (no específico de cada país): úsalo como control o
aproximación, no como el CEMBI oficial de cada país.

Si tenés acceso a CEMBI real, reemplazá la **Parte C** del `.do` cargando tu
export y haciendo `merge` por `iso3 + mes`.

## Requisitos

- Stata **15.1+** (para el comando nativo `import fred`).
- API key gratuita de FRED → https://fredaccount.stlouisfed.org/apikeys
  ```stata
  set fredkey TU_API_KEY, permanently
  ```
- Conexión a internet (el script descarga World Bank y FRED).
- Alternativa sin API key: paquete SSC `freduse` (el script lo instala solo si
  hace falta).

## Uso

```stata
cd "data/embi_cembi"
do build_embi_cembi_monthly.do
```

El script: descarga el GEM, **autodetecta** la hoja de EMBI, la reestructura a
panel largo, baja el proxy de FRED, mapea país→`iso3`→región y exporta el panel.

## Notas de reproducibilidad

- El `.do` **autodetecta** la hoja de EMBI buscando `"EMBI"` en los nombres de
  hoja del Excel (el nombre exacto cambia entre versiones del GEM).
- El crosswalk país→`iso3`→región está en la **Parte B** del `.do`. Si una
  versión del GEM agrega países nuevos, sumalos ahí (los que no matchean se
  descartan del panel final).
- Complemento para LatAm: la API del **BCRP** (`estadisticas.bcrp.gob.pe`) tiene
  EMBIG mensual por país, muy limpia, por si querés cruzar/rellenar la región.
- Este entorno de ejecución no tiene salida de red hacia estas fuentes, por eso
  el `.do` está pensado para correrse en tu máquina.
