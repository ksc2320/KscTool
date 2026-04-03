# KscTool dotfiles

개인 설정 파일 백업/샘플 보관 디렉토리.

| 파일 | 설명 |
|------|------|
| `dv_up.conf.sample` | `dv up` / `dv file` 설정 샘플 |

## 설정 복원 방법
```bash
cp dv_up.conf.sample ~/.dv_up.conf
# 이후 dv up set 으로 환경에 맞게 수정
```

## 실제 설정파일 위치
- `~/.dv_up.conf` — dv up/file 설정 (직접 편집 또는 `dv up set`)
- `~/.dv_up.log` — 배포 이력
