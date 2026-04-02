"""
CLI wrapper pentru ReportEngine din raportare_juridic_app.py
Folosit de server.ps1 pentru a rula rapoarte asincron.

Intrare: python run_raport.py <params.json>
Iesire:  linii JSON pe stdout: {"pct": N, "msg": "..."} si {"done": true, "files": [...], "error": null}
"""
import sys
import os
import json
import re
import traceback
from datetime import datetime

# Adauga calea catre raportare_juridic_app.py
_HERE = os.path.dirname(os.path.abspath(__file__))
_JURIDIC_DIR = r"C:\CC\Adeverinte\raport_juridic"
sys.path.insert(0, _JURIDIC_DIR)

from raportare_juridic_app import ReportEngine


def emit(pct, msg):
    print(json.dumps({"pct": pct, "msg": msg}, ensure_ascii=False), flush=True)


def done(files, error=None):
    print(json.dumps({"done": True, "files": files, "error": error}, ensure_ascii=False), flush=True)


def main():
    if len(sys.argv) < 2:
        done([], "Lipseste fisierul params JSON")
        return

    params_path = sys.argv[1]
    try:
        with open(params_path, encoding="utf-8") as f:
            params = json.load(f)
    except Exception as e:
        done([], f"Eroare citire params: {e}")
        return

    task_type   = params.get("task")          # individual / 32ah / both / verify / export_common / update_30ah / insert_common
    source_path = params.get("source", "")
    grafic_path = params.get("grafic", "")
    output_dir  = params.get("output_dir", "")
    common_path = params.get("common", "")
    common_out  = params.get("common_out", "")
    denomination = params.get("denomination", "")

    if not task_type:
        done([], "Lipseste campul 'task' in params")
        return
    if not source_path or not os.path.exists(source_path):
        done([], f"Fisier sursa invalid: {source_path}")
        return
    if not grafic_path or not os.path.exists(grafic_path):
        done([], f"Fisier grafic invalid: {grafic_path}")
        return

    engine = ReportEngine()
    generated_files = []

    try:
        emit(2, "Incarcare fisier sursa...")
        engine.load_source(source_path)

        emit(5, "Incarcare grafic plati...")
        engine.load_grafic(grafic_path)

        tpl_name  = engine.grafic_sheet_name
        data_name = engine.sheet_names[0] if engine.sheet_names else ""

        emit(8, "Citire pattern plati...")
        engine.read_payment_pattern(tpl_name, callback=emit)

        emit(15, "Citire beneficiari...")
        engine.read_beneficiaries(data_name, callback=emit)

        timestamp = datetime.now().strftime("%d.%m.%Y")

        if task_type in ("individual", "both"):
            emit(20, "Generare sheet-uri individuale...")
            if not output_dir:
                done([], "Lipseste output_dir pentru task individual")
                return
            os.makedirs(output_dir, exist_ok=True)
            out_indiv = os.path.join(output_dir, f"Raportare_Individuale_{timestamp}.xlsx")
            n = engine.generate_individual_sheets(out_indiv, callback=emit)
            generated_files.append(out_indiv)
            emit(50 if task_type == "both" else 95, f"Individuale: {n} beneficiari salvati -> {os.path.basename(out_indiv)}")

        if task_type in ("32ah", "both"):
            emit(55 if task_type == "both" else 20, "Generare raport sintetic 32AH...")
            if not output_dir:
                done([], "Lipseste output_dir pentru task 32ah")
                return
            os.makedirs(output_dir, exist_ok=True)
            benef_values = list(engine.beneficiaries.values())
            if denomination:
                raport_name = denomination
            elif len(benef_values) == 1:
                raport_name = benef_values[0]["info"]["nume_ah"]
            else:
                raport_name = f"{len(benef_values)} beneficiari"
            full_name = f"Raport Sintetic {raport_name}"
            safe_name = re.sub(r'[\\/:*?"<>|]', "_", full_name)
            out_32ah = os.path.join(output_dir, f"{safe_name}_{timestamp}.xlsx")
            n = engine.generate_32ah_report(out_32ah, callback=emit, sheet_name=full_name[:31])
            generated_files.append(out_32ah)
            emit(95, f"32AH: {n} beneficiari -> {os.path.basename(out_32ah)}")

        if task_type == "verify":
            emit(20, "Verificare transe...")
            result = engine.verify_transe(callback=emit)
            emit(95, result)
            done([], None)
            return

        if task_type == "export_common":
            if not common_path or not os.path.exists(common_path):
                done([], f"Fisier comun invalid: {common_path}")
                return
            emit(20, "Export in fisierul comun...")
            out_path, n_matched, unmatched = engine.export_to_common(common_path, callback=emit)
            generated_files.append(out_path)
            if unmatched:
                emit(90, f"Atentie: {len(unmatched)} nepotriviti: {', '.join(unmatched)}")
            else:
                emit(95, f"Export ok: {n_matched} beneficiari potriviti")

        if task_type == "update_30ah":
            if not output_dir:
                done([], "Lipseste output_dir")
                return
            os.makedirs(output_dir, exist_ok=True)
            out_30ah = os.path.join(output_dir, f"Sursa_30AH_actualizat_{timestamp}.xlsx")
            emit(20, "Actualizare 30 AH...")
            n_matched, unmatched = engine.update_30ah_in_source(out_30ah, callback=emit)
            generated_files.append(out_30ah)
            if unmatched:
                emit(95, f"Atentie: {len(unmatched)} nepotriviti: {', '.join(unmatched)}")

        if task_type == "insert_common":
            if not common_path or not os.path.exists(common_path):
                done([], f"Fisier comun sursa invalid: {common_path}")
                return
            if not common_out:
                done([], "Lipseste common_out (calea fisierului comun rezultat)")
                return
            emit(20, "Inserare sheet-uri in fisierul comun...")
            added = engine.insert_sheets_into_common(common_path, common_out, callback=emit)
            generated_files.append(common_out)
            emit(95, f"Inserate/actualizate: {', '.join(added)}")

        done(generated_files, None)

    except PermissionError as e:
        done([], f"Fisier deschis in Excel sau permisiuni insuficiente: {e}")
    except Exception:
        done([], traceback.format_exc())


if __name__ == "__main__":
    main()
