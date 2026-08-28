#!/usr/bin/env bash
# migrate_test_to_hdd.sh — ~/test 를 /hdd/ksc/test 로 옮기고 심볼릭 링크로 잇는다.
#
# 왜: / 파티션이 92% 찼는데(2026-08-28) ~/test 가 3.5G 다. /hdd 는 322G 여유.
#     큰 시험 로그는 큰 디스크에 두고, ~/test 경로는 심볼릭 링크로 그대로 유지한다.
#     경로가 안 바뀌므로 문서·메모리·스킬을 하나도 안 고쳐도 된다.
#
# 주의: /hdd/ksc/test 에 이미 15G 가 있다(2100 시험). 단순 이동이 아니라 **병합**이다.
#       덮어쓰기 전 원본을 .merge_backup_<날짜>/ 에 보관하므로 아무것도 사라지지 않는다.
#
#   migrate_test_to_hdd.sh check    지금 옮겨도 되는지 점검만 (기본, 아무것도 안 바꿈)
#   migrate_test_to_hdd.sh plan     무엇이 옮겨지고 무엇이 덮어써지는지 미리보기
#   migrate_test_to_hdd.sh run      실제 병합 + 심볼릭 링크 (안전조건 통과해야 실행)
#   migrate_test_to_hdd.sh finish   검증 후 남겨둔 원본 폴더 삭제 (마지막 단계)
#
# 안전조건 (run 이 스스로 거부한다)
#   - ~/test 안의 파일을 열고 있는 프로세스가 있으면 거부
#     (S1KTHOME-1440 무인시험 수집 스크립트가 3일째 돌고 있었다 — 옮기면 수집분이 사라진다)
#   - 최근 10분 안에 수정된 파일이 있으면 거부 (다른 세션이 작업 중)
#   - /hdd 여유 공간이 부족하면 거부
#   --force 로 무시할 수 있지만, 무인시험이 끝난 걸 눈으로 확인한 뒤에만 쓸 것.

set -uo pipefail

SRC="$HOME/test"
DST="/hdd/ksc/test"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="${DST}/.merge_backup_${STAMP}"
PARKED="${HOME}/test.pre_hdd_${STAMP}"
QUIET_MIN=10

C_OK=$'\e[1;32m'; C_NG=$'\e[1;31m'; C_WARN=$'\e[1;33m'; C_H=$'\e[38;5;153m'; C_R=$'\e[0m'
[ -t 1 ] || { C_OK=; C_NG=; C_WARN=; C_H=; C_R=; }

_hd() { printf '%s──────────────────────────────────────────────%s\n %s\n%s──────────────────────────────────────────────%s\n' "$C_H" "$C_R" "$*" "$C_H" "$C_R"; }

# ── 안전조건 점검 ─────────────────────────────────────────
# 0 = 지금 옮겨도 됨 / 1 = 아직 안 됨
_check() {
    local bad=0 procs recent free_kb need_kb

    _hd "이전 가능 여부 점검"

    if [ -L "$SRC" ]; then
        printf '%s이미 심볼릭 링크다%s → %s\n' "$C_OK" "$C_R" "$(readlink -f "$SRC")"
        echo "이미 옮겨진 상태. 할 일 없음."
        return 2
    fi
    [ -d "$SRC" ] || { printf '%s%s 가 없다%s\n' "$C_NG" "$SRC" "$C_R"; return 1; }

    # 1) 열려 있는 파일
    procs=$(lsof +D "$SRC" 2>/dev/null | tail -n +2)
    if [ -n "$procs" ]; then
        printf '%s✗ %s 안의 파일을 쓰고 있는 프로세스가 있다%s\n' "$C_NG" "$SRC" "$C_R"
        printf '%s\n' "$procs" | awk '{printf "    %-14s pid %-8s %s\n", $1, $2, $NF}' | head -8
        echo "    → 이게 끝나기 전에 옮기면 그 프로세스가 쓰던 내용이 사라진다."
        bad=1
    else
        printf '%s✓ 열려 있는 파일 없음%s\n' "$C_OK" "$C_R"
    fi

    # 2) 최근 수정 (다른 세션이 작업 중일 수 있다)
    recent=$(find "$SRC" -type f -mmin -${QUIET_MIN} 2>/dev/null | wc -l)
    if [ "$recent" -gt 0 ]; then
        printf '%s✗ 최근 %s분 안에 수정된 파일 %s건 — 누가 작업 중이다%s\n' "$C_NG" "$QUIET_MIN" "$recent" "$C_R"
        find "$SRC" -type f -mmin -${QUIET_MIN} 2>/dev/null | head -5 | sed 's|^|    |'
        bad=1
    else
        printf '%s✓ 최근 %s분간 조용함%s\n' "$C_OK" "$QUIET_MIN" "$C_R"
    fi

    # 3) 여유 공간
    need_kb=$(du -sk "$SRC" 2>/dev/null | cut -f1)
    free_kb=$(df -k --output=avail "$(dirname "$DST")" 2>/dev/null | tail -1 | tr -d ' ')
    if [ -n "$free_kb" ] && [ "$free_kb" -lt "$need_kb" ]; then
        printf '%s✗ /hdd 여유 부족 (필요 %sG / 여유 %sG)%s\n' "$C_NG" "$((need_kb/1024/1024))" "$((free_kb/1024/1024))" "$C_R"
        bad=1
    else
        printf '%s✓ 공간 충분 (필요 %sG / 여유 %sG)%s\n' "$C_OK" "$((need_kb/1024/1024))" "$((free_kb/1024/1024))" "$C_R"
    fi

    echo
    if [ $bad -eq 0 ]; then
        printf '%s지금 옮겨도 된다 → migrate_test_to_hdd.sh plan 으로 미리보기%s\n' "$C_OK" "$C_R"
    else
        printf '%s아직 안 된다. 위 항목이 해소된 뒤 다시 확인할 것.%s\n' "$C_WARN" "$C_R"
    fi
    return $bad
}

_plan() {
    _hd "병합 미리보기 (아무것도 바꾸지 않음)"
    echo "원본: $SRC"
    echo "대상: $DST  (이미 $(du -sh "$DST" 2>/dev/null | cut -f1) 들어있음)"
    echo
    echo "── 덮어쓰게 되는 파일 (원본은 .merge_backup 에 보관된다) ──"
    rsync -a --dry-run --itemize-changes --existing "$SRC/" "$DST/" 2>/dev/null \
        | grep -E '^>f\.st|^>f\.s|^>f\..t' | awk '{print "  " $2}' | head -20
    local n
    n=$(rsync -a --dry-run --itemize-changes --existing "$SRC/" "$DST/" 2>/dev/null | grep -cE '^>f')
    echo "  (덮어쓰기 대상 총 ${n}건)"
    echo
    echo "── 새로 들어가는 파일 수 ──"
    printf '  %s건\n' "$(rsync -a --dry-run --itemize-changes "$SRC/" "$DST/" 2>/dev/null | grep -c '^>f+++++++++')"
}

_run() {
    local force=0
    [ "${1:-}" = "--force" ] && force=1

    _check; local rc=$?
    [ $rc -eq 2 ] && return 0
    if [ $rc -ne 0 ] && [ $force -eq 0 ]; then
        echo
        echo "중단했다. 무인시험이 끝난 걸 확인했으면 --force 로 다시 실행할 것."
        return 1
    fi

    _hd "병합 실행"
    mkdir -p "$BACKUP" || return 1
    echo "덮어쓰기 백업 위치: $BACKUP"
    if ! rsync -a --backup --backup-dir="$BACKUP" --info=stats1 "$SRC/" "$DST/"; then
        printf '%s rsync 실패 — 원본은 그대로 두었다.%s\n' "$C_NG" "$C_R"
        return 1
    fi

    _hd "검증"
    local left
    left=$(rsync -a --dry-run --itemize-changes "$SRC/" "$DST/" 2>/dev/null | grep -c '^>f')
    if [ "$left" -ne 0 ]; then
        printf '%s✗ 아직 %s건이 안 옮겨졌다. 원본을 지우지 않는다.%s\n' "$C_NG" "$left" "$C_R"
        return 1
    fi
    printf '%s✓ 전부 옮겨졌다%s\n' "$C_OK" "$C_R"
    rmdir "$BACKUP" 2>/dev/null && echo "  (덮어쓴 파일 없음 — 백업 폴더 삭제)"

    _hd "심볼릭 링크 연결"
    # 원본은 지우지 않고 옆으로 치워둔다. 확인 후 finish 로 지운다.
    mv "$SRC" "$PARKED" || { printf '%s원본 이동 실패%s\n' "$C_NG" "$C_R"; return 1; }
    ln -s "$DST" "$SRC" || { printf '%s링크 생성 실패 — 되돌린다%s\n' "$C_NG" "$C_R"; mv "$PARKED" "$SRC"; return 1; }
    printf '%s✓ %s → %s%s\n' "$C_OK" "$SRC" "$DST" "$C_R"
    echo
    echo "원본은 아직 안 지웠다: $PARKED"
    echo "며칠 써보고 이상 없으면:  migrate_test_to_hdd.sh finish"
}

_finish() {
    local parked
    parked=$(ls -d "$HOME"/test.pre_hdd_* 2>/dev/null | head -1)
    [ -z "$parked" ] && { echo "치워둔 원본이 없다. 할 일 없음."; return 0; }
    [ -L "$SRC" ] || { printf '%s%s 가 심볼릭 링크가 아니다 — 상태가 이상하다. 손으로 확인할 것.%s\n' "$C_NG" "$SRC" "$C_R"; return 1; }
    _hd "원본 삭제"
    echo "지울 대상: $parked ($(du -sh "$parked" 2>/dev/null | cut -f1))"
    printf '정말 지울까? (yes 입력): '
    local ans; read -r ans
    [ "$ans" = "yes" ] || { echo "취소."; return 0; }
    rm -rf "$parked" && printf '%s✓ 삭제 완료 — / 파티션 확보%s\n' "$C_OK" "$C_R"
    df -h / | tail -1
}

case "${1:-check}" in
    check)  _check ;;
    plan)   _plan ;;
    run)    shift; _run "${1:-}" ;;
    finish) _finish ;;
    *) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0" ;;
esac
