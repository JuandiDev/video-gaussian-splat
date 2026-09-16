# -*- coding: utf-8 -*-
"""Ventana: elegir video, ver preview del train y cancelar si va mal."""

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
        self.geometry("920x720")
        self.minsize(760, 600)
        self.video_path = tk.StringVar()
        self.status = tk.StringVar(value="Elegí un video y pulsá Generar splat.")
        self.output_dir = None
        self.proc = None
        self.cancelled = False
        self.preview_mtime = 0
        self.preview_photo = None
        self._build()
        self.after(1500, self._poll_preview)

    def _build(self):
        pad = {"padx": 12, "pady": 6}
        frm = ttk.Frame(self)
        frm.pack(fill="both", expand=True, **pad)

        ttk.Label(
            frm,
            text="Elegí el video. Mientras entrena vas a ver una foto de cómo va. Si se ve mal, Cancelar.",
            font=("Segoe UI", 11),
        ).pack(anchor="w")

        row = ttk.Frame(frm)
        row.pack(fill="x", pady=(10, 4))
        ttk.Entry(row, textvariable=self.video_path).pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="Elegir video…", command=self.pick_video).pack(side="left", padx=(8, 0))

        btns = ttk.Frame(frm)
        btns.pack(fill="x", pady=8)
        self.go_btn = ttk.Button(btns, text="Generar splat", command=self.start)
        self.go_btn.pack(side="left")
        self.cancel_btn = ttk.Button(btns, text="Cancelar", command=self.cancel, state="disabled")
        self.cancel_btn.pack(side="left", padx=8)
        ttk.Button(btns, text="Abrir carpeta del resultado", command=self.open_output).pack(side="left")
        ttk.Button(btns, text="Ver el splat (SuperSplat)", command=self.open_viewer).pack(side="left", padx=8)

        ttk.Label(frm, textvariable=self.status).pack(anchor="w", pady=(4, 4))

        self.preview_label = ttk.Label(
            frm,
            text="Acá se va a ver el splat mientras se arma (cada ~200 pasos).",
            anchor="center",
        )
        self.preview_label.pack(fill="x", pady=(0, 8))

        self.log = ScrolledText(frm, height=14, wrap="word", font=("Consolas", 9))
        self.log.pack(fill="both", expand=True)
        self._log(
            "Entrada = el video. Salida = point_cloud.ply\n"
            "Durante el entrenamiento aparece una vista previa arriba.\n"
            "Si se ve una mancha o está mal, Cancelar y cambiá captura/video.\n"
        )

    def _log(self, text):
        self.log.insert("end", text)
        self.log.see("end")

    def _preview_path(self):
        video = self.video_path.get().strip().strip('"')
        if not video:
            return None
        work = work_dir_for_video(video)
        return os.path.join(work, "output", "preview.png")

    def _poll_preview(self):
        path = self._preview_path()
        if path and os.path.isfile(path):
            try:
                mtime = os.path.getmtime(path)
                if mtime != self.preview_mtime:
                    self.preview_mtime = mtime
                    img = tk.PhotoImage(file=path)
                    # shrink if huge
                    w = img.width()
                    if w > 640:
                        factor = max(2, int(round(w / 640.0)))
                        img = img.subsample(factor, factor)
                    self.preview_photo = img
                    self.preview_label.config(image=self.preview_photo, text="")
                    iter_file = os.path.join(os.path.dirname(path), "preview_iter.txt")
                    extra = ""
                    if os.path.isfile(iter_file):
                        with open(iter_file, "r") as f:
                            extra = "  (paso {})".format(f.read().strip())
                    if self.proc and self.proc.poll() is None:
                        self.status.set("Entrenando… vista previa actualizada." + extra)
            except tk.TclError:
                pass
        self.after(1500, self._poll_preview)

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
        self.cancelled = False
        self.preview_mtime = 0
        self.go_btn.config(state="disabled")
        self.cancel_btn.config(state="normal")
        self.status.set("Procesando… notebook enchufada. La foto aparece cuando arranca el train.")
        self.output_dir = None
        threading.Thread(target=self._run, args=(video,), daemon=True).start()

    def cancel(self):
        if not self.proc or self.proc.poll() is not None:
            return
        self.cancelled = True
        self.status.set("Cancelando…")
        try:
            if os.name == "nt":
                subprocess.run(
                    ["taskkill", "/F", "/T", "/PID", str(self.proc.pid)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            else:
                self.proc.terminate()
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass

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
        self.cancel_btn.config(state="disabled")
        if self.cancelled:
            self.status.set("Cancelado. Podés elegir otro video o Generar de nuevo.")
            self._log("\nCancelado por el usuario.\n")
            return
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
            messagebox.showinfo(
                "Listo",
                "Splat generado:\n\n{}\n\nDespués: Ver el splat (SuperSplat) y arrastrá el .ply.".format(ply),
            )
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
