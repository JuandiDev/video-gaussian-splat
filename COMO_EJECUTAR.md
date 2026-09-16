# Cómo generar el splat (Windows)

Paquete para clonar el repo, instalar herramientas y generar un Gaussian Splat **desde un video**.

Licencia del código original: uso **no comercial / investigación** (ver `LICENSE.md`).

## PC de destino (confirmada)

Lenovo 82B1 · Windows 11 · Ryzen 7 4800H · 16 GB RAM · **NVIDIA GeForce RTX 2060 laptop (~6 GB VRAM)** + Radeon integrada.

| | |
|---|---|
| ¿Puede entrenar 3DGS? | **Sí.** Turing, Compute 7.5 (el paper pide 7.0+) |
| VRAM dedicada | ~6 GB → perfil automático **7000 iteraciones**, fotos en CPU |
| GPU híbrida | CUDA usa la RTX. Cerrar Chrome/juegos. **Notebook enchufada.** |
| RAM | 16 GB: no dejar el mapper + entrenamiento con mil pestañas abiertas |

No uses la iGPU Radeon para Python. Si Windows pregunta, elegí **High performance / NVIDIA**.

## Uso diario (sin Cursor)

No hace falta Cursor ni escribir comandos. Después de la instalación de una vez:

1. Doble clic en **`EMPEZAR.bat`**
2. **Elegir video…** (el `.mp4` que te mandaron, en Descargas, Escritorio, USB, da igual)
3. **Generar splat** y esperar (30–90 min, notebook enchufada)
4. **Ver el splat (SuperSplat)** se abre el navegador → **arrastrá** el archivo `point_cloud.ply`

El splat **no se mete en ningún programa**. El video es la **entrada**. El `.ply` es la **salida** que crea la app.

```text
video.mp4  →  (esta app)  →  point_cloud.ply  →  SuperSplat en el navegador
```

Carpeta típica del resultado:

`C:\...\NombreDelVideo_splat\output\point_cloud\iteration_7000\point_cloud.ply`

## Qué hace falta una vez

Doble clic **`INSTALLAR.bat`** (con la notebook enchufada). Instala Git, Miniconda, Visual Studio C++, CUDA 11.8, FFmpeg, COLMAP y el entorno conda. Puede pedir permisos de Windows y tardar bastante.

Si VS/CUDA se acaban de instalar y el env falla, **reiniciá Windows** y volvé a correr `INSTALLAR.bat`.

Disco: ~15 GB libres.

## 1. Clonar (con submódulos)

```powershell
git clone --recursive https://github.com/<USUARIO>/<REPO>.git
cd <REPO>
```

Si ya clonaste sin `--recursive`:

```powershell
git submodule update --init --recursive
```

## 2–3. Instalación automática (una vez)

Doble clic **`INSTALLAR.bat`** (FFmpeg + COLMAP + conda). Equivale a:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install_windows.ps1
powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1
```

Si `fused-ssim` falla al compilar, el entrenamiento igual puede correr:

```powershell
conda activate gaussian_splatting
$env:DISTUTILS_USE_SDK = 1
pip install submodules/diff-gaussian-rasterization
pip install submodules/simple-knn
```

## 4. Generar el splat (día a día)

El video se manda por Drive / USB / WhatsApp. **No va en el repo.**

Doble clic **`EMPEZAR.bat`** → elegir video → Generar splat.

Si preferís PowerShell:

```powershell
conda activate gaussian_splatting
cd C:\ruta\al\repo
python splat_app.py
```

En esta PC el script va a:

1. Extraer 1 foto por segundo  
2. Correr COLMAP  
3. Entrenar **7000 iters** (perfil 6 GB)  
4. Escribir el `.ply` en:

`<carpeta_del_video>\<nombre_del_video>_splat\output\point_cloud\iteration_7000\point_cloud.ply`

Abrilo en [SuperSplat](https://superspl.at/editor).

Tiempo esperado (orientativo, notebook enchufada): COLMAP 5–20 min + train 20–60 min.

### Opciones útiles

| Flag | Qué hace |
|---|---|
| `--fps 2` | Más frames (mejor overlap, más lento) |
| `--cpu-sfm` | COLMAP solo en CPU |
| `--iterations 7000` | Ya es el default en esta GPU |
| `--work D:\escena` | Carpeta de trabajo |
| `--skip-train` | Solo COLMAP, no entrena |

No subas a `--iterations 30000` en esta 2060 de 6 GB: suele quedarse sin VRAM.

## Si algo falla

- **Pocas cámaras registradas:** video de WhatsApp muy comprimido o poco movimiento. Órbita lenta, archivo original, objeto quieto.
- **CUDA / `cl.exe`:** VS C++ **antes** que CUDA Toolkit; recrear el env.
- **Out of memory:** ya está el perfil 6 GB; cerrá el resto de programas.
- **Python usa la Radeon:** Configuración de Windows → Sistema → Pantalla → Gráficos → `python.exe` → **Alto rendimiento (NVIDIA)**.
- **`fbgemm.dll` / WinError 182:** PyTorch no carga. Doble clic **`ARREGLAR_TORCH.bat`**, reiniciá Windows, otra vez **EMPEZAR.bat**. No hace falta `INSTALLAR.bat`. Si COLMAP ya había terminado, se reusa.

## Flujo interno

```text
video.mp4 → ffmpeg (JPGs) → COLMAP sequential → train.py → point_cloud.ply
```
