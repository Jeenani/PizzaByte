#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PizzaByte Build & GitHub Release Automation Script
--------------------------------------------------
Автоматизирует экспорт Godot 4.7.2, создание установочных скриптов,
упаковку в .zip и публикацию в GitHub Releases через REST API.
"""

import os
import sys
import json
import shutil
import zipfile
import argparse
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
BUILD_DIR = PROJECT_ROOT / "build"
RELEASE_PACKAGE_NAME = "PizzaByte"
DEFAULT_VERSION = "v1.0.0"

POSSIBLE_GODOT_PATHS = [
    Path(r"C:\Users\User\Desktop\GodotEngine\Godot_v4.7.2-stable_win64_console.exe"),
    Path(r"C:\Users\User\Desktop\GodotEngine\Godot_v4.7.2-stable_win64.exe"),
]


def find_godot_executable() -> Path:
    for path in POSSIBLE_GODOT_PATHS:
        if path.exists():
            return path
    which = shutil.which("godot")
    if which:
        return Path(which)
    raise FileNotFoundError("Исполняемый файл Godot 4.7.2 не найден!")


def ensure_export_templates():
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return
    template_dir = Path(appdata) / "Godot" / "export_templates" / "4.7.2.stable"
    template_dir.mkdir(parents=True, exist_ok=True)
    release_tpl = template_dir / "windows_release_x86_64.exe"
    debug_tpl = template_dir / "windows_debug_x86_64.exe"

    godot_exe = Path(r"C:\Users\User\Desktop\GodotEngine\Godot_v4.7.2-stable_win64.exe")
    if not godot_exe.exists():
        godot_exe = find_godot_executable()

    if not release_tpl.exists():
        print(f"[*] Копирование шаблона release: {release_tpl.name}...")
        shutil.copy2(godot_exe, release_tpl)
    if not debug_tpl.exists():
        print(f"[*] Копирование шаблона debug: {debug_tpl.name}...")
        shutil.copy2(godot_exe, debug_tpl)


def create_installer_scripts(dist_dir: Path):
    installer_bat = dist_dir / "Установить_PizzaByte.bat"
    installer_bat.write_text(r"""@echo off
chcp 65001 >nul
title Установка PizzaByte
echo ====================================================
echo      Установка PizzaByte (Симулятор пиццемата)
echo ====================================================
echo.
set "INSTALL_DIR=%LOCALAPPDATA%\PizzaByte"
echo [1/3] Копирование файлов в %INSTALL_DIR%...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy /E /Y /I "%~dp0PizzaByte.exe" "%INSTALL_DIR%\" >nul
xcopy /E /Y /I "%~dp0PizzaByte.pck" "%INSTALL_DIR%\" >nul
if exist "%~dp0README.txt" xcopy /Y "%~dp0README.txt" "%INSTALL_DIR%\" >nul

echo [2/3] Создание ярлыков на Рабочем столе и в меню Пуск...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $desk = [Environment]::GetFolderPath('Desktop'); $s1 = $ws.CreateShortcut(\"$desk\PizzaByte.lnk\"); $s1.TargetPath = \"$env:LOCALAPPDATA\PizzaByte\PizzaByte.exe\"; $s1.WorkingDirectory = \"$env:LOCALAPPDATA\PizzaByte\"; $s1.Description = \"PizzaByte\"; $s1.Save(); $sm = [Environment]::GetFolderPath('StartMenu') + '\Programs'; $s2 = $ws.CreateShortcut(\"$sm\PizzaByte.lnk\"); $s2.TargetPath = \"$env:LOCALAPPDATA\PizzaByte\PizzaByte.exe\"; $s2.WorkingDirectory = \"$env:LOCALAPPDATA\PizzaByte\"; $s2.Description = \"PizzaByte\"; $s2.Save();"

echo [3/3] Создание деинсталлятора...
(
  echo @echo off
  echo chcp 65001 ^^>nul
  echo echo Удаление PizzaByte...
  echo powershell -Command "Remove-Item -Force '$env:USERPROFILE\Desktop\PizzaByte.lnk' -ErrorAction SilentlyContinue; Remove-Item -Force '$env:APPDATA\Microsoft\Windows\Start Menu\Programs\PizzaByte.lnk' -ErrorAction SilentlyContinue"
  echo rmdir /S /Q "%%LOCALAPPDATA%%\PizzaByte"
  echo echo PizzaByte успешно удалена.
  echo pause
) > "%INSTALL_DIR%\Удалить_PizzaByte.bat"

echo.
echo ====================================================
echo   Установка успешно завершена! Ярлык на Рабочем столе.
echo ====================================================
echo.
set /p RUN_NOW="Запустить PizzaByte сейчас? (Y/N): "
if /i "%RUN_NOW%"=="Y" start "" "%INSTALL_DIR%\PizzaByte.exe"
""", encoding="utf-8")

    shortcut_bat = dist_dir / "Создать_ярлык_на_рабочий_стол.bat"
    shortcut_bat.write_text(r"""@echo off
chcp 65001 >nul
echo Создание ярлыка PizzaByte на Рабочем столе...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $desk = [Environment]::GetFolderPath('Desktop'); $s = $ws.CreateShortcut(\"$desk\PizzaByte.lnk\"); $s.TargetPath = \"\"\"%~dp0PizzaByte.exe\"\"\"; $s.WorkingDirectory = \"\"\"%~dp0\"\"\"; $s.Description = \"PizzaByte\"; $s.Save();"
echo Готово! Ярлык появился на Рабочем столе.
pause
""", encoding="utf-8")

    readme_txt = dist_dir / "README.txt"
    readme_txt.write_text("""🍕 PizzaByte — 2D симулятор автомата по продаже пиццы
=====================================================
Варианты запуска:
1. Без установки: просто запустите `PizzaByte.exe`.
2. Установка в систему: запустите `Установить_PizzaByte.bat` (копирует в %LOCALAPPDATA% и создает ярлык на Рабочем столе).
3. Создать ярлык для текущей папки: запустите `Создать_ярлык_на_рабочий_стол.bat`.

Управление:
- ЛКМ — выбор ингредиентов, навигация по экрану, оплата, забор пиццы.
- Колесико мыши — плавный зум камеры.
- F1 — режим Дизайнера.
- F3 — сброс камеры к общему виду улицы.
- F4 — сохранить разметку (в режиме F1).
- Esc / F11 — полноэкранный режим.
""", encoding="utf-8")


def build_game() -> Path:
    godot_exe = find_godot_executable()
    print(f"[*] Используется Godot: {godot_exe}")
    ensure_export_templates()

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    for item in BUILD_DIR.iterdir():
        if item.is_file():
            item.unlink()
        elif item.is_dir():
            shutil.rmtree(item)

    print("[*] Экспорт Godot проекта в Windows Desktop...")
    out_exe = BUILD_DIR / "PizzaByte.exe"
    cmd = [str(godot_exe), "--headless", "--export-release", "Windows Desktop", str(out_exe)]
    res = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[!] Ошибка экспорта (код {res.returncode}):")
        print(res.stderr or res.stdout)
        raise RuntimeError("Godot export failed")

    tmp_file = BUILD_DIR / "PizzaByte.tmp"
    if tmp_file.exists():
        tmp_file.unlink()

    out_pck = BUILD_DIR / "PizzaByte.pck"
    if not out_exe.exists() or not out_pck.exists():
        raise FileNotFoundError(f"Файлы сборки не найдены в {BUILD_DIR}")

    print(f"[+] Экспорт завершен:")
    print(f"    - {out_exe.name} ({out_exe.stat().st_size / (1024*1024):.1f} MB)")
    print(f"    - {out_pck.name} ({out_pck.stat().st_size / (1024*1024):.1f} MB)")
    create_installer_scripts(BUILD_DIR)
    return BUILD_DIR


def package_release(version_tag: str) -> Path:
    archive_name = f"{RELEASE_PACKAGE_NAME}_{version_tag}_Windows_x64.zip"
    archive_path = PROJECT_ROOT / archive_name
    if archive_path.exists():
        archive_path.unlink()

    print(f"[*] Упаковка релизного архива: {archive_name}...")
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for file_path in BUILD_DIR.rglob("*"):
            if file_path.is_file() and not file_path.name.endswith(".tmp"):
                zf.write(file_path, file_path.relative_to(BUILD_DIR))

    print(f"[+] Релизный архив создан: {archive_path.name} ({archive_path.stat().st_size / (1024*1024):.1f} MB)")
    return archive_path


def get_github_token() -> str:
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    try:
        p = subprocess.Popen(
            ["git", "credential", "fill"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        stdout, _ = p.communicate("protocol=https\nhost=github.com\n\n")
        creds = dict(l.split("=", 1) for l in stdout.strip().splitlines() if "=" in l)
        pwd = creds.get("password")
        if pwd:
            return pwd
    except Exception as e:
        print(f"[!] Ошибка получения токена из git: {e}")
    raise RuntimeError("GitHub токен не найден в git credentials или переменной GITHUB_TOKEN.")


def get_repo_slug() -> str:
    try:
        out = subprocess.check_output(["git", "remote", "get-url", "origin"], cwd=PROJECT_ROOT, text=True).strip()
        if out.endswith(".git"):
            out = out[:-4]
        if "github.com/" in out:
            return out.split("github.com/")[1]
        elif "github.com:" in out:
            return out.split("github.com:")[1]
    except Exception:
        pass
    return "Jeenani/PizzaByte"


def create_and_push_tag(version_tag: str):
    print(f"[*] Проверка/создание Git тега '{version_tag}'...")
    try:
        tags = subprocess.check_output(["git", "tag"], cwd=PROJECT_ROOT, text=True).splitlines()
        if version_tag not in tags:
            subprocess.run(["git", "tag", "-a", version_tag, "-m", f"Release {version_tag}"], cwd=PROJECT_ROOT, check=True)
        subprocess.run(["git", "push", "origin", version_tag], cwd=PROJECT_ROOT, check=True)
        print(f"[+] Тег '{version_tag}' отправлен на GitHub.")
    except Exception as e:
        print(f"[!] Предупреждение при отправке тега: {e}")



def publish_github_release(version_tag: str, archive_path: Path, draft: bool = False) -> str:
    token = get_github_token()
    repo_slug = get_repo_slug()
    print(f"[*] Публикация релиза на GitHub ({repo_slug})...")

    headers = {
        "User-Agent": "PizzaByte-Release-Bot",
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github.v3+json",
    }

    body = f"""## 🍕 PizzaByte {version_tag} — Windows Release

Официальный установочный билд игры **PizzaByte** (2D симулятор автомата по продаже пиццы).

### 🚀 Варианты установки и запуска:
1. **Портативная версия (без установки)**:
   - Скачайте и распакуйте архив `{archive_path.name}`.
   - Запустите `PizzaByte.exe`.
2. **Установка в систему**:
   - Запустите скрипт `Установить_PizzaByte.bat` внутри папки.
   - Игра скопируется в программы с автоматическим созданием ярлыков на **Рабочем столе** и в **меню Пуск**!

### 🎮 Основные возможности:
- Реалистичный процесс приготовления: запекание, динамические ТЭНы, индикатор нагрева печи.
- Неоновое табло выдачи («ЗАБЕРИ СВОЮ ПИЦЦУ») со световой индикацией готовности.
- Сенсорная панель заказа: «Ручной» и «Автоматический» режимы, кастомизация рецепта, промокоды.
- Плавный зум камеры колесиком мыши (масштаб от панорамы улицы до крупного плана тачпада).
"""

    create_payload = {
        "tag_name": version_tag,
        "name": f"PizzaByte {version_tag}",
        "body": body,
        "draft": draft,
        "prerelease": False,
    }

    get_req = urllib.request.Request(
        f"https://api.github.com/repos/{repo_slug}/releases/tags/{version_tag}",
        headers=headers,
    )
    release_data = None
    try:
        with urllib.request.urlopen(get_req) as resp:
            release_data = json.loads(resp.read().decode())
            print(f"[*] Релиз для {version_tag} уже существует (ID: {release_data['id']}).")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            pass
        else:
            raise

    if not release_data:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{repo_slug}/releases",
            headers=headers,
            data=json.dumps(create_payload).encode("utf-8"),
            method="POST",
        )
        with urllib.request.urlopen(req) as resp:
            release_data = json.loads(resp.read().decode())
            print(f"[+] Релиз создан: {release_data['html_url']}")

    upload_url = release_data["upload_url"].split("{")[0]

    for asset in release_data.get("assets", []):
        if asset["name"] == archive_path.name:
            print(f"[*] Удаление старого ассета '{asset['name']}'...")
            del_req = urllib.request.Request(
                f"https://api.github.com/repos/{repo_slug}/releases/assets/{asset['id']}",
                headers=headers,
                method="DELETE",
            )
            with urllib.request.urlopen(del_req):
                pass

    print(f"[*] Загрузка {archive_path.name} в релиз ({archive_path.stat().st_size / (1024*1024):.1f} MB)...")
    with open(archive_path, "rb") as f:
        file_bytes = f.read()

    upload_headers = {
        "User-Agent": "PizzaByte-Release-Bot",
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/zip",
        "Content-Length": str(len(file_bytes)),
    }
    url = f"{upload_url}?name={archive_path.name}"
    upload_req = urllib.request.Request(url, headers=upload_headers, data=file_bytes, method="POST")

    with urllib.request.urlopen(upload_req) as resp:
        asset_info = json.loads(resp.read().decode())
        print(f"[+] Файл успешно загружен!")
        print(f"    Прямая ссылка на скачивание: {asset_info['browser_download_url']}")

    return release_data["html_url"]


def main():
    parser = argparse.ArgumentParser(description="PizzaByte Build & GitHub Release Automation")
    parser.add_argument("--version", default=DEFAULT_VERSION, help="Версия релиза")
    parser.add_argument("--build-only", action="store_true", help="Только собрать без отправки на GitHub")
    parser.add_argument("--draft", action="store_true", help="Создать релиз как draft")

    args = parser.parse_args()
    version_tag = args.version if args.version.startswith("v") else f"v{args.version}"

    print("====================================================")
    print(f"   Сборка и публикация PizzaByte ({version_tag})")
    print("====================================================")

    build_game()
    archive_path = package_release(version_tag)

    if args.build_only:
        print(f"\n[+] Сборка завершена (--build-only): {archive_path.resolve()}")
        return

    create_and_push_tag(version_tag)
    release_url = publish_github_release(version_tag, archive_path, draft=args.draft)

    print("\n====================================================")
    print("🎉 ВСЕ ЭТАПЫ УСПЕШНО ЗАВЕРШЕНЫ!")
    print(f"🔗 Ссылка на релиз: {release_url}")
    print("====================================================")


if __name__ == "__main__":
    main()

