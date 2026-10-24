#!/usr/bin/env bash
# Импорт, автотесты и сборка Windows. Общий шаг для CI и релиза.
# Ошибка скрипта GDScript не всегда меняет код выхода Godot, поэтому дополнительно ищем её в логе.
set -euo pipefail

godot --headless --path . --import 2>&1 | tee import.log
if grep -E "SCRIPT ERROR|Parse Error" import.log; then
	echo "::error::Ошибки скриптов при импорте"
	exit 1
fi

set +e
timeout 300 godot --headless --path . -s tests/run_tests.gd 2>&1 | tee tests.log
status=${PIPESTATUS[0]}
set -e
if [ "$status" -ne 0 ] || grep -E "SCRIPT ERROR|Parse Error" tests.log; then
	echo "::error::Автотесты не прошли (код $status)"
	exit 1
fi

mkdir -p build
godot --headless --path . --export-release "Windows Desktop" build/PhillipsMachine.exe 2>&1 | tee export.log
if [ ! -s build/PhillipsMachine.exe ]; then
	echo "::error::Сборка Windows не создала build/PhillipsMachine.exe"
	exit 1
fi
ls -lh build/
