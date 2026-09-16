# -*- coding: utf-8 -*-
"""Ventana simple: elegir un video y generar el Gaussian Splat."""

import os
import sys
import threading
import webbrowser
import subprocess
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from tkinter.scrolledtext import ScrolledText

from run_splat import work_dir_for_video

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
RUN_SPLAT = os.path.join(REPO_ROOT, "run_splat.py")
SUPERSPLAT = "https://superspl.at/editor"


class SplatApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Video → Gaussian Splat")
        self.geometry("760x560")
        self.minsize(640, 480)
        self.video_path = tk.StringVar()
        self.status = tk.StringVar(value="Elegí un video y pulsá Generar splat.")
        self.output_dir = None
        self.proc = None
        self._build()

    def _build(self):
        pad = {"padx": 12, "pady": 6}
        frm = ttk.Frame(self)
        frm.pack(fill="both", expand=True, **pad)

        ttk.Label(frm, text="No hace falta Cursor. Elegí el video y esperá el .ply.",
                  font=("Segoe UI", 11)).pack(anchor="w")

        row = ttk.Frame(frm)
        row.pack(fill="x", pady=(10, 4))
        ttk.Entry(row, textvariable=self.video_path).pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="Elegir video…", command=self.pick_video).pack(side="left", padx=(8, 0))

        btns = ttk.Frame(frm)
        btns.pack(fill="x", pady=8)
        self.go_btn = ttk.Button(btns, text="Generar splat", command=self.start)
        self.go_btn.pack(side="left")
        ttk.Button(btns, text="Abrir carpeta del resultado", command=self.open_output).pack(side="left", padx=8)
        ttk.Button(btns, text="Ver el splat (SuperSplat)", command=self.open_viewer).pack(side="left")

        ttk.Label(frm, textvariable=self.status).pack(anchor="w", pady=(4, 4))

        self.log = ScrolledText(frm, height=22, wrap="word", font=("Consolas", 9))
        self.log.pack(fill="both", expand=True)
        self._log("El splat no se 'sube' a ningún programa especial.\n"
                  "Entrada = el video. Salida = un archivo point_cloud.ply\n"
                  "Cuando termine, Abrí SuperSplat en el navegador y arrastrá el .ply.\n")

    def _log(self, text):
        self.log.insert("end", text)
        self.log.see("end")

    def pick_video(self):
        path = filedialog.askopenfilename(
            title="Video de la escena",
            filetypes=[
                ("Video", "*.mp4 *.mov *.mkv *.avi *.webm"),
                ("Todos", "*.*"),
            ],
        )
        if path:
            self.video_path.set(path)

    def start(self):
        video = self.video_path.get().strip().strip('"')
        if not video or not os.path.isfile(video):
            messagebox.showerror("Video", "Elegí un archivo de video válido.")
            return
        if not os.path.isfile(RUN_SPLAT):
            messagebox.showerror("Repo", "No encuentro run_splat.py. Abrí EMPEZAR.bat desde la carpeta del repo.")
            return
        self.go_btn.config(state="disabled")
        self.status.set("Procesando… puede tardar 30–90 minutos. Dejá la notebook enchufada.")
        self.output_dir = None
        threading.Thread(target=self._run, args=(video,), daemon=True).start()

    def _run(self, video):
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        cmd = [sys.executable, RUN_SPLAT, "--video", video]
        try:
            self.proc = subprocess.Popen(
                cmd,
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                env=env,
            )
            for line in self.proc.stdout:
                self.after(0, self._log, line)
            code = self.proc.wait()
        except Exception as exc:
            self.after(0, self._done, 1, str(exc), video)
            return
        self.after(0, self._done, code, None, video)

    def _done(self, code, error, video):
        self.go_btn.config(state="normal")
        if error:
            self.status.set("Error al lanzar el proceso.")
            self._log("\n" + error + "\n")
            messagebox.showerror("Error", error)
            return
        if code != 0:
            self.status.set("Falló (código {}). Mirá el registro.".format(code))
            messagebox.showerror("Falló", "El proceso terminó con error. Revisá el texto de abajo.")
            return
        ply = self._find_ply(video)
        if ply:
            self.output_dir = os.path.dirname(ply)
            self.status.set("Listo: " + ply)
            self._log("\nSPLAT LISTO:\n{}\n\nAbrí SuperSplat y arrastrá ese archivo.\n".format(ply))
            messagebox.showinfo("Listo", "Splat generado:\n\n{}\n\nDespués: Ver el splat (SuperSplat) y arrastrá el .ply.".format(ply))
        else:
            self.status.set("Terminó, pero no encontré el .ply. Revisá el registro.")

    def _find_ply(self, video):
        work = work_dir_for_video(video)
        cloud = os.path.join(work, "output", "point_cloud")
        found = []
        if os.path.isdir(cloud):
            for root, _dirs, files in os.walk(cloud):
                if "point_cloud.ply" in files:
                    found.append(os.path.join(root, "point_cloud.ply"))
        if not found:
            return None
        found.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        return found[0]

    def open_output(self):
        folder = self.output_dir
        if not folder or not os.path.isdir(folder):
            video = self.video_path.get().strip()
            if video:
                ply = self._find_ply(video)
                folder = os.path.dirname(ply) if ply else None
        if not folder:
            messagebox.showinfo("Carpeta", "Todavía no hay resultado. Generá el splat primero.")
            return
        os.startfile(folder)

    def open_viewer(self):
        webbrowser.open(SUPERSPLAT)
        messagebox.showinfo(
            "SuperSplat",
            "Se abre el visor en el navegador.\nArrastrá el archivo point_cloud.ply a esa página.",
        )


if __name__ == "__main__":
    SplatApp().mainloop()
