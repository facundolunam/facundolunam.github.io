*==============================================================================
*  build_embi_cembi_monthly.do
*------------------------------------------------------------------------------
*  Construye un panel MENSUAL con la mayor cobertura de paises posible:
*
*        iso3   mes(ym)   embi   cembi_proxy
*
*  Definiciones
*  ------------
*  embi        : spread soberano en puntos basicos (bps). Fuente gratuita:
*                World Bank Global Economic Monitor (GEM), que redistribuye el
*                JP Morgan EMBI+/EMBIG (stripped spread) por pais, mensual.
*
*  cembi_proxy : *aproximacion* al spread corporativo emergente (tipo CEMBI).
*                CEMBI por pais NO se publica gratis (es propietario de JP
*                Morgan). Como proxy usamos el ICE BofA EM Corporate Plus OAS
*                de FRED, asignado a cada pais segun su REGION
*                (LatAm / Asia / EMEA) mas el agregado EM como respaldo.
*                Es un spread REGIONAL, no especifico de cada pais: usar con
*                esa salvedad. Unidad: convertido a bps para ser comparable
*                con embi.
*
*  Salidas
*  -------
*        embi_cembi_monthly.dta
*        embi_cembi_monthly.csv
*
*  Requisitos
*  ----------
*  - Stata 15.1+ (para el comando nativo -import fred-).
*  - Una API key gratuita de FRED: https://fredaccount.stlouisfed.org/apikeys
*        set fredkey TU_API_KEY, permanently
*  - Conexion a internet (World Bank + FRED). Este .do descarga los datos.
*  - Paquete opcional SSC -freduse- como alternativa si no queres usar API key.
*
*  Uso
*  ---
*        cd "<carpeta de este .do>"
*        do build_embi_cembi_monthly.do
*==============================================================================

clear all
set more off
version 15.1

*--- Carpeta de trabajo: la del propio do-file --------------------------------
*  Si lo corres interactivamente, seteala a mano:
*     cd "ruta/a/data/embi_cembi"
capture confirm file "build_embi_cembi_monthly.do"
if _rc {
    di as error "Corre este script desde su propia carpeta (cd ...)."
}

local WBURL "https://databank.worldbank.org/data/download/GemDataEXTR.zip"

*==============================================================================
*  PARTE A. EMBI soberano por pais (World Bank GEM)
*==============================================================================
di as txt "== Parte A: descargando World Bank GEM =="

*--- A.1 Descarga y descompresion ---------------------------------------------
capture erase "GemDataEXTR.zip"
capture copy "`WBURL'" "GemDataEXTR.zip", replace
if _rc {
    di as error "No se pudo descargar el GEM. Descarga manual:"
    di as error "  `WBURL'"
    di as error "y descomprimi GemDataEXTR.xlsx en esta carpeta."
}
capture unzipfile "GemDataEXTR.zip", replace   // deja GemDataEXTR.xlsx

local XLSX "GemDataEXTR.xlsx"
capture confirm file "`XLSX'"
if _rc {
    di as error "No se encuentra `XLSX'. Revisar la descarga."
    exit 601
}

*--- A.2 Autodeteccion de la hoja de EMBI -------------------------------------
*  El GEM usa una hoja por indicador; el nombre exacto puede cambiar entre
*  versiones (ej. "JP Morgan EMBI+ (stripped s...", "EMBIG", etc.).
*  Buscamos la primera hoja cuyo nombre contenga "EMBI".
import excel using "`XLSX'", describe
local NS = r(N_worksheet)
local EMBISHEET ""
forvalues s = 1/`NS' {
    local wn = r(worksheet_`s')
    if strpos(upper(`"`wn'"'), "EMBI") & "`EMBISHEET'"=="" {
        local EMBISHEET `"`wn'"'
    }
}
if "`EMBISHEET'"=="" {
    di as error "No se encontro hoja con 'EMBI' en `XLSX'."
    di as error "Hojas disponibles:"
    forvalues s = 1/`NS' {
        di as error "   " r(worksheet_`s')
    }
    exit 111
}
di as txt "Hoja EMBI detectada: `EMBISHEET'"

*--- A.3 Import de la hoja EMBI ------------------------------------------------
*  Layout tipico GEM (hojas mensuales):
*     fila de encabezado -> nombres de pais en las columnas B, C, D, ...
*     columna A          -> etiqueta temporal (ej. "1994M01")
*  Puede haber 0-2 filas de titulo por encima. Importamos TODO como texto
*  (sin firstrow) para parsear el encabezado y las fechas nosotros mismos.
import excel using "`XLSX'", sheet(`"`EMBISHEET'"') allstring clear

*  Lista de columnas tal como las nombro Stata (A, B, C, ...). La primera (A)
*  es la columna de fechas.
qui ds
local ALLV `r(varlist)'
local datevar : word 1 of `ALLV'

*  Localizar la primera fila de DATOS: aquella cuya col A es una fecha mensual
*  ("YYYYMmm", "YYYY-MM" o "YYYY/MM"). La fila de encabezado (nombres de pais)
*  es la inmediatamente anterior.
gen long _obs = _n
gen byte  _isd = regexm(`datevar', "^[0-9]{4}(M|[-/])0?[0-9]{1,2}")
qui su _obs if _isd==1
if r(N)==0 {
    di as error "No se detectaron fechas mensuales en la columna A de la hoja EMBI."
    exit 459
}
local FIRSTDATA = r(min)
local HDRROW    = `FIRSTDATA' - 1
if `HDRROW' < 1 local HDRROW = 1

*  Capturar el nombre de pais de cada columna (celda de la fila de encabezado)
*  y renombrar las columnas a c1, c2, ... guardando el mapeo cid -> pais.
tempname cw
tempfile colnames
postfile `cw' int cid str80 country using "`colnames'"
local k = 0
foreach v of local ALLV {
    if "`v'"=="`datevar'" continue
    local cname = `v'[`HDRROW']
    if `"`cname'"'=="" continue           // columna sin encabezado -> saltar
    local ++k
    post `cw' (`k') (`"`cname'"')
    rename `v' c`k'
}
postclose `cw'
if `k'==0 {
    di as error "No se hallaron columnas de pais en la hoja EMBI."
    exit 459
}

*  Quedarnos solo con las filas de datos y construir el mes (Stata %tm).
keep if _obs >= `FIRSTDATA'
rename `datevar' _rawdate
gen int _y = real(regexs(1)) if regexm(_rawdate, "^([0-9]{4})")
gen int _m = .
replace _m = real(regexs(1)) if regexm(_rawdate, "M0?([0-9]{1,2})$")            // YYYYMmm
replace _m = real(regexs(1)) if missing(_m) & regexm(_rawdate, "^[0-9]{4}[-/]0?([0-9]{1,2})") // YYYY-MM
gen int mdate = ym(_y,_m) if !missing(_y,_m)
format mdate %tm
drop if missing(mdate)
drop _obs _isd _rawdate _y _m

*  Valores a numerico (force: "..", "n/a", "" -> missing) y reshape a largo.
forvalues i = 1/`k' {
    destring c`i', replace force
}
reshape long c, i(mdate) j(cid)
rename c embi
drop if missing(embi)

*  Pegar el nombre de pais real.
merge m:1 cid using "`colnames'", keep(match) nogen
drop cid

*  embi (GEM) ya viene en puntos basicos (bps).
label var embi    "Spread soberano EMBI (bps) - World Bank GEM / JP Morgan"
label var country "Nombre de pais (GEM)"

tempfile EMBI
save "`EMBI'"
di as txt "EMBI: `=_N' observaciones pais-mes."

*==============================================================================
*  PARTE B. Crosswalk pais -> iso3 + region  (para EMBI e para el proxy CEMBI)
*==============================================================================
*  Mapea los nombres de pais que aparecen en el GEM a iso3 y a una region de
*  spread corporativo: LATAM / ASIA / EMEA. Los que no matchean usan el
*  agregado EM (region = "EM"). Ampliar esta tabla si el GEM agrega paises.
clear
input str80 country str3 iso3 str6 region
"Argentina"            "ARG" "LATAM"
"Belize"               "BLZ" "LATAM"
"Bolivia"              "BOL" "LATAM"
"Brazil"               "BRA" "LATAM"
"Chile"                "CHL" "LATAM"
"Colombia"             "COL" "LATAM"
"Costa Rica"           "CRI" "LATAM"
"Dominican Republic"   "DOM" "LATAM"
"Ecuador"              "ECU" "LATAM"
"El Salvador"          "SLV" "LATAM"
"Guatemala"            "GTM" "LATAM"
"Honduras"             "HND" "LATAM"
"Jamaica"              "JAM" "LATAM"
"Mexico"               "MEX" "LATAM"
"Panama"               "PAN" "LATAM"
"Paraguay"             "PRY" "LATAM"
"Peru"                 "PER" "LATAM"
"Suriname"             "SUR" "LATAM"
"Trinidad and Tobago"  "TTO" "LATAM"
"Uruguay"              "URY" "LATAM"
"Venezuela"            "VEN" "LATAM"
"China"                "CHN" "ASIA"
"India"                "IND" "ASIA"
"Indonesia"            "IDN" "ASIA"
"Malaysia"             "MYS" "ASIA"
"Mongolia"             "MNG" "ASIA"
"Pakistan"             "PAK" "ASIA"
"Papua New Guinea"     "PNG" "ASIA"
"Philippines"          "PHL" "ASIA"
"Sri Lanka"            "LKA" "ASIA"
"Vietnam"              "VNM" "ASIA"
"Angola"               "AGO" "EMEA"
"Armenia"              "ARM" "EMEA"
"Azerbaijan"           "AZE" "EMEA"
"Bahrain"              "BHR" "EMEA"
"Belarus"              "BLR" "EMEA"
"Bulgaria"             "BGR" "EMEA"
"Cameroon"             "CMR" "EMEA"
"Croatia"              "HRV" "EMEA"
"Egypt"                "EGY" "EMEA"
"Ethiopia"             "ETH" "EMEA"
"Gabon"                "GAB" "EMEA"
"Georgia"              "GEO" "EMEA"
"Ghana"                "GHA" "EMEA"
"Hungary"              "HUN" "EMEA"
"Iraq"                 "IRQ" "EMEA"
"Ivory Coast"          "CIV" "EMEA"
"Cote d'Ivoire"        "CIV" "EMEA"
"Jordan"               "JOR" "EMEA"
"Kazakhstan"           "KAZ" "EMEA"
"Kenya"                "KEN" "EMEA"
"Lebanon"              "LBN" "EMEA"
"Lithuania"            "LTU" "EMEA"
"Morocco"              "MAR" "EMEA"
"Mozambique"           "MOZ" "EMEA"
"Namibia"              "NAM" "EMEA"
"Nigeria"              "NGA" "EMEA"
"Oman"                 "OMN" "EMEA"
"Poland"               "POL" "EMEA"
"Qatar"                "QAT" "EMEA"
"Romania"              "ROU" "EMEA"
"Russia"               "RUS" "EMEA"
"Russian Federation"   "RUS" "EMEA"
"Rwanda"               "RWA" "EMEA"
"Saudi Arabia"         "SAU" "EMEA"
"Senegal"              "SEN" "EMEA"
"Serbia"               "SRB" "EMEA"
"Slovakia"             "SVK" "EMEA"
"South Africa"         "ZAF" "EMEA"
"Tanzania"             "TZA" "EMEA"
"Tunisia"              "TUN" "EMEA"
"Turkey"               "TUR" "EMEA"
"Turkiye"              "TUR" "EMEA"
"Ukraine"              "UKR" "EMEA"
"United Arab Emirates" "ARE" "EMEA"
"Uzbekistan"           "UZB" "EMEA"
"Zambia"               "ZMB" "EMEA"
end
tempfile XWALK
save "`XWALK'"

*==============================================================================
*  PARTE C. Proxy CEMBI: ICE BofA EM Corporate OAS por region (FRED)
*==============================================================================
di as txt "== Parte C: descargando FRED (proxy CEMBI) =="

*  Series ICE BofA EM Corporate Plus - Option-Adjusted Spread (OAS), en %:
*     BAMLEMCBPIOAS        Agregado Emerging Markets
*     BAMLEMRLCRPILAOAS    Latin America
*     BAMLEMRACRPIASIAOAS  Asia
*     BAMLEMRECRPIEMEAOAS  EMEA
*  Son diarias -> las colapsamos a mensual (promedio) y pasamos a bps (x100).

local FREDOK = 1
capture import fred BAMLEMCBPIOAS BAMLEMRLCRPILAOAS BAMLEMRACRPIASIAOAS BAMLEMRECRPIEMEAOAS, clear
if _rc {
    di as error "Fallo -import fred- (revisar 'set fredkey ...'). Intentando -freduse-..."
    capture which freduse
    if _rc ssc install freduse, replace
    capture freduse BAMLEMCBPIOAS BAMLEMRLCRPILAOAS BAMLEMRACRPIASIAOAS BAMLEMRECRPIEMEAOAS, clear
    if _rc {
        di as error "No se pudo bajar FRED. cembi_proxy quedara vacio."
        local FREDOK = 0
    }
    *  (la normalizacion de la fecha diaria -> mensual se hace mas abajo,
    *   detectando 'daten' de -import fred- o 'date' de -freduse-.)
}

if `FREDOK' {
    *  Normalizar la variable de fecha diaria a mensual segun el importador usado.
    capture confirm variable daten
    if !_rc {
        gen mdate = mofd(daten)          // -import fred- entrega 'daten' (%td)
    }
    else {
        capture confirm variable date
        if !_rc gen mdate = mofd(date)   // -freduse- entrega 'date' (%td)
    }
    format mdate %tm

    collapse (mean) BAMLEMCBPIOAS BAMLEMRLCRPILAOAS BAMLEMRACRPIASIAOAS ///
                    BAMLEMRECRPIEMEAOAS, by(mdate)

    *  Pasar de % a bps y renombrar por region.
    rename BAMLEMCBPIOAS       cembi_EM
    rename BAMLEMRLCRPILAOAS   cembi_LATAM
    rename BAMLEMRACRPIASIAOAS cembi_ASIA
    rename BAMLEMRECRPIEMEAOAS cembi_EMEA
    foreach r in EM LATAM ASIA EMEA {
        replace cembi_`r' = cembi_`r' * 100    // % -> bps
    }
    tempfile CEMBI
    save "`CEMBI'"
    di as txt "Proxy CEMBI: `=_N' meses."
}

*==============================================================================
*  PARTE D. Ensamble del panel final
*==============================================================================
di as txt "== Parte D: ensamblando panel =="

use "`EMBI'", clear

*  Asignar iso3 + region.
merge m:1 country using "`XWALK'", keep(match) nogen
*  (los nombres del GEM que NO estan en el crosswalk -agregados regionales,
*   "Emerging Markets", etc.- se descartan; ampliar XWALK para sumar paises.)

*  Pegar el proxy CEMBI regional por mes.
if `FREDOK' {
    merge m:1 mdate using "`CEMBI'", keep(match master) nogen

    *  Elegir el spread corporativo segun la region del pais; si falta, usar EM.
    gen double cembi_proxy = .
    replace cembi_proxy = cembi_LATAM if region=="LATAM"
    replace cembi_proxy = cembi_ASIA  if region=="ASIA"
    replace cembi_proxy = cembi_EMEA  if region=="EMEA"
    replace cembi_proxy = cembi_EM    if missing(cembi_proxy)
    label var cembi_proxy "Proxy CEMBI: ICE BofA EM Corp OAS regional (bps)"
    drop cembi_EM cembi_LATAM cembi_ASIA cembi_EMEA
}
else {
    gen double cembi_proxy = .
    label var cembi_proxy "Proxy CEMBI (no disponible - fallo FRED)"
}

*--- Orden, etiquetas y limpieza ----------------------------------------------
rename mdate mes
label var mes    "Mes (Stata %tm)"
label var iso3   "Codigo ISO3 del pais"
label var region "Region del proxy corporativo (LATAM/ASIA/EMEA/EM)"

order iso3 country region mes embi cembi_proxy
sort iso3 mes
drop if missing(iso3)

*  Declarar el panel (no rellena huecos). Protegido ante duplicados residuales.
duplicates drop iso3 mes, force
egen _pid = group(iso3)
capture xtset _pid mes
drop _pid

*--- Exportar -----------------------------------------------------------------
compress
save "embi_cembi_monthly.dta", replace

preserve
    gen mes_str = string(year(dofm(mes)))+"-"+string(month(dofm(mes)),"%02.0f")
    order iso3 country region mes_str embi cembi_proxy
    keep iso3 country region mes_str embi cembi_proxy
    export delimited using "embi_cembi_monthly.csv", replace
restore

*--- Resumen ------------------------------------------------------------------
di as result _n "== LISTO =="
qui levelsof iso3, local(cc)
local ncc : word count `cc'
di as txt "Paises (iso3): `ncc'"
qui su mes
di as txt "Rango de meses: " %tm r(min) "  a  " %tm r(max)
di as txt "Archivos: embi_cembi_monthly.dta / .csv"
list iso3 mes embi cembi_proxy in 1/10, noobs sepby(iso3)

*==============================================================================
*  NOTAS
*  -----
*  1) EMBI es soberano y por pais (dato real). cembi_proxy es un spread
*     corporativo REGIONAL (no por pais): sirve como control/aproximacion,
*     no como CEMBI oficial de cada pais.
*  2) Para CEMBI real por pais necesitas Bloomberg (indices JPMorgan CEMBI),
*     Refinitiv/Datastream o J.P. Morgan Markets. Si tenes acceso, reemplaza
*     la Parte C cargando tu export y mergeando por iso3 + mes.
*  3) Alternativa/complemento de EMBI para LatAm: API del BCRP
*     (estadisticas.bcrp.gob.pe) tiene EMBIG mensual por pais, muy limpia.
*==============================================================================
