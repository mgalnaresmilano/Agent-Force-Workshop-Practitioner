#!/usr/bin/env python3
"""Crea una Agentforce Data Library de tipo ficheros (SFDRIVE), sube un PDF e
indexa su contenido para grounding (RAG) de un agente NGA.

El token de sesion se obtiene internamente de `sf org display --json` y NUNCA
se imprime por stdout. Requiere que el usuario del CLI tenga el permiso
Data Cloud Architect y Data Cloud aprovisionado en la org.

Uso:
    python3 scripts/create_data_library.py \
        --org agentforce-workshop \
        --label "Pronto FAQ y Politicas" \
        --api-name Pronto_FAQ_Politicas \
        --file docs/Pronto-FAQ-Politicas.pdf
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API_VERSION = "v67.0"


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def get_org_auth(org_alias):
    """Devuelve (instance_url, access_token) sin imprimir el token."""
    res = _run(["sf", "org", "display", "--target-org", org_alias, "--json"])
    if res.returncode != 0:
        sys.exit(f"ERROR: no se pudo obtener auth de la org '{org_alias}':\n{res.stderr}")
    data = json.loads(res.stdout)["result"]
    return data["instanceUrl"].rstrip("/"), data["accessToken"]


def api(method, url, token, body=None, extra_headers=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if extra_headers:
        headers.update(extra_headers)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {"raw": raw}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--org", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--api-name", required=True)
    ap.add_argument("--file", required=True)
    ap.add_argument("--description", default="Politicas de servicio y FAQ de Pronto para grounding del Agente Pronto.")
    args = ap.parse_args()

    if not os.path.isfile(args.file):
        sys.exit(f"ERROR: no existe el fichero {args.file}")
    file_name = os.path.basename(args.file)
    file_size = os.path.getsize(args.file)

    instance_url, token = get_org_auth(args.org)
    base = f"{instance_url}/services/data/{API_VERSION}/einstein/data-libraries"

    # 1) Crear la libreria SFDRIVE (idempotente: si ya existe, la localiza)
    print(f"[1/6] Creando Data Library SFDRIVE '{args.label}' ({args.api_name})...")
    status, resp = api("POST", base, token, {
        "masterLabel": args.label,
        "developerName": args.api_name,
        "description": args.description,
        "groundingSource": {"sourceType": "SFDRIVE", "indexMode": "BASIC"},
    })
    library_id = resp.get("libraryId") if isinstance(resp, dict) else None
    if status in (200, 201) and library_id:
        print(f"      libraryId = {library_id}")
    else:
        print(f"      create devolvio {status}: {json.dumps(resp)[:200]} -> buscando existente...")
        st, lst = api("GET", base, token)
        for lib in (lst.get("libraries", []) if isinstance(lst, dict) else []):
            if lib.get("developerName") == args.api_name:
                library_id = lib.get("libraryId")
                break
        if not library_id:
            sys.exit("ERROR: no se pudo crear ni localizar la libreria.")
        print(f"      libraryId existente = {library_id}")

    # 2) Esperar a que el UDLO este ACTIVE (upload-readiness con espera server-side)
    print("[2/6] Esperando a que la libreria este lista para subir ficheros...")
    ready = False
    for attempt in range(30):
        status, resp = api("GET", f"{base}/{library_id}/upload-readiness?waitMaxTime=120000", token)
        if status == 200 and resp.get("ready"):
            ready = True
            print(f"      {resp.get('message', 'ready')}")
            break
        print(f"      intento {attempt + 1}: aun no lista ({resp.get('message', resp)})")
        time.sleep(10)
    if not ready:
        sys.exit("ERROR: la libreria no alcanzo el estado upload-ready.")

    # 3) Obtener URL presignada de S3
    print("[3/6] Solicitando URL presignada de subida...")
    status, resp = api("POST", f"{base}/{library_id}/file-upload-urls", token,
                       {"files": [{"fileName": file_name}]})
    if status not in (200, 201):
        sys.exit(f"ERROR file-upload-urls ({status}): {json.dumps(resp)[:300]}")
    up = resp["uploadUrls"][0]
    upload_url = up["uploadUrl"]
    file_path = up["filePath"]
    up_headers = up.get("headers") or {}

    # 4) Subir el PDF a S3 (PUT binario con los headers indicados)
    print(f"[4/6] Subiendo {file_name} ({file_size} bytes) a S3...")
    with open(args.file, "rb") as fh:
        body = fh.read()
    put = urllib.request.Request(upload_url, data=body, method="PUT")
    for k, v in up_headers.items():
        put.add_header(k, v)
    try:
        with urllib.request.urlopen(put) as pr:
            print(f"      HTTP {pr.status} subida completada")
    except urllib.error.HTTPError as e:
        sys.exit(f"ERROR subiendo a S3 ({e.code}): {e.read().decode('utf-8')[:300]}")

    # 5) Disparar indexacion
    print("[5/6] Disparando indexacion (DLO/DMO/SearchIndex/Retriever)...")
    status, resp = api("POST", f"{base}/{library_id}/indexing", token,
                       {"uploadedFiles": [{"filePath": file_path, "fileSize": file_size}]})
    if status not in (200, 201):
        sys.exit(f"ERROR indexing ({status}): {json.dumps(resp)[:300]}")
    print(f"      estado inicial: {resp.get('status')}")

    # 6) Poll de estado hasta READY (best-effort; la indexacion puede tardar minutos)
    print("[6/6] Esperando a que el SearchIndex quede READY (puede tardar varios minutos)...")
    final_status = None
    for attempt in range(60):
        status, resp = api("GET", f"{base}/{library_id}/status", token)
        idx = resp.get("indexingStatus", {}) if status == 200 else {}
        final_status = idx.get("status")
        stage = idx.get("currentStage")
        print(f"      intento {attempt + 1}: status={final_status} stage={stage}")
        if final_status in ("READY", "FAILED"):
            break
        time.sleep(15)

    print("\n=== RESUMEN ===")
    print(f"Data Library ID : {library_id}")
    print(f"API name        : {args.api_name}")
    print(f"Estado final    : {final_status}")
    if final_status != "READY":
        print("NOTA: si no esta READY, la indexacion sigue en curso. Reintenta el poll de /status mas tarde.")
    print("El retriever creado por ADL tendra prefijo 'File_'. Asocialo al agente en la pestana Knowledge de Agent Builder 2.0.")


if __name__ == "__main__":
    main()
